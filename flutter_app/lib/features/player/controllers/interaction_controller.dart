import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:logger/logger.dart';

import '../../../core/user_session.dart';
import '../../../data/api_client.dart';
import '../../../data/models.dart';
import 'interaction_socket_client.dart';

/// 短剧专属：高光 / 冲突投票 / 分支抉择 / 弹屏鹅笑
class InteractionController extends ChangeNotifier {
  InteractionController(this._api);

  final ApiClient _api;
  final _socket = InteractionSocketClient();
  final _log = Logger();
  final List<_PendingInteraction> _pendingQueue = [];
  static const Duration _highlightPanelMaxVisible = Duration(seconds: 6);
  Timer? _retryTimer;
  bool _isFlushing = false;
  bool _disposed = false;
  int _eventSeq = 0;
  final Map<int, int> _highlightCrowdDelta = {};
  final Set<String> _appliedCrowdEventKeys = {};
  final List<InteractionDebugEntry> _debugEntries = [];

  List<Highlight> highlights = const [];
  List<BranchFork> forks = const [];
  List<InteractionTimelineBucket> timeline = const [];
  Highlight? activeHighlight;
  BranchFork? pendingFork;
  bool legacyForksEnabled = false;
  String? currentBranchId; // 选中的分支
  String? episodeId;
  BranchStory? generatedStory;
  StoryThread? storyThread;
  String storyStyleCode = 'cinematic_literary';
  bool isGeneratingStory = false;
  String? storyError;
  int storyLikes = 0;
  final List<String> storyComments = [];
  // 远端汇总（包含其他用户的评论）
  StoryFeedback? remoteStoryFeedback;
  final Set<int> _handledForkIds = {};
  String connectionState = 'closed';
  int onlineCount = 1;
  int pendingInteractionCount = 0;
  int effectPulse = 0;
  String? latestRemoteAction;
  int? gooseCrowdCount;
  int? likeCrowdCount;

  // 差异化高光特效：本地触发
  int highlightEffectPulse = 0;
  String highlightEffectType = '搞笑';
  double highlightEffectIntensity = .7;

  // 差异化高光特效：远端他人触发
  int remoteEffectPulse = 0;
  String remoteEffectType = '搞笑';
  double remoteEffectIntensity = .55;
  String? remoteEffectUid;

  // 剧尾撒花：仅触发一次
  int endingEffectPulse = 0;
  bool _endingTriggered = false;

  // 笑出鹅叫累计
  int gooseCount = 0;
  int likeCount = 0;
  bool liked = false;
  DateTime _gooseGuard = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _likeGuard = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _highlightReactionGuard = DateTime.fromMillisecondsSinceEpoch(0);
  final Set<int> _suppressedHighlightIds = {};
  final Set<int> _autoTriggeredHighlightIds = {};
  int? _visibleHighlightId;
  DateTime _visibleHighlightSince = DateTime.fromMillisecondsSinceEpoch(0);

  // 手动 seek 粘性 —— 与 iOS PlayerViewModel 完全一致
  Highlight? _seekStickyHighlight;
  DateTime _seekStickyUntil = DateTime.fromMillisecondsSinceEpoch(0);

  List<InteractionDebugEntry> get debugEntries =>
      List<InteractionDebugEntry>.unmodifiable(_debugEntries);

  List<StoryTurn> get storyTurns => storyThread?.turns ?? const [];

  List<StoryChoice> get latestStoryChoices {
    final turns = storyThread?.turns ?? const [];
    for (final turn in turns.reversed) {
      if (turn.isAssistant && turn.choices.isNotEmpty) {
        return turn.choices;
      }
    }
    return const [];
  }

