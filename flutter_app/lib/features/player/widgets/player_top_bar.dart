import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import '../../../core/theme.dart';

class PlayerTopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool danmakuVisible;
  final VoidCallback? onToggleDanmaku;
  final VoidCallback? onMore;

  const PlayerTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.danmakuVisible = true,
    this.onToggleDanmaku,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.topScrim),
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 18),
          onPressed: () => Modular.to.pop(),
        ),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            if (subtitle != null)
              Text(subtitle!,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
          ]),
        ),
        IconButton(
          tooltip: danmakuVisible ? '隐藏弹幕' : '显示弹幕',
          icon: Icon(
            danmakuVisible
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: Colors.white,
            size: 18,
          ),
          onPressed: onToggleDanmaku,
        ),
        IconButton(
          icon: const Icon(Icons.more_horiz, color: Colors.white),
          onPressed: onMore,
        ),
      ]),
    );
  }
}
