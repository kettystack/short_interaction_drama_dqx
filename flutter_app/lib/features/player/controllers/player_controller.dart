import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce/hive.dart';

import '../../../data/api_client.dart';
import '../../../data/models.dart';
import '../../aigc_video/aigc_video_controller.dart';
import '../../branch_video/controllers/branch_video_controller.dart';
import '../../branch_video/data/branch_video_api.dart';
import '../../branch_video/data/branch_video_models.dart';
import 'danmaku_controller.dart';
import 'interaction_controller.dart';
import 'insert_clip_controller.dart';
import 'playback_controller.dart';
import 'player_experience_coordinator.dart';

/// 聚合控制器 —— 仿 Kazumi `PlayerController` 设计：
/// 内部持有 playback / danmaku / interaction 子 controller，统一生命周期。
class PlayerController extends ChangeNotifier {
  static const bool _ignoreCachedProgress =
      bool.fromEnvironment('IGNORE_CACHED_PROGRESS');

  PlayerController() : _api = Modular.get<ApiClient>() {
    playback = PlaybackController();
    danmaku = DanmakuPlayerController(_api);
    interaction = InteractionController(_api);
    aigc = AigcVideoController(_api);
    insertClip = InsertClipController();
    branchVideo = BranchVideoController(BranchVideoApi.create());
    experience = PlayerExperienceCoordinator();
    aigc.addListener(_maybePlayReadyAigcJob);
    branchVideo.addListener(_onBranchVideoChanged);
    insertClip.addListener(_syncExperienceState);
    _insertClipCompletedSubscription = insertClip.completed.listen((_) {
      if (_disposed || insertClip.isResumingMain) return;
      unawaited(resumeMainAfterInsertedClip());
    });

    // 主时间轴 -> 弹幕 + 互动联动（Kazumi 风格事件驱动）
    _positionSubscription = playback.player.stream.position.listen((d) {
      if (_disposed) return;
      if (insertClip.isPlayingInsertedClip) return;
      final branchTicksSuppressed = _areBranchTicksSuppressed;
      if (!branchTicksSuppressed) {
        branchVideo.onTick(d.inMilliseconds / 1000.0);
      }
      danmaku.onTick(d);
      interaction.onTick(d.inMilliseconds / 1000.0);
      _updateActiveBoostPoint(d.inMilliseconds / 1000.0);
      // 剧尾撒花触发（最后 5 秒）
      final dur = playback.duration.inMilliseconds / 1000.0;
      if (dur > 0 && !branchTicksSuppressed) {
        interaction.notifyEnding(d.inMilliseconds / 1000.0, dur);
      }
      if (!branchTicksSuppressed) {
        _saveProgressIfNeeded(d);
      }
    });

    // 自适应码率（ABR）：30s 窗内出现 ≥2 次 stall（缓冲 >1.5s）就自动降一档清晰度。
    _bufferingSubscription = playback.player.stream.buffering.listen((b) {
      if (_disposed) return;
      final now = DateTime.now();
      if (b) {
        _stallStart = now;
      } else if (_stallStart != null) {
        final stallMs = now.difference(_stallStart!).inMilliseconds;
        _stallStart = null;
        if (stallMs >= 1500 && playback.playing) {
          _stallEventsAt.add(now);
          _stallEventsAt.removeWhere(
              (t) => now.difference(t) > const Duration(seconds: 30));
          if (_stallEventsAt.length >= 2) {
            _stallEventsAt.clear();
            unawaited(_autoDowngradeQuality());
          }
        }
      }
    });

    _playingSubscription = playback.player.stream.playing.listen((playing) {
      if (_disposed) return;
      danmaku.setPlaybackRunning(playing);
    });

    _completedSubscription = playback.player.stream.completed.listen((done) {
      if (_disposed || !done) return;
      if (_isCurrentMainVideo && !_isMainCompletionSuppressed) {
        unawaited(_maybeAdvanceAfterMainCompleted());
      }
    });

    _durationSubscription = playback.player.stream.duration.listen((duration) {
      if (_disposed || !_validDuration(duration)) return;
      // 插片时长不能覆盖正片缓存，否则恢复位置会被错误压到插片末尾。
      if (insertClip.isPlayingInsertedClip) return;
      final ep = episode;
      if (ep == null) return;
      cachedMediaDuration = duration;
      Hive.box('media_durations').put(ep.id, duration.inMilliseconds);
      _safeNotify();
    });
  }

