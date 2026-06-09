import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// 仿腾讯视频底部：5 个 tab，中央会员位金色 V 字标
enum HomeTab { home, shorts, vip, picks, profile }

class BottomTabBar extends StatelessWidget {
  final HomeTab selected;
  final ValueChanged<HomeTab> onChanged;

  const BottomTabBar({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilterBar(
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              _tab(HomeTab.home, Icons.play_arrow_outlined,
                  Icons.play_arrow_rounded, '首页'),
              _tab(HomeTab.shorts, Icons.video_collection_outlined,
                  Icons.video_collection, '短剧'),
              _vipTab(),
              _tab(HomeTab.picks, Icons.thumb_up_alt_outlined,
                  Icons.thumb_up_alt, '好片'),
              _tab(HomeTab.profile, Icons.sentiment_satisfied_alt_outlined,
                  Icons.sentiment_satisfied_alt, '个人中心'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(HomeTab t, IconData ico, IconData icoFilled, String label) {
    final active = t == selected;
    final color = active ? AppColors.accentHot : Colors.grey;
    return Expanded(
      child: InkWell(
        onTap: () => onChanged(t),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedScale(
              scale: active ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(active ? icoFilled : ico, size: 24, color: color),
            ),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight:
                        active ? FontWeight.bold : FontWeight.normal)),
          ]),
        ),
      ),
    );
  }

  Widget _vipTab() {
    final active = selected == HomeTab.vip;
    return Expanded(
      child: InkWell(
        onTap: () => onChanged(HomeTab.vip),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                colors: [Color(0xFFFFE2A8), Color(0xFFFFB23F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(rect),
              child: const Text('V3',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.0,
                      letterSpacing: -1)),
            ),
            const SizedBox(height: 3),
            Text('会员专区',
                style: TextStyle(
                    color: active
                        ? AppColors.accentGold
                        : AppColors.accentGold.withValues(alpha: 0.75),
                    fontSize: 11,
                    fontWeight:
                        active ? FontWeight.bold : FontWeight.normal)),
          ]),
        ),
      ),
    );
  }
}

class BackdropFilterBar extends StatelessWidget {
  final Widget child;
  const BackdropFilterBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .85),
        border: Border(
          top: BorderSide(
              color: Colors.white.withValues(alpha: .07), width: .5),
        ),
      ),
      child: child,
    );
  }
}
