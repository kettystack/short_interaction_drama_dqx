import 'dart:async';
import 'dart:math' as math;

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme.dart';
import '../../core/user_session.dart';
import '../../data/models.dart';
import '../../shared/widgets/play_pause_indicator.dart';
import '../branch_video/data/branch_video_models.dart';
import '../branch_video/widgets/personalized_branch_overlay.dart';
import '../highlights/highlight_list_sheet.dart';
import 'controllers/player_controller.dart';
import 'controllers/interaction_controller.dart' show InteractionDebugEntry;
import 'widgets/ai_branch_sheet.dart';
import 'widgets/boost_pack_overlay.dart';
import 'widgets/danmaku_settings_sheet.dart';
import 'widgets/episode_picker_sheet.dart';
import 'widgets/floating_hearts.dart';
import 'widgets/highlight_emotion_prompt.dart';
import 'widgets/gesture_hud.dart';
import 'widgets/highlight_effect_overlay.dart';
import 'widgets/immersive_highlight.dart';
import 'widgets/player_bottom_bar.dart';
import 'widgets/player_right_rail.dart';
import 'widgets/player_top_bar.dart';

class PlayerPage extends StatefulWidget {
  final String episodeId;
  const PlayerPage({super.key, required this.episodeId});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  static const double _desktopViewportAspectRatio = 9 / 16;
  static const int _likeDisplayBase = 1348;