  final ApiClient _api;
  late final PlaybackController playback;
  late final DanmakuPlayerController danmaku;
  late final InteractionController interaction;
  late final AigcVideoController aigc;
  late final InsertClipController insertClip;
  late final BranchVideoController branchVideo;
  late final PlayerExperienceCoordinator experience;

  Episode? episode;
  List<Episode> dramaEpisodes = const [];
  List<AigcBoostPoint> boostPoints = const [];
  AigcBoostPoint? activeBoostPoint;
  AigcBoostPoint? playingBoostPoint;
  VideoQuality? selectedQuality;
  String? _currentMainVideoUrl;
  Duration cachedMediaDuration = Duration.zero;
  bool isFavorite = false;
  String? _lastPlayedAigcJobId;
  String? _lastPlayedBranchVariantId;
  BranchPlaybackTicket? playingBranchTicket;
  bool _resumeAfterBranchChoice = false;
  final Set<String> _dismissedBoostPointIds = <String>{};
  final Set<String> _playedBoostPointIds = <String>{};
  DateTime _lastProgressSync = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<void>? _insertClipCompletedSubscription;
  DateTime? _stallStart;
  final List<DateTime> _stallEventsAt = [];
  Timer? _insertClipWatchdog;
  DateTime? _insertClipStartedAt;
  Duration? _expectedInsertedClipDuration;
  DateTime? _suppressMainCompletedUntil;
  DateTime? _suppressBranchTicksUntil;
  bool _resumeMainInFlight = false;
  bool _autoAdvanceInFlight = false;
  bool _disposed = false;

  bool get _isCurrentMainVideo {
    final current = playback.currentVideoUrl;
    final main = _currentMainVideoUrl;
    return current != null && main != null && current == main;
  }

  bool get _isMainCompletionSuppressed {
    final until = _suppressMainCompletedUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _suppressMainCompletedUntil = null;
    return false;
  }

  bool get _areBranchTicksSuppressed {
    final until = _suppressBranchTicksUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _suppressBranchTicksUntil = null;
    return false;
  }

  Future<void> _autoDowngradeQuality() async {
    final ep = episode;
    final current = selectedQuality;
    if (ep == null || current == null) return;
    final options = ep.qualityOptions;
    if (options.length < 2) return;
    // qualityOptions 默认按从高到低排列；找到当前清晰度再选下一档
    final idx = options
        .indexWhere((q) => q.label == current.label && q.url == current.url);
    if (idx < 0 || idx + 1 >= options.length) return;
    debugPrint(
        '[ABR] auto downgrade: ${current.label} -> ${options[idx + 1].label}');
    await setQuality(options[idx + 1]);
  }

  Future<void> load(String episodeId) async {
    if (_disposed) return;
    episode = await _api.getEpisode(episodeId);
    if (_disposed) return;
    cachedMediaDuration = _cachedMediaDurationFor(episodeId);
    isFavorite = Hive.box('favorites').containsKey(episodeId);
    dramaEpisodes = await _api.getEpisodes(dramaId: episode!.dramaId);
    if (_disposed) return;
    dramaEpisodes = [...dramaEpisodes]
      ..sort((a, b) => a.episodeNo.compareTo(b.episodeNo));
    selectedQuality = _defaultQualityFor(episode!);
    _currentMainVideoUrl = selectedQuality!.url;
    _lastPlayedAigcJobId = null;
    _lastPlayedBranchVariantId = null;
    playingBranchTicket = null;
    _resumeAfterBranchChoice = false;
    _suppressMainCompletedUntil = null;
    activeBoostPoint = null;
    playingBoostPoint = null;
    boostPoints = const [];
    _dismissedBoostPointIds.clear();
    _playedBoostPointIds.clear();
    insertClip.reset();
    aigc.clear();
    unawaited(branchVideo.loadFor(episodeId));
    final boostPointsFuture = _api
        .getAigcBoostPoints(episodeId)
        .catchError((Object _) => <AigcBoostPoint>[]);
    await Future.wait([
      playback.open(selectedQuality!.url, autoplay: true),
      danmaku.loadFor(episodeId),
      interaction.loadFor(episodeId),
      boostPointsFuture,
    ]);
    boostPoints = await boostPointsFuture;
    if (_disposed) return;
    final cached =
        _ignoreCachedProgress ? null : Hive.box('progress').get(episodeId);
    final resumeAt = _cachedResumePosition(cached);
    if (resumeAt != null) {
      await seekTo(resumeAt);
    }
    if (_disposed) return;
    _safeNotify();
  }

