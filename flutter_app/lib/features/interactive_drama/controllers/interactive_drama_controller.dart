import 'package:flutter/foundation.dart';

import '../data/interactive_drama_api.dart';
import '../data/interactive_drama_models.dart';

class InteractiveDramaController extends ChangeNotifier {
  InteractiveDramaController({InteractiveDramaApi? api})
      : _api = api ?? InteractiveDramaApi();

  final InteractiveDramaApi _api;

  InteractiveRun? run;
  String latestStoryText = '';
  bool isLoading = false;
  bool isChoosing = false;
  String? error;

  InteractiveNode? get activeNode => run?.activeNode;
  InteractiveDramaState? get state => run?.state;
  InteractiveEnding? get ending => run?.ending;

  Future<void> start({bool reset = false}) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      run = await _api.startRun(reset: reset);
      latestStoryText = reset ? '' : _lastStoryText(run);
    } catch (exception) {
      error = '互动版加载失败：$exception';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> choose(InteractiveOption option) async {
    final currentRun = run;
    final node = currentRun?.activeNode;
    if (currentRun == null || node == null || isChoosing) return;
    isChoosing = true;
    error = null;
    notifyListeners();
    try {
      final result = await _api.choose(
        runId: currentRun.runId,
        nodeId: node.nodeId,
        optionId: option.optionId,
      );
      run = result.run;
      latestStoryText = result.storyText;
    } catch (exception) {
      error = '选择失败：$exception';
    } finally {
      isChoosing = false;
      notifyListeners();
    }
  }

  Future<void> reset() async {
    final currentRun = run;
    if (currentRun == null) {
      await start(reset: true);
      return;
    }
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      run = await _api.resetRun(currentRun.runId);
      latestStoryText = '';
    } catch (exception) {
      error = '重开路线失败：$exception';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> rewind() async {
    final currentRun = run;
    if (currentRun == null) {
      await start(reset: true);
      return;
    }
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      run = await _api.rewindRun(currentRun.runId);
      latestStoryText = _lastStoryText(run);
    } catch (exception) {
      error = '回到上个选择点失败：$exception';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  String _lastStoryText(InteractiveRun? run) {
    final path = run?.selectedPath ?? const [];
    if (path.isEmpty) return '';
    return (path.last['story_text'] ?? '').toString();
  }
}
