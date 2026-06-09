import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models.dart';

class InteractionHeatStrip extends StatelessWidget {
  final List<InteractionTimelineBucket> timeline;
  final Duration total;
  final double height;
  final ValueChanged<Duration>? onSeek;

  const InteractionHeatStrip({
    super.key,
    required this.timeline,
    required this.total,
    this.height = 18,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: total.inMilliseconds <= 0 || onSeek == null
          ? null
          : (details) {
              final box = context.findRenderObject() as RenderBox?;
              final width = box?.size.width ?? 0;
              if (width <= 0) return;
              final ratio = (details.localPosition.dx / width).clamp(0.0, 1.0);
              onSeek!(Duration(
                milliseconds: (total.inMilliseconds * ratio).round(),
              ));
            },
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _HeatPainter(timeline: timeline, total: total),
        ),
      ),
    );
  }
}

class _HeatPainter extends CustomPainter {
  final List<InteractionTimelineBucket> timeline;
  final Duration total;

  _HeatPainter({required this.timeline, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    if (timeline.isEmpty || total.inMilliseconds <= 0) return;
    if (size.width <= 0 || size.height <= 0) return;
    final maxCount =
        timeline.map((e) => e.count).fold<int>(1, (a, b) => a > b ? a : b);
    final bg = Paint()..color = Colors.white.withValues(alpha: .08);
    final hot = Paint()
      ..shader = AppColors.ctaGradient
          .createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, size.height - 3, size.width, 3),
          const Radius.circular(2)),
      bg,
    );
    for (final bucket in timeline) {
      final start =
          (bucket.tsStart * 1000 / total.inMilliseconds).clamp(0.0, 1.0);
      final end = (bucket.tsEnd * 1000 / total.inMilliseconds).clamp(0.0, 1.0);
      final x = start * size.width;
      final maxWidth = (size.width - x).clamp(0.0, size.width).toDouble();
      if (maxWidth <= 0) continue;
      final minWidth = maxWidth < 2 ? maxWidth : 2.0;
      final w =
          ((end - start) * size.width).clamp(minWidth, maxWidth).toDouble();
      final h = (bucket.count / maxCount).clamp(.12, 1.0) * size.height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, size.height - h, w, h), const Radius.circular(3)),
        hot,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeatPainter oldDelegate) {
    return oldDelegate.timeline != timeline || oldDelegate.total != total;
  }
}
