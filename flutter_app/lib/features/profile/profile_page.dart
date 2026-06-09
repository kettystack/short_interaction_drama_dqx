import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce/hive.dart';

import '../../core/theme.dart';
import '../../core/user_session.dart';
import '../../data/models.dart';
import '../../shared/widgets/glass_card.dart';

class ProfilePage extends StatelessWidget {
  final List<DramaGroup> groups;

  const ProfilePage({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    final favoriteCount = Hive.box('favorites').length;
    final progressBox = Hive.box('progress');
    final watchedCount = progressBox.values.where((v) {
      return v is Map && ((v['seconds'] ?? 0) as num) > 10;
    }).length;
    final totalEpisodes =
        groups.fold<int>(0, (sum, g) => sum + g.episodes.length);
    final historyRaw =
        Hive.box('interaction_history').get('items', defaultValue: const []);
    final history = historyRaw is List
        ? historyRaw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : <Map<String, dynamic>>[];
    final pendingRaw =
        Hive.box('interaction_queue').get('items', defaultValue: const []);
    final pendingCount = pendingRaw is List ? pendingRaw.length : 0;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
        children: [
          Row(children: [
            Container(
              width: 54,
              height: 54,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, gradient: AppColors.ctaGradient),
              child: const Icon(Icons.person, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('本地观众',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(UserSession.userId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary)),
                  ]),
            ),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _MetricCard(label: '已追', value: '$favoriteCount')),
            const SizedBox(width: 10),
            Expanded(child: _MetricCard(label: '看过', value: '$watchedCount')),
            const SizedBox(width: 10),
            Expanded(child: _MetricCard(label: '剧集', value: '$totalEpisodes')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: _MetricCard(label: '互动', value: '${history.length}')),
            const SizedBox(width: 10),
            Expanded(child: _MetricCard(label: '待同步', value: '$pendingCount')),
          ]),
          const SizedBox(height: 18),
          GlassCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('开发与运营',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _CapabilityRow(
                icon: Icons.admin_panel_settings_outlined,
                text: '运营后台',
                onTap: () => Modular.to.pushNamed('/admin'),
              ),
              _CapabilityRow(
                icon: Icons.fact_check_outlined,
                text: '高光评测 / AIGC 任务',
                onTap: () => Modular.to.pushNamed('/admin'),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          if (history.isNotEmpty)
            GlassCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('我的互动画像',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(_actionInsight(history),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 14),
                    _InteractionBarChart(
                      data: _aggregateByAction(history),
                    ),
                  ]),
            ),
          const SizedBox(height: 14),
          GlassCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('互动记录',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (history.isEmpty) ...const [
                _CapabilityRow(icon: Icons.flash_on, text: '高光点互动'),
                _CapabilityRow(icon: Icons.alt_route, text: '剧情分支'),
                _CapabilityRow(icon: Icons.auto_awesome, text: 'AI 续写'),
                _CapabilityRow(icon: Icons.subtitles, text: '弹幕'),
              ] else
                ...history.take(6).map((item) => _CapabilityRow(
                      icon: _iconForAction(item['action']?.toString()),
                      text:
                          '${item['action'] ?? '互动'} · ${item['episode_id'] ?? ''}',
                    )),
            ]),
          ),
        ],
      ),
    );
  }

  IconData _iconForAction(String? action) {
    if (action == null) return Icons.bolt;
    if (action.contains('branch')) return Icons.alt_route;
    if (action.contains('ai_story')) return Icons.auto_awesome;
    if (action.contains('鹅叫')) return Icons.favorite;
    return Icons.flash_on;
  }

  /// 把互动历史按 action 聚合成 (label -> count)
  Map<String, int> _aggregateByAction(List<Map<String, dynamic>> history) {
    final Map<String, int> map = {};
    for (final item in history) {
      final raw = item['action']?.toString() ?? '互动';
      final label = _normalizeAction(raw);
      map[label] = (map[label] ?? 0) + 1;
    }
    // 取 Top 6
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {for (final e in sorted.take(6)) e.key: e.value};
  }

  String _normalizeAction(String action) {
    if (action.contains('branch')) return '剧情分支';
    if (action.contains('ai_story_like')) return 'AI 点赞';
    if (action.contains('ai_story_comment')) return 'AI 评论';
    if (action.contains('鹅叫')) return '笑出鹅叫';
    if (action.contains('撒花')) return '完结撒花';
    if (action.contains('护主角')) return '护主角';
    if (action.contains('看反杀')) return '看反杀';
    return action.length > 6 ? '${action.substring(0, 6)}…' : action;
  }

  String _actionInsight(List<Map<String, dynamic>> history) {
    final agg = _aggregateByAction(history);
    if (agg.isEmpty) return '尚无互动';
    final top = agg.entries.first;
    final total = history.length;
    return '共 $total 次互动 · 最爱「${top.key}」(${top.value} 次)';
  }
}

class _InteractionBarChart extends StatelessWidget {
  final Map<String, int> data;
  const _InteractionBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    final maxVal = data.values.reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: data.entries.map((e) {
        final ratio = (e.value / maxVal).clamp(0.05, 1.0);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(
              width: 78,
              child: Text(e.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ),
            Expanded(
              child: Stack(children: [
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      gradient: AppColors.ctaGradient,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 28,
              child: Text('${e.value}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ]),
        );
      }).toList(),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(label,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ]),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  const _CapabilityRow({
    required this.icon,
    required this.text,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Icon(icon, color: AppColors.accentGold, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right,
                color: AppColors.textTertiary, size: 18),
        ]),
      ),
    );
  }
}
