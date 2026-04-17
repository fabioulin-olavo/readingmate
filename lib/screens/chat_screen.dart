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

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<ChatMessage> _messages = [];

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _connected = false;
  bool _connecting = false;
  bool _isRecording = false;
  bool _handsFree = false;
  bool _tutorTyping = false;

  final _player = AudioPlayer();
  final _recorder = AudioRecorder();
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
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
      setState(() { _connected = true; _connecting = false; });
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

      setState(() => _tutorTyping = false);

      if (type == 'text' || type == null) {
        _addMessage(ChatMessage(
          id: DateTime.now().toIso8601String(),
          role: MessageRole.tutor,
          text: content,
          timestamp: DateTime.now(),
        ));
      } else if (type == 'audio') {
        _addMessage(ChatMessage(
          id: DateTime.now().toIso8601String(),
          role: MessageRole.tutor,
          text: data['transcript'] ?? '🔊',
          audioBase64: content,
          timestamp: DateTime.now(),
        ));
        _playAudio(content);
      }
    } catch (_) {
      // Ignore parse errors
    }
  }

  Future<void> _playAudio(String base64Audio) async {
    try {
      final bytes = base64Decode(base64Audio);
      await _player.play(BytesSource(bytes));
    } catch (_) {}
  }

  void _handleDisconnect() {
    setState(() { _connected = false; _tutorTyping = false; });
  }

  void _addMessage(ChatMessage msg) {
    setState(() => _messages.add(msg));
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

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    _recordingPath = '${dir.path}/rm_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: _recordingPath!);
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

    _channel!.sink.add(jsonEncode({'type': 'audio', 'content': b64}));
    setState(() => _tutorTyping = true);
    await file.delete();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _channel?.sink.close();
    _player.dispose();
    _recorder.dispose();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.book.emoji} ${widget.book.title}'),
        actions: [
          // Hands-free toggle
          IconButton(
            icon: Icon(_handsFree ? Icons.hearing : Icons.hearing_disabled),
            tooltip: 'Hands-free',
            color: _handsFree ? Colors.green : null,
            onPressed: () => setState(() => _handsFree = !_handsFree),
          ),
          // Connection indicator
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
          // Status bar
          if (_connecting)
            const LinearProgressIndicator(),
          if (!_connected && !_connecting)
            MaterialBanner(
              content: const Text('Desconectado do backend'),
              actions: [
                TextButton(onPressed: _connect, child: const Text('Reconectar')),
              ],
            ),

          // Messages
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.book.emoji, style: const TextStyle(fontSize: 64)),
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
                    itemCount: _messages.length + (_tutorTyping ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (_tutorTyping && i == _messages.length) {
                        return const _TypingBubble();
                      }
                      return _MessageBubble(message: _messages[i]);
                    },
                  ),
          ),

          // Input area
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
            child: Row(
              children: [
                // Voice button
                GestureDetector(
                  onLongPressStart: _handsFree ? null : (_) => _startRecording(),
                  onLongPressEnd: _handsFree ? null : (_) => _stopRecording(),
                  child: IconButton(
                    icon: Icon(_isRecording ? Icons.mic : Icons.mic_none),
                    color: _isRecording ? Colors.red : null,
                    onPressed: _handsFree
                        ? () {
                            if (_isRecording) _stopRecording();
                            else _startRecording();
                          }
                        : null,
                    tooltip: _handsFree ? 'Tap para gravar/parar' : 'Segure para falar',
                  ),
                ),
                // Text field
                Expanded(
                  child: TextField(
                    controller: _textCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Escreva sua pergunta...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onSubmitted: (_) => _sendText(),
                    maxLines: null,
                  ),
                ),
                // Send button
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _connected ? _sendText : null,
                ),
              ],
            ),
          ),
        ],
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? colors.primary : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUser ? const Radius.circular(4) : null,
            bottomLeft: !isUser ? const Radius.circular(4) : null,
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(color: isUser ? colors.onPrimary : colors.onSurfaceVariant),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
        ),
        child: const Text('✍️ digitando...', style: TextStyle(fontStyle: FontStyle.italic)),
      ),
    );
  }
}
