import 'package:flutter/material.dart';
import 'screens/library_screen.dart';

void main() {
  runApp(const ReadingMateApp());
}

// Paleta ReadingMate — grafite escuro + âmbar (inspirado em Zest/Dribbble)
const _seed = Color(0xFF5C7A3E); // verde oliva — identidade ReadingMate

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

  // Tipografia: Georgia/serif para corpo (leitura), sistema para UI
  final textTheme = ThemeData(brightness: brightness).textTheme.copyWith(
    bodyLarge: TextStyle(
      fontFamily: 'Georgia',
      fontSize: 15,
      height: 1.6,
      color: brightness == Brightness.dark ? Colors.white : Colors.black87,
    ),
    bodyMedium: TextStyle(
      fontFamily: 'Georgia',
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
          ? const Color(0xFF0D0D1A)
          : const Color(0xFFF5F5F5),
      foregroundColor: brightness == Brightness.dark
          ? Colors.white
          : Colors.black87,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: brightness == Brightness.dark ? Colors.white : Colors.black87,
      ),
    ),
    // Scaffold com fundo grafite profundo
    scaffoldBackgroundColor: brightness == Brightness.dark
        ? const Color(0xFF1A1A14)
        : const Color(0xFFF7F3EE),
    // Cards
    cardTheme: CardTheme(
      color: brightness == Brightness.dark
          ? const Color(0xFF1E1E2E)
          : const Color(0xFFFFFFFF),
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
