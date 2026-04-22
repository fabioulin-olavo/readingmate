import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../widgets/chapter_progress_bar.dart';
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
  double _bookProgress = 0.0; // 0.0–1.0
  int _sessionScore = 0;
  int _currentChapter = 0;

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
      // Conectar ao WebSocket diretamente com o book_id
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

      if (type == 'session_info') {
        final chapter = (data['chapter'] as int? ?? 0);
        final score = (data['score'] as num?)?.toInt() ?? 0;
        final total = widget.book.chapters > 0 ? widget.book.chapters : 20;
        setState(() {
          _sessionScore = score;
          _currentChapter = chapter;
          _bookProgress = (chapter / total).clamp(0.0, 1.0);
        });
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

    // VAD local baseado em amplitude — sem depender do servidor
    // Detecta silêncio prolongado e para automaticamente
    int silentFrames = 0;
    int totalFrames = 0;
    const int silenceThreshold = 6; // 6 frames × 300ms = 1.8s de silêncio
    const double ampThresholdDb = -40.0;

    _vadTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (!_isRecording || !_connected) return;
      totalFrames++;

      try {
        final amp = await _recorder.getAmplitude();
        final db = amp.current; // dB, negativo = silêncio

        if (db < ampThresholdDb) {
          silentFrames++;
        } else {
          silentFrames = 0; // reset se detectar fala
        }

        // Só para após ter gravado pelo menos 1s de fala (totalFrames > 3)
        // e depois detectar silêncio prolongado
        if (silentFrames >= silenceThreshold && totalFrames > 4) {
          _stopHandsFreeRecording();
        }
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
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(36),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  // Barra de capítulos
                  Expanded(
                    child: ChapterProgressBar(
                      progress: _bookProgress,
                      totalChapters: widget.book.chapters > 0
                          ? widget.book.chapters
                          : 10,
                      currentChapter: _currentChapter,
                      height: 6,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // % do livro
                  Text(
                    '${(_bookProgress * 100).toInt()}%',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  const SizedBox(width: 10),
                  // Score
                  Icon(Icons.star_rounded,
                      size: 12, color: Colors.amber.shade400),
                  const SizedBox(width: 3),
                  Text(
                    '$_sessionScore',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  const SizedBox(width: 8),
                  // Conexão
                  Icon(
                    _connected ? Icons.circle : Icons.circle_outlined,
                    size: 7,
                    color: _connected ? Colors.green : Colors.red,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            // Hands-free toggle
            IconButton(
              icon: Icon(
                  _handsFree ? Icons.hearing : Icons.hearing_disabled),
              tooltip: 'Hands-free',
              color: _handsFree ? const Color(0xFF5C7A3E) : null,
              onPressed: _toggleHandsFree,
            ),
          ],
        ),
        body: Column(
          children: [
            if (_connecting) const LinearProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF5C7A3E)),
            ),
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

            // Input — Lei de Hick: simples, focado
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    // Hands-free ativo: mic grande e central, sem campo de texto
    if (_handsFree) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
                color: Colors.white.withOpacity(0.08)),
          ),
        ),
        child: Center(child: _buildMicButton()),
      );
    }

    // Modo manual: campo de texto + mic pequeno
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
      child: Row(
        children: [
          _buildMicButton(),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _textCtrl,
              decoration: InputDecoration(
                hintText: 'Escreva sua resposta...',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.07),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14),
              onSubmitted: (_) => _sendText(),
              maxLines: null,
            ),
          ),
          const SizedBox(width: 8),
          // Botão enviar — só ativo quando há texto
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _textCtrl,
            builder: (_, val, __) => AnimatedOpacity(
              opacity: val.text.isNotEmpty ? 1.0 : 0.3,
              duration: const Duration(milliseconds: 200),
              child: IconButton(
                icon: const Icon(Icons.send_rounded,
                    color: Color(0xFF5C7A3E)),
                onPressed:
                    _connected && val.text.isNotEmpty ? _sendText : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMicButton() {
    if (_handsFree && _isRecording) {
      // Mic GRANDE pulsando — gravando em hands-free (Lei de Fitts)
      return AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, child) => Transform.scale(
          scale: _pulseAnim.value,
          child: GestureDetector(
            onTap: _stopHandsFreeRecording,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF5C7A3E),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.mic, color: Colors.white, size: 36),
            ),
          ),
        ),
      );
    }

    if (_handsFree && _tutorSpeaking) {
      return Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF5C7A3E).withOpacity(0.12),
          border: Border.all(color: const Color(0xFF5C7A3E), width: 2),
        ),
        child: const Icon(Icons.volume_up,
            color: Color(0xFF5C7A3E), size: 32),
      );
    }

    if (_handsFree) {
      // Aguardando input — mic standby grande
      return GestureDetector(
        onTap: _toggleHandsFree,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.green.withOpacity(0.15),
            border: Border.all(color: Colors.green, width: 2),
          ),
          child: const Icon(Icons.mic_none, color: Colors.green, size: 32),
        ),
      );
    }

    // Modo manual (long-press) — mic pequeno na barra
    return GestureDetector(
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) => _stopRecording(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isRecording
              ? Colors.red.withOpacity(0.15)
              : Colors.white.withOpacity(0.07),
        ),
        child: Icon(
          _isRecording ? Icons.mic : Icons.mic_none,
          size: 20,
          color: _isRecording ? Colors.red : Colors.white60,
        ),
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

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 4, bottom: 4,
          left: isUser ? 48 : 0,
          right: isUser ? 0 : 48,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF5C7A3E)
              : const Color(0xFFEDE8E0),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: isUser ? null : Border.all(
            color: Colors.white.withOpacity(0.06),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            fontSize: 15,
            height: 1.55,
            color: isUser ? Colors.white : const Color(0xFF2A2A2A),
            fontWeight: isUser ? FontWeight.w500 : FontWeight.normal,
          ),
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
        margin: const EdgeInsets.only(top: 4, bottom: 4, right: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFEDE8E0),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(delay: 0),
            const SizedBox(width: 4),
            _Dot(delay: 150),
            const SizedBox(width: 4),
            _Dot(delay: 300),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(
      width: 7, height: 7,
      decoration: const BoxDecoration(
        color: Color(0xFF5C7A3E),
        shape: BoxShape.circle,
      ),
    ),
  );
}
