import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/config.dart';

/// 仿 Kazumi `PlayerPlaybackController`：封装 media_kit Player。
/// 负责 视频源加载 / 播放控制 / 进度回调 / 倍速 / 缓冲事件
class PlaybackController extends ChangeNotifier {
  final player = Player(
    configuration: const PlayerConfiguration(
      bufferSize: 32 * 1024 * 1024,
      title: 'sdi-player',
      // 与 Kazumi 一致的低延时启动配置可在此追加
    ),
  );
  late final controller = VideoController(player);

  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool playing = false;
  bool buffering = true;
  double playbackSpeed = 1.0;
  String? currentVideoUrl;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _disposed = false;

  /// Kazumi 风格：监听 stream，所有状态进入 notifier
  PlaybackController() {
    _subscriptions.add(player.stream.position.listen((d) {
      if (_disposed) return;
      position = d;
      _safeNotify();
    }));
    _subscriptions.add(player.stream.duration.listen((d) {
      if (_disposed) return;
      duration = d;
      _safeNotify();
    }));
    _subscriptions.add(player.stream.playing.listen((p) {
      if (_disposed) return;
      playing = p;
      _safeNotify();
    }));
    _subscriptions.add(player.stream.buffering.listen((b) {
      if (_disposed) return;
      buffering = b;
      _safeNotify();
    }));
  }

  Future<void> open(
    String videoUrl, {
    bool autoplay = false,
    Duration? startAt,
  }) async {
    if (_disposed) return;
    currentVideoUrl = videoUrl;
    _safeNotify();
    try {
      await player.open(
        Media(
          AppConfig.absoluteUrl(videoUrl),
          start: startAt,
        ),
        play: autoplay,
      );
    } catch (_) {
      if (!_disposed) rethrow;
    }
  }

  Future<void> togglePlay() async {
    if (_disposed) return;
    if (player.state.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> play() {
    if (_disposed) return Future.value();
    return player.play();
  }

  Future<void> pause() {
    if (_disposed) return Future.value();
    return player.pause();
  }

  Future<void> seek(Duration d) {
    if (_disposed) return Future.value();
    return player.seek(d);
  }

  Future<void> openAt(
    String videoUrl,
    Duration position, {
    bool autoplay = true,
  }) async {
    if (_disposed) return;
    await open(videoUrl, autoplay: false, startAt: position);
    if (_disposed) return;

    // Media.start lets mpv seek as part of loading. The explicit seek is a
    // second guard for platforms where the first range request finishes late.
    await seek(position);
    if (_disposed) return;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if ((this.position - position).abs() > const Duration(seconds: 2)) {
      await seek(position);
    }
    if (autoplay && !_disposed) {
      await play();
    }
  }

  Future<void> resumeCurrentAt(
    Duration position, {
    bool autoplay = true,
  }) async {
    if (_disposed) return;
    this.position = position;
    _safeNotify();
    await seek(position);
    if (_disposed) return;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if ((this.position - position).abs() > const Duration(seconds: 2)) {
      this.position = position;
      _safeNotify();
      await seek(position);
    }
    if (autoplay && !_disposed) {
      await play();
    }
  }

  Future<void> setSpeed(double rate) {
    if (_disposed) return Future.value();
    playbackSpeed = rate;
    _safeNotify();
    return player.setRate(rate);
  }

  Future<void> setVolume(double vol /* 0-100 */) {
    if (_disposed) return Future.value();
    return player.setVolume(vol);
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    player.dispose();
    super.dispose();
  }
}
