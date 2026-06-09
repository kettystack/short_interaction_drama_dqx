import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models.dart';

class BoostPackOverlay extends StatelessWidget {
  final AigcBoostPoint point;
  final VoidCallback onPlay;
  final VoidCallback onDismiss;

  const BoostPackOverlay({
    super.key,
    required this.point,
    required this.onPlay,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final seconds =
        point.duration > 0 ? '${point.duration.toStringAsFixed(0)}s' : '短片';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.accentGold.withValues(alpha: .56),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentHot.withValues(alpha: .28),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RocketBadge(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${point.title} x1',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: '跳过',
                          onPressed: onDismiss,
                          icon: const Icon(Icons.close, size: 18),
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                    Text(
                      '即梦AI生成 · $seconds · 播完回正片',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.accentGold,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (point.prompt.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        point.prompt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.28,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onPlay,
                            icon: const Icon(Icons.flash_on, size: 18),
                            label: const Text('一点即燃'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accentHot,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          point.qualityLabel,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RocketBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accentHot.withValues(alpha: .20),
              border: Border.all(color: AppColors.accentHot),
            ),
            child: const SizedBox.expand(),
          ),
          Transform.rotate(
            angle: -.48,
            child: const Icon(
              Icons.rocket_launch,
              color: AppColors.accentGold,
              size: 30,
            ),
          ),
          Positioned(
            right: 6,
            top: 8,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
