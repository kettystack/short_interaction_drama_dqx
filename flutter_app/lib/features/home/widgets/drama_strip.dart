import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import '../../../core/theme.dart';
import '../../../data/models.dart';
import '../../../shared/widgets/cover_image.dart';

class DramaStrip extends StatelessWidget {
  final DramaGroup group;
  const DramaStrip({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  gradient: AppColors.ctaGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(group.dramaName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              _statusBadge(),
              const Spacer(),
              const Text('全部',
                  style:
                      TextStyle(color: AppColors.textTertiary, fontSize: 12)),
              const Icon(Icons.chevron_right,
                  color: AppColors.textTertiary, size: 16),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Text(group.genres.join(' · '),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 158,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: group.episodes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _EpisodeThumb(episode: group.episodes[i]),
          ),
        ),
      ],
    );
  }

  Widget _statusBadge() {
    final color = group.isOngoing ? Colors.green : AppColors.accentGold;
    final text =
        group.isOngoing ? '续更·${group.totalCount}集' : '全${group.totalCount}集';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (group.isOngoing) ...[
          CircleAvatar(radius: 2.5, backgroundColor: color),
          const SizedBox(width: 3),
        ],
        Text(text,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class _EpisodeThumb extends StatelessWidget {
  final Episode episode;
  const _EpisodeThumb({required this.episode});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Modular.to.pushNamed('/play/${episode.id}'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 112,
          height: 158,
          child: Stack(children: [
            Positioned.fill(child: CoverImage(path: episode.coverUrl)),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: .8)
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 7,
              top: 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('第${episode.episodeNo}集',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            if (episode.hlsReady)
              Positioned(
                right: 7,
                bottom: 7,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AppColors.accentGold,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('HD',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 9,
                          fontWeight: FontWeight.w900)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
