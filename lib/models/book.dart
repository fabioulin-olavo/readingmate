class Book {
  final String id;
  final String title;
  final String author;
  final String emoji;
  final String added;
  final int chapters;
  final String? coverUrl; // URL relativa ex: /api/cover/abc123

  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.emoji,
    required this.added,
    required this.chapters,
    this.coverUrl,
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    final id = json['id'] ?? json['book_id'] ?? '';
    final added = json['created_at'] ?? json['added'] ?? '';

    int chapterCount = 0;
    if (json['chapters'] != null) {
      chapterCount = json['chapters'];
    } else if (json['outline'] != null && json['outline']['chapters'] != null) {
      chapterCount = (json['outline']['chapters'] as List).length;
    }

    return Book(
      id: id,
      title: json['title'] ?? 'Untitled',
      author: json['author'] ?? 'Unknown',
      emoji: json['emoji'] ?? '📚',
      added: added,
      chapters: chapterCount,
      coverUrl: json['cover_url'] as String?,
    );
  }
}
