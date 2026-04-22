import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/library_screen.dart';

void main() {
  runApp(const ReadingMateApp());
}

// Paleta ReadingMate — âmbar/sépia (foco, leitura)
const _seed = Color(0xFFD97706); // âmbar

class ReadingMateApp extends StatelessWidget {
  const ReadingMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ReadingMate',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const LibraryScreen(),
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
  );

  // Tipografia: Merriweather para corpo (leitura), Inter para UI
  final textTheme = GoogleFonts.interTextTheme(
    ThemeData(brightness: brightness).textTheme,
  ).copyWith(
    // Mensagens do tutor — serifa, mais "livro"
    bodyLarge: GoogleFonts.merriweather(
      fontSize: 15,
      height: 1.6,
      color: brightness == Brightness.dark ? Colors.white : Colors.black87,
    ),
    bodyMedium: GoogleFonts.merriweather(
      fontSize: 14,
      height: 1.5,
      color: brightness == Brightness.dark
          ? Colors.white70
          : Colors.black.withOpacity(0.75),
    ),
  );

  return ThemeData(
    colorScheme: colorScheme,
    textTheme: textTheme,
    useMaterial3: true,
    // AppBar discreta
    appBarTheme: AppBarTheme(
      backgroundColor: brightness == Brightness.dark
          ? const Color(0xFF1A1612)
          : const Color(0xFFFFF8EE),
      foregroundColor: brightness == Brightness.dark
          ? Colors.white
          : Colors.black87,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: brightness == Brightness.dark ? Colors.white : Colors.black87,
      ),
    ),
    // Scaffold com fundo sépia escuro
    scaffoldBackgroundColor: brightness == Brightness.dark
        ? const Color(0xFF1A1612)
        : const Color(0xFFFFF8EE),
    // Cards
    cardTheme: CardTheme(
      color: brightness == Brightness.dark
          ? const Color(0xFF2A2218)
          : const Color(0xFFFFF3DC),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: brightness == Brightness.dark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.08),
        ),
      ),
    ),
    // FAB âmbar
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: _seed,
      foregroundColor: Colors.white,
    ),
    // FilledButton âmbar
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _seed,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}
