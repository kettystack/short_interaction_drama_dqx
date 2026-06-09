import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/models.dart';
import 'animated_emoji_glyph.dart';
import 'lottie_goose_gift_overlay.dart';

/// 高光情绪的统一视觉语言（emoji / 动词 / 配色），供紧凑胶囊与他人互动层共用。
class HighlightEmotionStyle {
  final String title; // 笑出鹅叫
  final String verb; // 笑（用于「N 人正笑」）
  final String emoji; // 主表情 🦢
  final List<String> reactions; // 上浮的他人互动表情池
  final List<String> words; // 上浮情绪词：哈 / 爽 / 甜 / 破防
  final String banner;
  final String primaryAction;
  final String primaryEvent;
  final String leftAction;
  final String leftEvent;
  final String rightAction;
  final String rightEvent;
  final String giftText;
  final List<String> giftTokens;
  final String? giftActorAsset;
  final bool useGooseActor;
  final bool useVoteActions;
  final Color primary;
  final Color secondary;

  const HighlightEmotionStyle({
    required this.title,
    required this.verb,
    required this.emoji,
    required this.reactions,
    required this.words,
    required this.banner,
    required this.primaryAction,
    required this.primaryEvent,
    required this.leftAction,
    required this.leftEvent,
    required this.rightAction,
    required this.rightEvent,
    required this.giftText,
    required this.giftTokens,
    this.giftActorAsset,
    this.useGooseActor = false,
    this.useVoteActions = false,
    required this.primary,
    required this.secondary,
  });

