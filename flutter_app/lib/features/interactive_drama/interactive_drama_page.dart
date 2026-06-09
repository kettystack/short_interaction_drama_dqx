import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce/hive.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/models.dart';
import '../player/controllers/playback_controller.dart';
import 'controllers/interactive_drama_controller.dart';
import 'data/interactive_drama_models.dart';

class InteractiveDramaPage extends StatefulWidget {
  const InteractiveDramaPage({super.key});

  @override
  State<InteractiveDramaPage> createState() => _InteractiveDramaPageState();
}

class _InteractiveDramaPageState extends State<InteractiveDramaPage> {
  static const double _desktopViewportAspectRatio = 9 / 16;
  static const String _progressKey = 'tianxiadyi';
  static const int _totalEndingCount = 11;
  static const List<_EndingMeta> _endingCatalog = [
    _EndingMeta('exposed_early', '锋芒过早结局', '失败结局'),
    _EndingMeta('betrayed_ally', '错信盟友结局', '失败结局'),
    _EndingMeta('broken_evidence', '证据断裂结局', '失败结局'),
    _EndingMeta('blood_debt', '血债失控结局', '失败结局'),
    _EndingMeta('faith_lost', '失信败局', '失败结局'),
    _EndingMeta('lonely_power', '孤家寡人结局', '失败结局'),
    _EndingMeta('public_legend', '天下扬名结局', '通关结局'),
    _EndingMeta('mask_master', '藏锋为王结局', '通关结局'),
    _EndingMeta('chess_winner', '权谋翻盘结局', '通关结局'),
    _EndingMeta('guardian', '守护羁绊结局', '通关结局'),
    _EndingMeta('hidden_truth', '隐藏真相结局', '隐藏结局'),
  ];
  static const List<String> _keyItemIds = [
    'account_book',
    'token',
    'edict',
  ];

  late final InteractiveDramaController _controller =
      InteractiveDramaController();
  late final PlaybackController _playback = PlaybackController();
  final ApiClient _api = ApiClient.create();

  Episode? _episode;
  String? _loadedEpisodeId;
  String? _promptedNodeId;
  bool _choiceVisible = false;
  bool _starting = true;
  bool _playingBranchClip = false;
  bool _finishingBranchClip = false;
  double _branchClipStartAt = 0;
  InteractiveNode? _branchSourceNode;
  InteractiveOption? _branchOption;
  Timer? _storyToastTimer;
  bool _showStoryToast = false;
  String? _pageError;

  Box get _progressBox => Hive.box('interactive_drama_progress');

  @override
  void initState() {
    super.initState();
    _playback.addListener(_onPlaybackTick);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _storyToastTimer?.cancel();
    _playback.removeListener(_onPlaybackTick);
    _playback.dispose();
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
    if (available.width <= 0 || available.height <= 0) return available;
    final width = math.min(
      available.width,
      available.height * _desktopViewportAspectRatio,
    );
    return Size(width, width / _desktopViewportAspectRatio);
  }

