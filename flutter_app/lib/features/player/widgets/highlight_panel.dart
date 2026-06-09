import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models.dart';

/// 高光触发面板（顶部内容卡）+ 冲突投票模块（短剧专属）
class HighlightPanel extends StatefulWidget {
  final Highlight highlight;
  final double positionSeconds;
  final int crowdCount;
  final VoidCallback? onClose;
  final VoidCallback? onReact;
  final ValueChanged<int>? onVote;

  const HighlightPanel({
    super.key,
    required this.highlight,
    required this.positionSeconds,
    this.crowdCount = 0,
    this.onClose,
    this.onReact,
    this.onVote,
  });

  @override
  State<HighlightPanel> createState() => _HighlightPanelState();
}

class _HighlightPanelState extends State<HighlightPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highlight = widget.highlight;
    final progress = _playbackProgress(highlight);
    final intensity = highlight.intensity.clamp(0.0, 1.0);
    final palette = _HighlightPalette.forHighlight(highlight);

    return AnimatedBuilder(
      animation: _motion,
      builder: (context, _) {
        final lift = math.sin(_motion.value * math.pi * 2) * 1.8;
        return Transform.translate(
          offset: Offset(0, lift),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: palette.primary.withValues(alpha: .52),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: palette.primary.withValues(alpha: .18),
                  blurRadius: 22,
                  spreadRadius: -10,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: CustomPaint(
                  painter: _HologramPainter(
                    palette: palette,
                    motion: _motion.value,
                    progress: progress,
                    intensity: intensity,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          _TypeChip(highlight: highlight, palette: palette),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              highlight.summary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (widget.onClose != null)
                            IconButton(
                              tooltip: '关闭',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 28,
                                height: 28,
                              ),
                              onPressed: widget.onClose,
                              icon: const Icon(Icons.close_rounded,
                                  color: AppColors.textTertiary, size: 17),
                            ),
                        ]),
                        const SizedBox(height: 7),
                        _PlaybackBeam(
                          progress: progress,
                          palette: palette,
                        ),
                        const SizedBox(height: 7),
                        Row(children: [
                          _MetricPill(
                            icon: Icons.local_fire_department_rounded,
                            label: '${(intensity * 100).round()}%',
                            color: palette.secondary,
                          ),
                          const SizedBox(width: 6),
                          _MetricPill(
                            icon: Icons.groups_rounded,
                            label: '${widget.crowdCount}',
                            color: AppColors.accentMint,
                          ),
                          if (widget.onReact != null) ...[
                            const Spacer(),
                            _ReactButton(
                              label: highlight.interaction,
                              palette: palette,
                              onTap: widget.onReact,
                            ),
                          ],
                        ]),
                        if (highlight.type.contains('冲突') ||
                            highlight.interaction.contains('冲突')) ...[
                          const SizedBox(height: 8),
                          _ClashVoteModule(onVote: widget.onVote),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _playbackProgress(Highlight highlight) {
    final length = math.max(0.1, highlight.tsEnd - highlight.tsStart);
    return ((widget.positionSeconds - highlight.tsStart) / length)
        .clamp(0.0, 1.0);
  }
}

class _HighlightPalette {
  final Color primary;
  final Color secondary;
  final Color surface;

  const _HighlightPalette({
    required this.primary,
    required this.secondary,
    required this.surface,
  });

  factory _HighlightPalette.forHighlight(Highlight highlight) {
    final type = '${highlight.type}${highlight.interaction}';
    if (type.contains('甜')) {
      return const _HighlightPalette(
        primary: Color(0xFFFF74B8),
        secondary: Color(0xFFFFD166),
        surface: Color(0xFF21101B),
      );
    }
    if (type.contains('反转') || type.contains('转折')) {
      return const _HighlightPalette(
        primary: Color(0xFF64E8FF),
        secondary: Color(0xFF8A5BFF),
        surface: Color(0xFF071E28),
      );
    }
    if (type.contains('虐') || type.contains('泪') || type.contains('哭')) {
      return const _HighlightPalette(
        primary: Color(0xFF7EA2FF),
        secondary: Color(0xFFB5F2FF),
        surface: Color(0xFF0B1027),
      );
    }
    if (type.contains('悬') || type.contains('炸')) {
      return const _HighlightPalette(
        primary: Color(0xFFB967FF),
        secondary: Color(0xFFFFD166),
        surface: Color(0xFF140B27),
      );
    }
    return const _HighlightPalette(
      primary: AppColors.accentHot,
      secondary: AppColors.accentGold,
      surface: Color(0xFF1D0E12),
    );
  }
}

class _HologramPainter extends CustomPainter {
  final _HighlightPalette palette;
  final double motion;
  final double progress;
  final double intensity;

  const _HologramPainter({
    required this.palette,
    required this.motion,
    required this.progress,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          palette.surface.withValues(alpha: .86),
          Colors.black.withValues(alpha: .76),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    final sweepX = size.width * ((motion * 1.25) % 1.0);
    final sweep = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          palette.primary.withValues(alpha: .14 + intensity * .1),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(sweepX - 90, 0, 180, size.height));
    canvas.drawRect(rect, sweep);

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = palette.primary.withValues(alpha: .09);
    final horizon = size.height * .64;
    for (var i = 0; i < 8; i++) {
      final y = horizon + math.pow(i / 7, 1.8) * size.height * .42;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var i = -4; i <= 4; i++) {
      final x = size.width / 2 + i * size.width * .12;
      canvas.drawLine(
          Offset(x, horizon), Offset(x + i * 18, size.height), grid);
    }

    final beam = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2
      ..color = palette.secondary.withValues(alpha: .34 + intensity * .24);
    final beamY = size.height * (.18 + .18 * math.sin(motion * math.pi * 2));
    canvas.drawLine(
      Offset(size.width * .1, beamY),
      Offset(size.width * (.28 + progress * .6), beamY + size.height * .09),
      beam,
    );

    final pin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = palette.secondary.withValues(alpha: .2);
    canvas.drawCircle(
      Offset(size.width * (.18 + progress * .66), size.height * .48),
      24 + 10 * math.sin(motion * math.pi * 2),
      pin,
    );
  }

  @override
  bool shouldRepaint(covariant _HologramPainter oldDelegate) =>
      oldDelegate.motion != motion ||
      oldDelegate.progress != progress ||
      oldDelegate.intensity != intensity ||
      oldDelegate.palette != palette;
}

class _TypeChip extends StatelessWidget {
  final Highlight highlight;
  final _HighlightPalette palette;

  const _TypeChip({required this.highlight, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 104),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [palette.primary, palette.secondary]),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 12),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '${highlight.interaction} · ${highlight.type}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ]),
    );
  }
}

