import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import 'highlight_effect_painter.dart';

/// 按高光类型分发差异化全屏动效（搞笑 / 冲突 / 甜蜜 / 反转 / 名场面 / 悬念 / 虐心 / 剧尾）
/// 通过 [trigger] 自增触发一次播放；[type] 决定动画与配色。
/// [remote] = true 时使用低饱和半透明配色，避免与本地互动混淆。
class HighlightEffectOverlay extends StatefulWidget {
  final int trigger;
  final String type;
  final double intensity;
  final bool remote;

  const HighlightEffectOverlay({
    super.key,
    required this.trigger,
    this.type = '搞笑',
    this.intensity = .7,
    this.remote = false,
  });

  @override
  State<HighlightEffectOverlay> createState() => _HighlightEffectOverlayState();
}

class _HighlightEffectOverlayState extends State<HighlightEffectOverlay>
    with TickerProviderStateMixin {
  final List<HighlightEffectInstance> _effects = [];
  final _rand = Random();

  @override
  void didUpdateWidget(HighlightEffectOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger > oldWidget.trigger) {
      _spawn(widget.type, widget.remote);
    }
  }

  void _spawn(String type, bool remote) {
    final spec = _specFor(type);
    final controller = AnimationController(
      vsync: this,
      duration: spec.duration,
    );
    final instance = HighlightEffectInstance(
      controller: controller,
      spec: spec,
      seed: _rand.nextDouble(),
      remote: remote,
      intensity: widget.intensity.clamp(0.0, 1.0).toDouble(),
    );
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _effects.remove(instance);
        controller.dispose();
        if (mounted) setState(() {});
      }
    });
    _effects.add(instance);
    controller.forward();
    if (!remote && spec.haptic != null) {
      HapticFeedback.lightImpact();
      if (spec.haptic == HighlightEffectHaptic.heavy) {
        HapticFeedback.heavyImpact();
      }
    }
  }

  @override
  void dispose() {
    for (final e in _effects) {
      e.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_effects.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: _effects
              .map((e) => CustomPaint(
                    painter: HighlightEffectPainter(instance: e),
                  ))
              .toList(),
        ),
      ),
    );
  }

  HighlightEffectSpec _specFor(String type) {
    final key = type.trim();
    final isRemote = widget.remote;
    final normalized = key.toLowerCase();
    if (key.contains('爽') ||
        key.contains('打脸') ||
        key.contains('反杀') ||
        key.contains('解气')) {
      return const HighlightEffectSpec(
        kind: HighlightEffectKind.ignition,
        colors: [Color(0xFFFF6B35), Color(0xFFFFD166), Color(0xFFFFFFFF)],
        label: '',
        duration: Duration(milliseconds: 1600),
        haptic: HighlightEffectHaptic.heavy,
      );
    }
    if (key.contains('冲突') ||
        key.contains('燃') ||
        normalized.contains('power')) {
      return const HighlightEffectSpec(
        kind: HighlightEffectKind.ignition,
        colors: [Color(0xFFFF3D2E), Color(0xFFFFB23F), Color(0xFFFFF1B8)],
        label: '',
        duration: Duration(milliseconds: 1700),
        haptic: HighlightEffectHaptic.heavy,
      );
    }
    if (key.contains('反转') ||
        key.contains('转折') ||
        key.contains('悬念') ||
        key.contains('震惊') ||
        key.contains('紧张') ||
        key.contains('压迫') ||
        key.contains('窒息') ||
        key.contains('炸裂') ||
        normalized.contains('shock')) {
      return const HighlightEffectSpec(
        kind: HighlightEffectKind.fracture,
        colors: [Color(0xFF6CF1FF), Color(0xFF9A6BFF), Color(0xFFFF4D9D)],
        label: '',
        duration: Duration(milliseconds: 1450),
        haptic: HighlightEffectHaptic.heavy,
      );
    }
    if (key.contains('甜') || key.contains('心动') || key.contains('磕')) {
      return const HighlightEffectSpec(
        kind: HighlightEffectKind.roseBloom,
        colors: [Color(0xFFFF75B7), Color(0xFFFFC86F), Color(0xFFFFF0F7)],
        label: '',
        duration: Duration(milliseconds: 1800),
        haptic: HighlightEffectHaptic.light,
      );
    }
    if (key.contains('治愈') || key.contains('温暖')) {
      return const HighlightEffectSpec(
        kind: HighlightEffectKind.roseBloom,
        colors: [Color(0xFFFFD166), Color(0xFF5EE6A8), Color(0xFFFFFFFF)],
        label: '',
        duration: Duration(milliseconds: 1750),
        haptic: HighlightEffectHaptic.light,
      );
    }
    if (key.contains('名场面') || key.contains('封神')) {
      return const HighlightEffectSpec(
        kind: HighlightEffectKind.spotlight,
        colors: [Color(0xFFFFE6A3), Color(0xFFFFB23F), Color(0xFFFFFFFF)],
        label: '',
        duration: Duration(milliseconds: 1900),
        haptic: HighlightEffectHaptic.heavy,
      );
    }
    if (key.contains('搞笑') ||
        key.contains('笑') ||
        key.contains('离谱') ||
        key.contains('上头') ||
        normalized.contains('goose')) {
      return const HighlightEffectSpec(
        kind: HighlightEffectKind.comedyPop,
        colors: [Color(0xFFFFD24A), Color(0xFF66E1FF), Color(0xFFFF6F91)],
        label: '',
        duration: Duration(milliseconds: 1600),
        haptic: HighlightEffectHaptic.light,
      );
    }
    if (key.contains('虐') || key.contains('泪') || key.contains('哭')) {
      return const HighlightEffectSpec(
        kind: HighlightEffectKind.tearGlass,
        colors: [Color(0xFF7EA2FF), Color(0xFFB5F2FF), Color(0xFF1C244E)],
        label: '',
        duration: Duration(milliseconds: 1900),
        haptic: HighlightEffectHaptic.light,
      );
    }
    if (key.contains('破防') || key.contains('心疼')) {
      return const HighlightEffectSpec(
        kind: HighlightEffectKind.tearGlass,
        colors: [Color(0xFF8AB6FF), Color(0xFFFF9EC7), Color(0xFF1C244E)],
        label: '',
        duration: Duration(milliseconds: 1850),
        haptic: HighlightEffectHaptic.light,
      );
    }
    if (key.contains('完结') || key.contains('剧尾')) {
      return const HighlightEffectSpec(
        kind: HighlightEffectKind.finale,
        colors: [
          Color(0xFFFFE17B),
          Color(0xFFFF7AB6),
          Color(0xFF66E1FF),
          Color(0xFFA0FF8E),
        ],
        label: '',
        duration: Duration(milliseconds: 2200),
        haptic: HighlightEffectHaptic.heavy,
      );
    }

    return HighlightEffectSpec(
      kind: isRemote
          ? HighlightEffectKind.spotlight
          : HighlightEffectKind.ignition,
      colors: const [AppColors.accentHot, Color(0xFFFFB400), Colors.white],
      label: '',
      duration: const Duration(milliseconds: 1500),
      haptic: HighlightEffectHaptic.light,
    );
  }
}