  Future<void> loadFor(String epId) async {
    if (_disposed) return;
    _socket.close();
    episodeId = epId;
    currentBranchId = null;
    pendingFork = null;
    activeHighlight = null;
    _suppressedHighlightIds.clear();
    _autoTriggeredHighlightIds.clear();
    _highlightCrowdDelta.clear();
    _appliedCrowdEventKeys.clear();
    _visibleHighlightId = null;
    highlightEffectIntensity = .7;
    remoteEffectIntensity = .55;
    generatedStory = null;
    storyThread = null;
    storyError = null;
    storyLikes = 0;
    storyComments.clear();
    _handledForkIds.clear();
    onlineCount = 1;
    connectionState = 'connecting';
    latestRemoteAction = null;
    gooseCrowdCount = null;
    likeCrowdCount = null;
    likeCount = 0;
    liked = false;
    _endingTriggered = false;
    remoteEffectUid = null;
    _restorePendingQueue();

    try {
      final loadedHighlights = await _api.getHighlights(epId);
      if (_disposed || episodeId != epId) return;
      highlights = loadedHighlights;
      _safeNotify();
    } catch (error, stackTrace) {
      _log.w('Highlight load failed: $epId',
          error: error, stackTrace: stackTrace);
      if (_disposed || episodeId != epId) return;
      highlights = const [];
    }

    final results = await Future.wait([
      _api.getForks(epId),
      _api.getInteractionTimeline(epId, bucketSize: 6),
      _api.getStoryFeedback(epId),
      // 一次请求同时获取鹅叫 + 喜欢 的 display_count，减少 RTT
      _api.getMultiSummary(epId, actions: ['笑出鹅叫', '喜欢']),
      _api.getEpisodeActionState(episodeId: epId, action: 'like'),
    ]).catchError((Object error, StackTrace stackTrace) {
      _log.w('Interaction bootstrap failed: $epId',
          error: error, stackTrace: stackTrace);
      return <Object>[
        <BranchFork>[],
        <InteractionTimelineBucket>[],
        StoryFeedback(episodeId: epId, likes: 0, comments: const []),
        <String, Map<String, dynamic>>{},
        false,
      ];
    });
    if (_disposed || episodeId != epId) return;
    forks = results[0] as List<BranchFork>;
    timeline = results[1] as List<InteractionTimelineBucket>;
    remoteStoryFeedback = results[2] as StoryFeedback;
    final multiSummary = results[3] as Map<String, Map<String, dynamic>>;
    final gooseSummary = multiSummary['笑出鹅叫'];
    final displayCount = gooseSummary?['display_count'];
    if (displayCount is num) {
      gooseCrowdCount = displayCount.toInt();
    }
    final likeSummary = multiSummary['喜欢'];
    final likeDisplayCount = likeSummary?['display_count'];
    if (likeDisplayCount is num) {
      likeCrowdCount = likeDisplayCount.toInt();
    }
    liked = results[4] as bool;
    likeCount = liked ? 1 : 0;
    _pushDebug(
      channel: 'bootstrap',
      note: 'goose=${gooseCrowdCount ?? 0} timeline=${timeline.length}',
    );
    if (forks.isEmpty) {
      forks = [_fallbackFork(epId)];
    }
    _connectRealtime(epId);
    _safeNotify();
  }

  int crowdCountForHighlight(Highlight highlight) {
    final base = timeline.where((bucket) {
      return bucket.tsEnd >= highlight.tsStart &&
          bucket.tsStart <= highlight.tsEnd;
    }).fold<int>(0, (sum, bucket) => sum + bucket.count);
    return base + (_highlightCrowdDelta[highlight.id] ?? 0);
  }

  BranchFork _fallbackFork(String epId) {
    final trigger = highlights.isNotEmpty ? highlights.first.tsEnd + 2 : 30.0;
    return BranchFork(
      id: -1,
      episodeId: epId,
      tsTrigger: trigger,
      question: '如果你来决定下一幕，剧情该怎么走？',
      options: [
        BranchOption(
          id: -101,
          label: '正面硬刚',
          description: '当场反击，把情绪推到最燃点',
          votes: 0,
        ),
        BranchOption(
          id: -102,
          label: '暗中设局',
          description: '先忍一手，埋下反转伏笔',
          votes: 0,
        ),
        BranchOption(
          id: -103,
          label: '情感升温',
          description: '让角色关系出现新的牵绊',
          votes: 0,
        ),
      ],
    );
  }

  /// 时间 tick 主循环
  void onTick(double seconds) {
    if (_disposed) return;
    final now = DateTime.now();
    if (currentBranchId != null) {
      activeHighlight = null;
      _visibleHighlightId = null;
    } else {
      final hit = highlights.cast<Highlight?>().firstWhere(
            (h) => h != null && seconds >= h.tsStart && seconds <= h.tsEnd,
            orElse: () => null,
          );
      if (hit != null) {
        if (_suppressedHighlightIds.contains(hit.id)) {
          activeHighlight = null;
        } else {
          if (_visibleHighlightId != hit.id) {
            _visibleHighlightId = hit.id;
            _visibleHighlightSince = now;
            _triggerHighlightEntranceEffect(hit);
          }
          if (now.difference(_visibleHighlightSince) >=
              _highlightPanelMaxVisible) {
            _suppressedHighlightIds.add(hit.id);
            activeHighlight = null;
          } else {
            activeHighlight = hit;
            _seekStickyHighlight = null;
          }
        }
      } else if (DateTime.now().isBefore(_seekStickyUntil) &&
          _seekStickyHighlight != null) {
        activeHighlight = _seekStickyHighlight;
      } else {
        activeHighlight = null;
        _visibleHighlightId = null;
      }
    }
    _matchFork(seconds);
    if (_pendingQueue.isNotEmpty && !_isFlushing) {
      _scheduleRetry(const Duration(milliseconds: 300));
    }
    _safeNotify();
  }

