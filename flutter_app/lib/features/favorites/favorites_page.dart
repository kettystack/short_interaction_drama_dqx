import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce/hive.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../shared/widgets/cover_image.dart';

class FavoritesPage extends StatefulWidget {
  final List<DramaGroup> groups;

  const FavoritesPage({super.key, required this.groups});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  @override
  Widget build(BuildContext context) {
    final box = Hive.box('favorites');
    final favoriteIds = box.keys.map((e) => e.toString()).toList();
    final knownEpisodes = {
      for (final episode in widget.groups.expand((g) => g.episodes))
        episode.id: episode,
    };
    final episodes = favoriteIds
        .map((id) => knownEpisodes[id] ?? _episodeFromFavorite(id, box.get(id)))
        .whereType<Episode>()
        .toList();
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header(episodes.length)),
          if (episodes.isEmpty)
            const SliverFillRemaining(
                hasScrollBody: false, child: _EmptyFavorites())
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 10,
                  childAspectRatio: .68,
                ),
                itemCount: episodes.length,
                itemBuilder: (_, i) => _FavoriteTile(
                  episode: episodes[i],
                  onRemove: () async {
                    await Hive.box('favorites').delete(episodes[i].id);
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(int count) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Row(children: [
          const Icon(Icons.favorite, color: AppColors.accentHot),
          const SizedBox(width: 8),
          const Text('追剧',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
          const Spacer(),
          Text('$count 部',
              style: const TextStyle(color: AppColors.textSecondary)),
        ]),
      );

  Episode? _episodeFromFavorite(String id, Object? raw) {
    if (raw is! Map) return null;
    return Episode(
      id: raw['id']?.toString() ?? id,
      dramaId: raw['drama_id']?.toString() ?? '',
      title: raw['title']?.toString() ?? '已追短剧',
      episodeNo: (raw['episode_no'] as num?)?.toInt() ?? 1,
      duration: (raw['duration'] as num?)?.toDouble() ?? 0,
      videoUrl: raw['video_url']?.toString() ?? '',
      coverUrl: raw['cover_url']?.toString(),
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  final Episode episode;
  final VoidCallback onRemove;

  const _FavoriteTile({required this.episode, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Modular.to.pushNamed('/play/${episode.id}'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(children: [
          Positioned.fill(child: CoverImage(path: episode.coverUrl)),
          const Positioned.fill(
              child: DecoratedBox(
                  decoration: BoxDecoration(gradient: AppColors.posterScrim))),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Text(episode.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close, color: Colors.white, size: 16),
              style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  minimumSize: const Size(28, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          ),
        ]),
      ),
    );
  }
}

class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.bookmark_add_outlined,
            color: AppColors.textSecondary, size: 46),
        SizedBox(height: 12),
        Text('还没有追剧',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}
