import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../controllers/danmaku_controller.dart';

class DanmakuSettingsSheet extends StatefulWidget {
  final DanmakuPlayerController controller;

  const DanmakuSettingsSheet({super.key, required this.controller});

  @override
  State<DanmakuSettingsSheet> createState() => _DanmakuSettingsSheetState();
}

class _DanmakuSettingsSheetState extends State<DanmakuSettingsSheet> {
  final _wordController = TextEditingController();

  @override
  void dispose() {
    _wordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      decoration: const BoxDecoration(
        color: AppColors.bgPanel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: AnimatedBuilder(
        animation: c,
        builder: (_, __) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Row(children: [
              const Icon(Icons.subtitles, color: AppColors.accentMint),
              const SizedBox(width: 8),
              const Text('弹幕设置',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                tooltip: '恢复默认',
                onPressed: c.resetSettings,
                icon: const Icon(Icons.restart_alt, color: Colors.white70),
              ),
              Switch(value: c.enabled, onChanged: c.setEnabled),
            ]),
            const SizedBox(height: 10),
            _modeSelector(c),
            if (c.compactMode) ...[
              const SizedBox(height: 8),
              const Text('精简模式会把弹幕限制在画面上方，并自动隐藏底部弹幕。',
                  style:
                      TextStyle(color: AppColors.textTertiary, fontSize: 12)),
            ],
            _slider('字号', c.fontSize, 12, 28, (v) => c.setStyle(fontSize: v)),
            _slider('透明度', c.opacity, .25, 1, (v) => c.setStyle(opacity: v)),
            _slider('速度', c.speed, .6, 1.8, (v) => c.setStyle(speed: v)),
            _slider('区域', c.area, .1, 1, (v) => c.setDisplay(area: v)),
            _slider('持续', c.duration, 2, 16, (v) => c.setDisplay(duration: v)),
            _slider(
                '行高', c.lineHeight, .8, 3, (v) => c.setDisplay(lineHeight: v)),
            _slider(
                '偏移',
                c.timeOffset,
                -60,
                60,
                (v) => c.setTimeline(
                    timeOffset: double.parse(v.toStringAsFixed(1)))),
            _switch('顶部弹幕', c.showTop, (v) => c.setVisibility(top: v)),
            _switch('底部弹幕', c.showBottom, (v) => c.setVisibility(bottom: v)),
            _switch('滚动弹幕', c.showScroll, (v) => c.setVisibility(scroll: v)),
            _switch(
                '跟随倍速', c.followSpeed, (v) => c.setTimeline(followSpeed: v)),
            const SizedBox(height: 10),
            const Text('屏蔽词',
                style: TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _wordController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '输入关键词',
                    hintStyle: const TextStyle(color: AppColors.textTertiary),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: .08),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  c.addBlockedWord(_wordController.text);
                  _wordController.clear();
                },
                child: const Text('加入'),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: c.blockedWords
                  .map((w) => InputChip(
                        label: Text(w),
                        onDeleted: () => c.removeBlockedWord(w),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(
          width: 54,
          child: Text(label,
              style: const TextStyle(color: AppColors.textSecondary))),
      Expanded(
          child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged)),
      SizedBox(
        width: 42,
        child: Text(value.toStringAsFixed(value.abs() < 2 ? 1 : 0),
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.white70)),
      ),
    ]);
  }

  Widget _modeSelector(DanmakuPlayerController c) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: DanmakuDisplayMode.standard,
            icon: Icon(Icons.fullscreen_rounded, size: 18),
            label: Text('全屏'),
          ),
          ButtonSegment(
            value: DanmakuDisplayMode.compact,
            icon: Icon(Icons.vertical_align_top_rounded, size: 18),
            label: Text('精简上方'),
          ),
        ],
        selected: {c.displayMode},
        onSelectionChanged: (values) => c.setDisplayMode(values.first),
        showSelectedIcon: false,
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.white
                : AppColors.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.accentMint.withValues(alpha: .22)
                : Colors.white.withValues(alpha: .06),
          ),
        ),
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(children: [
      Expanded(
        child:
            Text(label, style: const TextStyle(color: AppColors.textSecondary)),
      ),
      Switch(value: value, onChanged: onChanged),
    ]);
  }
}
