import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/book.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

// Resolve a URL completa da capa
Future<String> _baseUrl() => ApiService.getBaseUrl();

// Paleta de capas geradas — 8 cores harmônicas, identidade própria ReadingMate
const _coverColors = [
  Color(0xFF5C7A3E), // verde oliva
  Color(0xFF3A5F7A), // azul sereno
  Color(0xFF8B4513), // castanho terra
  Color(0xFF6B4C7A), // roxo suave
  Color(0xFF2E6B5E), // verde água
  Color(0xFF7A4A3A), // terracota
  Color(0xFF4A6B8B), // azul aço
  Color(0xFF6B6B3A), // verde musgo
];
Color _coverColor(String id) => _coverColors[id.hashCode.abs() % _coverColors.length];

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
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

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
          child: CircularProgressIndicator(strokeWidth:2, color: Color(0xFF5C7A3E))),
        SizedBox(width:10),
        Text('Analisando livro... 30s'),
      ]),
      backgroundColor: Colors.white,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE8E0D8)),
      ),
      duration: const Duration(seconds: 40),
    ));
    try {
      final book = await ApiService.uploadFile(res.files.single.path!, res.files.single.name);
      setState(() => _books.insert(0, book));
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${book.emoji} ${book.title} adicionado!'),
          backgroundColor: Colors.white,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF5C7A3E)),
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Erro ao processar. Tente novamente.'),
          backgroundColor: Colors.red.shade100,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  Future<void> _delete(Book book) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFFFEFCF8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Remover livro?',
        style: TextStyle(color: Color(0xFF2A2A2A), fontWeight: FontWeight.bold)),
      content: Text('${book.emoji} ${book.title}',
        style: const TextStyle(color: Color(0xFF6B6B6B))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar', style: TextStyle(color: Color(0xFF6B6B6B)))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remover')),
      ],
    ));
    if (ok != true) return;
    await ApiService.deleteBook(book.id);
    setState(() => _books.remove(book));
  }

  List<Book> get _filtered => _query.isEmpty ? _books
    : _books.where((b) =>
        b.title.toLowerCase().contains(_query.toLowerCase()) ||
        b.author.toLowerCase().contains(_query.toLowerCase())).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F3EE),
      body: SafeArea(child: Column(children: [
        // ── Header ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Minha Biblioteca',
                style: TextStyle(color: Color(0xFF1A1A1A), fontSize: 26,
                  fontWeight: FontWeight.w800, letterSpacing: -0.8)),
              if (_books.isNotEmpty)
                Text('${_books.length} livro${_books.length != 1 ? "s" : ""}',
                  style: const TextStyle(color: Color(0xFF8E8682), fontSize: 13)),
            ])),
            GestureDetector(
              onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
              child: Container(width:36, height:36,
                decoration: BoxDecoration(color: const Color(0xFFEDE8E0),
                  borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.settings_outlined,
                  color: Color(0xFF6B6B6B), size: 18)),
            ),
            const SizedBox(width: 8),
            GestureDetector(onTap: _load,
              child: Container(width:36, height:36,
                decoration: BoxDecoration(color: const Color(0xFFEDE8E0),
                  borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.refresh_rounded,
                  color: Color(0xFF6B6B6B), size: 18)),
            ),
          ]),
        ),

        // ── Busca ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE8E0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Buscar livros...',
                hintStyle: TextStyle(color: Color(0xFF9E9892), fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded, color: Color(0xFF9E9892), size: 18),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // ── Grid ─────────────────────────────────────────────────────────
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF5C7A3E)))
          : _error != null ? _buildError()
          : _filtered.isEmpty ? _buildEmpty()
          : _buildGrid()),
      ])),

      // ── Bottom Nav ───────────────────────────────────────────────────
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFEFCF8),
          border: Border(top: BorderSide(color: Color(0xFFE8E0D8))),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(height: 60, child: Row(children: [
            _NavBtn(icon: Icons.library_books_rounded, label: 'Biblioteca',
              active: true, color: const Color(0xFF5C7A3E)),
            _NavBtn(icon: Icons.show_chart_rounded, label: 'Progresso',
              active: false, color: const Color(0xFF5C7A3E)),
            const SizedBox(width: 64), // espaço pro FAB
            _NavBtn(icon: Icons.search_rounded, label: 'Buscar',
              active: false, color: const Color(0xFF5C7A3E)),
            _NavBtn(icon: Icons.person_outline_rounded, label: 'Perfil',
              active: false, color: const Color(0xFF5C7A3E)),
          ])),
        ),
      ),
      floatingActionButton: GestureDetector(
        onTap: _upload,
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF5C7A3E),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(
              color: const Color(0xFF5C7A3E).withOpacity(0.4),
              blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildError() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFCCC5BC)),
    const SizedBox(height: 12),
    const Text('Sem conexão com o servidor',
      style: TextStyle(color: Color(0xFF8E8682), fontSize: 15)),
    const SizedBox(height: 16),
    TextButton(onPressed: _load,
      child: const Text('Tentar novamente',
        style: TextStyle(color: Color(0xFF5C7A3E)))),
  ]));

  Widget _buildEmpty() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 96, height: 96,
      decoration: BoxDecoration(color: const Color(0xFFEDE8E0),
        borderRadius: BorderRadius.circular(24)),
      child: const Center(child: Text('📚', style: TextStyle(fontSize: 44)))),
    const SizedBox(height: 20),
    const Text('Biblioteca vazia',
      style: TextStyle(color: Color(0xFF1A1A1A), fontSize: 20,
        fontWeight: FontWeight.bold)),
    const SizedBox(height: 6),
    const Text('Toque em + para adicionar seu primeiro livro',
      style: TextStyle(color: Color(0xFF8E8682), fontSize: 13)),
    const SizedBox(height: 100),
  ]));

  Widget _buildGrid() => GridView.builder(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 16,
      crossAxisSpacing: 12,
      childAspectRatio: 0.62,
    ),
    itemCount: _filtered.length,
    itemBuilder: (ctx, i) => _BookCover(
      book: _filtered[i],
      color: _coverColor(_filtered[i].id),
      isDue: _dueBookIds.contains(_filtered[i].id),
      onTap: () async {
        await Navigator.push(ctx,
          MaterialPageRoute(builder: (_) => ChatScreen(book: _filtered[i])));
        _load();
      },
      onLongPress: () => _delete(_filtered[i]),
    ),
  );
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color color;
  const _NavBtn({required this.icon, required this.label,
    required this.active, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(child:
    Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 22,
        color: active ? color : const Color(0xFFBDB7B0)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(
        fontSize: 10,
        color: active ? color : const Color(0xFFBDB7B0),
        fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
    ]));
}

