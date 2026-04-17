enum MessageRole { user, tutor }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String text;
  final String? audioBase64;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.audioBase64,
    required this.timestamp,
  });
}
