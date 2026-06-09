import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../data/branch_video_models.dart';

class PersonalizedBranchOverlay extends StatefulWidget {
  final PersonalizedBranchSession session;
  final String? selectedOptionId;
  final bool isSubmitting;
  final String? error;
  final ValueChanged<PersonalizedBranchOption> onPick;
  final ValueChanged<String> onCustomPrompt;
  final VoidCallback onSkip;

  const PersonalizedBranchOverlay({
    super.key,
    required this.session,
    required this.onPick,
    required this.onCustomPrompt,
    required this.onSkip,
    this.selectedOptionId,
    this.isSubmitting = false,
    this.error,
  });

  @override
  State<PersonalizedBranchOverlay> createState() =>
      _PersonalizedBranchOverlayState();
}

class _PersonalizedBranchOverlayState extends State<PersonalizedBranchOverlay> {
  final TextEditingController _promptController = TextEditingController();
  bool _showPrompt = false;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .74),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.alt_route,
                    color: AppColors.accentMint,
                    size: 38,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '个性化剧情分支',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.session.question,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      height: 1.3,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ...widget.session.options.map(_optionButton),
                  if (_showPrompt) _customPrompt(),
                  if (widget.error?.isNotEmpty ?? false)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        widget.error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFF8A80),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: widget.isSubmitting
                            ? null
                            : () => setState(() => _showPrompt = !_showPrompt),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('自定义剧情'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: widget.isSubmitting ? null : widget.onSkip,
                        child: const Text('跳过'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _optionButton(PersonalizedBranchOption option) {
    final selected = widget.selectedOptionId == option.id;
    final status = _status(option);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            backgroundColor: selected
                ? AppColors.accentMint.withValues(alpha: .16)
                : Colors.white.withValues(alpha: .07),
            side: BorderSide(
              color: selected
                  ? AppColors.accentMint
                  : AppColors.accentMint.withValues(alpha: .48),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: widget.isSubmitting || !option.canSelect
              ? null
              : () => widget.onPick(option),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (option.description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        option.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              status,
            ],
          ),
        ),
      ),
    );
  }

  Widget _status(PersonalizedBranchOption option) {
    if (widget.selectedOptionId == option.id &&
        (widget.isSubmitting || !option.isReady)) {
      return const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.accentMint,
        ),
      );
    }
    if (option.isReady) {
      return Column(
        children: [
          const Icon(Icons.play_circle_fill,
              color: AppColors.accentMint, size: 22),
          if (option.qualityLabel.isNotEmpty)
            Text(
              option.qualityLabel,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 9,
              ),
            ),
        ],
      );
    }
    if (option.status == 'review_required') {
      return const Icon(Icons.fact_check_outlined,
          color: AppColors.accentGold, size: 21);
    }
    if (option.status == 'failed') {
      return const Icon(Icons.refresh, color: Color(0xFFFF8A80), size: 21);
    }
    return const Icon(Icons.auto_awesome,
        color: AppColors.textSecondary, size: 20);
  }

  Widget _customPrompt() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _promptController,
              maxLength: 200,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                counterText: '',
                hintText: '输入你希望主角采取的行动',
                hintStyle: const TextStyle(color: AppColors.textTertiary),
                filled: true,
                fillColor: Colors.white.withValues(alpha: .08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: '生成自定义分支',
            onPressed: widget.isSubmitting
                ? null
                : () => widget.onCustomPrompt(_promptController.text),
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