  static HighlightEmotionStyle of(Highlight h) {
    final key = '${h.type}${h.interaction}${h.summary}';
    final typeKey = '${h.type}${h.summary}';
    if (key.contains('笑') ||
      key.contains('搞笑') ||
      key.contains('包袱') ||
      key.contains('年龄反差')) {
      return const HighlightEmotionStyle(
        title: '笑出鹅叫',
        verb: '笑',
        emoji: '🦢',
        reactions: ['🦢', '😂', '🤣', '😆'],
        words: ['哈', '笑', '鹅', '离谱'],
        banner: '开心开心，有人笑出鹅叫!',
        primaryAction: '鹅叫',
        primaryEvent: '笑出鹅叫',
        leftAction: '笑死',
        leftEvent: '笑',
        rightAction: '离谱',
        rightEvent: '离谱',
        giftText: '鹅叫暴击',
        giftTokens: ['🪙', '👏', '✨', '⚡'],
        giftActorAsset: 'assets/lottie/highlight/goose_talk.json',
        useGooseActor: true,
        primary: Color(0xFFFFD24A),
        secondary: Color(0xFF66E1FF),
      );
    }
    if (typeKey.contains('爽') ||
        typeKey.contains('打脸') ||
        typeKey.contains('反杀') ||
      typeKey.contains('解气') ||
      typeKey.contains('护短') ||
      typeKey.contains('撑腰')) {
      return const HighlightEmotionStyle(
        title: '爽到了',
        verb: '爽',
        emoji: '😎',
        reactions: ['😎', '🔥', '👊', '💥'],
        words: ['爽', '打脸', '解气', '反杀'],
        banner: '好爽，有人爽到了!',
        primaryAction: '爽到',
        primaryEvent: '爽',
        leftAction: '打脸',
        leftEvent: '打脸',
        rightAction: '反杀',
        rightEvent: '反杀',
        giftText: '燃爆入场',
        giftTokens: ['🪙', '🔥', '⚡', '👊'],
        giftActorAsset: 'assets/lottie/highlight/gift_power_flare.json',
        useVoteActions: true,
        primary: Color(0xFFFF6B35),
        secondary: Color(0xFFFFD166),
      );
    }
    if (key.contains('破防') || key.contains('心疼')) {
      return const HighlightEmotionStyle(
        title: '破防了',
        verb: '破防',
        emoji: '🥺',
        reactions: ['🥺', '😭', '💧', '💔'],
        words: ['破防', '心疼', '绷不住', '疼'],
        banner: '破防了，有人被戳中了',
        primaryAction: '破防',
        primaryEvent: '破防',
        leftAction: '心疼',
        leftEvent: '心疼',
        rightAction: '绷不住',
        rightEvent: '绷不住',
        giftText: '破防暴击',
        giftTokens: ['💧', '💔', '🪙', '✨'],
        giftActorAsset: 'assets/lottie/highlight/gift_tear_halo.json',
        primary: Color(0xFF8AB6FF),
        secondary: Color(0xFFFF9EC7),
      );
    }
    if (key.contains('泪') || key.contains('哭') || key.contains('虐')) {
      return const HighlightEmotionStyle(
        title: '泪目了',
        verb: '哭',
        emoji: '😭',
        reactions: ['😭', '💧', '🥺', '💔'],
        words: ['哭', '虐', '心疼', '破防'],
        banner: '破防了，有人一起泪目',
        primaryAction: '破防',
        primaryEvent: '哭',
        leftAction: '心疼',
        leftEvent: '心疼',
        rightAction: '抱抱',
        rightEvent: '抱抱',
        giftText: '泪目暴击',
        giftTokens: ['💧', '🥺', '🪙', '✨'],
        giftActorAsset: 'assets/lottie/highlight/gift_tear_halo.json',
        primary: Color(0xFF7EA2FF),
        secondary: Color(0xFFB5F2FF),
      );
    }
    if (key.contains('反转') ||
        key.contains('转折') ||
        key.contains('悬念') ||
        key.contains('震惊') ||
        key.contains('炸裂')) {
      return const HighlightEmotionStyle(
        title: '反转了',
        verb: '惊',
        emoji: '😱',
        reactions: ['😱', '⚡', '❗', '🤯'],
        words: ['反', '转', '震惊', '炸裂'],
        banner: '高能反转，有人被震到了!',
        primaryAction: '震惊',
        primaryEvent: '震惊',
        leftAction: '细思',
        leftEvent: '细思',
        rightAction: '炸裂',
        rightEvent: '炸裂',
        giftText: '反转警报',
        giftTokens: ['🪙', '❗', '⚡', '🌀'],
        giftActorAsset: 'assets/lottie/highlight/gift_shock_pulse.json',
        primary: Color(0xFF6CF1FF),
        secondary: Color(0xFF9A6BFF),
      );
    }
    if (key.contains('紧张') || key.contains('压迫') || key.contains('窒息')) {
      return const HighlightEmotionStyle(
        title: '紧张了',
        verb: '屏息',
        emoji: '😨',
        reactions: ['😨', '⚡', '⏳', '👀'],
        words: ['紧张', '压迫', '屏息', '危险'],
        banner: '气氛压住了，有人屏住呼吸',
        primaryAction: '紧张',
        primaryEvent: '紧张',
        leftAction: '危险',
        leftEvent: '危险',
        rightAction: '别停',
        rightEvent: '别停',
        giftText: '屏息预警',
        giftTokens: ['⏳', '⚡', '👀', '🪙'],
        giftActorAsset: 'assets/lottie/highlight/gift_shock_pulse.json',
        primary: Color(0xFF45E0FF),
        secondary: Color(0xFFFF4D9D),
      );
    }
    if (key.contains('甜') || key.contains('心动') || key.contains('磕')) {
      return const HighlightEmotionStyle(
        title: '好甜啊',
        verb: '甜',
        emoji: '😍',
        reactions: ['😍', '💕', '🥰', '💗'],
        words: ['甜', '磕', '心动', '上头'],
        banner: '甜到了，有人已经开始磕了',
        primaryAction: '磕到',
        primaryEvent: '磕到',
        leftAction: '心动',
        leftEvent: '心动',
        rightAction: '上头',
        rightEvent: '上头',
        giftText: '甜度拉满',
        giftTokens: ['💕', '✨', '🪙', '🥰'],
        giftActorAsset: 'assets/lottie/highlight/gift_heart_bloom.json',
        primary: Color(0xFFFF75B7),
        secondary: Color(0xFFFFC86F),
      );
    }
    if (key.contains('治愈') || key.contains('温暖')) {
      return const HighlightEmotionStyle(
        title: '被治愈了',
        verb: '暖',
        emoji: '☺️',
        reactions: ['☺️', '🌟', '🫶', '💛'],
        words: ['暖', '治愈', '安心', '戳中'],
        banner: '好暖，有人被治愈到了',
        primaryAction: '治愈',
        primaryEvent: '治愈',
        leftAction: '暖到',
        leftEvent: '暖到',
        rightAction: '安心',
        rightEvent: '安心',
        giftText: '治愈光环',
        giftTokens: ['🌟', '🫶', '🪙', '✨'],
        giftActorAsset: 'assets/lottie/highlight/gift_heal_orbit.json',
        primary: Color(0xFFFFD166),
        secondary: Color(0xFF5EE6A8),
      );
    }
    if (key.contains('离谱') || key.contains('上头') || key.contains('吐槽')) {
      return const HighlightEmotionStyle(
        title: '太上头了',
        verb: '上头',
        emoji: '🤯',
        reactions: ['🤯', '😂', '🔥', '❗'],
        words: ['离谱', '上头', '绝了', '继续'],
        banner: '上头了，有人想继续看!',
        primaryAction: '上头',
        primaryEvent: '上头',
        leftAction: '离谱',
        leftEvent: '离谱',
        rightAction: '继续',
        rightEvent: '继续',
        giftText: '上头预警',
        giftTokens: ['🔥', '❗', '🪙', '⚡'],
        giftActorAsset: 'assets/lottie/highlight/gift_power_flare.json',
        primary: Color(0xFFFF8A3D),
        secondary: Color(0xFF6CF1FF),
      );
    }
    if (key.contains('名场面') || key.contains('封神')) {
      return const HighlightEmotionStyle(
        title: '封神了',
        verb: '燃',
        emoji: '👑',
        reactions: ['👑', '🔥', '✨', '💯'],
        words: ['神', '绝', '名场面', '封神'],
        banner: '名场面来了，有人已经封神',
        primaryAction: '封神',
        primaryEvent: '封神',
        leftAction: '名场面',
        leftEvent: '名场面',
        rightAction: '绝了',
        rightEvent: '绝了',
        giftText: '封神时刻',
        giftTokens: ['👑', '✨', '🪙', '💯'],
        giftActorAsset: 'assets/lottie/highlight/gift_crown_glow.json',
        primary: Color(0xFFFFE6A3),
        secondary: Color(0xFFFFB23F),
      );
    }
    return const HighlightEmotionStyle(
      title: '燃起来',
      verb: '燃',
      emoji: '🔥',
      reactions: ['🔥', '👊', '💥', '⚡'],
      words: ['燃', '爽', '冲', '高能'],
      banner: '高能时刻，有人一起燃起来',
      primaryAction: '燃爆',
      primaryEvent: '燃',
      leftAction: '护主角',
      leftEvent: '护主角',
      rightAction: '看反杀',
      rightEvent: '看反杀',
      giftText: '高能入场',
      giftTokens: ['🔥', '⚡', '🪙', '✨'],
      giftActorAsset: 'assets/lottie/highlight/gift_power_flare.json',
      useVoteActions: true,
      primary: Color(0xFFFF5A3D),
      secondary: Color(0xFFFFB23F),
    );
  }
}

