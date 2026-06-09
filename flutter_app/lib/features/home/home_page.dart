import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce/hive.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../core/theme.dart';
import '../../core/user_session.dart';
import '../../data/api_client.dart';
import '../../data/models.dart';
import '../membership/membership_page.dart';
import '../picks/picks_page.dart';
import '../profile/profile_page.dart';
import '../shorts/shorts_feed_page.dart';
import '../../shared/widgets/cover_image.dart';
import 'home_controller.dart';
import 'widgets/bottom_tab_bar.dart';
import 'widgets/drama_strip.dart';
import 'widgets/hero_banner.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final HomeController _controller =
      HomeController(Modular.get<ApiClient>());
  HomeTab _tab = HomeTab.home;

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _bodyForTab(),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: BottomTabBar(
            selected: _tab,
            onChanged: (t) => setState(() => _tab = t),
          ),
        ),
      ]),
    );
  }

  Widget _bodyForTab() {
    switch (_tab) {
      case HomeTab.home:
        return _homeBody();
      case HomeTab.shorts:
        return const ShortsFeedPage();
      case HomeTab.vip:
        return const MembershipPage();
      case HomeTab.picks:
        return const PicksPage();
      case HomeTab.profile:
        return ProfilePage(groups: _controller.groups);
    }
  }

  Widget _homeBody() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return SafeArea(
          bottom: false,
          child: Column(children: [
            _topBar(),
            Expanded(child: _content()),
          ]),
        );
      },
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: Row(children: [
          const Icon(Icons.movie_filter, color: AppColors.accentHot, size: 20),
          const SizedBox(width: 6),
          const Text('短剧互动',
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: Colors.white)),
          const Spacer(),
          IconButton(
              icon: const Icon(Icons.search, color: Colors.white, size: 22),
              onPressed: _openSearchSheet),
          IconButton(
              icon: const Icon(Icons.notifications_none,
                  color: Colors.white, size: 22),
              onPressed: _openUpdatesSheet),
        ]),
      );

  Widget _content() {
    if (_controller.isLoading && _controller.groups.isEmpty) {
      return Skeletonizer(
        enabled: true,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          children: [
            Container(height: 240, color: AppColors.bgPanel),
            const SizedBox(height: 24),
            ...List.generate(2, (_) => _skeletonStrip()),
          ],
        ),
      );
    }
    if (_controller.errorMessage != null && _controller.groups.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off, color: AppColors.accentHot, size: 40),
          const SizedBox(height: 12),
          const Text('连接后端失败',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_controller.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _controller.load, child: const Text('重试')),
        ]),
      );
    }
    return RefreshIndicator(
      color: AppColors.accentHot,
      onRefresh: _controller.load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          HeroBanner(groups: _controller.groups),
          const SizedBox(height: 28),
          const _InteractiveDramaStrip(),
          for (final g in _controller.groups) ...[
            const SizedBox(height: 28),
            DramaStrip(group: g),
          ],
        ],
      ),
    );
  }

  Widget _skeletonStrip() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 120, height: 16, color: AppColors.bgPanel),
          const SizedBox(height: 12),
          SizedBox(
            height: 158,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, __) => Container(
                width: 112,
                decoration: BoxDecoration(
                  color: AppColors.bgPanel,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ]),
      );

  void _openSearchSheet() {
    final all = _controller.groups.expand((g) => g.episodes).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgPanel,
      builder: (_) => _EpisodeSearchSheet(episodes: all),
    );
  }

  void _openUpdatesSheet() {
    final favorites = Hive.box('favorites').length;
    final progress = Hive.box('progress').length;
    final pendingRaw =
        Hive.box('interaction_queue').get('items', defaultValue: const []);
    final historyRaw =
        Hive.box('interaction_history').get('items', defaultValue: const []);
    final pendingCount = pendingRaw is List ? pendingRaw.length : 0;
    final history = historyRaw is List
        ? historyRaw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .take(5)
            .toList()
        : <Map<String, dynamic>>[];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
        decoration: const BoxDecoration(
          color: AppColors.bgPanel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const Text('互动动态',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            _updateMetric('设备 ID', UserSession.userId),
            _updateMetric('追剧 / 进度', '$favorites 部追剧 · $progress 条进度'),
            _updateMetric('待同步', '$pendingCount 条互动'),
            const SizedBox(height: 14),
            const Text('最近互动',
                style: TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            if (history.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('还没有本地互动记录',
                    style: TextStyle(color: AppColors.textSecondary)),
              )
            else
              ...history.map((item) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bolt,
                        color: AppColors.accentGold, size: 20),
                    title: Text(item['action']?.toString() ?? '互动',
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text(item['episode_id']?.toString() ?? '',
                        style: const TextStyle(color: AppColors.textSecondary)),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _updateMetric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 92,
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
}

class _InteractiveDramaStrip extends StatefulWidget {
  const _InteractiveDramaStrip();

  @override
  State<_InteractiveDramaStrip> createState() => _InteractiveDramaStripState();
}

class _InteractiveDramaStripState extends State<_InteractiveDramaStrip> {
  late final Stream _progressStream;

  static const _chapters = [
    _InteractiveChapter(
      title: '第1幕',
      subtitle: '羞辱局',
      cover: '/frames/txy_001/scene_00073.jpg',
      tag: '三选一',
    ),
    _InteractiveChapter(
      title: '第2幕',
      subtitle: '暗线追查',
      cover: '/frames/txy_002/scene_00003.jpg',
      tag: '藏锋',
    ),
    _InteractiveChapter(
      title: '第3幕',
      subtitle: '盟友选择',
      cover: '/frames/txy_003/scene_00020.jpg',
      tag: '关系',
    ),
    _InteractiveChapter(
      title: '第4幕',
      subtitle: '朝堂交锋',
      cover: '/frames/txy_004/scene_00028.jpg',
      tag: '高压',
    ),
    _InteractiveChapter(
      title: '第5幕',
      subtitle: '牢狱审判',
      cover: '/frames/txy_005/scene_00006.jpg',
      tag: '败局',
    ),
    _InteractiveChapter(
      title: '第6幕',
      subtitle: '宫门夜局',
      cover: '/frames/txy_006/scene_00020.jpg',
      tag: '隐藏',
    ),
    _InteractiveChapter(
      title: '终幕',
      subtitle: '藏锋为王',
      cover: '/frames/txy_007/scene_00028.jpg',
      tag: '多结局',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _progressStream = Hive.box('interactive_drama_progress').watch();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _progressStream,
      builder: (context, _) => _buildStrip(context),
    );
  }

  Widget _buildStrip(BuildContext context) {
    final progress = _interactiveProgress();
    final unlocked = progress.unlockedEndings;
    final selectedCount = progress.selectedCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                gradient: AppColors.ctaGradient,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '天下第一纨绔：藏锋互动版',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _interactiveBadge(unlocked),
            const SizedBox(width: 8),
            Text(
              '已解锁 $unlocked/11',
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textTertiary,
              size: 16,
            ),
          ]),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Text(
            progress.lastEndingTitle.isEmpty
                ? '古装 · 互动影游 · 多结局'
                : '最近解锁：${progress.lastEndingTitle}',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _chapters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, index) => _InteractiveChapterCard(
              chapter: _chapters[index],
              isLaterChapter: index > 0,
              explored: selectedCount > index,
              progressText: index == 0
                  ? '已解锁 $unlocked/11 结局'
                  : '已探索 ${selectedCount.clamp(0, 11)}/11',
            ),
          ),
        ),
      ],
    );
  }

  _InteractiveProgress _interactiveProgress() {
    final raw = Hive.box('interactive_drama_progress')
        .get('tianxiadyi', defaultValue: const {});
    if (raw is! Map) return const _InteractiveProgress();
    final data = Map<String, dynamic>.from(raw);
    final endings = data['unlocked_endings'];
    return _InteractiveProgress(
      unlockedEndings: endings is List ? endings.length : 0,
      selectedCount: ((data['selected_count'] ?? 0) as num).toInt(),
      lastEndingTitle: data['last_ending_title']?.toString() ?? '',
    );
  }

  Widget _interactiveBadge(int unlocked) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentHot.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.account_tree_rounded,
            color: AppColors.accentHot, size: 12),
        const SizedBox(width: 3),
        Text(
          unlocked > 0 ? '互动·$unlocked/11' : '互动·7幕',
          style: const TextStyle(
            color: AppColors.accentHot,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ]),
    );
  }
}

