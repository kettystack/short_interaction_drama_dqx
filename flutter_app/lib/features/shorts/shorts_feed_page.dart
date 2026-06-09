import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../shared/widgets/cover_image.dart';
import '../../shared/widgets/play_pause_indicator.dart';

/// 仿腾讯视频「短剧」频道：竖屏 PageView 上下滑切换，单击=播放/暂停，
/// 右侧互动/评论/分享栏，保留进入完整互动播放的入口。
class ShortsFeedPage extends StatefulWidget {
  const ShortsFeedPage({super.key});

  @override
  State<ShortsFeedPage> createState() => _ShortsFeedPageState();
}

class _ShortsFeedPageState extends State<ShortsFeedPage> {
  static const double _desktopViewportAspectRatio = 9 / 16;

  final _api = Modular.get<ApiClient>();
  final _pageCtl = PageController();
  List<Episode> _episodes = [];
  bool _loading = true;
  String? _error;
  int _currentIndex = 0;
  int _playTogglePulse = 0;
  bool _spacePressed = false;
  bool _keyboardEnabled = true;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.getShortsFeed(limit: 50);
      if (!mounted) return;
      setState(() {
        _episodes = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    _pageCtl.dispose();
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

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (!_keyboardEnabled) return false;
    if (event.logicalKey != LogicalKeyboardKey.space) return false;
    if (event is KeyUpEvent) {
      _spacePressed = false;
      return true;
    }
    if (event is KeyDownEvent && !_spacePressed) {
      _spacePressed = true;
      if (mounted && _episodes.isNotEmpty) {
        setState(() => _playTogglePulse++);
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final page = _buildFeedContent(context);

    if (!_isDesktopPlatform()) return page;

    return LayoutBuilder(builder: (context, constraints) {
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
                child: page,
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildFeedContent(BuildContext context) {
    if (_loading) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
            child: CircularProgressIndicator(color: AppColors.accentHot)),
      );
    }
    if (_error != null || _episodes.isEmpty) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off, color: AppColors.accentHot, size: 36),
            const SizedBox(height: 8),
            const Text('短剧流加载失败',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('重试')),
          ]),
        ),
      );
    }
    return Stack(children: [
      Positioned.fill(
        child: PageView.builder(
          controller: _pageCtl,
          scrollDirection: Axis.vertical,
          itemCount: _episodes.length,
          onPageChanged: (index) => setState(() => _currentIndex = index),
          itemBuilder: (_, index) => _ShortVideoCard(
            key: ValueKey(_episodes[index].id),
            episode: _episodes[index],
            isActive: index == _currentIndex,
            playTogglePulse: index == _currentIndex ? _playTogglePulse : 0,
            onFullPlayerActiveChanged: (active) {
              if (mounted) setState(() => _keyboardEnabled = !active);
            },
          ),
        ),
      ),
      // 顶部 logo / 搜索
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Row(children: [
              const Text('短剧',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900)),
              const SizedBox(width: 6),
              const Icon(Icons.swap_horiz, color: Colors.white70, size: 18),
              const SizedBox(width: 18),
              _topTab('推荐', false),
              _topTab('精选', true),
              _topTab('看过', false),
              _topTab('短剧夜', false),
              const Spacer(),
              const Icon(Icons.search, color: Colors.white, size: 22),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _topTab(String label, bool active) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Text(label,
            style: TextStyle(
                color: active ? Colors.white : Colors.white60,
                fontSize: active ? 18 : 15,
                fontWeight: active ? FontWeight.w900 : FontWeight.normal)),
      );
}

/// 单条短剧卡片：播放器 + 右侧操作栏 + 底部标题
class _ShortVideoCard extends StatefulWidget {
  final Episode episode;
  final bool isActive;
  final int playTogglePulse;
  final ValueChanged<bool> onFullPlayerActiveChanged;

  const _ShortVideoCard({
    super.key,
    required this.episode,
    required this.isActive,
    required this.playTogglePulse,
    required this.onFullPlayerActiveChanged,
  });

  @override
  State<_ShortVideoCard> createState() => _ShortVideoCardState();
}

class _ShortVideoCardState extends State<_ShortVideoCard>
    with AutomaticKeepAliveClientMixin {
  late final Player _player = Player(
    configuration: const PlayerConfiguration(bufferSize: 16 * 1024 * 1024),
  );
  late final VideoController _vc = VideoController(_player);
  bool _ready = false;
  int _tapPulse = 0;
  bool _indicatorIsPlaying = false;
  int _likeCount = 0;
  bool _liked = false;
  bool _wasPlayingBeforeFullPlayer = false;

  @override
  void initState() {
    super.initState();
    _likeCount = 1200 + (widget.episode.episodeNo * 37) % 7000;
    _open();
  }

  Future<void> _open() async {
    try {
      await _player.open(
        Media(AppConfig.absoluteUrl(widget.episode.preferredVideoUrl)),
        play: widget.isActive,
      );
      await _player.setPlaylistMode(PlaylistMode.loop);
      if (!widget.isActive) {
        await _player.setVolume(0);
      }
      if (mounted) setState(() => _ready = true);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant _ShortVideoCard old) {
    super.didUpdateWidget(old);
    if (widget.isActive &&
        old.isActive &&
        widget.playTogglePulse != old.playTogglePulse) {
      _togglePlayback();
    }
    if (widget.isActive == old.isActive) return;
    if (widget.isActive) {
      _player.setVolume(100);
      _player.play();
    } else {
      // 离开当前页：立即静音·暂停·回头，避免上一集声音残留
      _player.setVolume(0);
      _player.pause();
      _player.seek(Duration.zero);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  void _togglePlayback() {
    final nextPlaying = !_player.state.playing;
    if (nextPlaying) {
      _player.play();
    } else {
      _player.pause();
    }
    setState(() {
      _indicatorIsPlaying = nextPlaying;
      _tapPulse++;
    });
  }

  void _toggleLike() {
    setState(() {
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
    });
  }

  Future<void> _openFullPlayer() async {
    _wasPlayingBeforeFullPlayer = _player.state.playing;
    await _player.setVolume(0);
    await _player.pause();
    widget.onFullPlayerActiveChanged(true);
    try {
      await Modular.to.pushNamed('/play/${widget.episode.id}');
    } finally {
      widget.onFullPlayerActiveChanged(false);
    }
    if (!mounted || !widget.isActive) return;
    await _player.setVolume(100);
    if (_wasPlayingBeforeFullPlayer) {
      await _player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return GestureDetector(
      onTap: _togglePlayback,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(children: [
          // 视频
          Positioned.fill(
            child: _ready
                ? Video(
                    controller: _vc,
                    controls: NoVideoControls,
                    fit: BoxFit.cover,
                  )
                : CoverImage(
                    path: widget.episode.coverUrl,
                    width: double.infinity,
                    height: double.infinity,
                  ),
          ),
          // 底部渐变 + 标题
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 60, 90, 110),
              decoration: const BoxDecoration(gradient: AppColors.bottomScrim),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: AppColors.accentHot,
                            borderRadius: BorderRadius.circular(3)),
                        child: const Text('独播',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 6),
                      Text('第${widget.episode.episodeNo}集',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ]),
                    const SizedBox(height: 8),
                    Text(widget.episode.title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text('点击进入完整互动版',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12)),
                  ]),
            ),
          ),
          // 右侧操作栏
          Positioned(
            right: 8,
            bottom: 110,
            child: Column(children: [
              _sideAction(_liked ? Icons.favorite : Icons.favorite_border,
                  '$_likeCount',
                  color: _liked ? AppColors.accentHot : Colors.white,
                  onTap: _toggleLike),
              const SizedBox(height: 14),
              _sideAction(Icons.mode_comment_outlined, '互动',
                  onTap: _openFullPlayer),
              const SizedBox(height: 14),
              _sideAction(Icons.share_outlined, '分享'),
              const SizedBox(height: 14),
              _sideAction(Icons.playlist_play_rounded, '选集',
                  onTap: _openFullPlayer),
            ]),
          ),
          // 中央播放/暂停反馈
          Positioned.fill(
            child: PlayPauseIndicator(
              trigger: _tapPulse,
              isPlaying: _indicatorIsPlaying,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _sideAction(IconData icon, String label,
      {Color color = Colors.white, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ]),
    );
  }
}
