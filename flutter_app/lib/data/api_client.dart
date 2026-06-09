import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../core/config.dart';
import '../core/user_session.dart';
import 'models.dart';

/// Dio + 简单错误包装；与 iOS APIClient.swift 接口一致
class ApiClient {
  ApiClient._(this._dio);

  final Dio _dio;

  static ApiClient create() {
    final dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
    ));
    dio.interceptors.add(LogInterceptor(
      request: false,
      requestHeader: false,
      requestBody: false,
      responseHeader: false,
      responseBody: false,
      error: true,
      logPrint: (m) => Logger().d(m),
    ));
    return ApiClient._(dio);
  }

  Future<List<Episode>> getEpisodes({String? dramaId}) async {
    final res = await _dio.get(
      '/api/episodes',
      queryParameters: dramaId == null ? null : {'drama_id': dramaId},
    );
    return (res.data as List).map((e) => Episode.fromJson(e)).toList();
  }

  Future<List<Episode>> getShortsFeed({int limit = 50}) async {
    try {
      final res = await _dio.get(
        '/api/feed/shorts',
        queryParameters: {'limit': limit},
      );
      return (res.data as List).map((e) => Episode.fromJson(e)).toList();
    } catch (_) {
      // 后端尚未升级时回退到普通列表
      final list = await getEpisodes();
      list.shuffle();
      return list.take(limit).toList();
    }
  }

  Future<List<PickFeedItem>> getPicksFeed({
    String genre = '全部',
    int limit = 30,
  }) async {
    try {
      final res = await _dio.get(
        '/api/feed/picks',
        queryParameters: {'genre': genre, 'limit': limit},
      );
      return (res.data as List).map((e) => PickFeedItem.fromJson(e)).toList();
    } catch (_) {
      final list = await getEpisodes();
      return list.take(limit).toList().asMap().entries.map((entry) {
        return PickFeedItem(
          episode: entry.value,
          score: 7.5 + ((entry.key * 7) % 30) / 10,
          reason: 'AI 互动高能短剧',
          tags: const ['短剧', '互动'],
        );
      }).toList();
    }
  }

  Future<VipProfile> getVipProfile({String? userId}) async {
    try {
      final res = await _dio.get(
        '/api/vip/profile',
        queryParameters: {'user_id': userId ?? UserSession.userId},
      );
      return VipProfile.fromJson(res.data as Map<String, dynamic>);
    } catch (_) {
      final episodes = await getEpisodes();
      return VipProfile(
        userId: userId ?? UserSession.userId,
        displayName:
            '用户${UserSession.userId.substring(UserSession.userId.length - 4)}',
        vipLevel: 3,
        vipBadge: 'SVIP3',
        gooseCoins: 0,
        diamonds: 0,
        benefits: [
          VipBenefit(code: '4k', title: '4K 蓝光'),
          VipBenefit(code: 'dolby', title: '杜比音效'),
          VipBenefit(code: 'no_ads', title: '免广告'),
          VipBenefit(code: 'devices', title: '4 端通用'),
          VipBenefit(code: 'ai_branch', title: 'AI 续写'),
          VipBenefit(code: 'early_access', title: '抢先看'),
          VipBenefit(code: 'skin', title: '专属皮肤'),
          VipBenefit(code: 'gift', title: '会员礼包'),
        ],
        vipEpisodes: episodes.take(8).toList(),
      );
    }
  }

  Future<Episode> getEpisode(String id) async {
    final res = await _dio.get('/api/episodes/$id');
    return Episode.fromJson(res.data);
  }

  Future<AigcVideoJob> createAigcVideoJob({
    required String episodeId,
    required double tsInVideo,
    String triggerType = 'boost',
    String userPrompt = '',
    String styleCode = 'short_drama_punchy',
    int? highlightId,
    String? storyThreadId,
    String? idempotencyKey,
    String? userId,
    double durationSeconds = 12,
  }) async {
    final res = await _dio.post('/api/aigc-video/jobs', data: {
      'episode_id': episodeId,
      'user_id': userId ?? UserSession.userId,
      'ts_in_video': tsInVideo,
      'trigger_type': triggerType,
      'user_prompt': userPrompt,
      'style_code': styleCode,
      'duration_seconds': durationSeconds,
      if (highlightId != null) 'highlight_id': highlightId,
      if (storyThreadId != null) 'story_thread_id': storyThreadId,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
    });
    return AigcVideoJob.fromJson(res.data as Map<String, dynamic>);
  }

  Future<AigcVideoJob> getAigcVideoJob(String jobId) async {
    final res = await _dio.get('/api/aigc-video/jobs/$jobId');
    return AigcVideoJob.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<AigcBoostPoint>> getAigcBoostPoints(String episodeId) async {
    final res = await _dio.get('/api/aigc-video/boost-points/$episodeId');
    return (res.data as List)
        .map((e) => AigcBoostPoint.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<AigcVideoJob>> listAigcVideoJobs({
    required String adminToken,
    String? episodeId,
    String? status,
    int limit = 50,
  }) async {
    final res = await _dio.get(
      '/api/aigc-video/jobs',
      queryParameters: {
        if (episodeId != null && episodeId.isNotEmpty) 'episode_id': episodeId,
        if (status != null && status.isNotEmpty) 'status': status,
        'limit': limit,
      },
      options: _adminOptions(adminToken),
    );
    return (res.data as List)
        .map((e) => AigcVideoJob.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<AigcVideoJob> reviewAigcVideoJob({
    required String jobId,
    required bool approve,
    required String adminToken,
    String reason = '',
  }) async {
    final action = approve ? 'approve' : 'reject';
    final res = await _dio.post(
      '/api/aigc-video/jobs/$jobId/$action',
      data: {'reason': reason},
      options: _adminOptions(adminToken),
    );
    return AigcVideoJob.fromJson(
      Map<String, dynamic>.from(res.data as Map),
    );
  }

  Future<List<AigcBoostPoint>> listAigcBoostPointsAdmin({
    required String episodeId,
    required String adminToken,
    int limit = 100,
  }) async {
    final res = await _dio.get(
      '/api/aigc-video/boost-points',
      queryParameters: {'episode_id': episodeId, 'limit': limit},
      options: _adminOptions(adminToken),
    );
    return (res.data as List)
        .map((e) => AigcBoostPoint.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<ClipAssetAdmin>> listClipAssets({
    required String episodeId,
    required String adminToken,
    int limit = 100,
  }) async {
    final res = await _dio.get(
      '/api/admin/clip-assets',
      queryParameters: {'episode_id': episodeId, 'limit': limit},
      options: _adminOptions(adminToken),
    );
    return (res.data as List)
        .map((e) => ClipAssetAdmin.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<AigcQualityCheckAdmin>> listAigcQualityChecks({
    required String adminToken,
    String? jobId,
    int limit = 100,
  }) async {
    final res = await _dio.get(
      '/api/admin/aigc-quality-checks',
      queryParameters: {
        if (jobId != null && jobId.isNotEmpty) 'job_id': jobId,
        'limit': limit,
      },
      options: _adminOptions(adminToken),
    );
    return (res.data as List)
        .map(
            (e) => AigcQualityCheckAdmin.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<InteractionEffectManifest> getEffectManifest() async {
    final res = await _dio.get('/api/assets/effects');
    return InteractionEffectManifest.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<HighlightGoldLabel>> getGoldLabels(
    String episodeId, {
    required String adminToken,
  }) async {
    final res = await _dio.get(
      '/api/evaluation/gold-labels/$episodeId',
      options: _adminOptions(adminToken),
    );
    return (res.data as List)
        .map((e) => HighlightGoldLabel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<HighlightGoldLabel> saveGoldLabel(
    HighlightGoldLabel label, {
    required String adminToken,
  }) async {
    final data = label.toJson();
    final res = label.id > 0
        ? await _dio.put(
            '/api/evaluation/gold-labels/${label.id}',
            data: data,
            options: _adminOptions(adminToken),
          )
        : await _dio.post(
            '/api/evaluation/gold-labels',
            data: data,
            options: _adminOptions(adminToken),
          );
    return HighlightGoldLabel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<HighlightEvalRun> runHighlightEvaluation({
    required String episodeId,
    required String adminToken,
    String pipelineVersion = 'db_highlights',
    double iouThreshold = .3,
  }) async {
    final res = await _dio.post(
      '/api/evaluation/runs',
      data: {
        'episode_id': episodeId,
        'pipeline_version': pipelineVersion,
        'candidate_source': 'db_highlights',
        'iou_threshold': iouThreshold,
      },
      options: _adminOptions(adminToken),
    );
    return HighlightEvalRun.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<Highlight>> getHighlights(String episodeId) async {
    final res = await _dio.get('/api/highlights/$episodeId');
    return (res.data as List).map((e) => Highlight.fromJson(e)).toList();
  }

  Future<List<BranchFork>> getForks(String episodeId) async {
    final res = await _dio.get('/api/branches/forks/$episodeId');
    return (res.data as List).map((e) => BranchFork.fromJson(e)).toList();
  }

  Future<List<DanmakuItem>> getDanmaku(
    String episodeId, {
    double? start,
    double? end,
    String density = 'all',
    int limit = 60000,
  }) async {
    final res = await _dio.get(
      '/api/danmaku/$episodeId',
      queryParameters: {
        'density': density,
        'limit': limit,
        if (start != null) 'start': start,
        if (end != null) 'end': end,
      },
    );
    return (res.data as List).map((e) => DanmakuItem.fromJson(e)).toList();
  }

  Future<DanmakuSettings> getDanmakuSettings({String? userId}) async {
    final res = await _dio.get(
      '/api/danmaku/settings/${userId ?? UserSession.userId}',
    );
    return DanmakuSettings.fromJson(res.data as Map<String, dynamic>);
  }

  Future<DanmakuSettings> saveDanmakuSettings(
    DanmakuSettings settings, {
    String? userId,
  }) async {
    final res = await _dio.put(
      '/api/danmaku/settings/${userId ?? UserSession.userId}',
      data: settings.toJson(),
    );
    return DanmakuSettings.fromJson(res.data as Map<String, dynamic>);
  }

  Future<DanmakuSettings> resetDanmakuSettings({String? userId}) async {
    final res = await _dio.delete(
      '/api/danmaku/settings/${userId ?? UserSession.userId}',
    );
    return DanmakuSettings.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<InteractionTimelineBucket>> getInteractionTimeline(
    String episodeId, {
    int bucketSize = 10,
    String? action,
  }) async {
    final res = await _dio.get(
      '/api/interactions/timeline/$episodeId',
      queryParameters: {
        'bucket_size': bucketSize,
        if (action != null) 'action': action,
      },
    );
    return (res.data as List)
        .map((e) => InteractionTimelineBucket.fromJson(e))
        .toList();
  }

  Future<Map<String, dynamic>> getInteractionSummary(
    String episodeId, {
    String action = '笑出鹅叫',
    int? highlightId,
  }) async {
    final res = await _dio.get(
      '/api/interactions/summary/$episodeId',
      queryParameters: {
        'action': action,
        if (highlightId != null) 'highlight_id': highlightId,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// 一次获取多个动作的汇总，避免并行发多条请求。
  /// 返回 { action: {count, display_count, label}, ... }
  Future<Map<String, Map<String, dynamic>>> getMultiSummary(
    String episodeId, {
    List<String> actions = const ['笑出鹅叫', '喜欢'],
    int? highlightId,
  }) async {
    final res = await _dio.get(
      '/api/interactions/multi-summary/$episodeId',
      queryParameters: {
        'actions': actions.join(','),
        if (highlightId != null) 'highlight_id': highlightId,
      },
    );
    final raw = res.data as Map;
    return raw.map(
        (k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)));
  }

  Future<Map<String, dynamic>> postInteraction({
    required String episodeId,
    required String action,
    required double ts,
    int? highlightId,
    String? effect,
    String? userId,
    String? clientEventId,
    Map<String, dynamic>? payload,
  }) async {
    final res = await _dio.post('/api/interactions', data: {
      'episode_id': episodeId,
      if (highlightId != null) 'highlight_id': highlightId,
      'action': action,
      'ts_in_video': ts,
      'user_id': userId ?? UserSession.userId,
      if (effect != null) 'effect': effect,
      if (clientEventId != null) 'client_event_id': clientEventId,
      if (payload != null && payload.isNotEmpty) 'payload': payload,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<BranchStory> generateBranchStory({
    required String episodeId,
    required String context,
    String? choice,
  }) async {
    final res = await _dio.post('/api/interactions/branch', data: {
      'episode_id': episodeId,
      'context': context,
      'choice': choice,
    });
    return BranchStory.fromJson(res.data as Map<String, dynamic>);
  }

  /// 证据链驱动的续写：后端基于 PlotEvent / 角色卡自行构造上下文，
  /// 前端只需提供 episode + 播放进度 + 用户选择。
  /// 返回结构兼容旧的 [BranchStory]（text + choices 文本）。
  Future<BranchStory> generateBranchStoryFromEvidence({
    required String episodeId,
    required double tsInVideo,
    String? selectedChoice,
    List<String> branchHistory = const [],
  }) async {
    final res = await _dio.post('/api/branches/generate', data: {
      'episode_id': episodeId,
      'user_id': UserSession.userId,
      'ts_in_video': tsInVideo,
      if (selectedChoice != null && selectedChoice.trim().isNotEmpty)
        'selected_choice': selectedChoice.trim(),
      if (branchHistory.isNotEmpty) 'branch_history': branchHistory,
    });
    final j = res.data as Map<String, dynamic>;
    final choices = ((j['choices'] ?? const []) as List)
        .map((e) => e is Map ? (e['label'] ?? '').toString() : e.toString())
        .where((s) => s.trim().isNotEmpty)
        .toList();
    return BranchStory(
      text: (j['text'] ?? '').toString(),
      choices: choices,
    );
  }

  Future<StoryThread> createStoryThread({
    required String episodeId,
    required double tsInVideo,
    String? initialChoice,
    String contextHint = '',
    String styleCode = 'cinematic_literary',
    List<String> branchHistory = const [],
    int? forkId,
  }) async {
    final res = await _dio.post('/api/story-chat/threads', data: {
      'episode_id': episodeId,
      'user_id': UserSession.userId,
      'ts_in_video': tsInVideo,
      'style_code': styleCode,
      if (forkId != null) 'fork_id': forkId,
      if (initialChoice != null && initialChoice.trim().isNotEmpty)
        'initial_choice': initialChoice.trim(),
      if (contextHint.trim().isNotEmpty) 'context_hint': contextHint.trim(),
      if (branchHistory.isNotEmpty) 'branch_history': branchHistory,
    });
    return StoryThread.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StoryThreadDelta> chooseStoryBranch({
    required String threadId,
    required StoryChoice choice,
    String? styleCode,
  }) async {
    final res =
        await _dio.post('/api/story-chat/threads/$threadId/choose', data: {
      'choice_id': choice.choiceId,
      'choice_label': choice.label,
      if (styleCode != null) 'style_code': styleCode,
    });
    return StoryThreadDelta.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StoryThreadDelta> sendStoryMessage({
    required String threadId,
    required String text,
    String? styleCode,
  }) async {
    final res =
        await _dio.post('/api/story-chat/threads/$threadId/message', data: {
      'text': text,
      if (styleCode != null) 'style_code': styleCode,
    });
    return StoryThreadDelta.fromJson(res.data as Map<String, dynamic>);
  }

  /// 拉取 AI 续写卡的远端互动汇总（点赞数 + 最近评论）
  Future<StoryFeedback> getStoryFeedback(String episodeId,
      {int limit = 30}) async {
    try {
      final res = await _dio.get(
        '/api/interactions/story/$episodeId',
        queryParameters: {'limit': limit},
      );
      return StoryFeedback.fromJson(res.data as Map<String, dynamic>);
    } catch (_) {
      return StoryFeedback(episodeId: episodeId, likes: 0, comments: const []);
    }
  }

  Future<void> postDanmaku({
    required String episodeId,
    required String content,
    required double ts,
    int color = 0xFFFFFFFF,
    int mode = 0,
    String? userId,
  }) async {
    await _dio.post('/api/danmaku', data: {
      'episode_id': episodeId,
      'ts_in_video': ts,
      'text': content,
      'user_id': userId ?? UserSession.userId,
    });
  }

  Future<void> saveProgress({
    required String episodeId,
    required double progressSeconds,
    required double duration,
    String? userId,
  }) async {
    await _dio.post('/api/users/progress', data: {
      'user_id': userId ?? UserSession.userId,
      'episode_id': episodeId,
      'progress_seconds': progressSeconds,
      'duration': duration,
      'completed': duration > 0 && progressSeconds / duration >= .92,
    });
  }

  Future<void> saveEpisodeAction({
    required String episodeId,
    required String action,
    required bool active,
    String? userId,
  }) async {
    await _dio.post('/api/users/actions', data: {
      'user_id': userId ?? UserSession.userId,
      'episode_id': episodeId,
      'action': action,
      'active': active,
    });
  }

  Future<bool> getEpisodeActionState({
    required String episodeId,
    required String action,
    String? userId,
  }) async {
    final resolvedUserId = userId ?? UserSession.userId;
    final res = await _dio.get(
      '/api/users/$resolvedUserId/actions/$episodeId',
      queryParameters: {'action': action},
    );
    final data = res.data;
    if (data == null) return false;
    return (data as Map<String, dynamic>)['active'] == true;
  }

  Options _adminOptions(String adminToken) => Options(
        headers: {'X-Admin-Token': adminToken},
      );
}