  /// 手动跳转：3-8 秒内保持高光，避免周期回调把状态抹掉
  void onSeek(double seconds) {
    if (_disposed) return;
    final hit = highlights.cast<Highlight?>().firstWhere(
          (h) => h != null && seconds >= h.tsStart && seconds <= h.tsEnd,
          orElse: () => null,
        );
    if (hit != null) {
      _suppressedHighlightIds.remove(hit.id);
      _visibleHighlightId = hit.id;
      _visibleHighlightSince = DateTime.now();
      _seekStickyHighlight = hit;
      _seekStickyUntil = DateTime.now().add(const Duration(seconds: 8));
      activeHighlight = hit;
      _triggerHighlightEntranceEffect(hit);
      _safeNotify();
    }
  }

  void dismissActiveHighlight() {
    final highlight = activeHighlight;
    if (highlight != null) {
      _suppressedHighlightIds.add(highlight.id);
    }
    _seekStickyHighlight = null;
    _seekStickyUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _visibleHighlightId = null;
    activeHighlight = null;
    _safeNotify();
  }

  void _matchFork(double seconds) {
    if (!legacyForksEnabled) return;
    if (pendingFork != null) return;
    for (final f in forks) {
      if (!_handledForkIds.contains(f.id) &&
          (seconds - f.tsTrigger).abs() < 0.6) {
        pendingFork = f;
        break;
      }
    }
  }

  Future<void> chooseBranch(BranchOption opt) async {
    if (_disposed) return;
    final fork = pendingFork;
    if (fork == null) return;
    _handledForkIds.add(fork.id);
    if (opt.videoUrl != null && opt.videoUrl!.isNotEmpty) {
      currentBranchId = opt.id.toString();
    }
    pendingFork = null;
    _safeNotify();
    if (episodeId != null) {
      await _submitInteraction(
        action: 'branch_pick',
        ts: fork.tsTrigger,
        effect: 'branch_choice',
        payload: {
          'fork_id': fork.id,
          'branch_id': opt.id,
          'choice_label': opt.label,
          'choice_description': opt.description,
          'has_video': opt.videoUrl != null && opt.videoUrl!.isNotEmpty,
        },
      );
    }
  }

  Future<void> reactToHighlight(Highlight highlight, double ts) async {
    await reactToHighlightAction(
      highlight,
      action: highlight.interaction,
      ts: ts,
    );
  }

  Future<void> reactToHighlightAction(
    Highlight highlight, {
    required String action,
    required double ts,
    String tapSlot = 'primary',
  }) async {
    if (_disposed || episodeId == null) return;
    final now = DateTime.now();
    if (now.isBefore(_highlightReactionGuard)) return;
    _highlightReactionGuard = now.add(const Duration(milliseconds: 320));
    // 本地触发差异化特效
    highlightEffectType = '${highlight.type} $action'.trim();
    highlightEffectIntensity = highlight.intensity;
    highlightEffectPulse += 1;
    _safeNotify();
    await _submitInteraction(
      action: action,
      ts: ts,
      highlightId: highlight.id,
      payload: {
        'highlight_type': highlight.type,
        'intensity': highlight.intensity,
        'description': highlight.summary,
        'tap_action': action,
        'tap_slot': tapSlot,
      },
    );
  }

  Future<void> voteClash(int side, double ts) async {
    if (_disposed || episodeId == null) return;
    final highlight = activeHighlight;
    await _submitInteraction(
      action: side == 0 ? '护主角' : '看反杀',
      ts: ts,
      highlightId: highlight?.id,
      effect: 'clash_vote',
      payload: {
        'side': side,
        if (highlight != null) 'highlight_type': highlight.type,
      },
    );
  }

