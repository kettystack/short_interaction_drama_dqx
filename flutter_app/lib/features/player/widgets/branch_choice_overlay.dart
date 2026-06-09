import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models.dart';

class BranchChoiceOverlay extends StatelessWidget {
  final BranchFork fork;
  final ValueChanged<BranchOption> onPick;
  final VoidCallback onSkip;

  const BranchChoiceOverlay({
    super.key,
    required this.fork,
    required this.onPick,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.alt_route, color: AppColors.accentMint, size: 36),
            const SizedBox(height: 12),
            Text('剧情分岔',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .85),
                  fontSize: 12,
                  letterSpacing: 2,
                )),
            const SizedBox(height: 6),
            Text(fork.question,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 22),
            ...fork.options.map((o) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.white.withValues(alpha: .08),
                        side: BorderSide(
                            color: AppColors.accentMint.withValues(alpha: .5)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => onPick(o),
                      child: Column(children: [
                        Text(o.label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                        if (o.description.isNotEmpty)
                          Text(o.description,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12)),
                      ]),
                    ),
                  ),
                )),
            const SizedBox(height: 6),
            TextButton(
              onPressed: onSkip,
              child: const Text('跳过本次抉择',
                  style: TextStyle(color: AppColors.textTertiary)),
            ),
          ],
        ),
      ),
    );
  }
}