class _BookCover extends StatelessWidget {
  final Book book;
  final Color color;
  final bool isDue;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _BookCover({required this.book, required this.color,
    required this.isDue, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Capa — real se disponível, gerada caso contrário
        Expanded(
          child: Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: book.coverUrl != null
                ? _RealCover(book: book, fallbackColor: color)
                : _GeneratedCover(book: book, color: color),
            ),
            // Badge de revisão
            if (isDue)
              Positioned(top: 6, right: 6,
                child: Container(
                  width: 20, height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8A020),
                    shape: BoxShape.circle),
                  child: const Center(
                    child: Text('!', style: TextStyle(
                      color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.bold))))),
          ]),
        ),
        const SizedBox(height: 7),
        // Título abaixo da capa
        Text(book.title,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF1A1A1A),
            fontSize: 11, fontWeight: FontWeight.w600)),
        Text(book.author,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF8E8682), fontSize: 10)),
      ]),
    );
  }
}

class _RealCover extends StatefulWidget {
  final Book book;
  final Color fallbackColor;
  const _RealCover({required this.book, required this.fallbackColor});
  @override
  State<_RealCover> createState() => _RealCoverState();
}

class _RealCoverState extends State<_RealCover> {
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final base = await ApiService.getBaseUrl();
    if (mounted) setState(() => _imageUrl = '$base${widget.book.coverUrl}');
  }

  @override
  Widget build(BuildContext context) {
    if (_imageUrl == null) {
      return _GeneratedCover(book: widget.book, color: widget.fallbackColor);
    }
    return Image.network(
      _imageUrl!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) =>
        _GeneratedCover(book: widget.book, color: widget.fallbackColor),
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(
          color: widget.fallbackColor,
          child: const Center(child: CircularProgressIndicator(
            strokeWidth: 2, color: Colors.white54)),
        );
      },
    );
  }
}

class _GeneratedCover extends StatelessWidget {
  final Book book;
  final Color color;
  const _GeneratedCover({required this.book, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        boxShadow: [BoxShadow(
          color: color.withOpacity(0.35),
          blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        Container(height: 4,
          color: Colors.white.withOpacity(0.25)),
        Expanded(child: Center(
          child: Text(book.emoji, style: const TextStyle(fontSize: 36)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          child: Text(book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white, fontSize: 10,
              fontWeight: FontWeight.w600, height: 1.3,
            )),
        ),
      ]),
    );
  }
}
