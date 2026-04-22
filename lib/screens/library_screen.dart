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
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await Future.wait([ApiService.fetchLibrary(), ApiService.fetchDueBooks()]);
      setState(() {
        _books = r[0] as List<Book>;
        _dueBookIds = Set<String>.from((r[1] as List).map((b) => b['book_id'] as String));
        _loading = false;
      });
    } catch (e) { setState(() { _error = e.toString(); _loading = false; }); }
  }

  Future<void> _upload() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf','epub','jpg','png']);
    if (res == null || res.files.single.path == null) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(children: [
        SizedBox(width:14, height:14,
          child: CircularProgressIndicator(strokeWidth:2, color: Color(0xFFF59E0B))),
        SizedBox(width:10),
        Text('Analisando...', style: TextStyle(color: Colors.white70)),
      ]),
      backgroundColor: const Color(0xFF1C1C1E),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 40),
    ));
    try {
      final book = await ApiService.uploadFile(res.files.single.path!, res.files.single.name);
      setState(() => _books.insert(0, book));
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${book.emoji} Adicionado!', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF1C1C1E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Erro. Tente novamente.', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.red.shade900, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  Future<void> _delete(Book book) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Remover?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      content: Text('${book.emoji} ${book.title}', style: const TextStyle(color: Colors.white54)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white38))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF453A)),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remover')),
      ],
    ));
    if (ok != true) return;
    await ApiService.deleteBook(book.id);
    setState(() => _books.remove(book));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Biblioteca', style: TextStyle(
                color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800,
                letterSpacing: -1.2, height: 1.0)),
              const SizedBox(height: 4),
              Text(_books.isEmpty ? 'Nenhum livro ainda'
                  : '${_books.length} livro${_books.length != 1 ? "s" : ""}',
                style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 15)),
            ])),
            GestureDetector(
              onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
              child: Container(width:38, height:38,
                decoration: BoxDecoration(color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.settings_outlined, color: Color(0xFF8E8E93), size:18)),
            ),
            const SizedBox(width: 8),
            GestureDetector(onTap: _load,
              child: Container(width:38, height:38,
                decoration: BoxDecoration(color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.refresh_rounded, color: Color(0xFF8E8E93), size:18)),
            ),
          ]),
        ),
        const SizedBox(height: 20),

        // ── Content ─────────────────────────────────────────────────────────
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
          : _error != null ? _buildError()
          : _books.isEmpty ? _buildEmpty()
          : _buildList()),
      ])),

      // ── Bottom Nav + FAB area ────────────────────────────────────────────
      bottomNavigationBar: Container(
        height: 82,
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          border: Border(top: BorderSide(color: Color(0xFF2C2C2E))),
        ),
        child: Row(children: [
          Expanded(child: _NavItem(icon: Icons.library_books_rounded, label: 'Biblioteca', active: true)),
          Expanded(child: _NavItem(icon: Icons.bar_chart_rounded, label: 'Progresso', active: false)),
          const SizedBox(width: 72),
          Expanded(child: _NavItem(icon: Icons.search_rounded, label: 'Buscar', active: false)),
          Expanded(child: _NavItem(icon: Icons.person_outline_rounded, label: 'Perfil', active: false)),
        ]),
      ),
      floatingActionButton: GestureDetector(
        onTap: _upload,
        child: Container(
          width: 56, height: 56,
          decoration: const BoxDecoration(
            color: Color(0xFFF59E0B),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x80F59E0B), blurRadius: 20, offset: Offset(0,6))],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.black, size: 28),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildError() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFF3A3A3C)),
    const SizedBox(height: 12),
    const Text('Sem conexão', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16)),
    const SizedBox(height: 20),
    TextButton(onPressed: _load, child: const Text('Tentar novamente',
      style: TextStyle(color: Color(0xFFF59E0B)))),
  ]));

  Widget _buildEmpty() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 100, height: 100,
      decoration: BoxDecoration(color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(28)),
      child: const Center(child: Text('📚', style: TextStyle(fontSize: 48)))),
    const SizedBox(height: 20),
    const Text('Biblioteca vazia', style: TextStyle(
      color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 6),
    const Text('Toque em + para adicionar um livro',
      style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
    const SizedBox(height: 120),
  ]));

  Widget _buildList() => ListView.builder(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
    itemCount: _books.length,
    itemBuilder: (ctx, i) => _BookRow(
      book: _books[i], isDue: _dueBookIds.contains(_books[i].id),
      onTap: () async {
        await Navigator.push(ctx, MaterialPageRoute(builder: (_) => ChatScreen(book: _books[i])));
        _load();
      },
      onDelete: () => _delete(_books[i]),
    ),
  );
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _NavItem({required this.icon, required this.label, required this.active});
  @override
  Widget build(BuildContext context) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(icon, color: active ? const Color(0xFFF59E0B) : const Color(0xFF3A3A3C), size: 24),
    const SizedBox(height: 3),
    Text(label, style: TextStyle(
      color: active ? const Color(0xFFF59E0B) : const Color(0xFF3A3A3C),
      fontSize: 10, fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
  ]);
}

class _BookRow extends StatelessWidget {
  final Book book;
  final bool isDue;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _BookRow({required this.book, required this.isDue, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 1),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF1C1C1E))),
        ),
        child: Row(children: [
          // Cover
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(book.emoji, style: const TextStyle(fontSize: 28)))),
          const SizedBox(width: 14),
          // Info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.w600, letterSpacing: -0.2)),
            const SizedBox(height: 3),
            Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13)),
            if (book.chapters > 0 || isDue) ...[
              const SizedBox(height: 6),
              Row(children: [
                if (book.chapters > 0)
                  _Chip('${book.chapters} cap.', const Color(0xFF2C2C2E), const Color(0xFF8E8E93)),
                if (book.chapters > 0 && isDue) const SizedBox(width: 6),
                if (isDue) _Chip('Revisar', const Color(0xFF3A1A00), const Color(0xFFF59E0B)),
              ]),
            ],
          ])),
          const SizedBox(width: 8),
          // Actions
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF3A3A3C), size: 20),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onDelete,
              child: Container(width: 28, height: 28,
                decoration: BoxDecoration(color: const Color(0xFF1C1C1E), shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, color: Color(0xFF8E8E93), size: 14)),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Chip(this.label, this.bg, this.fg);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}
