import 'dart:math';

import 'package:flutter/material.dart';

/// Full-screen AI highlight effects.
///
/// The painter is intentionally asset-free: highlight effects are generated
/// from Canvas primitives so the client can react to AI-detected cues without
/// waiting for Lottie/Rive files to be bundled.
enum HighlightEffectKind {
  ignition,
  fracture,
  tearGlass,
  comedyPop,
  roseBloom,
  spotlight,
  finale,
}

enum HighlightEffectHaptic { light, heavy }

class HighlightEffectSpec {
  final HighlightEffectKind kind;
  final List<Color> colors;
  final String label;
  final Duration duration;
  final HighlightEffectHaptic? haptic;

  const HighlightEffectSpec({
    required this.kind,
    required this.colors,
    required this.label,
    required this.duration,
    this.haptic,
  });
}

class HighlightEffectInstance {
  final AnimationController controller;
  final HighlightEffectSpec spec;
  final double seed;
  final bool remote;
  final double intensity;

  HighlightEffectInstance({
    required this.controller,
    required this.spec,
    required this.seed,
    required this.remote,
    required this.intensity,
  });
}

class HighlightEffectPainter extends CustomPainter {
  final HighlightEffectInstance instance;

  HighlightEffectPainter({required this.instance})
      : super(repaint: instance.controller);

  double get t => instance.controller.value;

  double get _strength {
    final intensity = instance.intensity.clamp(0.0, 1.0).toDouble();
    final floor = instance.remote ? 0.18 : 0.28;
    final span = instance.remote ? 0.14 : 0.28;
    return (floor + intensity * span).clamp(0.18, 0.56).toDouble();
  }

  double get _overlayStrength => _strength * .42;

  double get _flashStrength => _strength * .58;

  double _clamp01(double x) => x.clamp(0.0, 1.0).toDouble();

  double _easeOutCubic(double x) => 1 - pow(1 - _clamp01(x), 3).toDouble();

  double _easeOutQuart(double x) => 1 - pow(1 - _clamp01(x), 4).toDouble();

  double _easeOutBack(double x) {
    final v = _clamp01(x);
    const c1 = 1.70158;
    const c3 = c1 + 1;
    return 1 + c3 * pow(v - 1, 3).toDouble() + c1 * pow(v - 1, 2).toDouble();
  }

  double _fadeAfter(double start) {
    return 1 - _clamp01((t - start) / (1 - start));
  }

  double _u(int index, [double salt = 0]) {
    final value =
        sin(instance.seed * 9281.371 + index * 37.719 + salt * 113.17) *
            43758.5453123;
    return value - value.floorToDouble();
  }

  Color get _primary => instance.spec.colors.first;

  Color get _secondary => instance.spec.colors.length > 1
      ? instance.spec.colors[1]
      : instance.spec.colors.first;

