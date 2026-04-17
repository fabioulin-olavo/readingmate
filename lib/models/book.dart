class Book {
  final String id;
  final String title;
  final String author;
  final String emoji;
  final String added;
  final int chapters;

  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.emoji,
    required this.added,
    required this.chapters,
  });

  factory Book.fromJson(Map<String, dynamic> json) => Book(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        author: json['author'] ?? '',
        emoji: json['emoji'] ?? '📚',
        added: json['added'] ?? '',
        chapters: json['chapters'] ?? 0,
      );
}
