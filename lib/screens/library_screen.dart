import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/book.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

// Paleta de cores por livro — rotação
const _cardColors = [
  Color(0xFFFF6B6B), // vermelho coral
  Color(0xFFFFD93D), // amarelo vivo
  Color(0xFF6BCB77), // verde
  Color(0xFF4D96FF), // azul
  Color(0xFFFF922B), // laranja
  Color(0xFFCC5DE8), // roxo
  Color(0xFF20C997), // teal
  Color(0xFFF59E0B), // âmbar
];

Color _cardColor(int index) => _cardColors[index % _cardColors.length];

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Book> _books = [];
  Set<String> _dueBookIds = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        ApiService.fetchLibrary(),
        ApiService.fetchDueBooks(),
      ]);
      setState(() {
        _books = results[0] as List<Book>;
        _dueBookIds = Set<String>.from(
          (results[1] as List<dynamic>).map((b) => b['book_id'] as String),
        );
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'epub', 'jpg', 'png'],
    );
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    final name = result.files.single.name;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(children: [
          SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2,
              color: Color(0xFFF59E0B))),
          SizedBox(width: 12),
          Text('Analisando livro... pode levar 30s',
            style: TextStyle(color: Colors.white)),
        ]),
        backgroundColor: const Color(0xFF1A1A2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 40),
      ),
    );

    try {
      final book = await ApiService.uploadFile(path, name);
      setState(() => _books.insert(0, book));
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${book.emoji} ${book.title} adicionado!',
              style: const TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFF1A1A2E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao processar. Tente novamente.',
              style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.red.shade900,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _delete(Book book) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remover livro?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('${book.emoji} ${book.title}',
          style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar',
              style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ApiService.deleteBook(book.id);
    setState(() => _books.remove(book));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 20, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'My library ',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1,
                                height: 1.1,
                              )),
                            if (_books.isNotEmpty)
                              TextSpan(
                                text: '+',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.3),
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                )),
                          ],
                        )),
                        if (_books.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${_books.length} livro${_books.length != 1 ? "s" : ""}',
                              style: const TextStyle(
                                color: Colors.white38, fontSize: 14),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(children: [
                    _HeaderBtn(icon: Icons.settings_outlined,
                      onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()))),
                    const SizedBox(width: 4),
                    _HeaderBtn(icon: Icons.refresh_rounded, onTap: _load),
                  ]),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Body ────────────────────────────────────────────────────
            Expanded(
              child: _loading
                ? const Center(child: CircularProgressIndicator(
                    color: Color(0xFFF59E0B)))
                : _error != null
                  ? _buildError()
                  : _books.isEmpty
                    ? _buildEmpty()
                    : _buildList(),
            ),
          ],
        ),
      ),

      // ── FAB ─────────────────────────────────────────────────────────
      floatingActionButton: GestureDetector(
        onTap: _upload,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3),
                blurRadius: 20, offset: const Offset(0, 8)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.add_rounded, color: Color(0xFF0F0F1A), size: 22),
              SizedBox(width: 8),
              Text('Adicionar livro',
                style: TextStyle(
                  color: Color(0xFF0F0F1A),
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 56, color: Colors.white24),
            const SizedBox(height: 16),
            const Text('Sem conexão com o servidor',
              style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF59E0B),
                side: const BorderSide(color: Color(0xFFF59E0B)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12)),
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Text('📚', style: TextStyle(fontSize: 64)),
          SizedBox(height: 20),
          Text('Sua biblioteca está vazia',
            style: TextStyle(color: Colors.white, fontSize: 20,
              fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Toque em + para adicionar um livro',
            style: TextStyle(color: Colors.white38, fontSize: 14)),
          SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: _books.length,
      itemBuilder: (context, i) => _BookCard(
        book: _books[i],
        color: _cardColor(i),
        isDue: _dueBookIds.contains(_books[i].id),
        onTap: () async {
          await Navigator.push(context,
            MaterialPageRoute(builder: (_) => ChatScreen(book: _books[i])));
          _load();
        },
        onDelete: () => _delete(_books[i]),
      ),
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.white54, size: 20),
    ),
  );
}

class _BookCard extends StatelessWidget {
  final Book book;
  final Color color;
  final bool isDue;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _BookCard({
    required this.book,
    required this.color,
    required this.isDue,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Cor de texto: preto para cores claras, branco para escuras
    final luminance = color.computeLuminance();
    final textColor = luminance > 0.4 ? Colors.black87 : Colors.white;
    final subColor = luminance > 0.4
        ? Colors.black.withOpacity(0.5)
        : Colors.white.withOpacity(0.6);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Emoji grande
              Text(book.emoji, style: const TextStyle(fontSize: 44)),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        height: 1.2,
                      )),
                    const SizedBox(height: 6),
                    Text(book.author,
                      style: TextStyle(color: subColor, fontSize: 13)),
                    const SizedBox(height: 10),
                    // Tags
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (book.chapters > 0)
                          _Tag(
                            label: '${book.chapters} cap.',
                            textColor: textColor,
                            bgColor: Colors.black.withOpacity(0.12)),
                        if (isDue)
                          _Tag(
                            label: '📅 Revisar',
                            textColor: Colors.white,
                            bgColor: Colors.red.shade800),
                        _Tag(
                          label: book.added.isNotEmpty
                            ? book.added.substring(0, 7) : 'novo',
                          textColor: subColor,
                          bgColor: Colors.black.withOpacity(0.08)),
                      ],
                    ),
                  ],
                ),
              ),

              // Botão X
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close_rounded,
                    color: textColor.withOpacity(0.7), size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color textColor;
  final Color bgColor;

  const _Tag({
    required this.label,
    required this.textColor,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        )),
    );
  }
}
