import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models.dart';
import '../controllers/interaction_controller.dart';

class AiBranchSheet extends StatefulWidget {
  final InteractionController controller;
  final String defaultContext;
  final String? initialChoice;
  final double currentTime;

  const AiBranchSheet({
    super.key,
    required this.controller,
    required this.defaultContext,
    this.initialChoice,
    required this.currentTime,
  });

  @override
  State<AiBranchSheet> createState() => _AiBranchSheetState();
}

class _AiBranchSheetState extends State<AiBranchSheet> {
  late final TextEditingController _contextController =
      TextEditingController(text: widget.defaultContext);
  final _commentController = TextEditingController();
  late String? _choice = widget.initialChoice;
  late String _styleCode;
  int _lastRenderedTurnCount = 0;

  @override
  void initState() {
    super.initState();
    _styleCode = widget.controller.storyStyleCode;
    final initialChoice = widget.initialChoice?.trim();
    if (initialChoice != null && initialChoice.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _continueFromInitialChoice(initialChoice);
      });
    }
  }

  @override
  void dispose() {
    _contextController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .78,
      minChildSize: .5,
      maxChildSize: .94,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bgPanel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (_, __) {
            final c = widget.controller;
            final storyTurns = c.storyTurns;
            final hasStory = storyTurns.isNotEmpty || c.generatedStory != null;
            final renderedTurnCount =
                storyTurns.isNotEmpty ? storyTurns.length : (hasStory ? 1 : 0);
            _scrollToLatestTurn(scrollController, renderedTurnCount);
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 26),
              children: [
                Center(
                    child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                const Row(children: [
                  Icon(Icons.auto_awesome, color: AppColors.accentGold),
                  SizedBox(width: 8),
                  Text('AI 剧情续写',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 14),
                TextField(
                  controller: _contextController,
                  minLines: 4,
                  maxLines: 7,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '输入当前剧情或想看的方向',
                    hintStyle: const TextStyle(color: AppColors.textTertiary),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: .08),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['强势反杀', '甜蜜撒糖', '悬疑反转', '搞笑失控']
                      .map((item) => ChoiceChip(
                            label: Text(item),
                            selected: _choice == item,
                            onSelected: (_) => setState(() => _choice = item),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    ('cinematic_literary', '文艺电影感'),
                    ('suspense_noir', '克制悬疑'),
                    ('short_drama_punchy', '短剧高爽'),
                    ('classical_chapter', '古风章回'),
                  ]
                      .map((item) => ChoiceChip(
                            label: Text(item.$2),
                            selected: _styleCode == item.$1,
                            onSelected: (_) =>
                                setState(() => _styleCode = item.$1),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: c.isGeneratingStory
                      ? null
                      : () {
                          final value = _contextController.text.trim();
                          if (c.storyThread == null) {
                            c.generateStory(
                              context: value,
                              choice: _choice,
                              tsInVideo: widget.currentTime,
                              styleCode: _styleCode,
                            );
                          } else {
                            c.sendStoryMessage(
                              value,
                              widget.currentTime,
                              styleCode: _styleCode,
                            );
                          }
                        },
                  icon: c.isGeneratingStory
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bolt),
                  label: Text(c.isGeneratingStory
                      ? '生成中'
                      : c.storyThread == null
                          ? '生成续写'
                          : '发送指令'),
                ),
                if (c.storyError != null) ...[
                  const SizedBox(height: 12),
                  Text(c.storyError!,
                      style: const TextStyle(color: AppColors.accentHot)),
                ],
                if (hasStory) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Icon(Icons.forum_outlined,
                          color: AppColors.accentGold, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '续写对话',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .78),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (storyTurns.length > 1)
                        Text(
                          '${storyTurns.length} 条记录',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .45),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (storyTurns.isNotEmpty)
                    ...storyTurns.map((turn) => _StoryTurnBubble(turn: turn))
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.accentGold.withValues(alpha: .35)),
                      ),
                      child: Text(c.generatedStory!.text,
                          style: const TextStyle(
                              color: Colors.white, height: 1.55)),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: c.latestStoryChoices.isNotEmpty
                        ? c.latestStoryChoices
                            .map((choice) => _StoryChoiceChip(
                                  choice: choice,
                                  onPressed: () {
                                    setState(() => _choice = choice.label);
                                    c.chooseStoryChoice(
                                      choice,
                                      widget.currentTime,
                                      styleCode: _styleCode,
                                    );
                                  },
                                ))
                            .toList()
                        : c.generatedStory!.choices
                            .map((choice) => ActionChip(
                                  avatar: const Icon(Icons.alt_route, size: 16),
                                  label: Text(choice),
                                  onPressed: () {
                                    setState(() => _choice = choice);
                                    c.generateStory(
                                      context: c.generatedStory!.text,
                                      choice: choice,
                                      tsInVideo: widget.currentTime,
                                      styleCode: _styleCode,
                                    );
                                  },
                                ))
                            .toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    FilledButton.tonalIcon(
                      onPressed: () => c.likeGeneratedStory(widget.currentTime),
                      icon: const Icon(Icons.thumb_up_alt_outlined, size: 16),
                      label: Text(
                        '点赞 ${c.storyLikes + (c.remoteStoryFeedback?.likes ?? 0)}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '生成内容可继续互动',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: .6),
                          fontSize: 12),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: '评论这个续写',
                          hintStyle:
                              const TextStyle(color: AppColors.textTertiary),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: .08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _submitComment(c),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: () => _submitComment(c),
                      icon: const Icon(Icons.send),
                    ),
                  ]),
                  if (c.storyComments.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ...c.storyComments.take(3).map(
                          (comment) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(children: [
                              const Icon(Icons.chat_bubble_outline,
                                  color: AppColors.textTertiary, size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(comment,
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12)),
                              ),
                            ]),
                          ),
                        ),
                  ],
                  if ((c.remoteStoryFeedback?.comments ?? const [])
                      .isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Row(children: [
                      const Icon(Icons.groups_2_outlined,
                          color: AppColors.accentMint, size: 14),
                      const SizedBox(width: 6),
                      Text('其他观众也在说',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: .7),
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 6),
                    ...c.remoteStoryFeedback!.comments.take(5).map(
                          (cm) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.accentMint
                                        .withValues(alpha: .25),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    cm.userId.isNotEmpty
                                        ? cm.userId
                                            .substring(0, 1)
                                            .toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(cm.text,
                                      style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  void _continueFromInitialChoice(String initialChoice) {
    final controller = widget.controller;
    final thread = controller.storyThread;
    if (thread == null && controller.generatedStory == null) {
      controller.generateStory(
        context: _contextController.text.trim(),
        choice: initialChoice,
        tsInVideo: widget.currentTime,
        styleCode: _styleCode,
      );
      return;
    }
    if (thread != null && !thread.branchPath.contains(initialChoice)) {
      controller.sendStoryMessage(
        initialChoice,
        widget.currentTime,
        styleCode: _styleCode,
      );
    }
  }

  void _scrollToLatestTurn(ScrollController controller, int renderedTurnCount) {
    if (renderedTurnCount == 0 || renderedTurnCount == _lastRenderedTurnCount) {
      return;
    }
    _lastRenderedTurnCount = renderedTurnCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      controller.animateTo(
        controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _submitComment(InteractionController controller) {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    controller.commentGeneratedStory(text, widget.currentTime);
    _commentController.clear();
  }
}

class _StoryTurnBubble extends StatelessWidget {
  final StoryTurn turn;
  const _StoryTurnBubble({required this.turn});

  @override
  Widget build(BuildContext context) {
    final isUser = turn.isUserChoice;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 680),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.accentHot.withValues(alpha: .16)
              : Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
          border: Border.all(
            color: isUser
                ? AppColors.accentHot.withValues(alpha: .35)
                : AppColors.accentGold.withValues(alpha: .28),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              isUser ? '你的选择' : 'AI 续写',
              style: TextStyle(
                color: isUser ? AppColors.accentHot : AppColors.accentGold,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              turn.text,
              style: const TextStyle(color: Colors.white, height: 1.55),
            ),
            if (!isUser && turn.evidenceEventIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '引用剧情证据：${turn.evidenceEventIds.take(3).join(' / ')}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .42),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StoryChoiceChip extends StatelessWidget {
  final StoryChoice choice;
  final VoidCallback onPressed;

  const _StoryChoiceChip({
    required this.choice,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (choice.intent.trim().isNotEmpty) choice.intent.trim(),
      if (choice.tone.trim().isNotEmpty) choice.tone.trim(),
    ].join(' · ');
    final preview = choice.preview.trim();
    final tooltip = [
      choice.label,
      if (meta.isNotEmpty) meta,
      if (preview.isNotEmpty) preview,
    ].join('\n');

    return Tooltip(
      message: tooltip,
      child: ActionChip(
        avatar: const Icon(Icons.alt_route, size: 16),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(choice.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (preview.isNotEmpty)
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .56),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}
