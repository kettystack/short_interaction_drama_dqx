import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 自包含的「动态动画表情」——无需 Lottie/网络资源即可让 emoji 活起来：
/// 周期性放大缩小 + 挤压拉伸（squash & stretch）+ 轻微左右摆动，
/// 例如 🦢「笑出鹅叫」会像真的鹅一样一胀一缩、晃头。
class AnimatedEmojiGlyph extends StatefulWidget {
  final String emoji;
  final double size;

  /// 背后光晕颜色，null 则不画光晕。
  final Color? glow;

  /// 动画一个完整周期时长。
  final Duration period;

  /// 每个实例的相位偏移（0~1），用于让一群表情错峰跳动。
  final double phase;

  /// 弹跳幅度，1 = 默认，越大越夸张。
  final double bounce;

  const AnimatedEmojiGlyph({
    super.key,
    required this.emoji,
    this.size = 30,
    this.glow,
    this.period = const Duration(milliseconds: 1100),
    this.phase = 0,
    this.bounce = 1,
  });

  @override
  State<AnimatedEmojiGlyph> createState() => _AnimatedEmojiGlyphState();
}

class _AnimatedEmojiGlyphState extends State<AnimatedEmojiGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat();

  @override
  void didUpdateWidget(covariant AnimatedEmojiGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _c.duration = widget.period;
      if (!_c.isAnimating) _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = (_c.value + widget.phase) % 1.0;
        // 主脉冲：快速涨、缓慢落（easeOutBack 似的弹性）。
        final pop = math.pow(math.sin(t * math.pi), 0.6).toDouble();
        final wobble = math.sin(t * math.pi * 4);
        final scale = 1 + pop * .34 * widget.bounce;
        // 挤压拉伸：放大时变高变瘦，回落时变扁。
        final stretchY = 1 + pop * .12 * widget.bounce;
        final stretchX = 1 - pop * .08 * widget.bounce;
        final tilt = wobble * .12 * (1 - pop * .4);

        return Transform.rotate(
          angle: tilt,
          child: Transform.scale(
            scaleX: scale * stretchX,
            scaleY: scale * stretchY,
            child: child,
          ),
        );
      },
      child: SizedBox(
        width: widget.size * 1.6,
        height: widget.size * 1.6,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.glow != null)
              Container(
                width: widget.size * 1.5,
                height: widget.size * 1.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      widget.glow!.withValues(alpha: .55),
                      widget.glow!.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            Text(
              widget.emoji,
              style: TextStyle(
                fontSize: widget.size,
                height: 1,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: .35),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