class _InteractiveChapter {
  final String title;
  final String subtitle;
  final String cover;
  final String tag;

  const _InteractiveChapter({
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.tag,
  });
}

class _InteractiveChapterCard extends StatelessWidget {
  final _InteractiveChapter chapter;
  final bool isLaterChapter;
  final bool explored;
  final String progressText;

  const _InteractiveChapterCard({
    required this.chapter,
    required this.isLaterChapter,
    required this.explored,
    required this.progressText,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Modular.to.pushNamed('/interactive-drama'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 120,
          height: 170,
          child: Stack(children: [
            Positioned.fill(child: CoverImage(path: chapter.cover)),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black
                          .withValues(alpha: isLaterChapter ? .36 : .06),
                      Colors.black.withValues(alpha: .88),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .54),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  chapter.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 34,
              child: Text(
                chapter.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Positioned(
              left: 8,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: (explored
                              ? AppColors.accentMint
                              : AppColors.accentHot)
                          .withValues(alpha: .92),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      explored ? '已探索' : chapter.tag,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    progressText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentGold,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Text(
                  'HD',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            if (isLaterChapter)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .5),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(
                    Icons.route_rounded,
                    color: Colors.white,
                    size: 15,
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _InteractiveProgress {
  final int unlockedEndings;
  final int selectedCount;
  final String lastEndingTitle;

  const _InteractiveProgress({
    this.unlockedEndings = 0,
    this.selectedCount = 0,
    this.lastEndingTitle = '',
  });
}

class _EpisodeSearchSheet extends StatefulWidget {
  final List<Episode> episodes;

  const _EpisodeSearchSheet({required this.episodes});

  @override
  State<_EpisodeSearchSheet> createState() => _EpisodeSearchSheetState();
}

class _EpisodeSearchSheetState extends State<_EpisodeSearchSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = widget.episodes
        .where((e) {
          final q = _query.trim();
          return q.isEmpty ||
              e.title.contains(q) ||
              e.id.contains(q) ||
              '${e.episodeNo}'.contains(q);
        })
        .take(30)
        .toList();
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          autofocus: true,
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, color: AppColors.textTertiary),
            hintText: '搜索短剧 / 集数',
            hintStyle: const TextStyle(color: AppColors.textTertiary),
            filled: true,
            fillColor: Colors.white.withValues(alpha: .08),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: results.length,
            separatorBuilder: (_, __) =>
                const Divider(color: Colors.white10, height: 1),
            itemBuilder: (_, i) {
              final ep = results[i];
              return ListTile(
                title:
                    Text(ep.title, style: const TextStyle(color: Colors.white)),
                subtitle: Text('第${ep.episodeNo}集',
                    style: const TextStyle(color: AppColors.textSecondary)),
                trailing:
                    const Icon(Icons.play_arrow, color: AppColors.accentHot),
                onTap: () {
                  Navigator.pop(context);
                  Modular.to.pushNamed('/play/${ep.id}');
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
