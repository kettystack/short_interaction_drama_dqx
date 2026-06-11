import 'package:dio/dio.dart';

import '../../../core/config.dart';
import '../../../core/user_session.dart';
import 'interactive_drama_models.dart';

class InteractiveDramaApi {
  InteractiveDramaApi()
      : _dio = Dio(BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          headers: AppConfig.defaultHeaders,
        ));

  final Dio _dio;

  Future<InteractiveRun> startRun({
    String dramaId = 'tianxiadyi',
    String episodeId = 'txy_001',
    bool reset = false,
  }) async {
    final res = await _dio.post('/api/interactive-drama/runs', data: {
      'drama_id': dramaId,
      'episode_id': episodeId,
      'user_id': UserSession.userId,
      'reset': reset,
    });
    return InteractiveRun.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<InteractiveRun> getRun(String runId) async {
    final res = await _dio.get('/api/interactive-drama/runs/$runId');
    return InteractiveRun.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<InteractiveChooseResult> choose({
    required String runId,
    required String nodeId,
    required String optionId,
  }) async {
    final res =
        await _dio.post('/api/interactive-drama/runs/$runId/choose', data: {
      'node_id': nodeId,
      'option_id': optionId,
      'client_event_id': 'flutter_${DateTime.now().microsecondsSinceEpoch}',
    });
    return InteractiveChooseResult.fromJson(
      Map<String, dynamic>.from(res.data as Map),
    );
  }

  Future<InteractiveRun> resetRun(String runId) async {
    final res = await _dio.post('/api/interactive-drama/runs/$runId/reset');
    return InteractiveRun.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<InteractiveRun> rewindRun(String runId) async {
    final res = await _dio.post('/api/interactive-drama/runs/$runId/rewind');
    return InteractiveRun.fromJson(Map<String, dynamic>.from(res.data as Map));
  }
}
