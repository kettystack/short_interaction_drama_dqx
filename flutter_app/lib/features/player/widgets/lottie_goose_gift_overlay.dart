import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'animated_emoji_glyph.dart';

/// 右上角礼物挂件：
/// - 鹅高光使用真实 goose-talk + megaphone Lottie 资产；
/// - 其他高光复用同一礼物骨架，挂 emoji 徽章、喷字、金币和闪片；
/// - 客户端只负责固定挂载与分层组合，后续可直接替换为设计导出的正式资源。
class HighlightGiftOverlay extends StatefulWidget {
  final String title;
  final String emoji;
  final String giftText;
  final List<String> giftTokens;
  final String? actorAsset;
  final bool useGooseActor;
  final Color primary;
  final Color secondary;
  final int crowd;

  const HighlightGiftOverlay({
    super.key,
    required this.title,
    required this.emoji,
    required this.giftText,
    required this.giftTokens,
    this.actorAsset,
    this.useGooseActor = false,
    required this.primary,
    required this.secondary,
    required this.crowd,
  });

  @override
  State<HighlightGiftOverlay> createState() => _HighlightGiftOverlayState();
}

class _HighlightGiftOverlayState extends State<HighlightGiftOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 880),
  )..forward();

  @override
  void dispose() {
    _bob.dispose();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_bob, _entry]),
      builder: (context, child) {
        final bob = _bob.value;
        final entry = Curves.elasticOut.transform(_entry.value);
        final hover = math.sin(bob * math.pi * 2) * 4;
        final rotate = math.sin(bob * math.pi * 2) * .024;
        final scale = .82 + entry * .18 + math.sin(bob * math.pi * 4) * .01;
        return Opacity(
          opacity: Curves.easeOut.transform((_entry.value * 1.4).clamp(0, 1)),
          child: Transform.rotate(
            angle: rotate,
            alignment: Alignment.topRight,
            child: Transform.translate(
              offset: Offset((1 - entry) * 26, (1 - entry) * -32 + hover),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topRight,
                child: child,
              ),
            ),
          ),
        );
      },
      child: SizedBox(
        width: 304,
        height: 228,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _GiftBurstPainter(
                  progress: _entry.value,
                  shimmer: _bob.value,
                  primary: widget.primary,
                  secondary: widget.secondary,
                ),
              ),
            ),
            Positioned(
              right: 30,
              top: 54,
              child: Container(
                width: 184,
                height: 92,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.secondary.withValues(alpha: .26),
                      widget.primary.withValues(alpha: .18),
                      Colors.white.withValues(alpha: .08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.primary.withValues(alpha: .24),
                      blurRadius: 22,
                      spreadRadius: -8,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 4,
              top: 20,
              child: Transform.rotate(
                angle: -.08,
                child: Lottie.asset(
                  'assets/lottie/highlight/red_megaphone.json',
                  width: 154,
                  height: 154,
                  fit: BoxFit.contain,
                  repeat: true,
                  frameRate: FrameRate.max,
                ),
              ),
            ),
            if (widget.actorAsset != null)
              Positioned(
                right: widget.useGooseActor ? -18 : 8,
                top: widget.useGooseActor ? -4 : 8,
                child: Lottie.asset(
                  widget.actorAsset!,
                  width: widget.useGooseActor ? 188 : 156,
                  height: widget.useGooseActor ? 188 : 156,
                  fit: BoxFit.contain,
                  repeat: true,
                  frameRate: FrameRate.max,
                ),
              )
            else
              Positioned(
                right: 8,
                top: 2,
                child: _GiftEmojiMedal(
                  emoji: widget.emoji,
                  primary: widget.primary,
                  secondary: widget.secondary,
                ),
              ),
            Positioned(
              left: 20,
              top: 44,
              child: _GiftSprayTag(
                text: widget.giftText,
                primary: widget.primary,
                secondary: widget.secondary,
              ),
            ),
            ...List.generate(widget.giftTokens.length, (index) {
              final token = widget.giftTokens[index];
              final anchors = <Offset>[
                const Offset(20, 20),
                const Offset(46, 104),
                const Offset(122, 16),
                const Offset(134, 94),
                const Offset(74, 12),
              ];
              return _GiftOrbitToken(
                token: token,
                anchor: anchors[index % anchors.length],
                progress: _entry.value,
                shimmer: _bob.value,
                primary: widget.primary,
                secondary: widget.secondary,
                index: index,
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _GiftEmojiMedal extends StatelessWidget {
  final String emoji;
  final Color primary;
  final Color secondary;

  const _GiftEmojiMedal({
    required this.emoji,
    required this.primary,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      height: 148,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: .95),
            secondary.withValues(alpha: .78),
            primary.withValues(alpha: .9),
          ],
        ),
        border:
            Border.all(color: Colors.white.withValues(alpha: .82), width: 2),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: .28),
            blurRadius: 24,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 10,
            right: 18,
            child: Icon(
              Icons.auto_awesome,
              size: 16,
              color: Colors.white.withValues(alpha: .85),
            ),
          ),
          Container(
            width: 102,
            height: 102,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: .1),
              border: Border.all(color: Colors.white.withValues(alpha: .26)),
            ),
            child: Center(
              child: AnimatedEmojiGlyph(
                emoji: emoji,
                size: 64,
                glow: primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftSprayTag extends StatelessWidget {
  final String text;
  final Color primary;
  final Color secondary;

  const _GiftSprayTag({
    required this.text,
    required this.primary,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -.12,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 148),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: .96),
              secondary.withValues(alpha: .92),
              primary.withValues(alpha: .96),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: Colors.white.withValues(alpha: .85), width: 1.4),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: .28),
              blurRadius: 18,
              spreadRadius: -8,
            ),
          ],
        ),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xFF132033),
            fontSize: 18,
            height: 1.02,
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(
                color: Colors.white.withValues(alpha: .55),
                blurRadius: 10,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GiftOrbitToken extends StatelessWidget {
  final String token;
  final Offset anchor;
  final double progress;
  final double shimmer;
  final Color primary;
  final Color secondary;
  final int index;

  const _GiftOrbitToken({
    required this.token,
    required this.anchor,
    required this.progress,
    required this.shimmer,
    required this.primary,
    required this.secondary,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final reveal = Curves.easeOutBack.transform(progress.clamp(0.0, 1.0));
    final sway = math.sin(shimmer * math.pi * 2 + index * .9);
    final lift = (1 - reveal) * 18 - sway * (8 + index * 1.6);
    final drift = sway * (7 + index * 1.4);
    final scale = .72 + reveal * .28;

    return Positioned(
      left: anchor.dx + drift,
      top: anchor.dy + lift,
      child: Transform.scale(
        scale: scale,
        child: token == '🪙'
            ? _GiftCoin(primary: primary, secondary: secondary)
            : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: .18),
                      blurRadius: 16,
                      spreadRadius: -8,
                    ),
                  ],
                ),
                child: Text(
                  token,
                  style: const TextStyle(fontSize: 18, height: 1),
                ),
              ),
      ),
    );
  }
}

