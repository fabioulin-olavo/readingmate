import 'package:flutter/material.dart';

/// Barra de progresso do livro com tracinhos em cada capítulo/seção.
///
/// Exemplo:
///   |━━━━━━━━|┆    ┆    ┆    ┆    |
///        ↑ progresso atual
///              ↑ marcadores de capítulo
class ChapterProgressBar extends StatelessWidget {
  /// Progresso atual (0.0 a 1.0)
  final double progress;

  /// Número total de capítulos/seções
  final int totalChapters;

  /// Capítulo atual (0-indexed)
  final int currentChapter;

  /// Altura da barra
  final double height;

  const ChapterProgressBar({
    super.key,
    required this.progress,
    required this.totalChapters,
    required this.currentChapter,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(double.infinity, height + 8),
      painter: _ProgressPainter(
        progress: progress.clamp(0.0, 1.0),
        totalChapters: totalChapters,
        currentChapter: currentChapter,
        barHeight: height,
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  final double progress;
  final int totalChapters;
  final int currentChapter;
  final double barHeight;

  const _ProgressPainter({
    required this.progress,
    required this.totalChapters,
    required this.currentChapter,
    required this.barHeight,
  });

  static const _amber = Color(0xFFF59E0B);
  static const _trackColor = Color(0xFF3A3228);
  static const _tickDone = Color(0xFFF59E0B);
  static const _tickFuture = Color(0xFF5A5248);
  static const _tickCurrent = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final barTop = cy - barHeight / 2;
    final barRect = Rect.fromLTWH(0, barTop, size.width, barHeight);

    // 1. Trilha de fundo
    final trackPaint = Paint()
      ..color = _trackColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, const Radius.circular(3)),
      trackPaint,
    );

    // 2. Preenchimento do progresso
    if (progress > 0) {
      final fillRect = Rect.fromLTWH(0, barTop, size.width * progress, barHeight);
      final fillPaint = Paint()
        ..shader = LinearGradient(
          colors: [_amber, const Color(0xFFF59E0B)],
        ).createShader(fillRect)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, const Radius.circular(3)),
        fillPaint,
      );
    }

    // 3. Marcadores de capítulo (tracinhos verticais)
    if (totalChapters > 1) {
      for (int i = 1; i < totalChapters; i++) {
        final x = size.width * i / totalChapters;
        final isCurrent = i == currentChapter;
        final isDone = i < currentChapter || (progress * totalChapters) >= i;

        Color tickColor;
        double tickHeight;
        double tickWidth;

        if (isCurrent) {
          tickColor = _tickCurrent;
          tickHeight = barHeight + 6;
          tickWidth = 1.5;
        } else if (isDone) {
          tickColor = _tickDone.withOpacity(0.6);
          tickHeight = barHeight;
          tickWidth = 1.0;
        } else {
          tickColor = _tickFuture;
          tickHeight = barHeight;
          tickWidth = 1.0;
        }

        final tickPaint = Paint()
          ..color = tickColor
          ..strokeWidth = tickWidth
          ..style = PaintingStyle.stroke;

        canvas.drawLine(
          Offset(x, cy - tickHeight / 2),
          Offset(x, cy + tickHeight / 2),
          tickPaint,
        );
      }
    }

    // 4. Indicador de posição atual (bolinha âmbar)
    if (progress > 0 && progress < 1) {
      final dotX = size.width * progress;
      final dotPaint = Paint()
        ..color = _amber
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(dotX, cy), barHeight / 2 + 1.5, dotPaint);

      // Halo
      final haloPaint = Paint()
        ..color = _amber.withOpacity(0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(dotX, cy), barHeight / 2 + 4, haloPaint);
    }
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.progress != progress ||
      old.totalChapters != totalChapters ||
      old.currentChapter != currentChapter;
}