  Future<void> generateStory({
    required String context,
    String? choice,
    double? tsInVideo,
    String? styleCode,
  }) async {
    if (_disposed || episodeId == null || isGeneratingStory) return;
    isGeneratingStory = true;
    storyError = null;
    if (styleCode != null) storyStyleCode = styleCode;
    _safeNotify();
    try {
      if (tsInVideo != null) {
        storyThread = await _api.createStoryThread(
          episodeId: episodeId!,
          tsInVideo: tsInVideo,
          initialChoice: choice,
          contextHint: context,
          styleCode: storyStyleCode,
        );
        _syncGeneratedStoryFromThread();
      } else {
        storyThread = null;
        generatedStory = await _api.generateBranchStory(
          episodeId: episodeId!,
          context: context,
          choice: choice,
        );
      }
      storyLikes = 0;
      storyComments.clear();
    } catch (e) {
      // 对话接口不可用时退回旧的文本续写接口，再退回本地兜底
      try {
        storyThread = null;
        generatedStory = await _api.generateBranchStory(
          episodeId: episodeId!,
          context: context,
          choice: choice,
        );
        storyLikes = 0;
        storyComments.clear();
      } catch (_) {
        generatedStory = _fallbackStory(context, choice);
        storyLikes = 0;
        storyComments.clear();
        storyError = '后端 AI 暂不可用，已切换本地演示续写';
      }
    } finally {
      if (!_disposed) {
        isGeneratingStory = false;
        _safeNotify();
      }
    }
  }

  Future<void> chooseStoryChoice(
    StoryChoice choice,
    double ts, {
    String? styleCode,
  }) async {
    if (_disposed || episodeId == null || isGeneratingStory) return;
    if (styleCode != null) storyStyleCode = styleCode;
    final thread = storyThread;
    if (thread == null) {
      await generateStory(
        context: generatedStory?.text ?? '',
        choice: choice.label,
        tsInVideo: ts,
      );
      return;
    }
    isGeneratingStory = true;
    storyError = null;
    _safeNotify();
    try {
      final delta = await _api.chooseStoryBranch(
        threadId: thread.threadId,
        choice: choice,
        styleCode: storyStyleCode,
      );
      storyThread = delta.thread;
      _syncGeneratedStoryFromThread();
    } catch (_) {
      final fallback = _fallbackStory(generatedStory?.text ?? '', choice.label);
      final nextTurn = StoryTurn(
        turnId: 'local_${DateTime.now().microsecondsSinceEpoch}',
        threadId: thread.threadId,
        role: 'assistant_story',
        text: fallback.text,
        choices: fallback.choices
            .asMap()
            .entries
            .map((entry) => StoryChoice(
                  choiceId: 'local_c${entry.key + 1}',
                  label: entry.value,
                ))
            .toList(),
      );
      storyThread = StoryThread(
        threadId: thread.threadId,
        episodeId: thread.episodeId,
        userId: thread.userId,
        forkId: thread.forkId,
        tsInVideo: thread.tsInVideo,
        styleCode: thread.styleCode,
        title: thread.title,
        turns: [
          ...thread.turns,
          StoryTurn(
            turnId: 'local_user_${DateTime.now().microsecondsSinceEpoch}',
            threadId: thread.threadId,
            role: 'user_choice',
            selectedChoiceId: choice.choiceId,
            text: choice.label,
          ),
          nextTurn,
        ],
        branchPath: [...thread.branchPath, choice.label],
      );
      generatedStory = fallback;
      storyError = '后端 AI 暂不可用，已切换本地演示续写';
    } finally {
      if (!_disposed) {
        isGeneratingStory = false;
        _safeNotify();
      }
    }
  }

  Future<void> sendStoryMessage(
    String text,
    double ts, {
    String? styleCode,
  }) async {
    final value = text.trim();
    if (value.isEmpty) return;
    if (styleCode != null) storyStyleCode = styleCode;
    final thread = storyThread;
    if (thread == null) {
      await generateStory(context: value, tsInVideo: ts);
      return;
    }
    if (_disposed || isGeneratingStory) return;
    isGeneratingStory = true;
    storyError = null;
    _safeNotify();
    try {
      final delta = await _api.sendStoryMessage(
        threadId: thread.threadId,
        text: value,
        styleCode: storyStyleCode,
      );
      storyThread = delta.thread;
      _syncGeneratedStoryFromThread();
    } catch (_) {
      storyError = '发送失败，请稍后再试';
    } finally {
      if (!_disposed) {
        isGeneratingStory = false;
        _safeNotify();
      }
    }
  }

  void _syncGeneratedStoryFromThread() {
    final turns = storyThread?.turns ?? const [];
    for (final turn in turns.reversed) {
      if (turn.isAssistant) {
        generatedStory = BranchStory(
          text: turn.text,
          choices: turn.choices.map((choice) => choice.label).toList(),
        );
        return;
      }
    }
    generatedStory = null;
  }

  BranchStory _fallbackStory(String context, String? choice) {
    final direction =
        (choice == null || choice.trim().isEmpty) ? '反转升级' : choice.trim();
    final compactContext =
        context.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final seed = compactContext.length > 54
        ? '${compactContext.substring(0, 54)}...'
        : compactContext;
    return BranchStory(
      text:
          '沿着「$direction」的方向，$seed。主角没有立刻摊牌，而是借对方最得意的一句话反设局，现场情绪被瞬间点燃。下一幕，观众可以选择继续硬刚、暗中布局，或让关系线突然升温。',
      choices: const ['正面硬刚', '暗中设局', '情感升温'],
    );
  }