  Future<void> _bootstrap() async {
    setState(() {
      _starting = true;
      _pageError = null;
    });
    try {
      await _controller.start(reset: true);
      if (_controller.run == null) return;
      final node = _controller.activeNode;
      await _openMainVideo(
        node?.episodeId ?? _controller.run?.currentEpisodeId ?? 'txy_001',
        startAt: Duration.zero,
        autoplay: true,
      );
    } catch (exception) {
      if (mounted) _pageError = '视频或后端加载失败：$exception';
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _openMainVideo(
    String episodeId, {
    required Duration startAt,
    required bool autoplay,
  }) async {
    if (_loadedEpisodeId != episodeId || _episode == null) {
      final episode = await _api.getEpisode(episodeId);
      if (!mounted) return;
      setState(() {
        _episode = episode;
        _loadedEpisodeId = episodeId;
      });
    }
    final url = _episode?.preferredVideoUrl;
    if (url == null || url.isEmpty) return;
    await _playback.openAt(url, startAt, autoplay: autoplay);
  }

  void _onPlaybackTick() {
    if (!mounted || _starting || _controller.isChoosing) return;
    if (_playingBranchClip) {
      _checkBranchClipEnd();
      return;
    }
    final node = _controller.activeNode;
    if (node == null || _controller.ending != null || _choiceVisible) return;
    if (_promptedNodeId == node.nodeId) return;
    final position = _playback.position.inMilliseconds / 1000.0;
    if (position + 0.18 >= node.tsInVideo) {
      _promptedNodeId = node.nodeId;
      unawaited(_playback.pause());
      setState(() => _choiceVisible = true);
    }
  }

  void _checkBranchClipEnd() {
    if (_finishingBranchClip) return;
    final option = _branchOption;
    final duration = _playback.duration;
    final position = _playback.position;
    final expectedDuration = option?.branchDuration ?? 0;
    final elapsedSeconds =
        position.inMilliseconds / 1000.0 - _branchClipStartAt;
    final reachedExpectedDuration =
        expectedDuration > 0 && elapsedSeconds >= expectedDuration - .25;
    final reachedMediaEnd = duration > Duration.zero &&
        duration - position <= const Duration(milliseconds: 350);
    if (reachedExpectedDuration || reachedMediaEnd) {
      _finishingBranchClip = true;
      unawaited(_resumeMainAfterBranch());
    }
  }

  Future<void> _choose(InteractiveOption option) async {
    final sourceNode = _controller.activeNode;
    if (sourceNode == null) return;
    setState(() {
      _choiceVisible = false;
      _branchSourceNode = sourceNode;
      _branchOption = option;
      _branchClipStartAt = option.branchStartAt;
    });
    await _controller.choose(option);
    if (!mounted) return;
    await _saveProgress();
    _showStoryResultToast();

    if (option.branchVideoUrl.isNotEmpty) {
      setState(() {
        _playingBranchClip = true;
        _finishingBranchClip = false;
      });
      await _playback.open(
        option.branchVideoUrl,
        autoplay: true,
        startAt: Duration(milliseconds: (option.branchStartAt * 1000).round()),
      );
      return;
    }
    await _resumeMainAfterChoice(sourceNode);
  }

  Future<void> _resumeMainAfterChoice(InteractiveNode sourceNode) async {
    if (_controller.ending != null) {
      await _playback.pause();
      return;
    }
    final nextNode = _controller.activeNode;
    final targetEpisodeId = nextNode?.episodeId ?? sourceNode.episodeId;
    final resumeSeconds = targetEpisodeId == sourceNode.episodeId
        ? sourceNode.resumeAt
        : math.max(0, (nextNode?.tsInVideo ?? 0) - 12);
    await _openMainVideo(
      targetEpisodeId,
      startAt: Duration(milliseconds: (resumeSeconds * 1000).round()),
      autoplay: true,
    );
  }

  Future<void> _resumeMainAfterBranch() async {
    final sourceNode = _branchSourceNode;
    if (sourceNode == null) return;
    setState(() {
      _playingBranchClip = false;
      _finishingBranchClip = false;
    });
    await _resumeMainAfterChoice(sourceNode);
    if (!mounted) return;
    setState(() {
      _branchSourceNode = null;
      _branchOption = null;
      _branchClipStartAt = 0;
    });
  }

  Future<void> _resetRoute() async {
    _storyToastTimer?.cancel();
    setState(() {
      _choiceVisible = false;
      _playingBranchClip = false;
      _finishingBranchClip = false;
      _branchSourceNode = null;
      _branchOption = null;
      _promptedNodeId = null;
      _showStoryToast = false;
      _pageError = null;
      _starting = true;
    });
    try {
      await _controller.reset();
      if (_controller.run == null) return;
      final node = _controller.activeNode;
      await _openMainVideo(
        node?.episodeId ?? 'txy_001',
        startAt: Duration.zero,
        autoplay: true,
      );
    } catch (exception) {
      if (mounted) _pageError = '重开路线失败：$exception';
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _showStoryResultToast() {
    _storyToastTimer?.cancel();
    setState(() => _showStoryToast = true);
    _storyToastTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showStoryToast = false);
    });
  }

  Future<void> _togglePlay() async {
    if (_choiceVisible || _controller.ending != null) return;
    await _playback.togglePlay();
  }

  Future<void> _saveProgress() async {
    final run = _controller.run;
    if (run == null) return;
    final raw = _progressBox.get(_progressKey, defaultValue: const {});
    final data =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final unlocked = <String>{..._unlockedEndingIds()};
    final ending = run.ending;
    if (ending != null) {
      unlocked.add(ending.endingId);
      final titles = data['ending_titles'] is Map
          ? Map<String, dynamic>.from(data['ending_titles'] as Map)
          : <String, dynamic>{};
      titles[ending.endingId] = ending.title;
      data['ending_titles'] = titles;
      data['last_ending_id'] = ending.endingId;
      data['last_ending_title'] = ending.title;
      data['last_ending_category'] = ending.category;
    }
    data['unlocked_endings'] = unlocked.toList()..sort();
    data['selected_count'] = run.selectedPath.length;
    data['last_path'] = run.selectedPath;
    data['last_state'] = _stateToJson(run.state);
    data['updated_at'] = DateTime.now().toIso8601String();
    await _progressBox.put(_progressKey, data);
    if (mounted) setState(() {});
  }

  Map<String, dynamic> _stateToJson(InteractiveDramaState state) {
    return {
      'reputation': state.reputation,
      'disguise': state.disguise,
      'power': state.power,
      'suspicion': state.suspicion,
      'romance': state.romance,
      'justice': state.justice,
      'heroine': state.heroine,
      'old_friend': state.oldFriend,
      'emperor': state.emperor,
      'mastermind': state.mastermind,
      'route_tags': state.routeTags,
      'flags': state.flags,
    };
  }

  List<String> _unlockedEndingIds() {
    final raw = _progressBox.get(_progressKey, defaultValue: const {});
    if (raw is! Map) return const [];
    final values = raw['unlocked_endings'];
    if (values is! List) return const [];
    return values.map((item) => item.toString()).toList();
  }

  Future<void> _rewindToPreviousChoice() async {
    final path = _controller.run?.selectedPath ?? const [];
    if (path.isEmpty) {
      await _resetRoute();
      return;
    }
    _storyToastTimer?.cancel();
    setState(() {
      _choiceVisible = false;
      _playingBranchClip = false;
      _finishingBranchClip = false;
      _branchSourceNode = null;
      _branchOption = null;
      _branchClipStartAt = 0;
      _promptedNodeId = null;
      _showStoryToast = false;
      _starting = true;
    });
    await _controller.rewind();
    final node = _controller.activeNode;
    if (node != null) {
      await _openMainVideo(
        node.episodeId,
        startAt: Duration(
          milliseconds: (math.max(0, node.tsInVideo - 4) * 1000).round(),
        ),
        autoplay: true,
      );
    }
    if (mounted) setState(() => _starting = false);
  }

  bool _optionLocked(InteractiveOption option) {
    return !_conditionMet(option.condition);
  }

  bool _conditionMet(Map<String, dynamic> condition) {
    if (condition.isEmpty) return true;
    final state = _controller.state;
    if (state == null) return false;
    for (final entry in condition.entries) {
      final key = entry.key;
      final expected = entry.value;
      if (key == 'flag') {
        if (state.flags[expected.toString()] != true) return false;
        continue;
      }
      if (key == 'flags') {
        final flags = expected is List ? expected : [expected];
        if (!flags.every((item) => state.flags[item.toString()] == true)) {
          return false;
        }
        continue;
      }
      if (key == 'route_tag') {
        if (!state.routeTags.contains(expected.toString())) return false;
        continue;
      }
      final value = _stateValue(key, state);
      if (value == null || expected is! Map) return false;
      final cond = Map<String, dynamic>.from(expected);
      if (cond['gte'] != null && value < (cond['gte'] as num).toInt()) {
        return false;
      }
      if (cond['lte'] != null && value > (cond['lte'] as num).toInt()) {
        return false;
      }
    }
    return true;
  }

  int? _stateValue(String key, InteractiveDramaState state) {
    return switch (key) {
      'reputation' => state.reputation,
      'disguise' => state.disguise,
      'power' => state.power,
      'suspicion' => state.suspicion,
      'romance' => state.romance,
      'justice' => state.justice,
      'heroine' => state.heroine,
      'old_friend' => state.oldFriend,
      'emperor' => state.emperor,
      'mastermind' => state.mastermind,
      _ => null,
    };
  }

  String _conditionText(Map<String, dynamic> condition) {
    if (condition.isEmpty) return '';
    final requiredFlags = <String>[];
    final flag = condition['flag'];
    if (flag != null) requiredFlags.add(flag.toString());
    final flags = condition['flags'];
    if (flags is List) {
      requiredFlags.addAll(flags.map((item) => item.toString()));
    }
    final missing = requiredFlags
        .where((item) => _controller.state?.flags[item] != true)
        .map(_flagLabel)
        .toList();
    if (missing.isNotEmpty) return '需要：${missing.join('、')}';
    return '隐藏条件已满足';
  }

  void _openRouteMapSheet() {
    final run = _controller.run;
    if (run == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RouteMapSheet(
        path: run.selectedPath,
        activeNode: run.activeNode,
        ending: run.ending,
        tags: run.state.routeTags,
      ),
    );
  }

  void _openEndingCollectionSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EndingCollectionSheet(
        endings: _endingCatalog,
        unlockedIds: _unlockedEndingIds(),
      ),
    );
  }

  void _openStatusSheet() {
    final state = _controller.state;
    if (state == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StatusSheet(
        state: state,
        stateLabel: _stateLabel,
        flagLabel: _flagLabel,
      ),
    );
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
                          child: _scene(),
                        ),
                      ),
                    ),
                  ),
                );
              },
            )
          : _scene(),
    );
  }

  Widget _scene() {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _playback]),
      builder: (_, __) {
        final episode = _episode;
        final error = _controller.error ?? _pageError;
        return Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlay,
              child: ColoredBox(
                color: Colors.black,
                child: episode == null
                    ? const SizedBox.shrink()
                    : Video(
                        controller: _playback.controller,
                        controls: NoVideoControls,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
          ),
          const Positioned.fill(child: _ScrimLayer()),
          _topBar(episode),
          _rightStatusRail(),
          _bottomVideoMeta(episode),
          _branchPlayingBadge(),
          _storyToast(),
          if (error != null) _errorBanner(error),
          if (_starting || _playback.buffering) _loadingLayer(),
          if (_choiceVisible && _controller.activeNode != null)
            _choiceLayer(_controller.activeNode!),
          if (_controller.ending != null) _endingLayer(_controller.ending!),
        ]);
      },
    );
  }

  Widget _topBar(Episode? episode) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(children: [
            _roundIconButton(
              icon: Icons.arrow_back_ios_new,
              onTap: () => Modular.to.navigate('/'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _controller.run?.title ?? '天下第一纨绔：藏锋互动版',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(children: [
                    if (episode != null) ...[
                      _miniChip('第${episode.episodeNo}集', AppColors.accentGold),
                      const SizedBox(width: 6),
                    ],
                    _miniChip('视频互动版', AppColors.accentHot),
                    const SizedBox(width: 6),
                    _miniChip(
                      _playingBranchClip ? '正在播放分支' : '主线播放中',
                      _playingBranchClip
                          ? AppColors.accentGold
                          : AppColors.accentMint,
                    ),
                    const SizedBox(width: 6),
                    _miniChip(
                      '结局 ${_unlockedEndingIds().length}/$_totalEndingCount',
                      AppColors.accentVio,
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _roundIconButton(
              icon: Icons.account_tree_rounded,
              onTap: _openRouteMapSheet,
            ),
            const SizedBox(width: 8),
            _roundIconButton(
              icon: Icons.emoji_events_rounded,
              onTap: _openEndingCollectionSheet,
            ),
            const SizedBox(width: 8),
            _roundIconButton(icon: Icons.replay, onTap: _resetRoute),
          ]),
        ),
      ),
    );
  }

  Widget _rightStatusRail() {
    final state = _controller.state;
    if (state == null) return const SizedBox.shrink();
    final itemCount =
        _keyItemIds.where((item) => state.flags[item] == true).length;
    return Positioned(
      right: 10,
      top: 140,
      child: Column(
        children: [
          _statPill('名声', state.reputation, AppColors.accentGold),
          _statPill('伪装', state.disguise, AppColors.accentVio),
          _statPill('势力', state.power, AppColors.accentMint),
          _statPill('警惕', state.suspicion, AppColors.accentHot),
          const SizedBox(height: 8),
          _iconRailPill(
            icon: Icons.groups_rounded,
            label: '关系',
            value:
                '${state.heroine + state.oldFriend + state.emperor + state.mastermind}',
            color: AppColors.accentMint,
            onTap: _openStatusSheet,
          ),
          _iconRailPill(
            icon: Icons.inventory_2_rounded,
            label: '道具',
            value: '$itemCount/3',
            color: AppColors.accentGold,
            onTap: _openStatusSheet,
          ),
          _routeCountPill(_controller.run?.selectedPath.length ?? 0),
        ],
      ),
    );
  }

  Widget _bottomVideoMeta(Episode? episode) {
    final node = _controller.activeNode;
    final position = _playback.position;
    final duration = _playback.duration;
    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return Positioned(
      left: 18,
      right: 18,
      bottom: 20,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_choiceVisible && _controller.ending == null) ...[
              Text(
                _playingBranchClip ? '你的选择正在变成一段分支剧情' : '看到关键时刻会自动暂停，让你决定主角下一步',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .82),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              if (node != null) ...[
                const SizedBox(height: 7),
                _nextNodeCountdown(node),
              ],
              const SizedBox(height: 12),
            ],
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: .2),
                color: _playingBranchClip
                    ? AppColors.accentGold
                    : AppColors.accentHot,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nextNodeCountdown(InteractiveNode node) {
    final remain = node.tsInVideo - _playback.position.inMilliseconds / 1000.0;
    if (_promptedNodeId == node.nodeId) {
      return _miniChip('已触发互动点', AppColors.accentGold);
    }
    return _miniChip(
      remain <= 0 ? '互动点即将出现' : '距离互动点 ${remain.ceil()}s',
      AppColors.accentGold,
    );
  }

  Widget _choiceLayer(InteractiveNode node) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: .58),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 70, 16, 22),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xEF12101A),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: AppColors.accentGold.withValues(alpha: .5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentHot.withValues(alpha: .25),
                        blurRadius: 38,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        _miniChip('剧情分岔点', AppColors.accentGold),
                        const SizedBox(width: 8),
                        Text(
                          '${node.tsInVideo.toStringAsFixed(0)}s',
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Text(
                        node.question,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                      if (node.context.isNotEmpty) ...[
                        const SizedBox(height: 9),
                        Text(
                          node.context,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .72),
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      ...node.options.asMap().entries.map(
                            (entry) => _choiceOptionCard(
                              entry.key,
                              entry.value,
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _choiceOptionCard(int index, InteractiveOption option) {
    final locked = _optionLocked(option);
    final deltaText = option.stateDelta.entries
        .map((entry) =>
            '${_stateLabel(entry.key)} ${entry.value > 0 ? '+' : ''}${entry.value}')
        .join('  ');
    final itemText = option.flagsDelta.entries
        .where((entry) => entry.value)
        .map((entry) => _flagLabel(entry.key))
        .join('、');
    final conditionText = _conditionText(option.condition);
    final branchLabel =
        option.branchVideoSessionHint.contains('fallback') ? '素材片段' : '真实分支';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _controller.isChoosing || locked ? null : () => _choose(option),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: locked ? .06 : .13),
                Colors.white.withValues(alpha: locked ? .03 : .055),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: locked
                  ? AppColors.accentHot.withValues(alpha: .28)
                  : Colors.white.withValues(alpha: .15),
            ),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.ctaGradient,
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        option.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (option.branchVideoUrl.isNotEmpty)
                      _miniChip(branchLabel, AppColors.accentMint),
                    if (locked) ...[
                      const SizedBox(width: 6),
                      _miniChip('未解锁', AppColors.accentHot),
                    ],
                  ]),
                  if (option.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      option.description,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.32,
                      ),
                    ),
                  ],
                  if (conditionText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      conditionText,
                      style: TextStyle(
                        color:
                            locked ? AppColors.accentHot : AppColors.accentMint,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                  if (itemText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '获得：$itemText',
                      style: const TextStyle(
                        color: AppColors.accentMint,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  if (deltaText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      deltaText,
                      style: const TextStyle(
                        color: AppColors.accentGold,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _controller.isChoosing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    locked ? Icons.lock_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
          ]),
        ),
      ),
    );
  }

  Widget _branchPlayingBadge() {
    if (!_playingBranchClip || _branchOption == null) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 18,
      right: 18,
      top: 98,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.accentGold.withValues(alpha: .36),
            ),
          ),
          child: Row(children: [
            const Icon(Icons.alt_route_rounded,
                color: AppColors.accentGold, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '正在播放：${_branchOption!.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '结束后回主线',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _storyToast() {
    final text = _controller.latestStoryText;
    if (!_showStoryToast || text.isEmpty || _choiceVisible) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 18,
      right: 18,
      bottom: 62,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _showStoryToast ? 1 : 0,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .68),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.accentMint.withValues(alpha: .3),
              ),
            ),
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, height: 1.42),
            ),
          ),
        ),
      ),
    );
  }

  Widget _endingLayer(InteractiveEnding ending) {
    final routeCount = _controller.run?.selectedPath.length ?? 0;
    final unlockedCount = _unlockedEndingIds().length;
    final isFailure = ending.category.contains('失败');
    return Positioned.fill(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: .55),
              isFailure ? const Color(0xEE1D0710) : const Color(0xEE080510),
              Colors.black.withValues(alpha: .92),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _miniChip(ending.category, _endingColor(ending.category)),
                const SizedBox(width: 8),
                _miniChip('已解锁 $unlockedCount/$_totalEndingCount',
                    AppColors.accentVio),
              ]),
              const SizedBox(height: 16),
              Text(
                ending.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              _endingRouteSummary(routeCount),
              const SizedBox(height: 14),
              Text(
                ending.summary,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (routeCount > 0)
                    FilledButton.icon(
                      onPressed: _controller.isLoading
                          ? null
                          : _rewindToPreviousChoice,
                      icon: const Icon(Icons.undo_rounded),
                      label: const Text('回到上一个选择点'),
                    ),
                  FilledButton.icon(
                    onPressed: _resetRoute,
                    icon: const Icon(Icons.replay),
                    label: const Text('重开另一条路线'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openEndingCollectionSheet,
                    icon: const Icon(Icons.emoji_events_rounded),
                    label: const Text('结局收集'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Modular.to.navigate('/'),
                    icon: const Icon(Icons.home_rounded),
                    label: const Text('回首页'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loadingLayer() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .48),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const CircularProgressIndicator(color: AppColors.accentHot),
          ),
        ),
      ),
    );
  }

  Widget _errorBanner(String message) {
    return Positioned(
      left: 18,
      right: 18,
      top: 88,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.accentHot.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.accentHot.withValues(alpha: .45),
            ),
          ),
          child: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .42),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: .15)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _miniChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .38)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _statPill(String label, int value, Color color) {
    return Container(
      width: 54,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ]),
    );
  }

  Widget _routeCountPill(int count) {
    return Container(
      width: 54,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        gradient: AppColors.ctaGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const Text(
          '选择',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ]),
    );
  }

  Widget _iconRailPill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 54,
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: .34)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _endingRouteSummary(int routeCount) {
    final tags = _controller.state?.routeTags.take(4).toList() ?? const [];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          '本轮走过 $routeCount 个选择点',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags
                .map((tag) => _miniChip(tag, AppColors.accentGold))
                .toList(),
          ),
        ],
      ]),
    );
  }

  Color _endingColor(String category) {
    if (category.contains('失败')) return AppColors.accentHot;
    if (category.contains('隐藏')) return AppColors.accentVio;
    return AppColors.accentMint;
  }

  String _stateLabel(String key) {
    return switch (key) {
      'reputation' => '名声',
      'disguise' => '伪装',
      'power' => '势力',
      'suspicion' => '警惕',
      'romance' => '情感',
      'justice' => '民心',
      'heroine' => '女主',
      'old_friend' => '旧友',
      'emperor' => '皇帝',
      'mastermind' => '幕后人',
      _ => key,
    };
  }

  String _flagLabel(String key) {
    return switch (key) {
      'account_book' => '账本',
      'token' => '令牌',
      'edict' => '密诏',
      'witness' => '证人',
      'shadow_tail' => '暗线尾迹',
      _ => key,
    };
  }
}