/// 顶部紧凑「人气胶囊」——取代原先占满屏的大全息卡：
/// 一个会跳动的动画表情 + 「N 人正<动词>」+ 叠加头像，体量很小，不挡剧情。
class HighlightCrowdPill extends StatelessWidget {
  final Highlight highlight;
  final int crowdCount;

  const HighlightCrowdPill({
    super.key,
    required this.highlight,
    required this.crowdCount,
  });

  @override
  Widget build(BuildContext context) {
    final style = HighlightEmotionStyle.of(highlight);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: style.primary.withValues(alpha: .55)),
        boxShadow: [
          BoxShadow(
            color: style.primary.withValues(alpha: .32),
            blurRadius: 16,
            spreadRadius: -6,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedEmojiGlyph(emoji: style.emoji, size: 20, glow: style.primary),
          const SizedBox(width: 2),
          _AvatarStack(color: style.secondary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '${style.title} 热聊中',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .96),
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  final Color color;
  const _AvatarStack({required this.color});

  @override
  Widget build(BuildContext context) {
    const palette = [
      Color(0xFFFF8A65),
      Color(0xFF4FC3F7),
      Color(0xFFBA68C8),
    ];
    return SizedBox(
      width: 34,
      height: 18,
      child: Stack(
        children: [
          for (int i = 0; i < 3; i++)
            Positioned(
              left: i * 10.0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette[i],
                  border: Border.all(color: Colors.white, width: 1.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class HighlightActionRow extends StatelessWidget {
  final Highlight highlight;
  final VoidCallback onPrimary;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  const HighlightActionRow({
    super.key,
    required this.highlight,
    required this.onPrimary,
    required this.onLeft,
    required this.onRight,
  });

  @override
  Widget build(BuildContext context) {
    final style = HighlightEmotionStyle.of(highlight);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .28),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MiniActionButton(
              icon: style.emoji,
              label: style.primaryAction,
              color: style.primary,
              onTap: onPrimary,
            ),
            const SizedBox(width: 5),
            _MiniActionButton(
              icon: style.useVoteActions ? '🛡️' : style.reactions[1],
              label: style.leftAction,
              color: style.secondary,
              onTap: onLeft,
            ),
            const SizedBox(width: 5),
            _MiniActionButton(
              icon: style.useVoteActions ? '⚔️' : style.reactions[2],
              label: style.rightAction,
              color: style.primary,
              onTap: onRight,
            ),
          ],
        ),
      ),
    );
  }
}

class CollapsibleHighlightControls extends StatefulWidget {
  final Highlight highlight;
  final int crowdCount;
  final VoidCallback onPrimary;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  const CollapsibleHighlightControls({
    super.key,
    required this.highlight,
    required this.crowdCount,
    required this.onPrimary,
    required this.onLeft,
    required this.onRight,
  });

  @override
  State<CollapsibleHighlightControls> createState() =>
      _CollapsibleHighlightControlsState();
}

class _CollapsibleHighlightControlsState
    extends State<CollapsibleHighlightControls> with TickerProviderStateMixin {
  static const _expandedHold = Duration(milliseconds: 2600);
  Timer? _collapseTimer;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _scheduleCollapse();
  }

  @override
  void didUpdateWidget(covariant CollapsibleHighlightControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlight.id != widget.highlight.id) {
      _expanded = true;
      _scheduleCollapse();
    }
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }

  void _scheduleCollapse() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(_expandedHold, () {
      if (mounted) setState(() => _expanded = false);
    });
  }

  void _expandTemporarily() {
    setState(() => _expanded = true);
    _scheduleCollapse();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 210),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _expanded ? _expandedControls() : _collapsedStatus(),
      ),
    );
  }

  Widget _expandedControls() {
    return Column(
      key: const ValueKey('expanded-highlight-controls'),
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: widget.onPrimary,
          child: HighlightCrowdPill(
            highlight: widget.highlight,
            crowdCount: widget.crowdCount,
          ),
        ),
        const SizedBox(height: 7),
        HighlightActionRow(
          highlight: widget.highlight,
          onPrimary: widget.onPrimary,
          onLeft: widget.onLeft,
          onRight: widget.onRight,
        ),
      ],
    );
  }

  Widget _collapsedStatus() {
    return GestureDetector(
      key: const ValueKey('collapsed-highlight-status'),
      onTap: _expandTemporarily,
      child: HighlightThinStatusBar(
        highlight: widget.highlight,
        crowdCount: widget.crowdCount,
      ),
    );
  }
}

