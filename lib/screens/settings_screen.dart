import 'package:flutter/material.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _ctrl = TextEditingController();
  bool _saved = false;
  String _selectedLang = 'en';

  static const _languages = [
    ('en', '🇬🇧 English'),
    ('pt', '🇧🇷 Português'),
    ('ja', '🇯🇵 日本語'),
    ('zh', '🇨🇳 中文'),
    ('ko', '🇰🇷 한국어'),
    ('ru', '🇷🇺 Русский'),
    ('fr', '🇫🇷 Français'),
    ('es', '🇪🇸 Español'),
    ('de', '🇩🇪 Deutsch'),
  ];

  @override
  void initState() {
    super.initState();
    ApiService.getBaseUrl().then((url) => _ctrl.text = url);
    ApiService.getPreferredLanguage().then((lang) {
      if (mounted) setState(() => _selectedLang = lang);
    });
  }

  Future<void> _save() async {
    await ApiService.setBaseUrl(_ctrl.text.trim());
    await ApiService.setPreferredLanguage(_selectedLang);
    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Idioma preferencial ───────────────────────────────────
            const Text('Idioma preferencial',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            const Text(
              'Idioma padrão para as aulas do tutor.',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _selectedLang,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: _languages.map((l) => DropdownMenuItem(
                value: l.$1,
                child: Text(l.$2),
              )).toList(),
              onChanged: (v) { if (v != null) setState(() => _selectedLang = v); },
            ),

            const SizedBox(height: 24),

            // ── URL do backend ────────────────────────────────────────
            const Text('URL do backend',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                hintText: 'http://54.180.201.135:8765',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: Text(_saved ? '✓ Salvo!' : 'Salvar configurações'),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'O idioma pode ser alterado a cada livro ao abri-lo.',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