  late final PlayerController _controller;
  bool _showControls = true;
  int _likePulse = 0;
  int _playPausePulse = 0;
  bool _playPauseIndicatorIsPlaying = false;
  Timer? _hideTimer;
  bool _spacePressed = false;
  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'player_keyboard');

  @override
  void initState() {
    super.initState();
    _controller = PlayerController();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!_isDesktopPlatform()) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    _controller.load(widget.episodeId).then((_) {
      if (mounted) _armHideTimer();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _keyboardFocusNode.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!_isDesktopPlatform()) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    _controller.dispose();
    super.dispose();
  }

  bool _isDesktopPlatform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  Size _desktopViewportSize(Size available) {
    if (available.width <= 0 || available.height <= 0) {
      return available;
    }
    final width = math.min(
      available.width,
      available.height * _desktopViewportAspectRatio,
    );
    final height = width / _desktopViewportAspectRatio;
    return Size(width, height);
  }

  @override
  Widget build(BuildContext context) {
    final useDesktopViewport = _isDesktopPlatform();
    return Scaffold(
      backgroundColor: Colors.black,
      body: useDesktopViewport
          ? LayoutBuilder(
              builder: (context, constraints) {
                final media = MediaQuery.of(context);
                final size = _desktopViewportSize(constraints.biggest);
                return ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: ClipRect(
                      child: SizedBox(
                        width: size.width,
                        height: size.height,
                        child: MediaQuery(
                          data: media.copyWith(size: size),
                          child: Builder(
                            builder: (viewportContext) =>
                                _buildPlayerScene(viewportContext),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            )
          : _buildPlayerScene(context),
    );
  }

  Widget _buildPlayerScene(BuildContext sceneContext) {
    final videoFit = _isDesktopPlatform() ? BoxFit.contain : BoxFit.cover;
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _controller,
          _controller.playback,
          _controller.danmaku,
          _controller.interaction,
          _controller.aigc,
          _controller.insertClip,
          _controller.branchVideo,
          _controller.experience,
        ]),
        builder: (ctx, _) {
          final episode = _controller.episode;
          if (episode == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accentHot),
            );
          }
          final index =
              _controller.dramaEpisodes.indexWhere((e) => e.id == episode.id);
          final canPrevious = index > 0;
          final canNext =
              index >= 0 && index < _controller.dramaEpisodes.length - 1;
          return Stack(children: [
            Positioned.fill(
              child: GestureHud(
                playback: _controller.playback,
                onTap: _onTapTogglePlay,
                onDoubleTap: _triggerLike,
                onSeek: _controller.seekTo,
                child: Video(
                  controller: _controller.playback.controller,
                  controls: NoVideoControls,
                  fit: videoFit,
                ),
              ),
            ),
            _insertClipVideoLayer(videoFit),
            if (_controller.insertClip.isPlayingInsertedClip
                ? _controller.insertClip.buffering
                : _controller.playback.buffering)
              const Positioned.fill(
                child: Center(
                    child:
                        CircularProgressIndicator(color: AppColors.accentHot)),
              ),
            if (!_controller.insertClip.isPlayingInsertedClip)
              Positioned.fill(
                child: IgnorePointer(
                  child: DanmakuScreen(
                    createdController: _controller.danmaku.attach,
                    option: _controller.danmaku.option,
                  ),
                ),
              ),
            Positioned.fill(
              child: FloatingHearts(
                trigger: _likePulse + _controller.interaction.effectPulse,
              ),
            ),
            Positioned.fill(
              child: HighlightEffectOverlay(
                trigger: _controller.interaction.highlightEffectPulse,
                type: _controller.interaction.highlightEffectType,
                intensity: _controller.interaction.highlightEffectIntensity,
              ),
            ),
            Positioned.fill(
              child: HighlightEffectOverlay(
                trigger: _controller.interaction.remoteEffectPulse,
                type: _controller.interaction.remoteEffectType,
                intensity: _controller.interaction.remoteEffectIntensity,
                remote: true,
              ),
            ),
            Positioned.fill(
              child: HighlightEffectOverlay(
                trigger: _controller.interaction.endingEffectPulse,
                type: '完结',
              ),
            ),
            Positioned.fill(
              child: PlayPauseIndicator(
                trigger: _playPausePulse,
                isPlaying: _playPauseIndicatorIsPlaying,
              ),
            ),
            _ambientReactions(),
            _topPanel(episode),
            _insertClipBanner(sceneContext),
            _boostPointPrompt(sceneContext),
            _highlightPanel(sceneContext),
            _highlightEmotionPrompt(sceneContext),
            _endingPrompt(),
            _rightRail(),
            _bottomPanel(canPrevious: canPrevious, canNext: canNext),
            if (_controller.branchVideo.pendingSession != null &&
                !_controller.insertClip.isPlayingInsertedClip)
              Positioned.fill(
                child: PersonalizedBranchOverlay(
                  session: _controller.branchVideo.pendingSession!,
                  selectedOptionId: _controller.branchVideo.selectedOptionId,
                  isSubmitting: _controller.branchVideo.isSubmitting,
                  error: _controller.branchVideo.error,
                  onPick: _pickPersonalizedBranch,
                  onCustomPrompt: _createCustomPersonalizedBranch,
                  onSkip: _controller.skipPersonalizedBranch,
                ),
              ),
          ]);
        },
      ),
    );
  }

  Widget _insertClipVideoLayer(BoxFit videoFit) {
    final insertClip = _controller.insertClip;
    if (!insertClip.isPlayingInsertedClip) return const SizedBox.shrink();
    final controller = insertClip.videoController;
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTapTogglePlay,
        child: ColoredBox(
          color: Colors.black,
          child: controller == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.accentHot),
                )
              : Video(
                  key: ValueKey(insertClip.currentClipUrl),
                  controller: controller,
                  controls: NoVideoControls,
                  fit: videoFit,
                ),
        ),
      ),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) _spacePressed = false;
      return;
    }
    if (event is! KeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.mediaFastForward) {
      unawaited(_seekBy(const Duration(seconds: 10)));
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.mediaRewind) {
      unawaited(_seekBy(const Duration(seconds: -10)));
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.space && !_spacePressed) {
      _spacePressed = true;
      unawaited(_onTapTogglePlay());
    }
  }

  Future<void> _seekBy(Duration delta) async {
    if (_controller.insertClip.isPlayingInsertedClip) return;
    final duration = _controller.playback.duration;
    final position = _controller.playback.position;
    final rawTarget = position + delta;
    final target = rawTarget < Duration.zero
        ? Duration.zero
        : duration > Duration.zero && rawTarget > duration
            ? duration
            : rawTarget;
    await _controller.seekTo(target);
    if (!mounted) return;
    setState(() => _showControls = true);
    _armHideTimer();
  }

  Widget _topPanel(Episode episode) {
    return AnimatedSlide(
      offset: _showControls ? Offset.zero : const Offset(0, -1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _showControls ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: PlayerTopBar(
              title: episode.title,
              danmakuVisible: _controller.danmaku.enabled,
              onToggleDanmaku: () =>
                  _controller.danmaku.setEnabled(!_controller.danmaku.enabled),
              onMore: _openMoreSheet,
            ),
          ),
        ),
      ),
    );
  }

  List<String> _bottomStatusChips() {
    final interaction = _controller.interaction;
    final pending = interaction.pendingInteractionCount;
    final chips = <String>[
      '${_likeDisplayCount()} 人喜欢',
      '${interaction.onlineCount} 人同看',
    ];
    final highlight = interaction.activeHighlight;
    if (highlight != null) {
      final style = HighlightEmotionStyle.of(highlight);
      final crowd = interaction.crowdCountForHighlight(highlight);
      final fallbackCrowd = (highlight.intensity * 240).round().clamp(18, 9999);
      chips.add('${crowd > 0 ? crowd : fallbackCrowd} 人正在${style.verb}');
    }
    if (pending > 0) {
      chips.add('待同步 $pending');
    } else {
      chips.add(_connectionStateLabel(interaction.connectionState));
    }
    return chips;
  }

  String _connectionStateLabel(String state) {
    switch (state) {
      case 'open':
        return '实时联动';
      case 'connecting':
        return '连接中';
      case 'closed':
        return '已断开';
      case 'error':
        return '同步异常';
      default:
        return state.isEmpty ? '实时联动' : state;
    }
  }

  Widget _bottomPanel({required bool canPrevious, required bool canNext}) {
    return AnimatedSlide(
      offset: _showControls ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _showControls ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: PlayerBottomBar(
              playback: _controller.playback,
              durationFallback: _controller.effectiveDuration,
              highlights: _controller.interaction.highlights,
              statusChips: _bottomStatusChips(),
              danmakuEnabled: _controller.danmaku.enabled,
              canPrevious: canPrevious,
              canNext: canNext,
              qualityOptions: _controller.qualityOptions,
              currentQualityLabel: _controller.currentQualityLabel,
              onSeek: _controller.seekTo,
              onSetSpeed: _controller.setSpeed,
              onSetQuality: (quality) {
                unawaited(_controller.setQuality(quality));
                setState(() => _showControls = true);
                _armHideTimer();
              },
              onTogglePlay: _onTapTogglePlay,
              onPrevious: _controller.previousEpisode,
              onNext: _controller.nextEpisode,
              onToggleDanmaku: () =>
                  _controller.danmaku.setEnabled(!_controller.danmaku.enabled),
              onDanmakuSettings: _openDanmakuSettings,
              onOpenEpisodes: _openEpisodePicker,
              onOpenHighlights: _openHighlightsSheet,
              onSendDanmaku: _openDanmakuInput,
            ),
          ),
        ),
      ),
    );
  }

  Widget _rightRail() {
    return Positioned(
      right: 8,
      bottom: 170,
      child: AnimatedSlide(
        offset: _showControls ? Offset.zero : const Offset(1.2, 0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _showControls ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: PlayerRightRail(
            onLike: _toggleLike,
            onDanmaku: () =>
                _controller.danmaku.setEnabled(!_controller.danmaku.enabled),
            onFavorite: _controller.toggleFavorite,
            onAi: _openAiSheet,
            onAigcBoost: () => unawaited(_triggerAigcBoost()),
            onHighlights: _openHighlightsSheet,
            favoriteActive: _controller.isFavorite,
            likeActive: _controller.interaction.liked,
            danmakuEnabled: _controller.danmaku.enabled,
            aigcGenerating: _controller.aigc.isCreating,
            insertedClipActive: _controller.insertClip.isPlayingInsertedClip,
            likeCount: _likeDisplayCount(),
            danmakuCount: _controller.interaction.timeline
                .fold(0, (sum, e) => sum + e.count),
          ),
        ),
      ),
    );
  }

  /// 顶部紧凑「人气胶囊」——取代原先占满屏的大全息卡，几乎不挡画面。
  Widget _highlightPanel(BuildContext sceneContext) {
    if (_controller.experience.blocksAmbientOverlays) {
      return const SizedBox.shrink();
    }
    final highlight = _controller.interaction.activeHighlight;
    if (highlight == null) return const SizedBox.shrink();
    final style = HighlightEmotionStyle.of(highlight);
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      top: MediaQuery.of(sceneContext).padding.top + (_showControls ? 112 : 58),
      left: 0,
      right: 0,
      child: Align(
        alignment: Alignment.topCenter,
        child: CollapsibleHighlightControls(
          key: ValueKey('highlight-controls-${highlight.id}'),
          highlight: highlight,
          crowdCount: _crowdCountFor(highlight),
          onPrimary: () => _reactToHighlightAction(
            highlight,
            action: style.primaryEvent,
            tapSlot: 'primary',
          ),
          onLeft: () => style.useVoteActions
              ? _voteHighlight(0)
              : _reactToHighlightAction(
                  highlight,
                  action: style.leftEvent,
                  tapSlot: 'left',
                ),
          onRight: () => style.useVoteActions
              ? _voteHighlight(1)
              : _reactToHighlightAction(
                  highlight,
                  action: style.rightEvent,
                  tapSlot: 'right',
                ),
        ),
      ),
    );
  }

  /// 他人互动上浮层：高光激活时按人气持续飘出其他观众的表情反应。
  Widget _ambientReactions() {
    if (_controller.experience.blocksAmbientOverlays) {
      return const SizedBox.shrink();
    }
    final highlight = _controller.interaction.activeHighlight;
    return Positioned.fill(
      child: AmbientCrowdReactions(
        highlight: highlight,
        crowdCount: highlight == null ? 0 : _crowdCountFor(highlight),
      ),
    );
  }

  Widget _highlightEmotionPrompt(BuildContext sceneContext) {
    if (_controller.experience.blocksAmbientOverlays) {
      return const SizedBox.shrink();
    }
    final highlight = _controller.interaction.activeHighlight;
    if (highlight == null) return const SizedBox.shrink();
    final media = MediaQuery.of(sceneContext);
    final top = (media.size.height * .43)
        .clamp(media.padding.top + 126, media.size.height - 238)
        .toDouble();
    return Positioned(
      left: 10,
      top: top,
      child: HighlightEmotionPrompt(
        highlight: highlight,
        crowdCount: _crowdCountFor(highlight),
        onReact: () => _reactToHighlight(highlight),
      ),
    );
  }

  void _reactToHighlight(Highlight highlight) {
    _reactToHighlightAction(
      highlight,
      action: highlight.interaction,
      tapSlot: 'default',
    );
  }

  void _reactToHighlightAction(
    Highlight highlight, {
    required String action,
    required String tapSlot,
  }) {
    unawaited(_controller.interaction.reactToHighlightAction(
      highlight,
      action: action,
      ts: _controller.playback.position.inMilliseconds / 1000.0,
      tapSlot: tapSlot,
    ));
    _armHideTimer();
  }

  void _voteHighlight(int side) {
    unawaited(_controller.interaction.voteClash(
      side,
      _controller.playback.position.inMilliseconds / 1000.0,
    ));
    _armHideTimer();
  }

  Widget _endingPrompt() {
    if (_controller.experience.blocksAmbientOverlays) {
      return const SizedBox.shrink();
    }
    final duration = _controller.playback.duration.inMilliseconds;
    final position = _controller.playback.position.inMilliseconds;
    if (!_showControls || duration <= 30000 || position / duration < .9) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 14,
      right: 86,
      bottom: 142,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .62),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: AppColors.accentGold.withValues(alpha: .35)),
        ),
        child: Row(children: [
          const Icon(Icons.auto_awesome, color: AppColors.accentGold),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '追到尾声了，生成一个专属后续',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(onPressed: _openAiSheet, child: const Text('续写')),
        ]),
      ),
    );
  }

  Widget _insertClipBanner(BuildContext sceneContext) {
    final insertClip = _controller.insertClip;
    if (!insertClip.isPlayingInsertedClip) return const SizedBox.shrink();
    final job = _controller.aigc.currentJob;
    final boostPoint = _controller.playingBoostPoint;
    final branchTicket = _controller.playingBranchTicket;
    final subtitle =
        branchTicket?.storyText ?? boostPoint?.prompt ?? job?.prompt ?? '';
    return Positioned(
      left: 14,
      right: 14,
      top: MediaQuery.of(sceneContext).padding.top + 72,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .70),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.accentGold.withValues(alpha: .46),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.bolt, color: AppColors.accentGold),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    branchTicket != null
                        ? '个性化分支 · ${branchTicket.label}'
                        : boostPoint == null
                            ? 'AIGC 加速包插播中'
                            : '${boostPoint.title}插播中',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: insertClip.isResumingMain
                  ? null
                  : () => unawaited(_controller.resumeMainAfterInsertedClip()),
              child: Text(insertClip.isResumingMain ? '返回中' : '回正片'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boostPointPrompt(BuildContext sceneContext) {
    final point = _controller.activeBoostPoint;
    if (point == null ||
        _controller.insertClip.isPlayingInsertedClip ||
        !_controller.experience.canShowBoost) {
      return const SizedBox.shrink();
    }
    final media = MediaQuery.of(sceneContext);
    final bottom = math.max(media.padding.bottom + 222, 212.0);
    return Positioned(
      left: 14,
      right: 84,
      bottom: bottom,
      child: AnimatedOpacity(
        opacity: 1,
        duration: const Duration(milliseconds: 180),
        child: Align(
          alignment: Alignment.centerRight,
          child: BoostPackOverlay(
            point: point,
            onPlay: () => unawaited(_playBoostPoint(point)),
            onDismiss: () {
              _controller.dismissBoostPoint(point);
              _armHideTimer();
            },
          ),
        ),
      ),
    );
  }

  int _crowdCountFor(Highlight highlight) {
    return _controller.interaction.crowdCountForHighlight(highlight);
  }

  int _likeDisplayCount() {
    final remote = _controller.interaction.likeCrowdCount;
    if (remote != null) return remote;
    return _likeDisplayBase + _controller.interaction.likeCount;
  }

  /// 单击：立即切换播放/暂停 + 视觉反馈；同时短暂显示控制条。
  Future<void> _onTapTogglePlay() async {
    final inserting = _controller.insertClip.isPlayingInsertedClip;
    final willPlay = inserting
        ? !_controller.insertClip.playing
        : !_controller.playback.player.state.playing;
    if (inserting) {
      await _controller.insertClip.togglePlay();
    } else {
      await _controller.playback.togglePlay();
    }
    if (!mounted) return;
    setState(() {
      _playPauseIndicatorIsPlaying = willPlay;
      _playPausePulse++;
      _showControls = true;
    });
    _armHideTimer();
  }

  void _armHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted ||
          (!_controller.playback.playing && !_controller.insertClip.playing)) {
        return;
      }
      setState(() => _showControls = false);
    });
  }

  void _triggerLike() {
    if (_controller.interaction.liked) return;
    unawaited(_controller.interaction
        .triggerLike(_controller.playback.position.inMilliseconds / 1000));
    setState(() {
      _likePulse++;
      _showControls = true;
    });
    _armHideTimer();
  }

  void _toggleLike() {
    final wasLiked = _controller.interaction.liked;
    unawaited(_controller.interaction
        .toggleLike(_controller.playback.position.inMilliseconds / 1000));
    setState(() {
      if (!wasLiked) {
        _likePulse++;
      }
      _showControls = true;
    });
    _armHideTimer();
  }

  void _openHighlightsSheet() {
    setState(() => _showControls = true);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => HighlightListSheet(
        highlights: _controller.interaction.highlights,
        onPick: (h) => _controller.seekTo(Duration(seconds: h.tsStart.toInt())),
      ),
    );
  }

  void _openEpisodePicker() {
    final episode = _controller.episode;
    if (episode == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EpisodePickerSheet(
        episodes: _controller.dramaEpisodes,
        currentId: episode.id,
        onPick: (ep) => _controller.load(ep.id),
      ),
    );
  }

  void _openDanmakuSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DanmakuSettingsSheet(controller: _controller.danmaku),
    );
  }

  void _openAiSheet() {
    _openAiSheetWithChoice();
  }

  void _openMoreSheet() {
    setState(() => _showControls = true);
    final interaction = _controller.interaction;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        decoration: const BoxDecoration(
          color: AppColors.bgPanel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            _statusRow('观影房间',
                '${interaction.onlineCount} 人在线 · ${interaction.connectionState}'),
            _statusRow('同步队列', '${interaction.pendingInteractionCount} 条待同步'),
            _statusRow('最近回流', interaction.latestRemoteAction ?? '暂无'),
            _statusRow('设备 ID', UserSession.userId),
            const SizedBox(height: 8),
            _moreTile(Icons.subtitles, '弹幕设置', () {
              Navigator.pop(context);
              _openDanmakuSettings();
            }),
            _moreTile(Icons.video_collection_outlined, '选集', () {
              Navigator.pop(context);
              _openEpisodePicker();
            }),
            _moreTile(Icons.bolt_outlined, '高光时间线', () {
              Navigator.pop(context);
              _openHighlightsSheet();
            }),
            _moreTile(Icons.auto_awesome, 'AI 剧情续写', () {
              Navigator.pop(context);
              _openAiSheet();
            }),
            _moreTile(Icons.bolt, 'AIGC 加速包插片', () {
              Navigator.pop(context);
              unawaited(_triggerAigcBoost());
            }),
            _moreTile(
              _controller.isFavorite ? Icons.favorite : Icons.favorite_border,
              _controller.isFavorite ? '取消追剧' : '加入追剧',
              () {
                Navigator.pop(context);
                _controller.toggleFavorite();
              },
            ),
            _moreTile(Icons.sync, '立即同步互动', () {
              interaction.flushPending();
              Navigator.pop(context);
            }),
            _moreTile(Icons.bug_report_outlined, '互动调试面板', () {
              Navigator.pop(context);
              _openInteractionDebugSheet();
            }),
          ],
        ),
      ),
    );
  }

  void _openInteractionDebugSheet() {
    final interaction = _controller.interaction;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .72,
        child: AnimatedBuilder(
          animation: interaction,
          builder: (context, __) {
            final entries = interaction.debugEntries;
            return Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              decoration: const BoxDecoration(
                color: AppColors.bgPanel,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '互动调试',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _statusRow(
                    '鹅叫总数',
                    '${interaction.gooseCrowdCount ?? interaction.gooseCount}',
                  ),
                  _statusRow(
                      '同步队列', '${interaction.pendingInteractionCount} 条'),
                  _statusRow('最后远端', interaction.latestRemoteAction ?? '暂无'),
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Row(
                      children: [
                        Expanded(
                          child: Text(
                            '最近事件',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          'send / ack / ws / crowd',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: entries.isEmpty
                        ? const Center(
                            child: Text(
                              '暂无互动事件',
                              style: TextStyle(color: Colors.white38),
                            ),
                          )
                        : ListView.separated(
                            itemCount: entries.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: Colors.white.withValues(alpha: .08),
                            ),
                            itemBuilder: (_, index) =>
                                _debugEntryRow(entries[index]),
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _statusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 76,
          child: Text(label, style: const TextStyle(color: Colors.white54)),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ]),
    );
  }

  Widget _moreTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.accentMint),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }

  Widget _debugEntryRow(InteractionDebugEntry entry) {
    final meta = <String>[
      entry.action,
      if (entry.effect?.isNotEmpty ?? false) entry.effect!,
      if (entry.highlightId != null) 'h#${entry.highlightId}',
      if (entry.note?.isNotEmpty ?? false) entry.note!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: _debugChannelColor(entry.channel).withValues(alpha: .18),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _debugChannelColor(entry.channel).withValues(alpha: .44),
              ),
            ),
            child: Text(
              entry.channel,
              style: TextStyle(
                color: _debugChannelColor(entry.channel),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatDebugTime(entry.at),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _debugChannelColor(String channel) {
    switch (channel) {
      case 'tx':
        return AppColors.accentMint;
      case 'ack':
        return AppColors.accentGold;
      case 'ws':
      case 'ws-self':
        return AppColors.accentHot;
      case 'crowd+':
        return const Color(0xFF66E1FF);
      case 'queue':
      case 'retry-fail':
        return const Color(0xFFFF8A65);
      default:
        return Colors.white70;
    }
  }

  String _formatDebugTime(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  Future<void> _pickPersonalizedBranch(
    PersonalizedBranchOption option,
  ) async {
    await _controller.choosePersonalizedBranch(option);
    if (!mounted) return;
    if (_controller.branchVideo.pendingPlaybackTicket == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在生成所选剧情，通过质检后会自动播放'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _createCustomPersonalizedBranch(String prompt) async {
    if (prompt.trim().isEmpty) return;
    await _controller.createCustomPersonalizedBranch(prompt);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('自定义剧情已提交，生成完成后会自动播放'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _triggerAigcBoost() async {
    if (_controller.aigc.isCreating) return;
    if (_controller.insertClip.isPlayingInsertedClip) {
      await _controller.resumeMainAfterInsertedClip();
      return;
    }
    final boostPoint = _controller.activeBoostPoint;
    if (boostPoint != null) {
      await _playBoostPoint(boostPoint);
      return;
    }
    final highlight = _controller.interaction.activeHighlight;
    final prompt = highlight == null
        ? '按当前剧情节奏生成一个高能加速包插片，推进冲突但不改写正片主线。'
        : '围绕「${highlight.summary}」生成一个高能加速包插片，强化${highlight.interaction}。';
    setState(() => _showControls = true);
    final job = await _controller.requestAigcBoost(
      userPrompt: prompt,
      highlightId: highlight?.id,
    );
    if (!mounted) return;
    final error = _controller.aigc.error;
    final message = error != null
        ? '加速包生成失败：$error'
        : job == null
            ? '当前无法生成加速包'
            : job.isFailed
                ? '加速包已拦截：${job.errorMessage.isEmpty ? '没有匹配的同集素材' : job.errorMessage}'
                : job.isReady
                    ? '加速包已生成，正在插播'
                    : '加速包生成中，可稍后自动插播';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
    _armHideTimer();
  }

  Future<void> _playBoostPoint(AigcBoostPoint point) async {
    setState(() => _showControls = true);
    await _controller.playBoostPoint(point);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${point.title}正在插播，结束后回到正片'),
        duration: const Duration(seconds: 2),
      ),
    );
    _armHideTimer();
  }

  void _openAiSheetWithChoice({String? choice}) {
    final episode = _controller.episode;
    if (episode == null) return;
    final highlight = _controller.interaction.activeHighlight;
    final contextText = highlight == null
        ? episode.title
        : '${episode.title}\n${highlight.summary}';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AiBranchSheet(
        controller: _controller.interaction,
        defaultContext: contextText,
        initialChoice: choice,
        currentTime: _controller.playback.position.inMilliseconds / 1000.0,
      ),
    );
  }

  void _openDanmakuInput() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgPanel,
      isScrollControlled: true,
      builder: (_) {
        final ctrl = TextEditingController();
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '发个友善的弹幕见证当下',
                  hintStyle: const TextStyle(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: .08),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _submitDanmaku(ctrl),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () => _submitDanmaku(ctrl),
              icon: const Icon(Icons.send),
            ),
          ]),
        );
      },
    );
  }

  void _submitDanmaku(TextEditingController ctrl) {
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    _controller.sendDanmaku(text);
    Navigator.pop(context);
  }
}