  Color get _accent =>
      instance.spec.colors.length > 2 ? instance.spec.colors[2] : Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    switch (instance.spec.kind) {
      case HighlightEffectKind.ignition:
        _paintIgnition(canvas, size);
        break;
      case HighlightEffectKind.fracture:
        _paintFracture(canvas, size);
        break;
      case HighlightEffectKind.tearGlass:
        _paintTearGlass(canvas, size);
        break;
      case HighlightEffectKind.comedyPop:
        _paintComedyPop(canvas, size);
        break;
      case HighlightEffectKind.roseBloom:
        _paintRoseBloom(canvas, size);
        break;
      case HighlightEffectKind.spotlight:
        _paintSpotlight(canvas, size);
        break;
      case HighlightEffectKind.finale:
        _paintFinale(canvas, size);
        break;
    }
    _paintLabel(canvas, size);
  }

  void _paintVignette(Canvas canvas, Size size,
      {Color color = Colors.black, double alpha = .62}) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -.12),
          radius: .82,
          colors: [
            Colors.transparent,
            color.withValues(alpha: alpha * _overlayStrength),
          ],
          stops: const [.48, 1],
        ).createShader(rect),
    );
  }

  void _drawGlow(Canvas canvas, Offset center, double radius, Color color) {
    if (radius <= 0) return;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
          stops: const [0, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  void _drawRing(
    Canvas canvas,
    Offset center,
    double radius,
    Color color, {
    double stroke = 3,
    double blur = 2.4,
  }) {
    if (radius <= 0) return;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..blendMode = BlendMode.plus
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
  }

  void _drawStar(Canvas canvas, Offset center, double outerR, double innerR,
      int points, double rotation, Paint paint) {
    final path = Path();
    final total = points * 2;
    for (int i = 0; i < total; i++) {
      final r = i.isEven ? outerR : innerR;
      final a = -pi / 2 + rotation + (i / total) * 2 * pi;
      final p = center + Offset(cos(a) * r, sin(a) * r);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawCapsuleText(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color start,
    Color end,
    double opacity,
  ) {
    final stroke = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = fontSize * .14
            ..color = Colors.black.withValues(alpha: opacity * .7),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final textRect = Rect.fromCenter(
      center: Offset.zero,
      width: stroke.width,
      height: stroke.height,
    );
    final fill = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          foreground: Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: opacity),
                start.withValues(alpha: opacity),
                end.withValues(alpha: opacity),
              ],
              stops: const [0, .48, 1],
            ).createShader(textRect),
          shadows: [
            Shadow(color: start.withValues(alpha: opacity), blurRadius: 16),
            Shadow(color: end.withValues(alpha: opacity * .65), blurRadius: 28),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    stroke.paint(canvas, Offset(-stroke.width / 2, -stroke.height / 2));
    fill.paint(canvas, Offset(-fill.width / 2, -fill.height / 2));
    canvas.restore();
  }

  void _paintIgnition(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = Offset(size.width * .52, size.height * .47);
    final p = _easeOutCubic(t);
    final fade = _fadeAfter(.64);
    final shortest = size.shortestSide;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            _primary.withValues(alpha: .18 * fade * _overlayStrength),
            Colors.transparent,
            Colors.black.withValues(alpha: .16 * fade * _overlayStrength),
          ],
          stops: const [0, .52, 1],
        ).createShader(rect),
    );
    _paintVignette(canvas, size, color: const Color(0xFF160303), alpha: .68);

    if (t < .18) {
      final flash = 1 - t / .18;
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = _accent.withValues(alpha: .28 * flash * _flashStrength),
      );
    }

    _drawGlow(canvas, Offset(size.width * .5, size.height * .72),
        shortest * (.36 + .18 * p), _primary.withValues(alpha: .34 * fade));
    _drawGlow(canvas, center, shortest * (.16 + .42 * p),
        _secondary.withValues(alpha: .28 * fade));

    final slashPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    for (int i = 0; i < 9; i++) {
      final local = _clamp01((t - i * .035) / .72);
      if (local <= 0) continue;
      final x = size.width * (-.12 + _u(i, 1) * 1.24) + size.width * .18 * p;
      final y = size.height * (.12 + _u(i, 2) * .72);
      final len =
          size.longestSide * (.24 + _u(i, 3) * .22) * _easeOutQuart(local);
      final angle = -0.78 + (_u(i, 4) - .5) * .18;
      final dir = Offset(cos(angle), sin(angle));
      final start = Offset(x, y) - dir * len * .45;
      final end = Offset(x, y) + dir * len;
      final alpha = sin(local * pi).clamp(0.0, 1.0).toDouble() * fade;
      slashPaint
        ..strokeWidth = (4.5 + _u(i, 5) * 8) * alpha
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            _accent.withValues(alpha: .72 * alpha * _strength),
            _primary.withValues(alpha: .65 * alpha * _strength),
            Colors.transparent,
          ],
        ).createShader(Rect.fromPoints(start, end));
      canvas.drawLine(start, end, slashPaint);
    }

    for (int i = 0; i < 4; i++) {
      final local = _clamp01((t - i * .09) / .72);
      if (local <= 0) continue;
      final alpha = (1 - local) * fade;
      _drawRing(
        canvas,
        center,
        shortest * (.12 + .62 * _easeOutQuart(local)),
        _secondary.withValues(alpha: .48 * alpha * _strength),
        stroke: 6 * alpha + .6,
        blur: 3,
      );
    }

    final emberPaint = Paint()..blendMode = BlendMode.plus;
    for (int i = 0; i < 58; i++) {
      final local = (t + _u(i, 8) * .42) % 1;
      final x = size.width * (.05 + _u(i, 9) * .9);
      final y = size.height * (1.05 - local * (.58 + _u(i, 10) * .34));
      final drift = sin(local * pi * 2 + _u(i, 11) * pi) * 28;
      final alpha = sin(local * pi).clamp(0.0, 1.0).toDouble() * fade;
      emberPaint.color = (i.isEven ? _secondary : _primary)
          .withValues(alpha: .78 * alpha * _strength);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + drift, y),
            width: 2.4 + _u(i, 12) * 4,
            height: 7 + _u(i, 13) * 12,
          ),
          const Radius.circular(2),
        ),
        emberPaint,
      );
    }
  }

  void _paintFracture(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = Offset(size.width * .52, size.height * .46);
    final p = _easeOutQuart(t);
    final fade = _fadeAfter(.7);
    final shortest = size.shortestSide;

    canvas.drawRect(
      rect,
      Paint()
        ..color =
            const Color(0xFF080816).withValues(alpha: .2 * fade * _overlayStrength),
    );
    _paintVignette(canvas, size, color: const Color(0xFF050515), alpha: .72);

    if (t < .14) {
      final flash = 1 - t / .14;
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = Colors.white.withValues(alpha: .56 * flash * _flashStrength),
      );
    }

    final scan = Paint()
      ..strokeWidth = 1
      ..color = _primary.withValues(alpha: .08 * fade * _strength);
    for (double y = 0; y < size.height; y += 8) {
      final offset = sin(y * .04 + t * 18) * 3;
      canvas.drawLine(Offset(offset, y), Offset(size.width + offset, y), scan);
    }

    final barPaint = Paint()..blendMode = BlendMode.plus;
    for (int i = 0; i < 12; i++) {
      final local = _clamp01((t - i * .025) / .6);
      if (local <= 0) continue;
      final y = size.height * _u(i, 1);
      final h = 3 + _u(i, 2) * 18;
      final w = size.width * (.22 + _u(i, 3) * .55) * sin(local * pi);
      final dir = _u(i, 4) > .5 ? 1.0 : -1.0;
      final x = size.width * _u(i, 5) + dir * (1 - local) * 90;
      final alpha = sin(local * pi).clamp(0.0, 1.0).toDouble() * fade;
      barPaint.color = (i.isEven ? _primary : _accent)
          .withValues(alpha: .32 * alpha * _strength);
      canvas.drawRect(Rect.fromLTWH(x - w / 2, y, w, h), barPaint);
      barPaint.color = _secondary.withValues(alpha: .22 * alpha * _strength);
      canvas.drawRect(
          Rect.fromLTWH(x - w / 2 - dir * 12, y + 2, w, h), barPaint);
    }

    _drawGlow(canvas, center, shortest * (.1 + .36 * p),
        _secondary.withValues(alpha: .24 * fade));
    for (int i = 0; i < 3; i++) {
      final local = _clamp01((t - i * .12) / .68);
      if (local <= 0) continue;
      final alpha = (1 - local) * fade;
      _drawRing(
        canvas,
        center,
        shortest * (.1 + .58 * _easeOutQuart(local)),
        _primary.withValues(alpha: .5 * alpha * _strength),
        stroke: 5 * alpha + .5,
      );
    }

    final crackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = BlendMode.plus;
    for (int i = 0; i < 11; i++) {
      final angle = -pi + (i / 10) * 2 * pi + (_u(i, 6) - .5) * .24;
      final reach = shortest * (.32 + _u(i, 7) * .36) * p;
      final path = Path()..moveTo(center.dx, center.dy);
      const segments = 5;
      for (int s = 1; s <= segments; s++) {
        final frac = s / segments;
        final jitter = (_u(i * 17 + s, 8) - .5) * .45;
        final dist = reach * frac;
        path.lineTo(
          center.dx + cos(angle + jitter) * dist,
          center.dy + sin(angle + jitter) * dist,
        );
      }
      final alpha = fade * (.85 - i * .035).clamp(.2, .85);
      crackPaint
        ..strokeWidth = 1.2 + _u(i, 9) * 2.4
        ..color = (i.isEven ? _accent : _primary)
            .withValues(alpha: alpha * _strength);
      canvas.drawPath(path, crackPaint);
    }

    final shardPaint = Paint()..blendMode = BlendMode.plus;
    for (int i = 0; i < 18; i++) {
      final local = _clamp01((t - .08 - i * .01) / .68);
      if (local <= 0) continue;
      final angle = _u(i, 10) * 2 * pi;
      final dist = shortest * (.12 + _u(i, 11) * .54) * _easeOutQuart(local);
      final pos = center + Offset(cos(angle) * dist, sin(angle) * dist);
      final r = 5 + _u(i, 12) * 14;
      final alpha = (1 - local) * fade;
      final path = Path()
        ..moveTo(pos.dx, pos.dy - r)
        ..lineTo(pos.dx + r * .72, pos.dy + r * .54)
        ..lineTo(pos.dx - r * .58, pos.dy + r * .42)
        ..close();
      shardPaint.color =
          (i.isEven ? _primary : _accent).withValues(alpha: .24 * alpha);
      canvas.drawPath(path, shardPaint);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8
          ..blendMode = BlendMode.plus
          ..color = Colors.white.withValues(alpha: .32 * alpha * _strength),
      );
    }
  }

  void _paintTearGlass(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final fade = _fadeAfter(.72);
    final shortest = size.shortestSide;
    final center = Offset(size.width * .5, size.height * .56);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF101840)
                .withValues(alpha: .34 * fade * _overlayStrength),
            _primary.withValues(alpha: .11 * fade * _overlayStrength),
            Colors.black.withValues(alpha: .22 * fade * _overlayStrength),
          ],
        ).createShader(rect),
    );
    _paintVignette(canvas, size, color: const Color(0xFF05091B), alpha: .76);
    _drawGlow(canvas, Offset(size.width * .5, size.height * .2), shortest * .72,
        _secondary.withValues(alpha: .12 * fade));

    final rainPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.1);
    for (int i = 0; i < 44; i++) {
      final speed = .42 + _u(i, 2) * .8;
      final progress = (t * speed + _u(i, 1)) % 1;
      final x = size.width * (.04 + _u(i, 3) * .92);
      final y = size.height * (-.1 + progress * 1.2);
      final len = 34 + _u(i, 4) * 92;
      final alpha = sin(progress * pi).clamp(0.0, 1.0).toDouble() * fade;
      rainPaint
        ..strokeWidth = .7 + _u(i, 5) * 1.8
        ..color = (i.isEven ? _secondary : _primary)
            .withValues(alpha: .34 * alpha * _strength);
      canvas.drawLine(Offset(x, y), Offset(x - len * .18, y + len), rainPaint);
    }

    for (int i = 0; i < 6; i++) {
      final local = _clamp01((t - i * .09) / .82);
      if (local <= 0) continue;
      final alpha = (1 - local) * fade;
      _drawRing(
        canvas,
        center.translate((_u(i, 8) - .5) * size.width * .32,
            (_u(i, 9) - .5) * size.height * .12),
        shortest * (.05 + .42 * _easeOutCubic(local)),
        _secondary.withValues(alpha: .26 * alpha * _strength),
        stroke: 2.6 * alpha + .4,
        blur: 2.8,
      );
    }

    final streamPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    for (int i = 0; i < 7; i++) {
      final local = _clamp01((t - .08 - i * .035) / .75);
      if (local <= 0) continue;
      final x = size.width * (.16 + _u(i, 10) * .68);
      final y = size.height * (.18 + local * .52);
      final alpha = sin(local * pi).clamp(0.0, 1.0).toDouble() * fade;
      final path = Path()
        ..moveTo(x, y - 26)
        ..cubicTo(
          x + 18 * sin(local * pi * 2),
          y + 12,
          x - 12,
          y + 40,
          x + 6 * cos(local * pi),
          y + 74,
        );
      streamPaint
        ..strokeWidth = 1.4 + _u(i, 11) * 2.2
        ..color = Colors.white.withValues(alpha: .22 * alpha * _strength);
      canvas.drawPath(path, streamPaint);
    }
  }

  void _paintComedyPop(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final p = _easeOutBack((t / .55).clamp(0.0, 1.0).toDouble());
    final fade = _fadeAfter(.68);
    final shortest = size.shortestSide;
    final center = Offset(size.width * .52, size.height * .43);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.18, -.22),
          radius: .92,
          colors: [
            _primary.withValues(alpha: .16 * fade * _overlayStrength),
            Colors.transparent,
            const Color(0xFF171000)
                .withValues(alpha: .2 * fade * _overlayStrength),
          ],
          stops: const [0, .58, 1],
        ).createShader(rect),
    );
    _paintVignette(canvas, size, color: const Color(0xFF1E1300), alpha: .54);

    if (t < .16) {
      final flash = 1 - t / .16;
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = _primary.withValues(alpha: .34 * flash * _flashStrength),
      );
    }

    final dotPaint = Paint()..blendMode = BlendMode.plus;
    final dotStep = max(22.0, shortest * .065);
    for (double y = size.height * .12; y < size.height * .78; y += dotStep) {
      for (double x = size.width * .08; x < size.width * .92; x += dotStep) {
        final dx = (x - center.dx) / size.width;
        final dy = (y - center.dy) / size.height;
        final dist = sqrt(dx * dx + dy * dy);
        final wave = _clamp01(1 - (dist - t * .55).abs() * 6);
        if (wave <= 0) continue;
        dotPaint.color =
            (_u(x.round() + y.round(), 1) > .5 ? _primary : _secondary)
                .withValues(alpha: .26 * wave * fade * _strength);
        canvas.drawCircle(Offset(x, y), (2.5 + 8 * wave) * fade, dotPaint);
      }
    }

    final ringColor = _primary.withValues(alpha: .7 * fade * _strength);
    for (int i = 0; i < 5; i++) {
      final local = _clamp01((t - i * .08) / .6);
      if (local <= 0) continue;
      final alpha = sin(local * pi).clamp(0.0, 1.0).toDouble() * fade;
      _drawRing(
        canvas,
        center.translate((_u(i, 2) - .5) * 62, (_u(i, 3) - .5) * 54),
        shortest * (.06 + (.18 + i * .04) * p * local),
        ringColor.withValues(alpha: .54 * alpha * _strength),
        stroke: 4.2 * alpha + .6,
      );
    }

    final ribbonPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    for (int i = 0; i < 16; i++) {
      final local = _clamp01((t - i * .018) / .75);
      if (local <= 0) continue;
      final angle = _u(i, 4) * 2 * pi;
      final dist = shortest * (.12 + _u(i, 5) * .44) * _easeOutQuart(local);
      final start =
          center + Offset(cos(angle) * dist * .42, sin(angle) * dist * .42);
      final end = center + Offset(cos(angle) * dist, sin(angle) * dist);
      final bend = Offset(-sin(angle), cos(angle)) * (22 + _u(i, 6) * 32);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(
          (start.dx + end.dx) / 2 + bend.dx,
          (start.dy + end.dy) / 2 + bend.dy,
          end.dx,
          end.dy,
        );
      final alpha = (1 - local) * fade;
      ribbonPaint
        ..strokeWidth = 3 + _u(i, 7) * 5
        ..color = (i % 3 == 0 ? _accent : (i.isEven ? _primary : _secondary))
            .withValues(alpha: .72 * alpha * _strength);
      canvas.drawPath(path, ribbonPaint);
    }

    final starPaint = Paint()..blendMode = BlendMode.plus;
    for (int i = 0; i < 18; i++) {
      final local = _clamp01((t - .06 - i * .015) / .65);
      if (local <= 0) continue;
      final angle = _u(i, 8) * 2 * pi;
      final dist = shortest * (.18 + _u(i, 9) * .42) * _easeOutQuart(local);
      final pos = center + Offset(cos(angle) * dist, sin(angle) * dist);
      final alpha = (1 - local) * fade;
      starPaint.color = (i.isEven ? _primary : _accent)
          .withValues(alpha: .8 * alpha * _strength);
      _drawStar(
          canvas, pos, 5 + _u(i, 10) * 6, 2.1, 4, t * 5 + angle, starPaint);
    }
  }

  void _paintRoseBloom(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final fade = _fadeAfter(.74);
    final shortest = size.shortestSide;
    final center = Offset(size.width * .5, size.height * .64);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            _primary.withValues(alpha: .18 * fade * _overlayStrength),
            Colors.transparent,
            _secondary.withValues(alpha: .08 * fade * _overlayStrength),
          ],
        ).createShader(rect),
    );
    _paintVignette(canvas, size, color: const Color(0xFF220818), alpha: .55);
    _drawGlow(
        canvas, center, shortest * .68, _primary.withValues(alpha: .22 * fade));

    for (int i = 0; i < 34; i++) {
      final local = (t * (.54 + _u(i, 1) * .42) + _u(i, 2)) % 1;
      final angle = _u(i, 3) * 2 * pi + local * 1.4;
      final radius = shortest * (.08 + _u(i, 4) * .54) * (1 - local * .18);
      final x = size.width * .5 + cos(angle) * radius;
      final y = size.height * (.94 - local * .72) + sin(angle) * radius * .16;
      final scale = (.65 + _u(i, 5) * .9) * sin(local * pi);
      final alpha = sin(local * pi).clamp(0.0, 1.0).toDouble() * fade;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle + t * 2.4);
      _drawHeart(
        canvas,
        10 * scale,
        (i.isEven ? _primary : _secondary)
            .withValues(alpha: .54 * alpha * _strength),
      );
      canvas.restore();
    }

    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    for (int i = 0; i < 4; i++) {
      final local = _clamp01((t - i * .1) / .78);
      if (local <= 0) continue;
      final alpha = (1 - local) * fade;
      final y = size.height * (.74 - i * .08);
      final path = Path()..moveTo(size.width * .12, y);
      for (int s = 0; s <= 6; s++) {
        final x = size.width * (.12 + s * .13);
        final yy = y + sin(s * 1.4 + t * 5 + i) * 16 * alpha;
        if (s == 0) {
          path.moveTo(x, yy);
        } else {
          path.lineTo(x, yy);
        }
      }
      wavePaint
        ..strokeWidth = 2.2 + 3.2 * alpha
        ..color = _accent.withValues(alpha: .2 * alpha * _strength);
      canvas.drawPath(path, wavePaint);
    }
  }

  void _drawHeart(Canvas canvas, double size, Color color) {
    final path = Path()
      ..moveTo(0, size * .42)
      ..cubicTo(
          -size * 1.12, -size * .22, -size * .56, -size * 1.05, 0, -size * .48)
      ..cubicTo(
          size * .56, -size * 1.05, size * 1.12, -size * .22, 0, size * .42)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = color,
    );
  }

  void _paintSpotlight(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final fade = _fadeAfter(.72);
    final shortest = size.shortestSide;
    final center = Offset(size.width * .5, size.height * .32);
    final p = _easeOutCubic(t);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF2A1800)
                .withValues(alpha: .24 * fade * _overlayStrength),
            Colors.transparent,
            Colors.black.withValues(alpha: .18 * fade * _overlayStrength),
          ],
        ).createShader(rect),
    );
    _paintVignette(canvas, size, color: const Color(0xFF130B00), alpha: .65);

    final beamPaint = Paint()..blendMode = BlendMode.plus;
    for (int i = 0; i < 5; i++) {
      final spread = size.width * (.1 + i * .14);
      final topX = size.width * (.22 + i * .14 + (_u(i, 1) - .5) * .08);
      final path = Path()
        ..moveTo(topX, 0)
        ..lineTo(center.dx + spread * (p - .5), size.height * .72)
        ..lineTo(center.dx - spread * (p - .5), size.height * .72)
        ..close();
      beamPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _primary.withValues(alpha: .18 * fade * _strength),
          _secondary.withValues(alpha: .08 * fade * _strength),
          Colors.transparent,
        ],
      ).createShader(rect);
      canvas.drawPath(path, beamPaint);
    }

    _drawGlow(canvas, center, shortest * (.12 + .48 * p),
        _primary.withValues(alpha: .32 * fade));
    _drawLensFlare(canvas, center, shortest * .7, _primary, fade * .56);

    final dustPaint = Paint()..blendMode = BlendMode.plus;
    for (int i = 0; i < 52; i++) {
      final x = size.width * (.08 + _u(i, 2) * .84);
      final y = size.height *
          (.08 + ((_u(i, 3) + t * (.12 + _u(i, 4) * .15)) % 1) * .78);
      final alpha = (.18 + _u(i, 5) * .62) *
          fade *
          (0.45 + 0.55 * sin(t * pi * 2 + _u(i, 6) * pi).abs());
      dustPaint.color = (i.isEven ? _primary : _accent)
          .withValues(alpha: .44 * alpha * _strength);
      if (i % 5 == 0) {
        _drawStar(
            canvas, Offset(x, y), 4.6, 1.8, 5, t * 3 + _u(i, 7), dustPaint);
      } else {
        canvas.drawCircle(Offset(x, y), 1.2 + _u(i, 8) * 2.2, dustPaint);
      }
    }

    for (int i = 0; i < 3; i++) {
      final local = _clamp01((t - i * .12) / .68);
      if (local <= 0) continue;
      _drawRing(
        canvas,
        center,
        shortest * (.12 + .52 * _easeOutQuart(local)),
        _secondary.withValues(alpha: .34 * (1 - local) * fade * _strength),
        stroke: 3.8 * (1 - local) + .5,
      );
    }
  }

  void _drawLensFlare(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double alpha,
  ) {
    final paint = Paint()
      ..blendMode = BlendMode.plus
      ..strokeCap = StrokeCap.round
      ..strokeWidth = radius * .024
      ..color = color.withValues(alpha: alpha * _strength);
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      paint,
    );
    paint.strokeWidth = radius * .012;
    canvas.drawLine(
      Offset(center.dx, center.dy - radius * .28),
      Offset(center.dx, center.dy + radius * .28),
      paint,
    );
  }

  void _paintFinale(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final fade = _fadeAfter(.8);
    final center = Offset(size.width * .5, size.height * .42);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF22143D)
              .withValues(alpha: .18 * fade * _overlayStrength),
            Colors.transparent,
            const Color(0xFF102B25)
              .withValues(alpha: .14 * fade * _overlayStrength),
          ],
        ).createShader(rect),
    );
    _paintVignette(canvas, size, color: const Color(0xFF080816), alpha: .56);

    for (int burst = 0; burst < 3; burst++) {
      final local = _clamp01((t - burst * .18) / .82);
      if (local <= 0) continue;
      final origin = Offset(
        size.width * (.25 + _u(burst, 1) * .5),
        size.height * (.2 + _u(burst, 2) * .35),
      );
      for (int i = 0; i < 30; i++) {
        final angle = _u(i + burst * 31, 3) * 2 * pi;
        final dist =
            size.shortestSide * (.14 + _u(i, 4) * .42) * _easeOutQuart(local);
        final fall = local * local * size.height * .22;
        final pos =
            origin + Offset(cos(angle) * dist, sin(angle) * dist + fall);
        final alpha = (1 - local) * fade;
        final color =
            instance.spec.colors[(i + burst) % instance.spec.colors.length];
        final paint = Paint()
          ..blendMode = BlendMode.plus
          ..color = color.withValues(alpha: .75 * alpha * _strength);
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(local * (i.isEven ? 5 : -5) + _u(i, 5) * pi);
        if (i % 4 == 0) {
          _drawStar(canvas, Offset.zero, 6, 2.4, 5, 0, paint);
        } else {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: 7, height: 15),
              const Radius.circular(2),
            ),
            paint,
          );
        }
        canvas.restore();
      }
      _drawRing(
        canvas,
        origin,
        size.shortestSide * (.08 + .36 * _easeOutQuart(local)),
        instance.spec.colors[burst % instance.spec.colors.length]
            .withValues(alpha: .4 * (1 - local) * fade * _strength),
        stroke: 3.5 * (1 - local) + .4,
      );
    }

    _drawGlow(
      canvas,
      center,
      size.shortestSide * .38,
      _primary.withValues(alpha: .22 * fade),
    );
  }

  void _paintLabel(Canvas canvas, Size size) {
    if (instance.spec.label.isEmpty) return;
    final appear = _easeOutBack(t / .34);
    final fadeOut = _fadeAfter(.74);
    final opacity = _clamp01(appear) * fadeOut * _strength;
    if (opacity <= 0) return;

    final center = Offset(size.width / 2, size.height * .38 - sin(t * pi) * 5);
    final fontSize = min(40.0, max(28.0, size.width * .096));
    final scale = .82 + appear * .18 + (1 - fadeOut) * .05;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    _drawGlow(
      canvas,
      Offset.zero,
      size.shortestSide * .24,
      _primary.withValues(alpha: .32 * opacity),
    );

    _drawCapsuleText(
      canvas,
      instance.spec.label,
      Offset.zero,
      fontSize,
      _primary,
      _secondary,
      opacity,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant HighlightEffectPainter oldDelegate) => true;
}