class _GiftCoin extends StatelessWidget {
  final Color primary;
  final Color secondary;

  const _GiftCoin({required this.primary, required this.secondary});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFFF4B2),
            const Color(0xFFFFD24A),
            primary.withValues(alpha: .82),
          ],
        ),
        border:
            Border.all(color: Colors.white.withValues(alpha: .68), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: secondary.withValues(alpha: .16),
            blurRadius: 16,
            spreadRadius: -8,
          ),
        ],
      ),
      child: const Center(
        child: Text(
          '礼',
          style: TextStyle(
            color: Color(0xFF7A4300),
            fontSize: 15,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _GiftBurstPainter extends CustomPainter {
  final double progress;
  final double shimmer;
  final Color primary;
  final Color secondary;

  const _GiftBurstPainter({
    required this.progress,
    required this.shimmer,
    required this.primary,
    required this.secondary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final reveal = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final rect = Offset.zero & size;
    final anchor = Offset(size.width * .7, size.height * .45);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(.58, -.2),
          radius: .96,
          colors: [
            secondary.withValues(alpha: .16 * reveal),
            Colors.transparent,
          ],
          stops: const [.0, 1],
        ).createShader(rect),
    );

    canvas.drawCircle(
      anchor,
      size.shortestSide * (.12 + reveal * .16),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            primary.withValues(alpha: .22 * reveal),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(
            center: anchor,
            radius: size.shortestSide * .28,
          ),
        ),
    );

    final beamPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    for (int i = 0; i < 8; i++) {
      final angle = -2.72 + i * .24 + math.sin(shimmer * math.pi * 2 + i) * .04;
      final len = size.width * (.16 + reveal * (.12 + i * .01));
      final start = anchor + Offset(math.cos(angle), math.sin(angle)) * 20;
      final end = start + Offset(math.cos(angle), math.sin(angle)) * len;
      beamPaint
        ..strokeWidth = 3.2 - i * .18
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            secondary.withValues(alpha: .45 * reveal),
            primary.withValues(alpha: .62 * reveal),
            Colors.transparent,
          ],
        ).createShader(Rect.fromPoints(start, end));
      canvas.drawLine(start, end, beamPaint);
    }

    final sparklePaint = Paint()..blendMode = BlendMode.plus;
    for (int i = 0; i < 14; i++) {
      final wave = (shimmer + i * .11) % 1;
      final x =
          size.width * (.24 + (i % 5) * .12) + math.sin(wave * math.pi * 2) * 6;
      final y = size.height * (.18 + (i ~/ 5) * .2) +
          math.cos(wave * math.pi * 2) * 5;
      final alpha = (.18 + math.sin(wave * math.pi).abs() * .42) * reveal;
      sparklePaint.color =
          (i.isEven ? primary : secondary).withValues(alpha: alpha);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: 4, height: 14),
          const Radius.circular(3),
        ),
        sparklePaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: 14, height: 4),
          const Radius.circular(3),
        ),
        sparklePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GiftBurstPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.shimmer != shimmer ||
        oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary;
  }
}
