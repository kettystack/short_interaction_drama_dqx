import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../shared/widgets/cover_image.dart';

/// 仿腾讯视频「会员专区」：金色卡片 + 权益网格
class MembershipPage extends StatefulWidget {
  const MembershipPage({super.key});

  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  final _api = Modular.get<ApiClient>();
  VipProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final profile = await _api.getVipProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.accentGold),
              )
            : profile == null
                ? _empty()
                : RefreshIndicator(
                    color: AppColors.accentGold,
                    onRefresh: _load,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 110),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(18, 12, 16, 12),
                            child: Text(
                              '会员专区',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          _vipCard(profile),
                          const SizedBox(height: 18),
                          _section('我的权益'),
                          _benefitsGrid(profile.benefits),
                          const SizedBox(height: 18),
                          _section('VIP 专享短剧'),
                          _vipDramaRow(profile.vipEpisodes),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off, color: AppColors.accentGold, size: 36),
          const SizedBox(height: 10),
          const Text(
            '会员信息加载失败',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('重试')),
        ]),
      );

  Widget _vipCard(VipProfile profile) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2C1B0E), Color(0xFF4A2E13)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.accentGold.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.accentGold.withValues(alpha: 0.2),
            child: const Icon(Icons.person, color: AppColors.accentGold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(
                      profile.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD27A), Color(0xFFFFB23F)],
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      profile.vipBadge,
                      style: const TextStyle(
                        color: Color(0xFF2C1B0E),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                  '鹅币：${profile.gooseCoins}   钻石：${profile.diamonds}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              colors: [Color(0xFFFFE2A8), Color(0xFFFFB23F)],
            ).createShader(rect),
            child: Text(
              'V${profile.vipLevel}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ]),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 16, 10),
        child: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget _benefitsGrid(List<VipBenefit> items) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.95,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final it = items[i];
          return Container(
            decoration: BoxDecoration(
              color: AppColors.bgPanel,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_iconFor(it.code), color: AppColors.accentGold, size: 26),
              const SizedBox(height: 6),
              Text(
                it.title,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          );
        },
      );

  IconData _iconFor(String code) => switch (code) {
        '4k' => Icons.hd,
        'dolby' => Icons.headphones,
        'no_ads' => Icons.bookmark_border,
        'devices' => Icons.devices,
        'ai_branch' => Icons.auto_awesome,
        'early_access' => Icons.movie_filter_outlined,
        'skin' => Icons.diamond_outlined,
        'gift' => Icons.card_giftcard,
        _ => Icons.workspace_premium,
      };

  Widget _vipDramaRow(List<Episode> episodes) => SizedBox(
        height: 158,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          scrollDirection: Axis.horizontal,
          itemCount: episodes.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final episode = episodes[i];
            return GestureDetector(
              onTap: () => Modular.to.pushNamed('/play/${episode.id}'),
              child: SizedBox(
                width: 104,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CoverImage(
                        path: episode.coverUrl,
                        width: 104,
                        height: 124,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      episode.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}