  List<VideoQuality> get qualityOptions => episode?.qualityOptions ?? const [];

  String get currentQualityLabel => selectedQuality?.displayLabel ?? '自动';

  VideoQuality _defaultQualityFor(Episode ep) {
    final options = ep.qualityOptions;
    if (options.isNotEmpty) return options.first;
    return VideoQuality(label: '默认', url: ep.preferredVideoUrl);
  }

  bool _validDuration(Duration value) {
    return value.inMilliseconds > 1000 && value.inHours < 12;
  }

  Duration get _episodeDurationFallback {
    if (_validDuration(cachedMediaDuration)) return cachedMediaDuration;
    final seconds = episode?.duration ?? 0;
    if (seconds <= 1 || seconds > 12 * 3600) return Duration.zero;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  Duration get effectiveDuration {
    if (_validDuration(playback.duration)) return playback.duration;
    return _episodeDurationFallback;
  }

  Duration _cachedMediaDurationFor(String episodeId) {
    final raw = Hive.box('media_durations').get(episodeId);
    if (raw is num) {
      final duration = Duration(milliseconds: raw.toInt());
      if (_validDuration(duration)) return duration;
    }
    final progress = Hive.box('progress').get(episodeId);
    if (progress is Map) {
      final seconds = progress['duration'];
      if (seconds is num) {
        final duration = Duration(milliseconds: (seconds * 1000).round());
        if (_validDuration(duration)) return duration;
      }
    }
    return Duration.zero;
  }

  Duration get _seekLimit {
    if (_validDuration(playback.duration)) return playback.duration;
    return _episodeDurationFallback;
  }

  Duration _clampSeekTarget(Duration target) {
    if (target < Duration.zero) return Duration.zero;
    final limit = _seekLimit;
    if (!_validDuration(limit)) return target;
    final safeEnd = limit > const Duration(seconds: 2)
        ? limit - const Duration(milliseconds: 800)
        : limit;
    return target > safeEnd ? safeEnd : target;
  }

  Duration? _cachedResumePosition(Object? cached) {
    if (cached is! Map) return null;
    final rawSeconds = cached['seconds'];
    if (rawSeconds is! num || rawSeconds <= 3) return null;
    final raw = Duration(milliseconds: (rawSeconds * 1000).round());
    final limit = _seekLimit;
    if (_validDuration(limit) && raw >= limit - const Duration(seconds: 2)) {
      return null;
    }
    return _clampSeekTarget(raw);
  }

  Future<void> setQuality(VideoQuality quality) async {
    if (_disposed || quality.url.isEmpty) return;
    final current = selectedQuality;
    if (current != null &&
        current.label == quality.label &&
        current.url == quality.url) {
      return;
    }
    final resumeAt = _clampSeekTarget(playback.position);
    final shouldPlay = playback.playing;
    selectedQuality = quality;
    _currentMainVideoUrl = quality.url;
    _safeNotify();
    await playback.open(quality.url, autoplay: false);
    if (_disposed) return;
    final target = _clampSeekTarget(resumeAt);
    await playback.seek(target);
    if (_disposed) return;
    danmaku.resetTo(target);
    interaction.onSeek(target.inMilliseconds / 1000.0);
    if (shouldPlay) await playback.play();
  }

  Future<void> seekTo(Duration d) async {
    if (_disposed) return;
    final target = _clampSeekTarget(d);
    await playback.seek(target);
    danmaku.resetTo(target);
    interaction.onSeek(target.inMilliseconds / 1000.0);
    _updateActiveBoostPoint(target.inMilliseconds / 1000.0);
  }

  Future<void> setSpeed(double rate) async {
    if (_disposed) return;
    await playback.setSpeed(rate);
    danmaku.setPlaybackRate(rate);
  }

  Future<void> chooseBranch(BranchOption option) async {
    await interaction.chooseBranch(option);
    if (option.videoUrl != null && option.videoUrl!.isNotEmpty) {
      final mainUrl = _currentMainVideoUrl ??
          selectedQuality?.url ??
          episode?.preferredVideoUrl;
      if (mainUrl == null || mainUrl.isEmpty) return;
      final resumeAt = _clampSeekTarget(
        playback.position + const Duration(seconds: 5),
      );
      await insertClip.playInsertedClip(
        playback: playback,
        currentMainVideoUrl: mainUrl,
        clipUrl: option.videoUrl!,
        resumeAt: resumeAt,
      );
      _startInsertedClipWatchdog();
    }
  }

  Future<void> choosePersonalizedBranch(
    PersonalizedBranchOption option,
  ) async {
    if (_disposed || insertClip.isPlayingInsertedClip) return;
    await branchVideo.selectOption(option);
  }

  Future<void> createCustomPersonalizedBranch(String prompt) async {
    if (_disposed || insertClip.isPlayingInsertedClip) return;
    await branchVideo.createCustomOption(prompt);
  }

  void skipPersonalizedBranch() {
    if (_disposed) return;
    branchVideo.skipPending();
  }

  Future<void> playPersonalizedBranch(
    BranchPlaybackTicket ticket,
  ) async {
    if (_disposed ||
        insertClip.isPlayingInsertedClip ||
        ticket.videoUrl.isEmpty) {
      return;
    }
    final currentMainUrl = _currentMainVideoUrl ??
        selectedQuality?.url ??
        episode?.preferredVideoUrl;
    if (currentMainUrl == null || currentMainUrl.isEmpty) return;
    _resumeAfterBranchChoice = false;
    playingBranchTicket = ticket;
    activeBoostPoint = null;
    playingBoostPoint = null;
    branchVideo.markPlaybackStarted(ticket);
    debugPrint(
      '[BranchVideo] play ticket session=${ticket.sessionId} '
      'option=${ticket.optionId} resumeAt=${ticket.resumeAt} '
      'duration=${ticket.duration} video=${ticket.videoUrl}',
    );
    _safeNotify();
    try {
      await insertClip.playInsertedClip(
        playback: playback,
        currentMainVideoUrl: currentMainUrl,
        clipUrl: ticket.videoUrl,
        resumeAt: _clampSeekTarget(
          Duration(milliseconds: (ticket.resumeAt * 1000).round()),
        ),
      );
      _startInsertedClipWatchdog(
        expectedDuration: Duration(
          milliseconds: (ticket.duration * 1000).round(),
        ),
      );
      unawaited(branchVideo.recordPlaybackEvent(ticket, 'play_start'));
    } catch (_) {
      playingBranchTicket = null;
      _lastPlayedBranchVariantId = null;
      rethrow;
    }
  }

  Future<AigcVideoJob?> requestAigcBoost({
    String triggerType = 'boost',
    String userPrompt = '',
    int? highlightId,
  }) async {
    if (_disposed || insertClip.isPlayingInsertedClip) return null;
    final ep = episode;
    if (ep == null) return null;
    await aigc.createJob(
      episodeId: ep.id,
      tsInVideo: playback.position.inMilliseconds / 1000.0,
      triggerType: triggerType,
      userPrompt: userPrompt,
      highlightId: highlightId ?? interaction.activeHighlight?.id,
      storyThreadId: interaction.storyThread?.threadId,
    );
    return aigc.currentJob;
  }

  Future<void> playAigcJob(AigcVideoJob job) async {
    if (_disposed || !job.isReady || insertClip.isPlayingInsertedClip) return;
    final currentMainUrl = _currentMainVideoUrl ??
        selectedQuality?.url ??
        episode?.preferredVideoUrl;
    if (currentMainUrl == null || currentMainUrl.isEmpty) return;
    final resumeAt = Duration(milliseconds: (job.resumeAt * 1000).round());
    playingBoostPoint = null;
    await insertClip.playInsertedClip(
      playback: playback,
      currentMainVideoUrl: currentMainUrl,
      clipUrl: job.outputVideoUrl,
      resumeAt: _clampSeekTarget(resumeAt),
    );
    _startInsertedClipWatchdog(
      expectedDuration: Duration(milliseconds: (job.duration * 1000).round()),
    );
  }

  Future<void> playBoostPoint(AigcBoostPoint point) async {
    if (_disposed || !point.isPlayable || insertClip.isPlayingInsertedClip) {
      return;
    }
    final currentMainUrl = _currentMainVideoUrl ??
        selectedQuality?.url ??
        episode?.preferredVideoUrl;
    if (currentMainUrl == null || currentMainUrl.isEmpty) return;
    _playedBoostPointIds.add(point.id);
    _dismissedBoostPointIds.add(point.id);
    activeBoostPoint = null;
    playingBoostPoint = point;
    _safeNotify();
    final resumeAt = Duration(milliseconds: (point.resumeAt * 1000).round());
    await insertClip.playInsertedClip(
      playback: playback,
      currentMainVideoUrl: currentMainUrl,
      clipUrl: point.outputVideoUrl,
      resumeAt: _clampSeekTarget(resumeAt),
    );
    _startInsertedClipWatchdog(
      expectedDuration: Duration(milliseconds: (point.duration * 1000).round()),
    );
  }

  void dismissBoostPoint(AigcBoostPoint point) {
    if (_disposed) return;
    _dismissedBoostPointIds.add(point.id);
    if (activeBoostPoint?.id == point.id) {
      activeBoostPoint = null;
      _safeNotify();
    }
  }

  Future<void> resumeMainAfterInsertedClip() async {
    if (_disposed || !insertClip.isPlayingInsertedClip || _resumeMainInFlight) {
      return;
    }
    _resumeMainInFlight = true;
    _suppressMainCompletedUntil = DateTime.now().add(
      const Duration(seconds: 30),
    );
    _suppressBranchTicksUntil = DateTime.now().add(
      const Duration(seconds: 4),
    );
    _cancelInsertedClipWatchdog();
    final target = insertClip.resumePosition ?? Duration.zero;
    final branchTicket = playingBranchTicket;
    debugPrint(
      '[InsertClip] resume main target=${target.inMilliseconds}ms '
      'episode=${episode?.id} main=$_currentMainVideoUrl',
    );
    try {
      await insertClip.resumeMainVideo(playback);
      debugPrint(
        '[InsertClip] main resumed position=${playback.position.inMilliseconds}ms '
        'duration=${playback.duration.inMilliseconds}ms playing=${playback.playing}',
      );
      if (_disposed) return;
      if (branchVideo.pendingSession != null) {
        branchVideo.skipPending();
      }
      _suppressBranchTicksUntil = DateTime.now().add(
        const Duration(seconds: 2),
      );
      final safeTarget = target < Duration.zero ? Duration.zero : target;
      danmaku.resetTo(safeTarget);
      interaction.onSeek(safeTarget.inMilliseconds / 1000.0);
      playingBoostPoint = null;
      playingBranchTicket = null;
      if (branchTicket != null) {
        unawaited(
          branchVideo.recordPlaybackEvent(
            branchTicket,
            'play_complete',
            clipPosition: branchTicket.duration,
          ),
        );
      }
      _updateActiveBoostPoint(safeTarget.inMilliseconds / 1000.0);
      _syncExperienceState();
      _safeNotify();
    } finally {
      _resumeMainInFlight = false;
    }
  }

  Future<void> nextEpisode() async {
    final next = _neighbor(1);
    if (next != null) await load(next.id);
  }

  Future<void> _maybeAdvanceAfterMainCompleted() async {
    if (_disposed ||
        _autoAdvanceInFlight ||
        insertClip.isPlayingInsertedClip ||
        insertClip.isResumingMain ||
        !_isCurrentMainVideo ||
        _isMainCompletionSuppressed ||
        branchVideo.hasBlockingExperience) {
      return;
    }
    final mainDuration = _episodeDurationFallback;
    if (!_validDuration(mainDuration)) return;
    if (playback.position < mainDuration - const Duration(milliseconds: 1200)) {
      return;
    }
    final next = _neighbor(1);
    if (next == null) return;
    _autoAdvanceInFlight = true;
    try {
      await load(next.id);
    } finally {
      _autoAdvanceInFlight = false;
    }
  }

  Future<void> previousEpisode() async {
    final prev = _neighbor(-1);
    if (prev != null) await load(prev.id);
  }

  Episode? _neighbor(int offset) {
    final current = episode;
    if (current == null || dramaEpisodes.isEmpty) return null;
    final index = dramaEpisodes.indexWhere((e) => e.id == current.id);
    final nextIndex = index + offset;
    if (index < 0 || nextIndex < 0 || nextIndex >= dramaEpisodes.length) {
      return null;
    }
    return dramaEpisodes[nextIndex];
  }

  Future<void> toggleFavorite() async {
    if (_disposed) return;
    final ep = episode;
    if (ep == null) return;
    final box = Hive.box('favorites');
    isFavorite = !isFavorite;
    if (isFavorite) {
      await box.put(ep.id, {
        'id': ep.id,
        'drama_id': ep.dramaId,
        'title': ep.title,
        'episode_no': ep.episodeNo,
        'cover_url': ep.coverUrl,
      });
    } else {
      await box.delete(ep.id);
    }
    _safeNotify();
    _api
        .saveEpisodeAction(
          episodeId: ep.id,
          action: 'favorite',
          active: isFavorite,
        )
        .catchError((_) {});
  }

  Future<void> sendDanmaku(String text) async {
    final ep = episode;
    if (ep == null) return;
    final ts = playback.position.inMilliseconds / 1000.0;
    danmaku.sendSelf(text);
    try {
      await _api.postDanmaku(episodeId: ep.id, content: text, ts: ts);
    } catch (_) {}
  }

  void _saveProgressIfNeeded(Duration position) {
    if (_disposed) return;
    final ep = episode;
    if (ep == null) return;
    final now = DateTime.now();
    if (now.difference(_lastProgressSync).inSeconds < 5) return;
    _lastProgressSync = now;
    final limit = _seekLimit;
    final safePosition = _validDuration(limit) && position > limit
        ? _clampSeekTarget(position)
        : position;
    final seconds = safePosition.inMilliseconds / 1000.0;
    final duration = _validDuration(limit)
        ? limit.inMilliseconds / 1000.0
        : playback.duration.inMilliseconds / 1000.0;
    Hive.box('progress').put(ep.id, {
      'seconds': seconds,
      'duration': duration,
      'title': ep.title,
      'cover_url': ep.coverUrl,
      'updated_at': now.toIso8601String(),
    });
    _api
        .saveProgress(
          episodeId: ep.id,
          progressSeconds: seconds,
          duration: duration,
        )
        .catchError((_) {});
  }

  void _maybePlayReadyAigcJob() {
    if (_disposed) return;
    final job = aigc.currentJob;
    if (job == null || !job.isReady || job.jobId == _lastPlayedAigcJobId) {
      return;
    }
    _lastPlayedAigcJobId = job.jobId;
    unawaited(playAigcJob(job));
  }

  void _onBranchVideoChanged() {
    if (_disposed) return;
    final ticket = branchVideo.pendingPlaybackTicket;
    if (ticket != null &&
        ticket.variantId.isNotEmpty &&
        ticket.variantId != _lastPlayedBranchVariantId) {
      _lastPlayedBranchVariantId = ticket.variantId;
      unawaited(playPersonalizedBranch(ticket));
    }
    final branchPending =
        branchVideo.pendingSession != null && !insertClip.isPlayingInsertedClip;
    if (branchPending && playback.playing) {
      _resumeAfterBranchChoice = true;
      unawaited(playback.pause());
    } else if (!branchPending &&
        _resumeAfterBranchChoice &&
        !insertClip.isPlayingInsertedClip &&
        ticket == null) {
      _resumeAfterBranchChoice = false;
      unawaited(playback.play());
    }
    if (branchPending && activeBoostPoint != null) {
      activeBoostPoint = null;
    }
    _syncExperienceState();
    _safeNotify();
  }

  void _syncExperienceState() {
    if (_disposed) return;
    final session = branchVideo.pendingSession;
    final selected = session?.optionById(branchVideo.selectedOptionId ?? '');
    final generating = branchVideo.isSubmitting ||
        (selected != null && !selected.isReady) ||
        (session?.isGenerating ?? false);
    experience.sync(
      insertedClip: insertClip.isPlayingInsertedClip,
      branchPending: session != null && !insertClip.isPlayingInsertedClip,
      branchGenerating: generating,
      boostAvailable: activeBoostPoint != null,
      highlightVisible: interaction.activeHighlight != null,
    );
  }

  void _updateActiveBoostPoint(double tsInSeconds) {
    if (_disposed ||
        insertClip.isPlayingInsertedClip ||
        branchVideo.hasBlockingExperience) {
      if (activeBoostPoint != null) {
        activeBoostPoint = null;
        _safeNotify();
      }
      return;
    }
    AigcBoostPoint? next;
    for (final point in boostPoints) {
      if (!point.isPlayable ||
          _dismissedBoostPointIds.contains(point.id) ||
          _playedBoostPointIds.contains(point.id)) {
        continue;
      }
      if (tsInSeconds >= point.triggerTs - 1.0 &&
          tsInSeconds <= point.triggerTs + 12.0) {
        next = point;
        break;
      }
    }
    if (activeBoostPoint?.id != next?.id) {
      activeBoostPoint = next;
      _syncExperienceState();
      _safeNotify();
    }
  }

  void _startInsertedClipWatchdog({
    Duration? expectedDuration,
  }) {
    _insertClipWatchdog?.cancel();
    _insertClipStartedAt = DateTime.now();
    _expectedInsertedClipDuration =
        expectedDuration != null && expectedDuration.inMilliseconds > 0
            ? expectedDuration
            : null;
    _insertClipWatchdog = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _checkInsertedClipCompletion(),
    );
  }

