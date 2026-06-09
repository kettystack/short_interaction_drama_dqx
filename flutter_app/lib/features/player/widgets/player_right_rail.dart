import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/utils/format.dart';

class PlayerRightRail extends StatelessWidget {
  final VoidCallback onLike;
  final VoidCallback onDanmaku;
  final VoidCallback onFavorite;
  final VoidCallback onAi;
  final VoidCallback onAigcBoost;
  final VoidCallback onHighlights;
  final bool favoriteActive;
  final bool likeActive;
  final bool danmakuEnabled;
  final bool aigcGenerating;
  final bool insertedClipActive;
  final int likeCount;
  final int danmakuCount;

  const PlayerRightRail({
    super.key,
    required this.onLike,
    required this.onDanmaku,
    required this.onFavorite,
    required this.onAi,
    required this.onAigcBoost,
    required this.onHighlights,
    this.favoriteActive = false,
    this.likeActive = false,
    this.danmakuEnabled = true,
    this.aigcGenerating = false,
    this.insertedClipActive = false,
    this.likeCount = 0,
    this.danmakuCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(
          likeActive ? Icons.favorite : Icons.favorite_border,
          compactCount(likeCount),
          onLike,
          accent: likeActive,
          semanticLabel:
              likeActive ? '$likeCount 人喜欢，已喜欢，再点取消' : '$likeCount 人喜欢',
        ),
        const SizedBox(height: 14),
        _btn(
          danmakuEnabled ? Icons.subtitles : Icons.subtitles_off,
          danmakuEnabled ? '弹幕' : '已关',
          onDanmaku,
        ),
        const SizedBox(height: 14),
        _btn(
          favoriteActive ? Icons.bookmark : Icons.bookmark_outline,
          favoriteActive ? '已追' : '追剧',
          onFavorite,
          accent: favoriteActive,
        ),
        const SizedBox(height: 14),
        _btn(Icons.auto_awesome, 'AI 剧情续写', onAi, accent: true),
        const SizedBox(height: 14),
        _btn(
          aigcGenerating ? Icons.hourglass_empty : Icons.bolt,
          insertedClipActive
              ? '插片中'
              : aigcGenerating
                  ? '生成中'
                  : '加速包',
          onAigcBoost,
          accent: aigcGenerating || insertedClipActive,
        ),
        const SizedBox(height: 14),
        _btn(Icons.movie_creation_outlined, '高光点', onHighlights),
      ],
    );
  }

  Widget _btn(
    IconData ico,
    String label,
    VoidCallback tap, {
    bool accent = false,
    String? semanticLabel,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: GestureDetector(
        onTap: tap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent
                  ? AppColors.accentHot.withValues(alpha: .25)
                  : Colors.white.withValues(alpha: .12),
              border: Border.all(
                color: accent
                    ? AppColors.accentHot.withValues(alpha: .7)
                    : Colors.transparent,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(ico,
                size: 22, color: accent ? AppColors.accentHot : Colors.white),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 62,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        ]),
      ),
    );
  }
}
