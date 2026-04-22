import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../models/book.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';

class ChatScreen extends StatefulWidget {
  final Book book;
  const ChatScreen({super.key, required this.book});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<ChatMessage> _messages = [];

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _connected = false;
  bool _connecting = false;
  bool _isRecording = false;
  bool _handsFree = false;
  bool _tutorSpeaking = false;
  bool _tutorTyping = false;
  int _messageCount = 0;

  final _player = AudioPlayer();
  final _recorder = AudioRecorder();
  String? _recordingPath;

  // VAD hands-free
  Timer? _vadTimer;
  bool _vadWaiting = false; // aguardando resposta do tutor

  // Animação de pulse no mic (hands-free)
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _connect();
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    try {
      final wsUrl = await ApiService.getWsUrl(widget.book.id);
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (_) => _handleDisconnect(),
        onDone: _handleDisconnect,
      );
      setState(() {
        _connected = true;
        _connecting = false;
      });
    } catch (e) {
      setState(() => _connecting = false);
      _showError('Erro de conexão: $e');
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String);
      final type = data['type'] as String?;
      final content = data['content'] as String? ?? '';

      if (type == 'vad_result') {
        // Resposta VAD: se silêncio detectado, parar gravação
        final speechDetected = data['speech_detected'] as bool? ?? true;
        if (!speechDetected && _isRecording && _handsFree) {
          _stopHandsFreeRecording();
        }
        return;
      }

      if (type == 'status') {
        if (content == 'processing') {
          setState(() => _tutorTyping = true);
        } else if (content == 'ready') {
          setState(() {
            _tutorTyping = false;
            _tutorSpeaking = false;
          });
          // Hands-free: iniciar próximo ciclo de gravação após tutor terminar
          if (_handsFree && !_vadWaiting && _connected) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (_handsFree && !_isRecording && _connected && mounted) {
                _startHandsFreeRecording();
              }
            });
          }
        }
        return;
      }

      setState(() => _tutorTyping = false);

      if (type == 'text' || type == null) {
        _addMessage(ChatMessage(
          id: DateTime.now().toIso8601String(),
          role: MessageRole.tutor,
          text: content,
          timestamp: DateTime.now(),
        ));
      } else if (type == 'audio') {
        final audioB64 = data['data'] as String? ?? content;
        _addMessage(ChatMessage(
          id: DateTime.now().toIso8601String(),
          role: MessageRole.tutor,
          text: data['transcript'] ?? '🔊',
          audioBase64: audioB64,
          timestamp: DateTime.now(),
        ));
        setState(() => _tutorSpeaking = true);
        _playAudio(audioB64);
      }
    } catch (_) {}
  }

  Future<void> _playAudio(String base64Audio) async {
    try {
      final bytes = base64Decode(base64Audio);
      await _player.setPlaybackRate(1.1);
      await _player.play(BytesSource(bytes));
      _player.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => _tutorSpeaking = false);
      });
    } catch (_) {}
  }

  void _handleDisconnect() {
    setState(() {
      _connected = false;
      _tutorTyping = false;
      _tutorSpeaking = false;
    });
    _stopVadTimer();
  }

  void _addMessage(ChatMessage msg) {
    setState(() {
      _messages.add(msg);
      if (msg.role == MessageRole.user || msg.role == MessageRole.tutor) {
        _messageCount++;
      }
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendText() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || !_connected) return;

    _addMessage(ChatMessage(
      id: DateTime.now().toIso8601String(),
      role: MessageRole.user,
      text: text,
      timestamp: DateTime.now(),
    ));

    _channel!.sink.add(jsonEncode({'type': 'text', 'content': text}));
    _textCtrl.clear();
    setState(() => _tutorTyping = true);
  }

  // ── Gravação manual (long-press) ─────────────────────────────────────────

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    _recordingPath =
        '${dir.path}/rm_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: _recordingPath!);
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    await _recorder.stop();
    setState(() => _isRecording = false);
    if (_recordingPath == null || !_connected) return;

    final file = File(_recordingPath!);
    if (!await file.exists()) return;

    final bytes = await file.readAsBytes();
    final b64 = base64Encode(bytes);

    _addMessage(ChatMessage(
      id: DateTime.now().toIso8601String(),
      role: MessageRole.user,
      text: '🎤 (áudio)',
      timestamp: DateTime.now(),
    ));

    _channel!.sink.add(jsonEncode({'type': 'audio', 'data': b64}));
    setState(() => _tutorTyping = true);
    await file.delete();
  }

  // ── Hands-free VAD ────────────────────────────────────────────────────────

  Future<void> _startHandsFreeRecording() async {
    if (!await _recorder.hasPermission()) return;
    if (_isRecording) return;

    final dir = await getTemporaryDirectory();
    _recordingPath =
        '${dir.path}/rm_hf_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: _recordingPath!);
    setState(() => _isRecording = true);

    // Polling VAD a cada 500ms
    _vadTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!_isRecording || !_connected) return;
      // Ler últimos dados gravados (snapshot parcial)
      final path = _recordingPath;
      if (path == null) return;
      try {
        final file = File(path);
        if (!await file.exists()) return;
        final bytes = await file.readAsBytes();
        if (bytes.length < 4000) return; // Menos de ~250ms — ignorar

        // Enviar últimos 2s (aprox 32KB em AAC) para VAD check
        final tail = bytes.length > 32000
            ? bytes.sublist(bytes.length - 32000)
            : bytes;
        final b64 = base64Encode(tail);
        _channel!.sink
            .add(jsonEncode({'type': 'vad_check', 'content': b64}));
      } catch (_) {}
    });
  }

  Future<void> _stopHandsFreeRecording() async {
    _stopVadTimer();
    if (!_isRecording) return;
    await _recorder.stop();
    setState(() => _isRecording = false);

    if (_recordingPath == null || !_connected) return;
    final file = File(_recordingPath!);
    if (!await file.exists()) return;

    final bytes = await file.readAsBytes();
    if (bytes.length < 4000) {
      // Áudio muito curto — ruído, ignorar
      await file.delete();
      // Reiniciar ciclo imediatamente
      if (_handsFree && _connected && mounted) {
        Future.delayed(const Duration(milliseconds: 300), _startHandsFreeRecording);
      }
      return;
    }

    final b64 = base64Encode(bytes);
    _addMessage(ChatMessage(
      id: DateTime.now().toIso8601String(),
      role: MessageRole.user,
      text: '🎤 (áudio)',
      timestamp: DateTime.now(),
    ));

    _channel!.sink.add(jsonEncode({'type': 'audio', 'data': b64}));
    setState(() {
      _tutorTyping = true;
      _vadWaiting = true;
    });
    await file.delete();

    // _vadWaiting será false quando status=ready chegar → próximo ciclo inicia
    Future.delayed(const Duration(seconds: 20), () {
      // Timeout de segurança: reiniciar após 20s sem resposta
      if (mounted && _handsFree && _vadWaiting) {
        setState(() => _vadWaiting = false);
      }
    });
  }

  void _stopVadTimer() {
    _vadTimer?.cancel();
    _vadTimer = null;
  }

  void _toggleHandsFree() {
    setState(() => _handsFree = !_handsFree);
    if (_handsFree) {
      _startHandsFreeRecording();
    } else {
      _stopVadTimer();
      if (_isRecording) _recorder.stop();
      setState(() => _isRecording = false);
      setState(() => _vadWaiting = false);
    }
  }

  // ── Modal de score pós-sessão ─────────────────────────────────────────────

  Future<void> _showReviewScoreDialog() async {
    if (_messageCount < 3) return; // Sessão muito curta

    final score = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Como foi a sessão?'),
        content: const Text(
            'Sua resposta ajuda o ReadingMate a agendar a próxima revisão.'),
        actions: [
          TextButton.icon(
            icon: const Text('😓'),
            label: const Text('Difícil'),
            onPressed: () => Navigator.pop(context, 0.3),
          ),
          TextButton.icon(
            icon: const Text('🤔'),
            label: const Text('Ok'),
            onPressed: () => Navigator.pop(context, 0.7),
          ),
          FilledButton.icon(
            icon: const Text('😊'),
            label: const Text('Fácil'),
            onPressed: () => Navigator.pop(context, 1.0),
          ),
        ],
      ),
    );

    if (score != null) {
      await ApiService.submitReviewScore(widget.book.id, score);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _stopVadTimer();
    _sub?.cancel();
    _channel?.sink.close();
    _player.dispose();
    _recorder.dispose();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) await _showReviewScoreDialog();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.book.emoji} ${widget.book.title}'),
          actions: [
            // Hands-free toggle
            IconButton(
              icon: Icon(
                  _handsFree ? Icons.hearing : Icons.hearing_disabled),
              tooltip: 'Hands-free',
              color: _handsFree ? Colors.green : null,
              onPressed: _toggleHandsFree,
            ),
            // Indicador de conexão
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                _connected ? Icons.circle : Icons.circle_outlined,
                size: 12,
                color: _connected ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_connecting) const LinearProgressIndicator(),
            if (!_connected && !_connecting)
              MaterialBanner(
                content: const Text('Desconectado do backend'),
                actions: [
                  TextButton(
                      onPressed: _connect,
                      child: const Text('Reconectar')),
                ],
              ),

            // Mensagens
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.book.emoji,
                              style: const TextStyle(fontSize: 64)),
                          const SizedBox(height: 16),
                          const Text('Comece sua aula!'),
                          const SizedBox(height: 8),
                          const Text(
                            'Faça uma pergunta sobre o livro\nou fale sobre o que quer aprender.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(16),
                      itemCount:
                          _messages.length + (_tutorTyping ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (_tutorTyping && i == _messages.length) {
                          return const _TypingBubble();
                        }
                        return _MessageBubble(message: _messages[i]);
                      },
                    ),
            ),

            // Input
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4)
                ],
              ),
              child: Row(
                children: [
                  // Botão de microfone (com pulse em hands-free)
                  _buildMicButton(),
                  // Campo de texto
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Escreva sua pergunta...',
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onSubmitted: (_) => _sendText(),
                      maxLines: null,
                    ),
                  ),
                  // Botão de enviar
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _connected ? _sendText : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMicButton() {
    if (_handsFree && _isRecording) {
      // Mic pulsando — gravando em hands-free
      return AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, child) => Transform.scale(
          scale: _pulseAnim.value,
          child: IconButton(
            icon: const Icon(Icons.mic, color: Colors.red),
            tooltip: 'Gravando... (hands-free)',
            onPressed: _stopHandsFreeRecording,
          ),
        ),
      );
    }

    if (_handsFree && _tutorSpeaking) {
      // Tutor falando
      return IconButton(
        icon: const Icon(Icons.volume_up, color: Colors.blue),
        tooltip: 'Tutor falando...',
        onPressed: null,
      );
    }

    if (_handsFree) {
      // Hands-free ativo mas aguardando/standby
      return IconButton(
        icon: const Icon(Icons.mic_none, color: Colors.green),
        tooltip: 'Hands-free ativo',
        onPressed: _toggleHandsFree,
      );
    }

    // Modo manual (long-press)
    return GestureDetector(
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) => _stopRecording(),
      child: IconButton(
        icon: Icon(_isRecording ? Icons.mic : Icons.mic_none),
        color: _isRecording ? Colors.red : null,
        onPressed: null,
        tooltip: 'Segure para falar',
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final colors = Theme.of(context).colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color:
              isUser ? colors.primary : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight:
                isUser ? const Radius.circular(4) : null,
            bottomLeft:
                !isUser ? const Radius.circular(4) : null,
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
              color: isUser
                  ? colors.onPrimary
                  : colors.onSurface),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
        ),
        child: const Text('✍️ digitando...',
            style: TextStyle(fontStyle: FontStyle.italic)),
      ),
    );
  }
}
