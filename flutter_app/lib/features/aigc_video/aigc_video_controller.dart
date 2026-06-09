import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/api_client.dart';
import '../../data/models.dart';

class AigcVideoController extends ChangeNotifier {
  AigcVideoController(this._api);

  final ApiClient _api;
  AigcVideoJob? currentJob;
  bool isCreating = false;
  String? error;
  Timer? _pollTimer;

  Future<void> createJob({
    required String episodeId,
    required double tsInVideo,
    String triggerType = 'boost',
    String userPrompt = '',
    int? highlightId,
    String? storyThreadId,
    double durationSeconds = 12,
  }) async {
    if (isCreating) return;
    isCreating = true;
    error = null;
    notifyListeners();
    try {
      final key =
          'aigc_i2v_v4_${episodeId}_${(tsInVideo * 1000).round()}_${triggerType}_${durationSeconds.round()}s';
      currentJob = await _api.createAigcVideoJob(
        episodeId: episodeId,
        tsInVideo: tsInVideo,
        triggerType: triggerType,
        userPrompt: userPrompt,
        highlightId: highlightId,
        storyThreadId: storyThreadId,
        durationSeconds: durationSeconds,
        idempotencyKey: key,
      );
      if (currentJob != null && !currentJob!.isReady && !currentJob!.isFailed) {
        startPolling(currentJob!.jobId);
      }
    } catch (e) {
      error = e.toString();
    } finally {
      isCreating = false;
      notifyListeners();
    }
  }

  void startPolling(String jobId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(pollJob(jobId));
    });
  }

  Future<void> pollJob(String jobId) async {
    try {
      currentJob = await _api.getAigcVideoJob(jobId);
      if (currentJob!.isReady || currentJob!.isFailed) {
        _pollTimer?.cancel();
      }
      notifyListeners();
    } catch (e) {
      error = e.toString();
      _pollTimer?.cancel();
      notifyListeners();
    }
  }

  void clear() {
    currentJob = null;
    error = null;
    _pollTimer?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
