import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models.dart';
import '../../../shared/widgets/cover_image.dart';

class EpisodePickerSheet extends StatelessWidget {
  final List<Episode> episodes;
  final String currentId;
  final ValueChanged<Episode> onPick;

  const EpisodePickerSheet({
    super.key,
    required this.episodes,
    required this.currentId,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .72,
      minChildSize: .38,
      maxChildSize: .92,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bgPanel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(children: [
          const SizedBox(height: 8),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('选集',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          Expanded(
            child: GridView.builder(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 10,
                childAspectRatio: .72,
              ),
              itemCount: episodes.length,
              itemBuilder: (_, i) {
                final ep = episodes[i];
                final active = ep.id == currentId;
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    onPick(ep);
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: active ? AppColors.accentHot : Colors.white12,
                          width: active ? 2 : 1),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(children: [
                        Positioned.fill(child: CoverImage(path: ep.coverUrl)),
                        const Positioned.fill(
                            child: DecoratedBox(
                                decoration: BoxDecoration(
                                    gradient: AppColors.posterScrim))),
                        Positioned(
                            left: 8,
                            right: 8,
                            bottom: 8,
                            child: Text('第${ep.episodeNo}集',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold))),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
