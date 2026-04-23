import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';

class ApiService {
  static const _urlKey = 'backend_url';
  static const _defaultUrl = 'http://54.180.201.135:8765'; // Servidor ReadingMate
  static const _langKey = 'preferred_language'; // idioma preferencial do usuário

  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_urlKey) ?? _defaultUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, url);
  }

  /// Idioma preferencial do usuário no app (padrão = idioma do sistema)
  static Future<String> getPreferredLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    // Padrão: idioma do sistema (simplificado para en ou pt)
    final stored = prefs.getString(_langKey);
    if (stored != null) return stored;
    // Detectar idioma do sistema via locale
    final locale = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return locale.startsWith('pt') ? 'pt' : 'en';
  }

  static Future<void> setPreferredLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langKey, lang);
  }

  static Future<List<Book>> fetchLibrary() async {
    final base = await getBaseUrl();
    final res = await http.get(Uri.parse('$base/api/library'));
    if (res.statusCode != 200) throw Exception('Library fetch failed');
    final List<dynamic> data = jsonDecode(res.body);
    return data.map((j) => Book.fromJson(j)).toList();
  }

  static Future<Book> uploadFile(String filePath, String fileName) async {
    final base = await getBaseUrl();
    final request = http.MultipartRequest('POST', Uri.parse('$base/api/upload'));
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) throw Exception('Upload failed: $body');
    return Book.fromJson(jsonDecode(body));
  }

  static Future<void> deleteBook(String bookId) async {
    final base = await getBaseUrl();
    await http.delete(Uri.parse('$base/api/library/$bookId'));
  }

  static Future<List<dynamic>> fetchDueBooks() async {
    try {
      final base = await getBaseUrl();
      final res = await http.get(Uri.parse('$base/api/reviews'));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      return (data['due_books'] as List<dynamic>?) ?? [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> submitReviewScore(String bookId, double score) async {
    try {
      final base = await getBaseUrl();
      await http.post(
        Uri.parse('$base/api/review/$bookId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'score': score}),
      );
    } catch (_) {}
  }

  static Future<String> getWsUrl(String bookId) async {
    final base = await getBaseUrl();
    final wsBase = base.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
    return '$wsBase/ws/$bookId';
  }
}
