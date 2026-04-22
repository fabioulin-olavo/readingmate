import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/book.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

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
        content: const Row(
          children: [
            SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B))),
            SizedBox(width: 12),
            Text('Analisando livro... pode levar 30s',
              style: TextStyle(color: Colors.white)),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 35),
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
            backgroundColor: const Color(0xFF1E1E2E),
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
            content: Text('Erro: $e', style: const TextStyle(color: Colors.white)),
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
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remover livro?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('${book.emoji} ${book.title}',
          style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
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
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Minha Biblioteca',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          )),
                        const SizedBox(height: 4),
                        Text(
                          _books.isEmpty
                              ? 'Adicione seu primeiro livro'
                              : '${_books.length} livro${_books.length != 1 ? "s" : ""}',
                          style: const TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, color: Colors.white54),
                    onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
                    onPressed: _load,
                  ),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────────────────
            Expanded(
              child: _loading
                ? const Center(child: CircularProgressIndicator(
                    color: Color(0xFFF59E0B)))
                : _error != null
                  ? _buildError()
                  : _books.isEmpty
                    ? _buildEmpty()
                    : _buildGrid(),
            ),
          ],
        ),
      ),

      // ── FAB ─────────────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _upload,
        backgroundColor: const Color(0xFFF59E0B),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text('Adicionar livro',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        elevation: 8,
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
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF59E0B),
                side: const BorderSide(color: Color(0xFFF59E0B)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
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
        children: [
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Center(
              child: Text('📚', style: TextStyle(fontSize: 52))),
          ),
          const SizedBox(height: 24),
          const Text('Sua biblioteca está vazia',
            style: TextStyle(color: Colors.white, fontSize: 20,
              fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Toque em + para adicionar um livro',
            style: TextStyle(color: Colors.white38, fontSize: 14)),
          const SizedBox(height: 80), // espaço pro FAB
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      itemCount: _books.length,
      itemBuilder: (context, i) => _BookCard(
        book: _books[i],
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

class _BookCard extends StatelessWidget {
  final Book book;
  final bool isDue;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _BookCard({
    required this.book,
    required this.isDue,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.06),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // Emoji / capa
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A3E),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(book.emoji,
                    style: const TextStyle(fontSize: 36)),
                ),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isDue)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('📅 Revisar hoje',
                          style: TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          )),
                      ),
                    Text(book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      )),
                    const SizedBox(height: 4),
                    Text(book.author,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                      )),
                    if (book.chapters > 0) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.menu_book_rounded,
                            size: 12, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 4),
                          Text('${book.chapters} capítulos',
                            style: const TextStyle(
                              color: Color(0xFFF59E0B),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            )),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Ações
              Column(
                children: [
                  const Icon(Icons.chevron_right_rounded,
                    color: Colors.white24, size: 24),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.close_rounded,
                        color: Colors.white38, size: 16),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
