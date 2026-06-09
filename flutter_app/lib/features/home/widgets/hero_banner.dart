import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce/hive.dart';

import '../../../core/theme.dart';
import '../../../data/api_client.dart';
import '../../../data/models.dart';
import '../../../shared/widgets/cover_image.dart';

class HeroBanner extends StatefulWidget {
  final List<DramaGroup> groups;
  const HeroBanner({super.key, required this.groups});

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        CarouselSlider(
          options: CarouselOptions(
            height: 240,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 4),
            autoPlayCurve: Curves.easeInOut,
            enlargeCenterPage: false,
            viewportFraction: 1,
            onPageChanged: (i, _) => setState(() => _index = i),
          ),
          items: widget.groups.map(_buildCard).toList(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 16, 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(widget.groups.length, (i) {
              final active = i == _index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: active ? 18 : 6,
                height: 4,
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.white38,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(DramaGroup g) {
    final ep = g.heroEpisode;
    return GestureDetector(
      onTap: () {
        if (ep != null) Modular.to.pushNamed('/play/${ep.id}');
      },
      child: Stack(
        children: [
          Positioned.fill(child: CoverImage(path: ep?.coverUrl)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: .55),
                    Colors.black.withValues(alpha: .92),
                  ],
                  stops: const [0.2, 0.6, 1.0],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 6,
                  children: [
                    ...g.genres
                        .take(3)
                        .map((t) => _chip(t, AppColors.accentGold)),
                    if (g.isOngoing) _ongoingDot(),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  g.dramaName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                  ),
                ),
                const SizedBox(height: 6),
                Text(g.tagline,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .75),
                        fontSize: 13)),
                const SizedBox(height: 4),
                Text('共 ${g.totalCount} 集',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .5),
                        fontSize: 11)),
                const SizedBox(height: 12),
                Row(children: [
                  _cta(
                    icon: Icons.play_arrow_rounded,
                    text: '立即观看',
                    bg: Colors.white,
                    fg: Colors.black,
                    onTap: () {
                      if (ep != null) Modular.to.pushNamed('/play/${ep.id}');
                    },
                  ),
                  const SizedBox(width: 10),
                  _cta(
                    icon: Icons.add,
                    text: '加入追剧',
                    bg: Colors.white24,
                    fg: Colors.white,
                    onTap: () => _followDrama(g),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(t,
            style:
                TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)),
      );

  Widget _ongoingDot() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 2.5, backgroundColor: Colors.green),
          SizedBox(width: 3),
          Text('续更中',
              style: TextStyle(
                  color: Colors.green,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ]),
      );

  Widget _cta({
    required IconData icon,
    required String text,
    required Color bg,
    required Color fg,
    VoidCallback? onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(40)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 4),
            Text(text,
                style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
          ]),
        ),
      );

  Future<void> _followDrama(DramaGroup group) async {
    final ep = group.heroEpisode;
    if (ep == null) return;
    await Hive.box('favorites').put(ep.id, {
      'id': ep.id,
      'drama_id': ep.dramaId,
      'drama_name': group.dramaName,
      'title': ep.title,
      'episode_no': ep.episodeNo,
      'cover_url': ep.coverUrl,
      'video_url': ep.videoUrl,
      'duration': ep.duration,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已加入追剧：${group.dramaName}')),
    );
    Modular.get<ApiClient>()
        .saveEpisodeAction(
          episodeId: ep.id,
          action: 'favorite',
          active: true,
        )
        .catchError((_) {});
  }
}