  Future<void> closeFork() async {
    if (_disposed) return;
    if (pendingFork != null) _handledForkIds.add(pendingFork!.id);
    pendingFork = null;
    _safeNotify();
  }

  Future<void> flushPending() => _flushPendingInteractions();

  /// 剧尾触发：由 PlayerController 在 position >= duration - 5s 时调用。
  /// 触发一次「完结撒花」全屏特效 + 上报互动事件，便于服务端记录闭播率。
  void notifyEnding(double positionSec, double durationSec) {
    if (_disposed) return;
    if (_endingTriggered || durationSec <= 30) return;
    if (positionSec < durationSec - 5) return;
    _endingTriggered = true;
    endingEffectPulse += 1;
    _safeNotify();
    if (episodeId != null) {
      unawaited(_submitInteraction(
        action: '完结撒花',
        ts: positionSec,
        effect: 'ending_confetti',
        payload: {'duration': durationSec},
      ));
    }
  }

  Future<void> likeGeneratedStory(double ts) async {
    if (_disposed || episodeId == null || generatedStory == null) return;
    storyLikes += 1;
    _safeNotify();
    await _submitInteraction(
      action: 'ai_story_like',
      ts: ts,
      effect: 'like',
      payload: {'story_likes': storyLikes},
    );
  }

  Future<void> commentGeneratedStory(String text, double ts) async {
    final value = text.trim();
    if (_disposed ||
        episodeId == null ||
        generatedStory == null ||
        value.isEmpty) {
      return;
    }
    storyComments.insert(0, value);
    _safeNotify();
    await _submitInteraction(
      action: 'ai_story_comment',
      ts: ts,
      effect: 'comment',
      payload: {'comment': value},
    );
    // 后台拉一下远端汇总，刷新点赞数 / 别人评论
    if (episodeId != null) {
      unawaited(_refreshStoryFeedback());
    }
  }

  Future<void> _refreshStoryFeedback() async {
    final ep = episodeId;
    if (_disposed || ep == null) return;
    try {
      remoteStoryFeedback = await _api.getStoryFeedback(ep);
      _safeNotify();
    } catch (_) {}
  }

  /// 笑出鹅叫（节流）
  Future<void> triggerGoose(double ts) async {
    if (_disposed) return;
    final now = DateTime.now();
    if (now.isBefore(_gooseGuard)) return;
    _gooseGuard = now.add(const Duration(milliseconds: 400));
    gooseCount += 1;
    highlightEffectType = '搞笑 笑出鹅叫';
    highlightEffectIntensity = .9;
    highlightEffectPulse += 1;
    _safeNotify();
    if (episodeId != null) {
      unawaited(_submitInteraction(
        action: '笑出鹅叫',
        ts: ts,
        effect: 'goose_laugh',
        payload: {'local_count': gooseCount},
      ));
    }
  }

  Future<void> triggerLike(double ts) async {
    if (_disposed) return;
    final now = DateTime.now();
    if (now.isBefore(_likeGuard) || liked) return;
    _likeGuard = now.add(const Duration(milliseconds: 400));
    liked = true;
    likeCount += 1;
    if (likeCrowdCount != null) likeCrowdCount = likeCrowdCount! + 1;
    _safeNotify();
    final ep = episodeId;
    if (ep != null) {
      try {
        await _api.saveEpisodeAction(
          episodeId: ep,
          action: 'like',
          active: true,
        );
      } catch (_) {
        liked = false;
        likeCount = (likeCount - 1).clamp(0, 1 << 30);
        if (likeCrowdCount != null) {
          likeCrowdCount = (likeCrowdCount! - 1).clamp(0, 1 << 30);
        }
        _safeNotify();
        return;
      }
      unawaited(_submitInteraction(
        action: '喜欢',
        ts: ts,
        effect: 'like',
        payload: {'local_count': likeCount, 'active': true},
      ));
    }
  }

