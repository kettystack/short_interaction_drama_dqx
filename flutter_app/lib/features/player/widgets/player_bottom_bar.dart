import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models.dart';
import '../controllers/playback_controller.dart';

class PlayerBottomBar extends StatelessWidget {
  final PlaybackController playback;
  final Duration durationFallback;
  final List<Highlight> highlights;
  final List<String> statusChips;
  final bool danmakuEnabled;
  final bool canPrevious;
  final bool canNext;
  final List<VideoQuality> qualityOptions;
  final String currentQualityLabel;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onSetSpeed;
  final ValueChanged<VideoQuality> onSetQuality;
  final VoidCallback onTogglePlay;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleDanmaku;
  final VoidCallback onDanmakuSettings;
  final VoidCallback onOpenEpisodes;
  final VoidCallback onOpenHighlights;
  final VoidCallback onSendDanmaku;

  const PlayerBottomBar({
    super.key,
    required this.playback,
    this.durationFallback = Duration.zero,
    required this.highlights,
    this.statusChips = const [],
    required this.danmakuEnabled,
    required this.canPrevious,
    required this.canNext,
    required this.qualityOptions,
    required this.currentQualityLabel,
    required this.onSeek,
    required this.onSetSpeed,
    required this.onSetQuality,
    required this.onTogglePlay,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleDanmaku,
    required this.onDanmakuSettings,
    required this.onOpenEpisodes,
    required this.onOpenHighlights,
    required this.onSendDanmaku,
  });