class HighlightThinStatusBar extends StatelessWidget {
  final Highlight highlight;
  final int crowdCount;

  const HighlightThinStatusBar({
    super.key,
    required this.highlight,
    required this.crowdCount,
  });

  @override
  Widget build(BuildContext context) {
    final style = HighlightEmotionStyle.of(highlight);
    return Container(
      height: 25,
      constraints: const BoxConstraints(maxWidth: 188),
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .34),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: style.primary.withValues(alpha: .42)),
        boxShadow: [
          BoxShadow(
            color: style.primary.withValues(alpha: .18),
            blurRadius: 14,
            spreadRadius: -7,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedEmojiGlyph(emoji: style.emoji, size: 15, glow: style.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${style.title} · 点开互动',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 14,
            color: Colors.white.withValues(alpha: .62),
          ),
        ],
      ),
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  final String icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MiniActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .2),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: color.withValues(alpha: .45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: const TextStyle(fontSize: 13, height: 1)),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「看到其他用户的互动」——高光激活时，按人气持续从右侧上浮一串他人表情，
/// 营造同看同乐的临场感（参考原型图的飘屏互动）。
class AmbientCrowdReactions extends StatefulWidget {
  final Highlight? highlight;
  final int crowdCount;

  const AmbientCrowdReactions({
    super.key,
    required this.highlight,
    required this.crowdCount,
  });

  @override
  State<AmbientCrowdReactions> createState() => _AmbientCrowdReactionsState();
}