  void _checkInsertedClipCompletion() {
    if (_disposed || !insertClip.isPlayingInsertedClip) {
      _cancelInsertedClipWatchdog();
      return;
    }
    if (insertClip.isResumingMain || _resumeMainInFlight) return;

    final position = insertClip.position;
    final duration = insertClip.duration;
    if (_validDuration(duration) &&
        position >= duration - const Duration(milliseconds: 650)) {
      unawaited(resumeMainAfterInsertedClip());
      return;
    }

    final expected = _expectedInsertedClipDuration;
    final startedAt = _insertClipStartedAt;
    if (expected == null || startedAt == null) return;
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed >= expected + const Duration(seconds: 2) &&
        (!insertClip.playing ||
            position >= expected - const Duration(milliseconds: 900))) {
      unawaited(resumeMainAfterInsertedClip());
    }
  }

  void _cancelInsertedClipWatchdog() {
    _insertClipWatchdog?.cancel();
    _insertClipWatchdog = null;
    _insertClipStartedAt = null;
    _expectedInsertedClipDuration = null;
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_bufferingSubscription?.cancel());
    unawaited(_playingSubscription?.cancel());
    unawaited(_completedSubscription?.cancel());
    unawaited(_insertClipCompletedSubscription?.cancel());
    _cancelInsertedClipWatchdog();
    aigc.removeListener(_maybePlayReadyAigcJob);
    branchVideo.removeListener(_onBranchVideoChanged);
    insertClip.removeListener(_syncExperienceState);
    playback.dispose();
    danmaku.dispose();
    interaction.dispose();
    aigc.dispose();
    insertClip.dispose();
    branchVideo.dispose();
    experience.dispose();
    super.dispose();
  }
}
