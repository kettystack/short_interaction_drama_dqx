import 'package:flutter/material.dart';

/// 仿腾讯视频：单击屏幕后中心弹出半透明播放/暂停图标，
/// 800ms 后自动淡出。
class PlayPauseIndicator extends StatefulWidget {
  /// 每次外部值变化（如 ++）触发一次动画
  final int trigger;
  final bool isPlaying;

  const PlayPauseIndicator({
    super.key,
    required this.trigger,
    required this.isPlaying,
  });

  @override
  State<PlayPauseIndicator> createState() => _PlayPauseIndicatorState();
}

class _PlayPauseIndicatorState extends State<PlayPauseIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void didUpdateWidget(covariant PlayPauseIndicator old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger) {
      _anim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, __) {
            final t = _anim.value;
            if (t == 0) return const SizedBox.shrink();
            final scale = 0.8 + 0.4 * t;
            final opacity = (1 - t).clamp(0.0, 1.0);
            return Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 54,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