  @override
  Widget build(BuildContext context) {
    final highlightFallback = _highlightDurationFallback();
    final total = playback.duration.inMilliseconds > 0
        ? playback.duration
        : durationFallback.inMilliseconds > 0
            ? durationFallback
            : highlightFallback;
    final progress = total > Duration.zero
        ? (playback.position < Duration.zero
            ? Duration.zero
            : playback.position > total
                ? total
                : playback.position)
        : Duration.zero;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Colors.transparent,
            Color(0xE60B0710),
            Color(0xF2050308),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: .08)),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentHot.withValues(alpha: .08),
            blurRadius: 28,
            spreadRadius: -20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (statusChips.isNotEmpty) ...[
          _statusStrip(),
          const SizedBox(height: 6),
        ],
        _ProgressTimeline(
          progress: progress,
          total: total,
          highlights: highlights,
          onSeek: onSeek,
        ),
        const SizedBox(height: 4),
        LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          if (compact) {
            return Column(children: [
              Row(children: [
                ..._transportControls(),
                const Spacer(),
                _qualityMenu(),
                _speedMenu(),
                IconButton(
                  tooltip: '选集',
                  onPressed: onOpenEpisodes,
                  icon: const Icon(Icons.video_library_outlined,
                      color: Colors.white),
                ),
                IconButton(
                  tooltip: '高光点',
                  onPressed: onOpenHighlights,
                  icon: const Icon(Icons.flash_on, color: AppColors.accentGold),
                ),
              ]),
              Row(children: [
                IconButton(
                  tooltip: danmakuEnabled ? '关闭弹幕' : '打开弹幕',
                  onPressed: onToggleDanmaku,
                  icon: Icon(
                      danmakuEnabled ? Icons.subtitles : Icons.subtitles_off,
                      color: Colors.white),
                ),
                IconButton(
                  tooltip: '弹幕设置',
                  onPressed: onDanmakuSettings,
                  icon: const Icon(Icons.tune, color: Colors.white),
                ),
                Expanded(child: _danmakuInput(context)),
              ]),
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            ..._transportControls(),
            IconButton(
              tooltip: danmakuEnabled ? '关闭弹幕' : '打开弹幕',
              onPressed: onToggleDanmaku,
              icon: Icon(danmakuEnabled ? Icons.subtitles : Icons.subtitles_off,
                  color: Colors.white),
            ),
            IconButton(
              tooltip: '弹幕设置',
              onPressed: onDanmakuSettings,
              icon: const Icon(Icons.tune, color: Colors.white),
            ),
            Expanded(child: _danmakuInput(context)),
            _qualityMenu(),
            _speedMenu(),
            IconButton(
              tooltip: '选集',
              onPressed: onOpenEpisodes,
              icon:
                  const Icon(Icons.video_library_outlined, color: Colors.white),
            ),
            IconButton(
              tooltip: '高光点',
              onPressed: onOpenHighlights,
              icon: const Icon(Icons.flash_on, color: AppColors.accentGold),
            ),
          ]);
        }),
      ]),
    );
  }

  Duration _highlightDurationFallback() {
    if (highlights.isEmpty) return Duration.zero;
    final maxSeconds = highlights.fold<double>(0, (maxValue, highlight) {
      return highlight.tsEnd > maxValue ? highlight.tsEnd : maxValue;
    });
    if (maxSeconds <= 1) return Duration.zero;
    return Duration(milliseconds: ((maxSeconds + 2) * 1000).round());
  }

  Widget _statusStrip() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xDB18111B), Color(0xCC0B0710)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentGold.withValues(alpha: .12),
            blurRadius: 24,
            spreadRadius: -14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  gradient: AppColors.ctaGradient,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .34),
                  ),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '同看现场',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: .4,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 34,
                height: 2,
                decoration: BoxDecoration(
                  gradient: AppColors.ctaGradient,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final text in statusChips) _hudChip(text),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hudChip(String text) {
    final spec = _chipSpec(text);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            spec.accent.withValues(alpha: .24),
            Colors.black.withValues(alpha: .18),
          ],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: spec.accent.withValues(alpha: .16),
            blurRadius: 18,
            spreadRadius: -10,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: spec.accent.withValues(alpha: .18),
              border: Border.all(color: spec.accent.withValues(alpha: .34)),
            ),
            child: Icon(spec.icon, size: 12, color: Colors.white),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  _HudChipSpec _chipSpec(String text) {
    if (text.contains('喜欢')) {
      return const _HudChipSpec(
        icon: Icons.favorite_rounded,
        accent: Color(0xFFFF3868),
      );
    }
    if (text.contains('鹅叫')) {
      return const _HudChipSpec(
        icon: Icons.campaign_rounded,
        accent: AppColors.accentGold,
      );
    }
    if (text.contains('同看') || text.contains('在线')) {
      return const _HudChipSpec(
        icon: Icons.groups_2_rounded,
        accent: AppColors.accentMint,
      );
    }
    if (text.contains('正在')) {
      return const _HudChipSpec(
        icon: Icons.local_fire_department_rounded,
        accent: AppColors.accentHot,
      );
    }
    if (text.contains('同步') || text.contains('连接') || text.contains('实时')) {
      return const _HudChipSpec(
        icon: Icons.sensors_rounded,
        accent: AppColors.accentVio,
      );
    }
    return const _HudChipSpec(
      icon: Icons.radio_button_checked_rounded,
      accent: AppColors.accentGold,
    );
  }

  List<Widget> _transportControls() => [
        IconButton(
          tooltip: playback.playing ? '暂停' : '播放',
          onPressed: onTogglePlay,
          icon: Icon(
            playback.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
          ),
        ),
        IconButton(
          tooltip: '上一集',
          onPressed: canPrevious ? onPrevious : null,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        IconButton(
          tooltip: '下一集',
          onPressed: canNext ? onNext : null,
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ];

  Widget _danmakuInput(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 36),
      child: GestureDetector(
        onTap: onSendDanmaku,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.edit, color: Colors.white70, size: 16),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                '发个友善的弹幕见证当下',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _speedMenu() {
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    return PopupMenuButton<double>(
      tooltip: '倍速',
      color: AppColors.bgRaised,
      onSelected: onSetSpeed,
      itemBuilder: (_) => [
        for (final speed in speeds)
          PopupMenuItem(
            value: speed,
            child:
                Text('${speed}x', style: const TextStyle(color: Colors.white)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
            '${playback.playbackSpeed.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '').replaceAll(RegExp(r'\.$'), '')}x',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _qualityMenu() {
    if (qualityOptions.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<VideoQuality>(
      tooltip: '清晰度',
      color: AppColors.bgRaised,
      onSelected: onSetQuality,
      itemBuilder: (_) => [
        for (final quality in qualityOptions)
          PopupMenuItem(
            value: quality,
            child: Row(children: [
              Icon(
                quality.label == currentQualityLabel ||
                        quality.displayLabel == currentQualityLabel
                    ? Icons.check_rounded
                    : Icons.hd_rounded,
                color: quality.label == currentQualityLabel ||
                        quality.displayLabel == currentQualityLabel
                    ? AppColors.accentMint
                    : Colors.white54,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                _qualityLabel(quality),
                style: const TextStyle(color: Colors.white),
              ),
            ]),
          ),
      ],
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: .10)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.hd_rounded, color: Colors.white, size: 17),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 58),
            child: Text(
              currentQualityLabel,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  String _qualityLabel(VideoQuality quality) {
    if (quality.height == null || quality.bandwidth == null) {
      return quality.displayLabel;
    }
    final mbps = quality.bandwidth! / 1000000;
    return '${quality.displayLabel} · ${mbps.toStringAsFixed(1)} Mbps';
  }
}

class _ProgressTimeline extends StatelessWidget {
  final Duration progress;
  final Duration total;
  final List<Highlight> highlights;
  final ValueChanged<Duration> onSeek;

  const _ProgressTimeline({
    required this.progress,
    required this.total,
    required this.highlights,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    void seekFromLocalPosition(Offset localPosition, double width) {
      if (total.inMilliseconds <= 0 || width <= 0) return;
      const thumbRadius = 7.0;
      const trackLeft = thumbRadius;
      final trackWidth = width - thumbRadius * 2;
      final ratio =
          ((localPosition.dx - trackLeft) / trackWidth).clamp(0.0, 1.0);
      onSeek(Duration(milliseconds: (total.inMilliseconds * ratio).round()));
    }

    return LayoutBuilder(builder: (context, constraints) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) =>
            seekFromLocalPosition(details.localPosition, constraints.maxWidth),
        onHorizontalDragUpdate: (details) =>
            seekFromLocalPosition(details.localPosition, constraints.maxWidth),
        child: SizedBox(
          height: 34,
          width: double.infinity,
          child: CustomPaint(
            painter: _ProgressTimelinePainter(
              progress: progress,
              total: total,
              highlights: highlights,
            ),
          ),
        ),
      );
    });
  }
}

class _ProgressTimelinePainter extends CustomPainter {
  final Duration progress;
  final Duration total;
  final List<Highlight> highlights;

  const _ProgressTimelinePainter({
    required this.progress,
    required this.total,
    required this.highlights,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const thumbRadius = 7.0;
    const trackY = 9.0;
    const trackLeft = thumbRadius;
    final trackRight = size.width - thumbRadius;
    final trackWidth = trackRight - trackLeft;
    if (trackWidth <= 0) return;

    final basePaint = Paint()
      ..color = Colors.white.withValues(alpha: .26)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final progressPaint = Paint()
      ..color = AppColors.accentHot
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        const Offset(trackLeft, trackY), Offset(trackRight, trackY), basePaint);

    final totalMs = total.inMilliseconds;
    final progressRatio =
        totalMs > 0 ? (progress.inMilliseconds / totalMs).clamp(0.0, 1.0) : 0.0;
    final progressX = trackLeft + trackWidth * progressRatio;
    canvas.drawLine(const Offset(trackLeft, trackY), Offset(progressX, trackY),
        progressPaint);

    if (totalMs > 0) {
      final dotFill = Paint()..color = AppColors.accentGold;
      final dotStroke = Paint()
        ..color = Colors.black.withValues(alpha: .6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (final highlight in highlights) {
        final ratio = (highlight.tsStart * 1000 / totalMs).clamp(0.0, 1.0);
        final x = trackLeft + trackWidth * ratio;
        final center = Offset(x, trackY);
        canvas.drawCircle(center, 4.8, dotFill);
        canvas.drawCircle(center, 4.8, dotStroke);
      }
    }

    final thumbPaint = Paint()..color = AppColors.accentHot;
    final thumbGlowPaint = Paint()
      ..color = AppColors.accentHot.withValues(alpha: .2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(progressX, trackY), 12, thumbGlowPaint);
    canvas.drawCircle(Offset(progressX, trackY), thumbRadius, thumbPaint);

    _paintTimeLabel(canvas, _formatDuration(progress), const Offset(0, 18));
    final totalLabel = _formatDuration(total);
    final totalPainter = _timeTextPainter(totalLabel);
    totalPainter.paint(canvas, Offset(size.width - totalPainter.width, 18));
  }

  void _paintTimeLabel(Canvas canvas, String text, Offset offset) {
    _timeTextPainter(text).paint(canvas, offset);
  }

  TextPainter _timeTextPainter(String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter;
  }

  String _formatDuration(Duration duration) {
    final value = duration.isNegative ? Duration.zero : duration;
    final minutes =
        value.inMinutes.remainder(Duration.minutesPerHour).toString();
    final seconds = value.inSeconds
        .remainder(Duration.secondsPerMinute)
        .toString()
        .padLeft(2, '0');
    return value.inHours > 0
        ? '${value.inHours}:${minutes.padLeft(2, '0')}:$seconds'
        : '$minutes:$seconds';
  }

  @override
  bool shouldRepaint(covariant _ProgressTimelinePainter oldDelegate) {
    return true;
  }
}

class _HudChipSpec {
  final IconData icon;
  final Color accent;

  const _HudChipSpec({required this.icon, required this.accent});
}