class _EndingMeta {
  final String id;
  final String title;
  final String category;

  const _EndingMeta(this.id, this.title, this.category);
}

class _SheetFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SheetFrame({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .74,
      minChildSize: .45,
      maxChildSize: .92,
      builder: (context, scrollController) => Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        decoration: const BoxDecoration(
          color: AppColors.bgPanel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              child: child,
            ),
          ),
        ]),
      ),
    );
  }
}

class _RouteMapSheet extends StatelessWidget {
  final List<Map<String, dynamic>> path;
  final InteractiveNode? activeNode;
  final InteractiveEnding? ending;
  final List<String> tags;

  const _RouteMapSheet({
    required this.path,
    required this.activeNode,
    required this.ending,
    required this.tags,
  });

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: '路线图',
      subtitle: '记录本轮所有选择，方便回看分支走向',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (tags.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags
                .take(8)
                .map((tag) => _sheetChip(tag, AppColors.accentGold))
                .toList(),
          ),
          const SizedBox(height: 16),
        ],
        if (path.isEmpty)
          _emptySheetHint('还没做出选择，播放到第一个分岔点后会生成路线。')
        else
          ...path.asMap().entries.map((entry) {
            final item = entry.value;
            return _routeStep(
              index: entry.key + 1,
              question: item['question']?.toString() ?? '剧情分岔点',
              label: item['label']?.toString() ?? '未命名选择',
              story: item['story_text']?.toString() ?? '',
            );
          }),
        if (activeNode != null) ...[
          const SizedBox(height: 12),
          _routeStep(
            index: path.length + 1,
            question: '当前待选择',
            label: activeNode!.question,
            story: activeNode!.context,
            active: true,
          ),
        ],
        if (ending != null) ...[
          const SizedBox(height: 12),
          _routeStep(
            index: path.length + 1,
            question: '已抵达结局',
            label: ending!.title,
            story: ending!.summary,
            active: true,
          ),
        ],
      ]),
    );
  }

  Widget _routeStep({
    required int index,
    required String question,
    required String label,
    required String story,
    bool active = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: active ? .1 : .055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active
              ? AppColors.accentGold.withValues(alpha: .45)
              : Colors.white.withValues(alpha: .1),
        ),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: active ? AppColors.accentGold : Colors.white24,
          child: Text(
            '$index',
            style: TextStyle(
              color: active ? Colors.black : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (story.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  story,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

class _EndingCollectionSheet extends StatelessWidget {
  final List<_EndingMeta> endings;
  final List<String> unlockedIds;

  const _EndingCollectionSheet({
    required this.endings,
    required this.unlockedIds,
  });

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: '结局收集',
      subtitle: '已解锁 ${unlockedIds.length}/${endings.length} 个结局',
      child: Column(
        children: endings.map((ending) {
          final unlocked = unlockedIds.contains(ending.id);
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: unlocked ? .09 : .045),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: unlocked
                    ? _categoryColor(ending.category).withValues(alpha: .5)
                    : Colors.white.withValues(alpha: .08),
              ),
            ),
            child: Row(children: [
              Icon(
                unlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                color: unlocked
                    ? _categoryColor(ending.category)
                    : AppColors.textTertiary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unlocked ? ending.title : '未解锁结局',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      unlocked ? ending.category : '继续探索不同选择路线',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _sheetChip(
                ending.category,
                unlocked
                    ? _categoryColor(ending.category)
                    : AppColors.textTertiary,
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Color _categoryColor(String category) {
    if (category.contains('失败')) return AppColors.accentHot;
    if (category.contains('隐藏')) return AppColors.accentVio;
    return AppColors.accentMint;
  }
}

class _StatusSheet extends StatelessWidget {
  final InteractiveDramaState state;
  final String Function(String key) stateLabel;
  final String Function(String key) flagLabel;

  const _StatusSheet({
    required this.state,
    required this.stateLabel,
    required this.flagLabel,
  });

  @override
  Widget build(BuildContext context) {
    final relationRows = [
      ('heroine', state.heroine),
      ('old_friend', state.oldFriend),
      ('emperor', state.emperor),
      ('mastermind', state.mastermind),
    ];
    final itemRows = ['account_book', 'token', 'edict'];
    return _SheetFrame(
      title: '角色关系与关键道具',
      subtitle: '关系值影响路线倾向，道具决定隐藏结局能否开启',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          '人物关系值',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        ...relationRows.map(
          (row) => _meterRow(stateLabel(row.$1), row.$2, AppColors.accentMint),
        ),
        const SizedBox(height: 18),
        const Text(
          '关键道具',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: itemRows.map((id) {
            final owned = state.flags[id] == true;
            return _itemChip(flagLabel(id), owned);
          }).toList(),
        ),
        const SizedBox(height: 18),
        const Text(
          '当前路线标签',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        if (state.routeTags.isEmpty)
          _emptySheetHint('还没有路线标签，做出选择后会自动记录。')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: state.routeTags
                .map((tag) => _sheetChip(tag, AppColors.accentGold))
                .toList(),
          ),
      ]),
    );
  }

  Widget _meterRow(String label, int value, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (value / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white12,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _itemChip(String label, bool owned) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: (owned ? AppColors.accentGold : Colors.white)
            .withValues(alpha: owned ? .18 : .06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: owned
              ? AppColors.accentGold.withValues(alpha: .55)
              : Colors.white.withValues(alpha: .12),
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          owned ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          color: owned ? AppColors.accentGold : AppColors.textTertiary,
          size: 16,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: owned ? AppColors.accentGold : AppColors.textSecondary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ]),
    );
  }
}

Widget _sheetChip(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .34)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

Widget _emptySheetHint(String text) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .055),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: .1)),
    ),
    child: Text(
      text,
      style: const TextStyle(color: AppColors.textSecondary),
    ),
  );
}

class _ScrimLayer extends StatelessWidget {
  const _ScrimLayer();

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      const Positioned(
        left: 0,
        right: 0,
        top: 0,
        height: 190,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.topScrim),
        ),
      ),
      const Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 260,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.bottomScrim),
        ),
      ),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withValues(alpha: .12),
                Colors.transparent,
                Colors.black.withValues(alpha: .2),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
      ),
    ]);
  }
}
