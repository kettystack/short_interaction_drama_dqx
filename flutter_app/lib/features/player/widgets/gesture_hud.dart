import 'package:flutter/material.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../../core/theme.dart';
import '../../../shared/utils/format.dart';
import '../controllers/playback_controller.dart';

/// 仿 Kazumi `player_adjustment_hud`：左半屏=亮度，右半屏=音量，
/// 横向滑动=进度，HUD 居中显示半透明面板。
class GestureHud extends StatefulWidget {
  final PlaybackController playback;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final ValueChanged<Duration>? onSeek;

  const GestureHud({
    super.key,
    required this.playback,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.onSeek,
  });

  @override
  State<GestureHud> createState() => _GestureHudState();
}

enum _Drag { none, brightness, volume, seek }

class _GestureHudState extends State<GestureHud> {
  _Drag _drag = _Drag.none;
  double _brightness = 0.5;
  double _volume = 0.5;
  Duration _seekTo = Duration.zero;
  double _startX = 0;
  Duration _startPos = Duration.zero;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap ?? () => widget.playback.togglePlay(),
      onDoubleTap: widget.onDoubleTap,
      onVerticalDragStart: _onVStart,
      onVerticalDragUpdate: _onVUpdate,
      onVerticalDragEnd: (_) => setState(() => _drag = _Drag.none),
      onHorizontalDragStart: _onHStart,
      onHorizontalDragUpdate: _onHUpdate,
      onHorizontalDragEnd: (_) {
        if (_drag == _Drag.seek) {
          if (widget.onSeek != null) {
            widget.onSeek!(_seekTo);
          } else {
            widget.playback.seek(_seekTo);
          }
        }
        setState(() => _drag = _Drag.none);
      },
      child: Stack(children: [
        Positioned.fill(child: widget.child),
        if (_drag != _Drag.none) Positioned.fill(child: _hud()),
      ]),
    );
  }

  Future<void> _onVStart(DragStartDetails d) async {
    _startX = d.localPosition.dx;
    final size = MediaQuery.of(context).size;
    if (_startX < size.width / 2) {
      _drag = _Drag.brightness;
      _brightness = await ScreenBrightness().application;
    } else {
      _drag = _Drag.volume;
      _volume = await FlutterVolumeController.getVolume() ?? .5;
    }
    setState(() {});
  }

  void _onVUpdate(DragUpdateDetails d) {
    final delta = -d.delta.dy / 200;
    if (_drag == _Drag.brightness) {
      _brightness = (_brightness + delta).clamp(0.0, 1.0);
      ScreenBrightness().setApplicationScreenBrightness(_brightness);
    } else if (_drag == _Drag.volume) {
      _volume = (_volume + delta).clamp(0.0, 1.0);
      FlutterVolumeController.setVolume(_volume);
    }
    setState(() {});
  }

  void _onHStart(DragStartDetails d) {
    _drag = _Drag.seek;
    _startPos = widget.playback.position;
    _seekTo = _startPos;
    setState(() {});
  }

  void _onHUpdate(DragUpdateDetails d) {
    final size = MediaQuery.of(context).size;
    final ratio = d.delta.dx / size.width;
    final total = widget.playback.duration;
    _seekTo += Duration(
      milliseconds: (ratio * total.inMilliseconds * .5).round(),
    );
    if (_seekTo < Duration.zero) _seekTo = Duration.zero;
    if (_seekTo > total) _seekTo = total;
    setState(() {});
  }

  Widget _hud() {
    String icon = '';
    String label = '';
    double pct = 0;
    switch (_drag) {
      case _Drag.brightness:
        icon = '亮';
        label = '亮度 ${(_brightness * 100).round()}%';
        pct = _brightness;
        break;
      case _Drag.volume:
        icon = '音';
        label = '音量 ${(_volume * 100).round()}%';
        pct = _volume;
        break;
      case _Drag.seek:
        icon = '进';
        label =
            '${formatDuration(_seekTo)} / ${formatDuration(widget.playback.duration)}';
        pct = widget.playback.duration.inMilliseconds == 0
            ? 0
            : _seekTo.inMilliseconds / widget.playback.duration.inMilliseconds;
        break;
      case _Drag.none:
        break;
    }
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$icon  $label',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 10),
            SizedBox(
              width: 160,
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: Colors.white24,
                color: AppColors.accentHot,
                minHeight: 3,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
