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

  factory Book.fromJson(Map<String, dynamic> json) {
    // Handle both 'id' and 'book_id'
    final id = json['id'] ?? json['book_id'] ?? '';
    
    // Handle 'created_at' from backend and 'added' from frontend/legacy
    final added = json['created_at'] ?? json['added'] ?? '';

    // Handle outline for chapters count if available
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
    );
  }
}
