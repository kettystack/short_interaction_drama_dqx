import 'package:dio/dio.dart';

import '../../../core/config.dart';
import '../../../core/user_session.dart';
import 'branch_video_models.dart';

class BranchVideoApi {
  BranchVideoApi._(this._dio);

  final Dio _dio;

  factory BranchVideoApi.create() {
    return BranchVideoApi._(
      Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(minutes: 3),
          headers: {
            ...AppConfig.defaultHeaders,
            'X-User-Id': UserSession.userId,
          },
        ),
      ),
    );
  }

  Future<List<PersonalizedBranchSession>> listEpisodeSessions(
    String episodeId,
  ) async {
    final response = await _dio.get(
      '/api/branch-video/episodes/$episodeId/sessions',
      queryParameters: {'user_id': UserSession.userId},
    );
    return (response.data as List)
        .whereType<Map>()
        .map((item) => PersonalizedBranchSession.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }

  Future<PersonalizedBranchSession> getSession(String sessionId) async {
    final response = await _dio.get(
      '/api/branch-video/sessions/$sessionId',
      queryParameters: {'user_id': UserSession.userId},
    );
    return PersonalizedBranchSession.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<PersonalizedBranchSession> prewarm(String sessionId) async {
    final response = await _dio.post(
      '/api/branch-video/sessions/$sessionId/prewarm',
      queryParameters: {'user_id': UserSession.userId},
    );
    return PersonalizedBranchSession.fromJson(
      Map<String, dynamic>.from((response.data as Map)['session'] as Map),
    );
  }

  Future<BranchSelectionResult> selectOption({
    required String sessionId,
    required String optionId,
    required String clientEventId,
  }) async {
    final response = await _dio.post(
      '/api/branch-video/sessions/$sessionId/select',
      queryParameters: {'user_id': UserSession.userId},
      data: {
        'option_id': optionId,
        'client_event_id': clientEventId,
      },
    );
    return BranchSelectionResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<PersonalizedBranchSession> createCustomOption({
    required String sessionId,
    required String prompt,
    double targetDuration = 12,
  }) async {
    final response = await _dio.post(
      '/api/branch-video/sessions/$sessionId/custom-options',
      queryParameters: {'user_id': UserSession.userId},
      data: {
        'prompt': prompt,
        'target_duration': targetDuration,
        'style': '竖屏短剧电影感',
      },
    );
    return PersonalizedBranchSession.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<void> recordEvent({
    required BranchPlaybackTicket ticket,
    required String eventType,
    required double tsInMainVideo,
    double clipPosition = 0,
  }) async {
    await _dio.post(
      '/api/branch-video/events',
      queryParameters: {'user_id': UserSession.userId},
      data: {
        'session_id': ticket.sessionId,
        'option_id': ticket.optionId,
        'variant_id': ticket.variantId,
        'event_type': eventType,
        'ts_in_main_video': tsInMainVideo,
        'clip_position': clipPosition,
        'client_event_id':
            '${UserSession.userId}:${ticket.variantId}:$eventType',
      },
    );
  }
}