class _AmbientCrowdReactionsState extends State<AmbientCrowdReactions>
    with TickerProviderStateMixin {
  final List<_AmbientParticle> _particles = [];
  final _rand = math.Random();
  Timer? _spawnTimer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant AmbientCrowdReactions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlight?.id != widget.highlight?.id ||
        oldWidget.crowdCount != widget.crowdCount) {
      _syncTimer();
    }
  }

  void _syncTimer() {
    _spawnTimer?.cancel();
    if (widget.highlight == null) return;
    // 人气越高，飘得越密，但保持克制，避免主画面过闪。
    final crowd = widget.crowdCount.clamp(0, 600);
    final interval = (880 - crowd).clamp(340, 880);
    _spawnTimer =
        Timer.periodic(Duration(milliseconds: interval), (_) => _spawn());
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 90), _spawn);
    }
  }

  void _spawn() {
    if (!mounted || widget.highlight == null) return;
    final style = HighlightEmotionStyle.of(widget.highlight!);
    final isWord = _rand.nextBool();
    final c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1600 + _rand.nextInt(900)),
    );
    final p = _AmbientParticle(
      controller: c,
      token: isWord
          ? style.words[_rand.nextInt(style.words.length)]
          : style.reactions[_rand.nextInt(style.reactions.length)],
      isWord: isWord,
      color: _rand.nextBool() ? style.primary : style.secondary,
      lane: _rand.nextDouble(),
      drift: (_rand.nextDouble() - .5) * 36,
      size: 16 + _rand.nextDouble() * 8,
    );
    c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _particles.remove(p);
        c.dispose();
        if (mounted) setState(() {});
      }
    });
    _particles.add(p);
    c.forward();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _spawnTimer?.cancel();
    for (final p in _particles) {
      p.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.highlight == null && _particles.isEmpty) {
      return const SizedBox.shrink();
    }
    final highlight = widget.highlight;
    final style =
        highlight == null ? null : HighlightEmotionStyle.of(highlight);
    final crowd = widget.crowdCount > 0
        ? widget.crowdCount
        : ((highlight?.intensity ?? .5) * 240).round().clamp(18, 9999);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              if (highlight != null && style != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 2,
                  right: -18,
                  child: HighlightGiftOverlay(
                    key: ValueKey('gift-${highlight.id}-${style.giftText}'),
                    title: style.title,
                    emoji: style.emoji,
                    giftText: style.giftText,
                    giftTokens: style.giftTokens,
                    actorAsset: style.giftActorAsset,
                    useGooseActor: style.useGooseActor,
                    primary: style.primary,
                    secondary: style.secondary,
                    crowd: crowd,
                  ),
                ),
              if (highlight != null && style != null)
                const SizedBox.shrink(),
              ..._particles.map((p) {
                return AnimatedBuilder(
                  animation: p.controller,
                  builder: (context, _) {
                    final t = p.controller.value;
                    final rise = Curves.easeOut.transform(t);
                    final opacity = t < .12
                        ? t / .12
                        : (1 - (t - .12) / .88).clamp(0.0, 1.0).toDouble();
                    final wobble = math.sin(t * math.pi * 3) * 10;
                    return Positioned(
                      right: 14 + p.lane * 52 + p.drift * t + wobble,
                      bottom: 150 + rise * 300,
                      child: Opacity(
                        opacity: opacity,
                        child: _ParticleToken(particle: p, progress: rise),
                      ),
                    );
                  },
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _ParticleToken extends StatelessWidget {
  final _AmbientParticle particle;
  final double progress;

  const _ParticleToken({required this.particle, required this.progress});

  @override
  Widget build(BuildContext context) {
    if (!particle.isWord) {
      return Text(
        particle.token,
        style: TextStyle(fontSize: particle.size * (0.7 + progress * 0.5)),
      );
    }
    return Transform.rotate(
      angle: (progress - .5) * .18,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: particle.color.withValues(alpha: .22),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: particle.color.withValues(alpha: .55)),
        ),
        child: Text(
          particle.token,
          style: TextStyle(
            color: Colors.white,
            fontSize: particle.size * .68,
            height: 1,
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(color: particle.color, blurRadius: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmbientParticle {
  final AnimationController controller;
  final String token;
  final bool isWord;
  final Color color;
  final double lane;
  final double drift;
  final double size;

  _AmbientParticle({
    required this.controller,
    required this.token,
    required this.isWord,
    required this.color,
    required this.lane,
    required this.drift,
    required this.size,
  });
}