class _PlaybackBeam extends StatelessWidget {
  final double progress;
  final _HighlightPalette palette;

  const _PlaybackBeam({required this.progress, required this.palette});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      child: LayoutBuilder(builder: (context, constraints) {
        final dotLeft = (constraints.maxWidth - 8) * progress;
        return Stack(children: [
          Align(
            alignment: Alignment.center,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: .14),
                color: palette.secondary,
              ),
            ),
          ),
          Positioned(
            left: dotLeft,
            top: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: palette.secondary.withValues(alpha: .75),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ]);
      }),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetricPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .1),
        border: Border.all(color: color.withValues(alpha: .36)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ]),
    );
  }
}

class _ReactButton extends StatelessWidget {
  final String label;
  final _HighlightPalette palette;
  final VoidCallback? onTap;

  const _ReactButton({
    required this.label,
    required this.palette,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            gradient:
                LinearGradient(colors: [palette.primary, palette.secondary]),
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: palette.primary.withValues(alpha: .32),
                blurRadius: 18,
                spreadRadius: -5,
              ),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.bolt_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ClashVoteModule extends StatefulWidget {
  final ValueChanged<int>? onVote;
  const _ClashVoteModule({this.onVote});

  @override
  State<_ClashVoteModule> createState() => _ClashVoteModuleState();
}

class _ClashVoteModuleState extends State<_ClashVoteModule> {
  int? _picked;
  int _leftCount = 1240;
  int _rightCount = 1180;

  @override
  Widget build(BuildContext context) {
    final total = _leftCount + _rightCount;
    final leftPct = total == 0 ? 50 : (_leftCount * 100 / total).round();
    final rightPct = 100 - leftPct;
    return Row(children: [
      Expanded(
        child: _faction(
          title: '护主角',
          subtitle: '正面硬刚',
          color: AppColors.accentHot,
          picked: _picked == 0,
          pct: leftPct,
          count: _leftCount,
          onTap: () => _vote(0),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _faction(
          title: '看反杀',
          subtitle: '等局势翻盘',
          color: AppColors.accentVio,
          picked: _picked == 1,
          pct: rightPct,
          count: _rightCount,
          onTap: () => _vote(1),
        ),
      ),
    ]);
  }

  void _vote(int side) {
    if (_picked != null) return;
    setState(() {
      _picked = side;
      if (side == 0) _leftCount += 1;
      if (side == 1) _rightCount += 1;
    });
    widget.onVote?.call(side);
  }

  Widget _faction({
    required String title,
    required String subtitle,
    required Color color,
    required bool picked,
    required int pct,
    required int count,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: picked ? .35 : .12),
            border: Border.all(
                color: color.withValues(alpha: picked ? 1 : .35), width: 1),
            borderRadius: BorderRadius.circular(AppRadius.m),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            Text(subtitle,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: .7), fontSize: 11)),
            const SizedBox(height: 6),
            Row(children: [
              Text('$pct%',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Text('· $count 人',
                  style: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 11)),
            ]),
          ]),
        ),
      );
}
