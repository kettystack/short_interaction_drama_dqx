import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/config.dart';
import 'playback_controller.dart';

class InsertClipController extends ChangeNotifier {
  bool isPlayingInsertedClip = false;
  bool isResumingMain = false;
  bool buffering = false;
  bool playing = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  Duration? resumePosition;
  String? mainVideoUrl;
  String? currentClipUrl;
  VideoController? videoController;

  Player? _player;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<bool>? _completedSubscription;
  final StreamController<void> _completedEvents =
      StreamController<void>.broadcast();
  bool _clipPositionAdvanced = false;
  bool _clipCompletionSent = false;
  bool _disposed = false;

  Stream<void> get completed => _completedEvents.stream;

  Future<void> playInsertedClip({
    required PlaybackController playback,
    required String currentMainVideoUrl,
    required String clipUrl,
    required Duration resumeAt,
  }) async {
    await _disposeClipPlayerNow();
    await playback.pause();
    mainVideoUrl = currentMainVideoUrl;
    resumePosition = resumeAt;
    currentClipUrl = clipUrl;
    position = Duration.zero;
    duration = Duration.zero;
    buffering = true;
    playing = false;
    _clipPositionAdvanced = false;
    _clipCompletionSent = false;
    isPlayingInsertedClip = true;
    isResumingMain = false;
    final player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 16 * 1024 * 1024,
        title: 'sdi-insert-clip',
      ),
    );
    _player = player;
    videoController = VideoController(player);
    _positionSubscription = player.stream.position.listen((value) {
      if (_disposed) return;
      position = value;
      if (value >= const Duration(milliseconds: 300)) {
        _clipPositionAdvanced = true;
      }
      _safeNotify();
    });
    _durationSubscription = player.stream.duration.listen((value) {
      if (_disposed) return;
      duration = value;
      _safeNotify();
    });
    _playingSubscription = player.stream.playing.listen((value) {
      if (_disposed) return;
      playing = value;
      _safeNotify();
    });
    _bufferingSubscription = player.stream.buffering.listen((value) {
      if (_disposed) return;
      buffering = value;
      _safeNotify();
    });
    _completedSubscription = player.stream.completed.listen((done) {
      if (_disposed || !done || !isPlayingInsertedClip || isResumingMain) {
        return;
      }
      if (_clipCompletionSent || !_clipPositionAdvanced) {
        return;
      }
      if (duration > const Duration(seconds: 1) &&
          position < duration - const Duration(milliseconds: 650)) {
        return;
      }
      _clipCompletionSent = true;
      _completedEvents.add(null);
    });
    notifyListeners();
    try {
      await player.open(Media(AppConfig.absoluteUrl(clipUrl)), play: true);
    } catch (_) {
      reset();
      rethrow;
    }
  }

  Future<void> resumeMainVideo(PlaybackController playback) async {
    final url = mainVideoUrl;
    final pos = resumePosition ?? Duration.zero;
    if (url == null || url.isEmpty || isResumingMain) return;
    isResumingMain = true;
    notifyListeners();
    try {
      await _player?.pause();
      await _disposeClipPlayerNow();
      isPlayingInsertedClip = false;
      buffering = false;
      playing = false;
      position = Duration.zero;
      duration = Duration.zero;
      _clipPositionAdvanced = false;
      _clipCompletionSent = false;
      notifyListeners();
      debugPrint(
        '[InsertClip] resume main url=$url at=${pos.inMilliseconds}ms',
      );
      if (playback.currentVideoUrl == url) {
        await playback.resumeCurrentAt(pos, autoplay: true);
      } else {
        await playback.openAt(url, pos, autoplay: true);
      }
    } finally {
      isPlayingInsertedClip = false;
      isResumingMain = false;
      buffering = false;
      playing = false;
      position = Duration.zero;
      duration = Duration.zero;
      resumePosition = null;
      mainVideoUrl = null;
      currentClipUrl = null;
      _clipPositionAdvanced = false;
      _clipCompletionSent = false;
      notifyListeners();
    }
  }

  Future<void> togglePlay() async {
    final player = _player;
    if (_disposed || player == null || !isPlayingInsertedClip) return;
    if (player.state.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  void reset() {
    _disposeClipPlayer();
    isPlayingInsertedClip = false;
    isResumingMain = false;
    buffering = false;
    playing = false;
    position = Duration.zero;
    duration = Duration.zero;
    resumePosition = null;
    mainVideoUrl = null;
    currentClipUrl = null;
    _clipPositionAdvanced = false;
    _clipCompletionSent = false;
    notifyListeners();
  }

  void _disposeClipPlayer() {
    unawaited(_disposeClipPlayerNow());
  }

  Future<void> _disposeClipPlayerNow() async {
    final subscriptions = [
      _positionSubscription,
      _durationSubscription,
      _playingSubscription,
      _bufferingSubscription,
      _completedSubscription,
    ];
    _positionSubscription = null;
    _durationSubscription = null;
    _playingSubscription = null;
    _bufferingSubscription = null;
    _completedSubscription = null;
    final player = _player;
    _player = null;
    videoController = null;
    await Future.wait<void>(
      subscriptions
          .whereType<StreamSubscription<dynamic>>()
          .map((subscription) => subscription.cancel()),
    );
    if (player != null) await player.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _disposeClipPlayer();
    unawaited(_completedEvents.close());
    super.dispose();
  }
}