  Future<void> toggleLike(double ts) async {
    if (_disposed) return;
    final now = DateTime.now();
    if (now.isBefore(_likeGuard)) return;
    if (!liked) {
      await triggerLike(ts);
      return;
    }
    _likeGuard = now.add(const Duration(milliseconds: 400));
    liked = false;
    likeCount = (likeCount - 1).clamp(0, 1 << 30);
    if (likeCrowdCount != null) {
      likeCrowdCount = (likeCrowdCount! - 1).clamp(0, 1 << 30);
    }
    _safeNotify();
    final ep = episodeId;
    if (ep == null) return;
    try {
      await _api.saveEpisodeAction(
        episodeId: ep,
        action: 'like',
        active: false,
      );
    } catch (_) {
      liked = true;
      likeCount += 1;
      if (likeCrowdCount != null) likeCrowdCount = likeCrowdCount! + 1;
      _safeNotify();
    }
  }

  void _connectRealtime(String epId) {
    _socket.connect(
      epId,
      onPresence: (count) {
        if (_disposed) return;
        onlineCount = count;
        _safeNotify();
      },
      onState: (state) {
        if (_disposed) return;
        connectionState = state;
        if (state == 'open') unawaited(_flushPendingInteractions());
        _safeNotify();
      },
      onInteraction: _handleRealtimeInteraction,
    );
  }

  void _handleRealtimeInteraction(Map<String, dynamic> message) {
    if (_disposed) return;
    final action = message['action']?.toString();
    final effect = message['effect']?.toString();
    final userId = message['user_id']?.toString();
    final clientEventId = message['client_event_id']?.toString();
    final isOwn = userId == UserSession.userId ||
        (clientEventId?.startsWith(UserSession.userId) ?? false);

    if (isOwn) {
      _pushDebug(
        channel: 'ws-self',
        action: action,
        effect: effect,
        highlightId: (message['highlight_id'] as num?)?.toInt(),
      );
      _applyServerAck(message);
      _recordInteractionHistory(message);
      return;
    }

    _applyLiveHighlightCrowd(message);

    latestRemoteAction = action;
    if (_isGoose(action, effect)) {
      effectPulse += 1;
      final displayCount = message['display_count'];
      if (displayCount is num) gooseCrowdCount = displayCount.toInt();
    }
    if (_isLike(action, effect)) {
      final displayCount = message['display_count'];
      if (displayCount is num) likeCrowdCount = displayCount.toInt();
    }

    // 全量远端互动也触发高光特效（使用半透明色调）
    final remoteType = _remoteEffectType(action, effect, message);
    if (remoteType != null) {
      remoteEffectType = remoteType;
      remoteEffectIntensity = _remoteEffectIntensity(message);
      remoteEffectPulse += 1;
      remoteEffectUid =
          userId == null || userId.length < 4 ? null : userId.substring(0, 4);
    }
    _pushDebug(
      channel: 'ws',
      action: action,
      effect: effect,
      highlightId: (message['highlight_id'] as num?)?.toInt(),
      note: remoteEffectUid == null ? null : 'uid:$remoteEffectUid',
    );
    _safeNotify();
  }

  /// 从远端事件推断该用什么高光动效。返回 null 表示不触发特效（如分支选择 / AI 点赞 / 评论）。
  String? _remoteEffectType(
      String? action, String? effect, Map<String, dynamic> message) {
    if (action == null) return null;
    const skip = {
      'branch_pick',
      'ai_story_like',
      'ai_story_comment',
    };
    if (skip.contains(action) ||
        effect == 'branch_choice' ||
        effect == 'comment' ||
        effect == 'like') {
      return null;
    }
    if (_isGoose(action, effect)) return '搞笑';
    final payload = message['payload'];
    if (payload is Map && payload['highlight_type'] is String) {
      return payload['highlight_type'] as String;
    }
    // 作为 fallback，直接用 action
    return action;
  }

  void _triggerHighlightEntranceEffect(Highlight highlight) {
    if (!_autoTriggeredHighlightIds.add(highlight.id)) return;
    highlightEffectType = _effectKeyFor(highlight);
    highlightEffectIntensity = highlight.intensity;
    highlightEffectPulse += 1;
  }

  String _effectKeyFor(Highlight highlight) {
    return '${highlight.type} ${highlight.interaction}'.trim();
  }

  double _remoteEffectIntensity(Map<String, dynamic> message) {
    final payload = message['payload'];
    if (payload is Map) {
      final raw = payload['intensity'];
      if (raw is num) return raw.toDouble().clamp(0.0, 1.0).toDouble();
    }
    return .55;
  }

