import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models.dart';
import 'animated_emoji_glyph.dart';

class HighlightEmotionPrompt extends StatefulWidget {
  final Highlight highlight;
  final int crowdCount;
  final VoidCallback? onReact;

  const HighlightEmotionPrompt({
    super.key,
    required this.highlight,
    this.crowdCount = 0,
    this.onReact,
  });

  @override
  State<HighlightEmotionPrompt> createState() => _HighlightEmotionPromptState();
}

class _HighlightEmotionPromptState extends State<HighlightEmotionPrompt>
    with TickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2100),
  )..repeat();
  late final AnimationController _tapPop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  int _combo = 0;
  Timer? _comboTimer;

  @override
  void didUpdateWidget(covariant HighlightEmotionPrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlight.id != widget.highlight.id) {
      _combo = 0;
      _comboTimer?.cancel();
      _tapPop.reset();
    }
  }

  @override
  void dispose() {
    _comboTimer?.cancel();
    _breath.dispose();
    _tapPop.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    setState(() => _combo += 1);
    _tapPop.forward(from: 0);
    _comboTimer?.cancel();
    _comboTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _combo = 0);
    });
    widget.onReact?.call();
  }

  @override
  Widget build(BuildContext context) {
    final spec = _EmotionPromptSpec.forHighlight(widget.highlight);

    return AnimatedBuilder(
      animation: Listenable.merge([_breath, _tapPop]),
      builder: (context, _) {
        final pulse = math.sin(_breath.value * math.pi * 2);
        final tap = Curves.easeOutBack.transform(_tapPop.value);
        final scale = 1 + tap * .13 + pulse * .018;
        final tilt = pulse * .035 - tap * .04;

        return Transform.rotate(
          angle: tilt,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.centerLeft,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: const Size(136, 132),
                  painter: _PromptAuraPainter(
                    spec: spec,
                    motion: _breath.value,
                    tapped: _tapPop.value,
                    intensity: widget.highlight.intensity,
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 18,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: _handleTap,
                      child: Container(
                        width: 128,
                        padding: const EdgeInsets.fromLTRB(7, 7, 9, 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: .14),
                              Colors.white.withValues(alpha: .05),
                              spec.dark.withValues(alpha: .78),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: spec.primary.withValues(alpha: .38),
                            width: 1.1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: spec.primary.withValues(alpha: .22),
                              blurRadius: 18,
                              spreadRadius: -7,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _StickerFace(spec: spec),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    spec.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      height: 1.05,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '点一下互动',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: .72),
                                      fontSize: 9.5,
                                      height: 1,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 78,
                  top: 0,
                  child: AnimatedOpacity(
                    opacity: _combo >= 2 ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: Transform.translate(
                      offset: Offset(0, -tap * 10),
                      child: _ComboBadge(
                        spec: spec,
                        combo: _combo,
                      ),
                    ),
                  ),
                ),
                for (int i = 0; i < 4; i++)
                  Positioned(
                    left: 20 + i * 19 + pulse * (i.isEven ? 3 : -3),
                    top: 106 - i * 7 - tap * (12 + i * 2),
                    child: Opacity(
                      opacity: (.18 + _tapPop.value * .55)
                          .clamp(0.0, .72)
                          .toDouble(),
                      child: Text(
                        spec.sparks[i % spec.sparks.length],
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12 + i * 1.8,
                          fontWeight: FontWeight.w900,
                          shadows: [
                            Shadow(
                              color: spec.primary.withValues(alpha: .86),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StickerFace extends StatelessWidget {
  final _EmotionPromptSpec spec;

  const _StickerFace({required this.spec});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-.25, -.35),
          radius: .9,
          colors: [
            Colors.white,
            spec.secondary,
            spec.primary,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: spec.primary.withValues(alpha: .32),
            blurRadius: 12,
            spreadRadius: -3,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedEmojiGlyph(emoji: spec.emoji, size: 26),
          Positioned(
            right: 3,
            bottom: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                spec.glyph,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComboBadge extends StatelessWidget {
  final _EmotionPromptSpec spec;
  final int combo;

  const _ComboBadge({
    required this.spec,
    required this.combo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [spec.primary, spec.secondary]),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: .72)),
        boxShadow: [
          BoxShadow(
            color: spec.primary.withValues(alpha: .5),
            blurRadius: 18,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Text(
        'x$combo',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PromptAuraPainter extends CustomPainter {
  final _EmotionPromptSpec spec;
  final double motion;
  final double tapped;
  final double intensity;

  const _PromptAuraPainter({
    required this.spec,
    required this.motion,
    required this.tapped,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const center = Offset(54, 64);
    final pulse = math.sin(motion * math.pi * 2);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    for (int i = 0; i < 3; i++) {
      final p = ((motion + i * .24) % 1.0);
      final fade = (1 - p) * (.09 + intensity * .12);
      ringPaint
        ..strokeWidth = 1.2 + (1 - p) * 2.4
        ..color = spec.primary.withValues(alpha: fade);
      canvas.drawCircle(center, 34 + p * 28 + tapped * 12, ringPaint);
    }

    final glow = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        colors: [
          spec.primary.withValues(alpha: .12 + tapped * .14),
          spec.primary.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: 72));
    canvas.drawCircle(center, 72 + pulse * 3, glow);

    final slash = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4
      ..blendMode = BlendMode.plus
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: .2 + tapped * .16),
          spec.secondary.withValues(alpha: .22),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 18, size.width, 78));
    canvas.drawLine(
      Offset(4 + pulse * 4, 94),
      Offset(102 - pulse * 2, 30),
      slash,
    );
  }

  @override
  bool shouldRepaint(covariant _PromptAuraPainter oldDelegate) =>
      oldDelegate.motion != motion ||
      oldDelegate.tapped != tapped ||
      oldDelegate.intensity != intensity ||
      oldDelegate.spec != spec;
}

class _EmotionPromptSpec {
  final String title;
  final String glyph;
  final String emoji;
  final IconData icon;
  final Color primary;
  final Color secondary;
  final Color dark;
  final List<String> sparks;

  const _EmotionPromptSpec({
    required this.title,
    required this.glyph,
    required this.emoji,
    required this.icon,
    required this.primary,
    required this.secondary,
    required this.dark,
    required this.sparks,
  });

  factory _EmotionPromptSpec.forHighlight(Highlight highlight) {
    final key = '${highlight.type}${highlight.interaction}${highlight.summary}';
    final typeKey = '${highlight.type}${highlight.summary}';
    if (key.contains('笑') ||
      key.contains('搞笑') ||
      key.contains('包袱') ||
      key.contains('年龄反差')) {
      return const _EmotionPromptSpec(
        title: '笑出鹅叫',
        glyph: '哈',
        emoji: '🦢',
        icon: Icons.sentiment_very_satisfied_rounded,
        primary: Color(0xFFFFD24A),
        secondary: Color(0xFF66E1FF),
        dark: Color(0xFF201605),
        sparks: ['哈', '哈', '笑', '鹅'],
      );
    }
    if (typeKey.contains('爽') ||
        typeKey.contains('打脸') ||
        typeKey.contains('反杀') ||
      typeKey.contains('解气') ||
      typeKey.contains('护短') ||
      typeKey.contains('撑腰')) {
      return const _EmotionPromptSpec(
        title: '爽到了',
        glyph: '爽',
        emoji: '😎',
        icon: Icons.whatshot_rounded,
        primary: Color(0xFFFF6B35),
        secondary: Color(0xFFFFD166),
        dark: Color(0xFF241007),
        sparks: ['爽', '打', '脸', '反杀'],
      );
    }
    if (key.contains('破防') || key.contains('心疼')) {
      return const _EmotionPromptSpec(
        title: '破防了',
        glyph: '破',
        emoji: '🥺',
        icon: Icons.heart_broken_rounded,
        primary: Color(0xFF8AB6FF),
        secondary: Color(0xFFFF9EC7),
        dark: Color(0xFF10182E),
        sparks: ['破', '防', '心疼', '疼'],
      );
    }
    if (key.contains('泪') || key.contains('哭') || key.contains('虐')) {
      return const _EmotionPromptSpec(
        title: '泪目了',
        glyph: '泪',
        emoji: '😭',
        icon: Icons.water_drop_rounded,
        primary: Color(0xFF7EA2FF),
        secondary: Color(0xFFB5F2FF),
        dark: Color(0xFF07122D),
        sparks: ['泪', '破', '防', '呜'],
      );
    }
    if (key.contains('反转') ||
        key.contains('转折') ||
        key.contains('悬念') ||
        key.contains('震惊') ||
        key.contains('炸裂')) {
      return const _EmotionPromptSpec(
        title: '反转了',
        glyph: '反',
        emoji: '😱',
        icon: Icons.bolt_rounded,
        primary: Color(0xFF6CF1FF),
        secondary: Color(0xFF9A6BFF),
        dark: Color(0xFF080E2C),
        sparks: ['反', '转', '!', '?'],
      );
    }
    if (key.contains('紧张') || key.contains('压迫') || key.contains('窒息')) {
      return const _EmotionPromptSpec(
        title: '紧张了',
        glyph: '紧',
        emoji: '😨',
        icon: Icons.visibility_rounded,
        primary: Color(0xFF45E0FF),
        secondary: Color(0xFFFF4D9D),
        dark: Color(0xFF071526),
        sparks: ['紧张', '压迫', '屏息', '危'],
      );
    }
    if (key.contains('甜') || key.contains('心动') || key.contains('磕')) {
      return const _EmotionPromptSpec(
        title: '好甜啊',
        glyph: '甜',
        emoji: '😍',
        icon: Icons.favorite_rounded,
        primary: Color(0xFFFF75B7),
        secondary: Color(0xFFFFC86F),
        dark: Color(0xFF2A0A1E),
        sparks: ['甜', '心', '动', '糖'],
      );
    }
    if (key.contains('治愈') || key.contains('温暖')) {
      return const _EmotionPromptSpec(
        title: '被治愈了',
        glyph: '暖',
        emoji: '☺️',
        icon: Icons.volunteer_activism_rounded,
        primary: Color(0xFFFFD166),
        secondary: Color(0xFF5EE6A8),
        dark: Color(0xFF132313),
        sparks: ['暖', '治愈', '安心', '戳中'],
      );
    }
    if (key.contains('离谱') || key.contains('上头') || key.contains('吐槽')) {
      return const _EmotionPromptSpec(
        title: '太上头了',
        glyph: '上',
        emoji: '🤯',
        icon: Icons.auto_awesome_rounded,
        primary: Color(0xFFFF8A3D),
        secondary: Color(0xFF6CF1FF),
        dark: Color(0xFF241008),
        sparks: ['离谱', '上头', '绝', '继续'],
      );
    }
    if (key.contains('名场面') || key.contains('封神')) {
      return const _EmotionPromptSpec(
        title: '封神了',
        glyph: '神',
        emoji: '👑',
        icon: Icons.workspace_premium_rounded,
        primary: Color(0xFFFFE6A3),
        secondary: Color(0xFFFFB23F),
        dark: Color(0xFF261701),
        sparks: ['神', '绝', '名', '场'],
      );
    }
    return const _EmotionPromptSpec(
      title: '燃起来',
      glyph: '燃',
      emoji: '🔥',
      icon: Icons.local_fire_department_rounded,
      primary: Color(0xFFFF3D2E),
      secondary: Color(0xFFFFB23F),
      dark: Color(0xFF230703),
      sparks: ['燃', '爽', '冲', '上'],
    );
  }
}
