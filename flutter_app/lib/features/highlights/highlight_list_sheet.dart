import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../shared/utils/format.dart';

class HighlightListSheet extends StatelessWidget {
  final List<Highlight> highlights;
  final ValueChanged<Highlight> onPick;

  const HighlightListSheet({
    super.key,
    required this.highlights,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .65,
      maxChildSize: .9,
      minChildSize: .35,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.bgPanel,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            const Text('高光时刻',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: highlights.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: Colors.white10, height: 1),
                itemBuilder: (_, i) {
                  final h = highlights[i];
                  return ListTile(
                    onTap: () {
                      Navigator.pop(context);
                      onPick(h);
                    },
                    leading: Container(
                      width: 6,
                      decoration: BoxDecoration(
                        color: AppColors.accentGold,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    title: Text(h.summary,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                        '${h.type} · ${formatDuration(Duration(seconds: h.tsStart.toInt()))}',
                        style: const TextStyle(color: AppColors.textSecondary)),
                    trailing: const Icon(Icons.play_arrow,
                        color: AppColors.accentHot),
                  );
                },
              ),
            ),
          ]),
        );
      },
    );
  }
}