  Future<void> _submitInteraction({
    required String action,
    required double ts,
    int? highlightId,
    String? effect,
    Map<String, dynamic>? payload,
  }) async {
    final epId = episodeId;
    if (_disposed || epId == null) return;
    final pending = _PendingInteraction(
      episodeId: epId,
      action: action,
      ts: ts,
      highlightId: highlightId,
      effect: effect,
      userId: UserSession.userId,
      clientEventId: _nextClientEventId(),
      payload: payload ?? const {},
    );

    _pushDebug(
      channel: 'tx',
      action: action,
      effect: effect,
      highlightId: highlightId,
      note: pending.payload['tap_slot']?.toString(),
    );

    if (_applyOptimisticHighlightCrowd(pending)) {
      _safeNotify();
    }

    try {
      final ack = await _postPending(pending);
      if (_disposed) return;
      _applyServerAck(ack);
      _recordInteractionHistory(ack);
      _safeNotify();
      if (_pendingQueue.isNotEmpty) unawaited(_flushPendingInteractions());
    } catch (error, stackTrace) {
      _log.w('Interaction queued: ${pending.action}',
          error: error, stackTrace: stackTrace);
      _pushDebug(
        channel: 'queue',
        action: pending.action,
        effect: pending.effect,
        highlightId: pending.highlightId,
      );
      _enqueuePending(pending);
    }
  }

  Future<Map<String, dynamic>> _postPending(_PendingInteraction pending) {
    return _api.postInteraction(
      episodeId: pending.episodeId,
      action: pending.action,
      ts: pending.ts,
      highlightId: pending.highlightId,
      effect: pending.effect,
      userId: pending.userId,
      clientEventId: pending.clientEventId,
      payload: pending.payload,
    );
  }

  void _enqueuePending(_PendingInteraction pending) {
    if (_disposed) return;
    if (_pendingQueue
        .any((item) => item.clientEventId == pending.clientEventId)) {
      return;
    }
    _pendingQueue.add(pending);
    _syncPendingCount();
    _persistPendingQueue();
    _scheduleRetry();
    _safeNotify();
  }

  Future<void> _flushPendingInteractions() async {
    if (_disposed || _isFlushing || _pendingQueue.isEmpty) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _isFlushing = true;
    while (_pendingQueue.isNotEmpty) {
      final pending = _pendingQueue.first;
      try {
        final ack = await _postPending(pending);
        if (_disposed) return;
        _pendingQueue.removeAt(0);
        _applyServerAck(ack);
        _recordInteractionHistory(ack);
        _syncPendingCount();
        _persistPendingQueue();
        _pushDebug(
          channel: 'retry-ok',
          action: pending.action,
          effect: pending.effect,
          highlightId: pending.highlightId,
        );
        _safeNotify();
      } catch (error, stackTrace) {
        _log.w('Interaction retry failed: ${pending.action}',
            error: error, stackTrace: stackTrace);
        _pushDebug(
          channel: 'retry-fail',
          action: pending.action,
          effect: pending.effect,
          highlightId: pending.highlightId,
        );
        break;
      }
    }
    _isFlushing = false;
    if (_pendingQueue.isNotEmpty) _scheduleRetry();
    _safeNotify();
  }

  void _applyServerAck(Map<String, dynamic> ack) {
    final action = ack['action']?.toString();
    final effect = ack['effect']?.toString();
    _applyLiveHighlightCrowd(ack);
    _pushDebug(
      channel: 'ack',
      action: action,
      effect: effect,
      highlightId: (ack['highlight_id'] as num?)?.toInt(),
      note: ack['display_count']?.toString(),
    );
    if (_isGoose(action, effect)) {
      final displayCount = ack['display_count'];
      if (displayCount is num) gooseCrowdCount = displayCount.toInt();
    }
    if (_isLike(action, effect)) {
      final likeDisplayCount = ack['display_count'];
      if (likeDisplayCount is num) likeCrowdCount = likeDisplayCount.toInt();
    }
  }

  bool _applyOptimisticHighlightCrowd(_PendingInteraction pending) {
    final highlightId = pending.highlightId;
    if (highlightId == null) return false;
    final key = 'client:${pending.clientEventId}';
    if (!_appliedCrowdEventKeys.add(key)) return false;
    _highlightCrowdDelta[highlightId] =
        (_highlightCrowdDelta[highlightId] ?? 0) + 1;
    _pushDebug(
      channel: 'crowd+',
      action: pending.action,
      highlightId: highlightId,
      note: 'optimistic:${_highlightCrowdDelta[highlightId]}',
    );
    return true;
  }

  void _applyLiveHighlightCrowd(Map<String, dynamic> event) {
    final rawHighlightId = event['highlight_id'];
    if (rawHighlightId is! num) return;
    final key = _crowdEventKey(event);
    if (key == null || !_appliedCrowdEventKeys.add(key)) return;
    final highlightId = rawHighlightId.toInt();
    _highlightCrowdDelta[highlightId] =
        (_highlightCrowdDelta[highlightId] ?? 0) + 1;
    _pushDebug(
      channel: 'crowd+',
      action: event['action']?.toString(),
      effect: event['effect']?.toString(),
      highlightId: highlightId,
      note: 'live:${_highlightCrowdDelta[highlightId]}',
    );
  }

