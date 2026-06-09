import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../shared/widgets/cover_image.dart';

/// 仿腾讯视频「好片」频道：题材筛选 + 高分卡片纵列
class PicksPage extends StatefulWidget {
  const PicksPage({super.key});

  @override
  State<PicksPage> createState() => _PicksPageState();
}

class _PicksPageState extends State<PicksPage> {
  final _api = Modular.get<ApiClient>();
  List<PickFeedItem> _items = [];
  bool _loading = true;
  int _genreIndex = 0;
  static const _genres = ['全部', '爱情', '喜剧', '古装', '合家欢', '悬疑', '犯罪', '动作'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _api.getPicksFeed(genre: _genres[_genreIndex]);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _topBar(),
          _filterRow(),
          Expanded(child: _list()),
        ]),
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 14, 4),
        child: Row(children: [
          Text(_today(),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
          const Spacer(),
          const Icon(Icons.search, color: Colors.white, size: 22),
          const SizedBox(width: 16),
          const Icon(Icons.filter_alt_outlined,
              color: Colors.white, size: 22),
        ]),
      );

  Widget _filterRow() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        child: Row(children: [
          const Text('题材',
              style: TextStyle(color: Colors.white, fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _genres.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) {
                  final active = i == _genreIndex;
                  return GestureDetector(
                    onTap: () {
                      if (_genreIndex == i) return;
                      setState(() => _genreIndex = i);
                      _load();
                    },
                    child: Center(
                      child: Text(_genres[i],
                          style: TextStyle(
                              color: active ? Colors.white : Colors.white60,
                              fontSize: 14,
                              fontWeight: active
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                    ),
                  );
                },
              ),
            ),
          ),
          const Icon(Icons.grid_view_rounded,
              color: Colors.white70, size: 18),
        ]),
      );

  Widget _list() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accentHot));
    }
    if (_items.isEmpty) {
      return const Center(
          child: Text('暂无内容', style: TextStyle(color: Colors.white60)));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 110),
      itemCount: _items.length,
      separatorBuilder: (_, __) =>
          Divider(color: Colors.white.withValues(alpha: 0.04), height: 24),
      itemBuilder: (_, i) => _PickCard(item: _items[i]),
    );
  }

  String _today() {
    final now = DateTime.now();
    return '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

class _PickCard extends StatelessWidget {
  final PickFeedItem item;
  const _PickCard({required this.item});

  Episode get episode => item.episode;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Modular.to.pushNamed('/play/${episode.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(children: [
              CoverImage(
                path: episode.coverUrl,
                width: 110,
                height: 150,
              ),
              const Positioned(
                top: 6, right: 6,
                child: _VipBadge(),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(episode.title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.emoji_events,
                          color: AppColors.accentGold, size: 14),
                      const SizedBox(width: 2),
                      Text('${item.score.toStringAsFixed(1)}分',
                          style: const TextStyle(
                              color: AppColors.accentGold,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(3)),
                        child: Row(children: [
                          Text(
                              item.tags.isEmpty
                                  ? '短剧 · 互动'
                                  : item.tags.join(' · '),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11)),
                          const Icon(Icons.chevron_right,
                              color: Colors.white, size: 12),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                        '2026 中国 · 第${episode.episodeNo}集 · 时长${(episode.duration / 60).toStringAsFixed(1)}分钟',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 8),
                    Text('“ ${item.reason.isEmpty ? 'AI 互动高能短剧' : item.reason} ”',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.playlist_add, size: 14, color: Colors.white),
                SizedBox(width: 2),
                Text('追',
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _VipBadge extends StatelessWidget {
  const _VipBadge();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFFFD27A), Color(0xFFFFB23F)]),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Text('VIP',
            style: TextStyle(
                color: Color(0xFF2C1B0E),
                fontSize: 10,
                fontWeight: FontWeight.w900)),
      );
}