  String? _crowdEventKey(Map<String, dynamic> event) {
    final clientEventId = event['client_event_id']?.toString();
    if (clientEventId != null && clientEventId.isNotEmpty) {
      return 'client:$clientEventId';
    }
    final eventId = event['event_id']?.toString();
    if (eventId != null && eventId.isNotEmpty) {
      return 'server:$eventId';
    }
    final id = event['id'];
    if (id is num) return 'db:${id.toInt()}';
    return null;
  }

  void _scheduleRetry([Duration delay = const Duration(seconds: 2)]) {
    if (_disposed) return;
    if (_retryTimer != null) return;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_flushPendingInteractions());
    });
  }

  void _restorePendingQueue() {
    _pendingQueue.clear();
    final raw =
        Hive.box('interaction_queue').get('items', defaultValue: const []);
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          _pendingQueue.add(_PendingInteraction.fromJson(
            Map<String, dynamic>.from(item),
          ));
        }
      }
    }
    _syncPendingCount();
  }

  void _persistPendingQueue() {
    unawaited(Hive.box('interaction_queue').put(
      'items',
      _pendingQueue.map((item) => item.toJson()).toList(),
    ));
  }

  void _recordInteractionHistory(Map<String, dynamic> event) {
    final box = Hive.box('interaction_history');
    final raw = box.get('items', defaultValue: const []);
    final items = raw is List
        ? raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : <Map<String, dynamic>>[];
    final clientEventId = event['client_event_id']?.toString();
    if (clientEventId != null &&
        items.any((item) => item['client_event_id'] == clientEventId)) {
      return;
    }
    items.insert(0, {
      ...event,
      'synced_at': DateTime.now().toIso8601String(),
    });
    unawaited(box.put('items', items.take(120).toList()));
  }

  void _syncPendingCount() {
    pendingInteractionCount = _pendingQueue.length;
  }

  String _nextClientEventId() {
    _eventSeq = (_eventSeq + 1) % 10000;
    return '${UserSession.userId}-${DateTime.now().microsecondsSinceEpoch}-$_eventSeq';
  }

  bool _isGoose(String? action, String? effect) {
    return action == '笑出鹅叫' ||
        effect == 'goose_laugh' ||
        effect == 'goose_burst';
  }

  bool _isLike(String? action, String? effect) {
    return action == '喜欢' || action == '点赞' || action == 'like';
  }

  void _pushDebug({
    required String channel,
    String? action,
    String? effect,
    int? highlightId,
    String? note,
  }) {
    _debugEntries.insert(
      0,
      InteractionDebugEntry(
        at: DateTime.now(),
        channel: channel,
        action: action ?? '-',
        effect: effect,
        highlightId: highlightId,
        note: note,
      ),
    );
    if (_debugEntries.length > 18) {
      _debugEntries.removeRange(18, _debugEntries.length);
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _socket.close();
    super.dispose();
  }
}

class _PendingInteraction {
  const _PendingInteraction({
    required this.episodeId,
    required this.action,
    required this.ts,
    required this.userId,
    required this.clientEventId,
    this.highlightId,
    this.effect,
    this.payload = const {},
  });

  final String episodeId;
  final String action;
  final double ts;
  final int? highlightId;
  final String? effect;
  final String userId;
  final String clientEventId;
  final Map<String, dynamic> payload;

  factory _PendingInteraction.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return _PendingInteraction(
      episodeId: json['episode_id']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      ts: (json['ts_in_video'] as num?)?.toDouble() ?? 0,
      highlightId: (json['highlight_id'] as num?)?.toInt(),
      effect: json['effect']?.toString(),
      userId: json['user_id']?.toString() ?? UserSession.userId,
      clientEventId: json['client_event_id']?.toString() ?? '',
      payload:
          rawPayload is Map ? Map<String, dynamic>.from(rawPayload) : const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'episode_id': episodeId,
        'action': action,
        'ts_in_video': ts,
        if (highlightId != null) 'highlight_id': highlightId,
        if (effect != null) 'effect': effect,
        'user_id': userId,
        'client_event_id': clientEventId,
        'payload': payload,
      };
}

class InteractionDebugEntry {
  final DateTime at;
  final String channel;
  final String action;
  final String? effect;
  final int? highlightId;
  final String? note;

  const InteractionDebugEntry({
    required this.at,
    required this.channel,
    required this.action,
    this.effect,
    this.highlightId,
    this.note,
  });
}
