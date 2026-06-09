/// 数据模型 —— 与 backend Schema/iOS Models 对齐
library;

class VideoQuality {
  final String label;
  final String url;
  final int? width;
  final int? height;
  final int? bandwidth;
  final bool isAuto;

  const VideoQuality({
    required this.label,
    required this.url,
    this.width,
    this.height,
    this.bandwidth,
    this.isAuto = false,
  });

  String get displayLabel => isAuto ? '自动' : label;

  factory VideoQuality.fromJson(Map<String, dynamic> j) => VideoQuality(
        label: j['label']?.toString() ?? '',
        url: j['url']?.toString() ?? '',
        width: (j['width'] as num?)?.toInt(),
        height: (j['height'] as num?)?.toInt(),
        bandwidth: (j['bandwidth'] as num?)?.toInt(),
      );
}

class Episode {
  final String id;
  final String dramaId;
  final String title;
  final int episodeNo;
  final double duration;
  final String videoUrl;
  final String? hlsUrl;
  final bool hlsReady;
  final List<VideoQuality> hlsVariants;
  final String? coverUrl;

  Episode({
    required this.id,
    required this.dramaId,
    required this.title,
    required this.episodeNo,
    required this.duration,
    required this.videoUrl,
    this.hlsUrl,
    this.hlsReady = false,
    this.hlsVariants = const [],
    this.coverUrl,
  });

  String get preferredVideoUrl =>
      hlsReady && (hlsUrl?.isNotEmpty ?? false) ? hlsUrl! : videoUrl;

  List<VideoQuality> get qualityOptions {
    final options = <VideoQuality>[];
    if (hlsReady && (hlsUrl?.isNotEmpty ?? false)) {
      options.add(VideoQuality(label: '自动', url: hlsUrl!, isAuto: true));
    }
    options.addAll(hlsVariants.where((item) => item.url.isNotEmpty));
    if (videoUrl.isNotEmpty) {
      options.add(VideoQuality(label: hlsReady ? '原片' : '默认', url: videoUrl));
    }
    return options;
  }

  factory Episode.fromJson(Map<String, dynamic> j) {
    final rawVariants = j['hls_variants'];
    return Episode(
      id: j['id'],
      dramaId: j['drama_id'],
      title: j['title'],
      episodeNo: j['episode_no'],
      duration: (j['duration'] ?? 0).toDouble(),
      videoUrl: j['video_url'] ?? '',
      hlsUrl: j['hls_url'],
      hlsReady: j['hls_ready'] ?? false,
      hlsVariants: rawVariants is List
          ? rawVariants
              .whereType<Map>()
              .map((item) =>
                  VideoQuality.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
      coverUrl: j['cover_url'],
    );
  }
}

class Highlight {
  final int id;
  final String episodeId;
  final double tsStart;
  final double tsEnd;
  final String type; // 冲突 / 转折 / 高能 ...
  final String interaction;
  final double intensity;
  final String summary;
  final String? coverFrame;

  Highlight({
    required this.id,
    required this.episodeId,
    required this.tsStart,
    required this.tsEnd,
    required this.type,
    this.interaction = '爽',
    this.intensity = .6,
    required this.summary,
    this.coverFrame,
  });

  factory Highlight.fromJson(Map<String, dynamic> j) => Highlight(
        id: j['id'],
        episodeId: j['episode_id'],
        tsStart: (j['ts_start'] ?? 0).toDouble(),
        tsEnd: (j['ts_end'] ?? 0).toDouble(),
        type: j['type'] ?? '',
        interaction: j['interaction'] ?? '爽',
        intensity: (j['intensity'] ?? .6).toDouble(),
        summary: j['summary'] ?? j['description'] ?? '',
        coverFrame: j['cover_frame'],
      );
}

class BranchFork {
  final int id;
  final String episodeId;
  final double tsTrigger;
  final String question;
  final List<BranchOption> options;

  BranchFork({
    required this.id,
    required this.episodeId,
    required this.tsTrigger,
    required this.question,
    required this.options,
  });

  factory BranchFork.fromJson(Map<String, dynamic> j) => BranchFork(
        id: j['id'],
        episodeId: j['episode_id'],
        tsTrigger: (j['ts_trigger'] ?? j['ts_in_video'] ?? 0).toDouble(),
        question: j['question'] ?? j['prompt_text'] ?? '',
        options: ((j['options'] ?? j['branches'] ?? []) as List)
            .map((e) => BranchOption.fromJson(e))
            .toList(),
      );
}

class BranchOption {
  final int id;
  final String label;
  final String description;
  final int votes;
  final String? videoUrl;
  final double duration;

  BranchOption({
    required this.id,
    required this.label,
    required this.description,
    required this.votes,
    this.videoUrl,
    this.duration = 0,
  });

  factory BranchOption.fromJson(Map<String, dynamic> j) => BranchOption(
        id: j['id'],
        label: j['label'] ?? j['choice_label'] ?? '',
        description: j['description'] ?? '',
        votes: j['votes'] ?? 0,
        videoUrl: j['video_url'],
        duration: (j['duration'] ?? 0).toDouble(),
      );
}

class DanmakuItem {
  final int id;
  final double ts;
  final String content;
  final int color; // 0xFFRRGGBB
  final int mode; // 0=滚动 1=顶 2=底
  final String userId;

  DanmakuItem({
    required this.id,
    required this.ts,
    required this.content,
    required this.color,
    required this.mode,
    required this.userId,
  });

  factory DanmakuItem.fromJson(Map<String, dynamic> j) => DanmakuItem(
        id: j['id'] ?? 0,
        ts: (j['ts_in_video'] ?? j['ts'] ?? 0).toDouble(),
        content: j['content'] ?? j['text'] ?? '',
        color: _parseColor(j['color']),
        mode: j['mode'] ?? 0,
        userId: j['user_id'] ?? '',
      );

  static int _parseColor(dynamic raw) {
    final value =
        int.tryParse('${raw ?? 'FFFFFF'}'.replaceFirst('#', ''), radix: 16);
    if (value == null) return 0xFFFFFFFF;
    return value <= 0xFFFFFF ? 0xFF000000 | value : value;
  }
}

class DanmakuSettings {
  final bool enabled;
  final String displayMode;
  final double fontSize;
  final double opacity;
  final double speed;
  final double area;
  final double duration;
  final double timeOffset;
  final bool showTop;
  final bool showBottom;
  final bool showScroll;
  final bool followSpeed;
  final double lineHeight;
  final List<String> blockedWords;

  const DanmakuSettings({
    this.enabled = true,
    this.displayMode = 'standard',
    this.fontSize = 16,
    this.opacity = .85,
    this.speed = 1.0,
    this.area = 1.0,
    this.duration = 8.0,
    this.timeOffset = 0.0,
    this.showTop = true,
    this.showBottom = true,
    this.showScroll = true,
    this.followSpeed = true,
    this.lineHeight = 1.6,
    this.blockedWords = const [],
  });

  factory DanmakuSettings.fromJson(Map<String, dynamic> j) => DanmakuSettings(
        enabled: j['enabled'] ?? true,
        displayMode: j['display_mode'] ?? 'standard',
        fontSize: (j['font_size'] ?? 16).toDouble(),
        opacity: (j['opacity'] ?? .85).toDouble(),
        speed: (j['speed'] ?? 1.0).toDouble(),
        area: (j['area'] ?? 1.0).toDouble(),
        duration: (j['duration'] ?? 8.0).toDouble(),
        timeOffset: (j['time_offset'] ?? 0.0).toDouble(),
        showTop: j['show_top'] ?? true,
        showBottom: j['show_bottom'] ?? true,
        showScroll: j['show_scroll'] ?? true,
        followSpeed: j['follow_speed'] ?? true,
        lineHeight: (j['line_height'] ?? 1.6).toDouble(),
        blockedWords: List<String>.from(j['blocked_words'] ?? const []),
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'display_mode': displayMode,
        'font_size': fontSize,
        'opacity': opacity,
        'speed': speed,
        'area': area,
        'duration': duration,
        'time_offset': timeOffset,
        'show_top': showTop,
        'show_bottom': showBottom,
        'show_scroll': showScroll,
        'follow_speed': followSpeed,
        'line_height': lineHeight,
        'blocked_words': blockedWords,
      };
}

class InteractionTimelineBucket {
  final double tsStart;
  final double tsEnd;
  final int count;

  InteractionTimelineBucket({
    required this.tsStart,
    required this.tsEnd,
    required this.count,
  });

  factory InteractionTimelineBucket.fromJson(Map<String, dynamic> j) =>
      InteractionTimelineBucket(
        tsStart: (j['ts_start'] ?? j['bucket_start'] ?? 0).toDouble(),
        tsEnd: (j['ts_end'] ??
                ((j['bucket_start'] ?? 0) + (j['bucket_size'] ?? 10)))
            .toDouble(),
        count: j['display_count'] ?? j['count'] ?? 0,
      );
}

class BranchStory {
  final String text;
  final List<String> choices;

  BranchStory({required this.text, required this.choices});

  factory BranchStory.fromJson(Map<String, dynamic> j) => BranchStory(
        text: j['text'] ?? '',
        choices: List<String>.from(j['choices'] ?? const []),
      );
}

class StoryChoice {
  final String choiceId;
  final String label;
  final String intent;
  final String preview;
  final String tone;

  StoryChoice({
    required this.choiceId,
    required this.label,
    this.intent = '',
    this.preview = '',
    this.tone = '',
  });

  factory StoryChoice.fromJson(Map<String, dynamic> j) => StoryChoice(
        choiceId: (j['choice_id'] ?? '') as String,
        label: (j['label'] ?? '') as String,
        intent: (j['intent'] ?? '') as String,
        preview: (j['preview'] ?? '') as String,
        tone: (j['tone'] ?? '') as String,
      );
}

class StoryTurn {
  final String turnId;
  final String threadId;
  final String role;
  final String? parentTurnId;
  final String? selectedChoiceId;
  final String text;
  final List<StoryChoice> choices;
  final List<String> evidenceEventIds;
  final String createdAt;

  StoryTurn({
    required this.turnId,
    required this.threadId,
    required this.role,
    this.parentTurnId,
    this.selectedChoiceId,
    required this.text,
    this.choices = const [],
    this.evidenceEventIds = const [],
    this.createdAt = '',
  });

  bool get isAssistant => role == 'assistant_story';
  bool get isUserChoice => role == 'user_choice';

  factory StoryTurn.fromJson(Map<String, dynamic> j) => StoryTurn(
        turnId: (j['turn_id'] ?? '') as String,
        threadId: (j['thread_id'] ?? '') as String,
        role: (j['role'] ?? '') as String,
        parentTurnId: j['parent_turn_id'] as String?,
        selectedChoiceId: j['selected_choice_id'] as String?,
        text: (j['text'] ?? '') as String,
        choices: ((j['choices'] ?? const []) as List)
            .whereType<Map>()
            .map((e) => StoryChoice.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        evidenceEventIds:
            List<String>.from(j['evidence_event_ids'] ?? const []),
        createdAt: (j['created_at'] ?? '') as String,
      );
}

class StoryThread {
  final String threadId;
  final String episodeId;
  final String userId;
  final int? forkId;
  final double tsInVideo;
  final String styleCode;
  final String title;
  final List<StoryTurn> turns;
  final List<String> branchPath;

  StoryThread({
    required this.threadId,
    required this.episodeId,
    required this.userId,
    this.forkId,
    required this.tsInVideo,
    this.styleCode = 'cinematic_literary',
    this.title = '',
    this.turns = const [],
    this.branchPath = const [],
  });

  factory StoryThread.fromJson(Map<String, dynamic> j) => StoryThread(
        threadId: (j['thread_id'] ?? '') as String,
        episodeId: (j['episode_id'] ?? '') as String,
        userId: (j['user_id'] ?? '') as String,
        forkId: (j['fork_id'] as num?)?.toInt(),
        tsInVideo: ((j['ts_in_video'] ?? 0) as num).toDouble(),
        styleCode: (j['style_code'] ?? 'cinematic_literary') as String,
        title: (j['title'] ?? '') as String,
        turns: ((j['turns'] ?? const []) as List)
            .whereType<Map>()
            .map((e) => StoryTurn.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        branchPath: List<String>.from(j['branch_path'] ?? const []),
      );
}

class StoryThreadDelta {
  final String threadId;
  final List<StoryTurn> appendedTurns;
  final StoryThread thread;

  StoryThreadDelta({
    required this.threadId,
    required this.appendedTurns,
    required this.thread,
  });

  factory StoryThreadDelta.fromJson(Map<String, dynamic> j) => StoryThreadDelta(
        threadId: (j['thread_id'] ?? '') as String,
        appendedTurns: ((j['appended_turns'] ?? const []) as List)
            .whereType<Map>()
            .map((e) => StoryTurn.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        thread: StoryThread.fromJson(j['thread'] as Map<String, dynamic>),
      );
}

class StoryComment {
  final int id;
  final String userId;
  final String text;
  final double tsInVideo;
  final String createdAt;

  StoryComment({
    required this.id,
    required this.userId,
    required this.text,
    required this.tsInVideo,
    required this.createdAt,
  });

  factory StoryComment.fromJson(Map<String, dynamic> j) => StoryComment(
        id: (j['id'] ?? 0) as int,
        userId: (j['user_id'] ?? '') as String,
        text: (j['text'] ?? '') as String,
        tsInVideo: ((j['ts_in_video'] ?? 0) as num).toDouble(),
        createdAt: (j['created_at'] ?? '') as String,
      );
}

class StoryFeedback {
  final String episodeId;
  final int likes;
  final List<StoryComment> comments;

  StoryFeedback({
    required this.episodeId,
    required this.likes,
    required this.comments,
  });

  factory StoryFeedback.fromJson(Map<String, dynamic> j) => StoryFeedback(
        episodeId: (j['episode_id'] ?? '') as String,
        likes: (j['likes'] ?? 0) as int,
        comments: ((j['comments'] ?? const []) as List)
            .whereType<Map>()
            .map((e) => StoryComment.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class PickFeedItem {
  final Episode episode;
  final double score;
  final String reason;
  final List<String> tags;

  PickFeedItem({
    required this.episode,
    required this.score,
    required this.reason,
    required this.tags,
  });

  factory PickFeedItem.fromJson(Map<String, dynamic> j) => PickFeedItem(
        episode: Episode.fromJson(j['episode'] as Map<String, dynamic>),
        score: (j['score'] ?? 0).toDouble(),
        reason: j['reason'] ?? '',
        tags: List<String>.from(j['tags'] ?? const []),
      );
}

class VipBenefit {
  final String code;
  final String title;
  final String subtitle;

  VipBenefit({
    required this.code,
    required this.title,
    this.subtitle = '',
  });

  factory VipBenefit.fromJson(Map<String, dynamic> j) => VipBenefit(
        code: j['code'] ?? '',
        title: j['title'] ?? '',
        subtitle: j['subtitle'] ?? '',
      );
}

class AigcVideoJob {
  final String jobId;
  final String episodeId;
  final String userId;
  final String status;
  final double progress;
  final String triggerType;
  final String prompt;
  final String provider;
  final String? providerJobId;
  final String outputVideoUrl;
  final String hlsUrl;
  final String coverUrl;
  final double duration;
  final double resumeAt;
  final String insertMode;
  final String errorMessage;
  final double qualityScore;
  final String qualityDecision;
  final List<Map<String, dynamic>> statusHistory;
  final List<String> reviewFrames;
  final String pollUrl;

  const AigcVideoJob({
    required this.jobId,
    required this.episodeId,
    required this.userId,
    required this.status,
    required this.progress,
    required this.triggerType,
    required this.prompt,
    required this.provider,
    this.providerJobId,
    this.outputVideoUrl = '',
    this.hlsUrl = '',
    this.coverUrl = '',
    this.duration = 0,
    this.resumeAt = 0,
    this.insertMode = 'pause_main_then_play_clip',
    this.errorMessage = '',
    this.qualityScore = 0,
    this.qualityDecision = '',
    this.statusHistory = const [],
    this.reviewFrames = const [],
    this.pollUrl = '',
  });

  bool get isReady => status == 'ready' && outputVideoUrl.isNotEmpty;
  bool get isFailed => status == 'failed';

  factory AigcVideoJob.fromJson(Map<String, dynamic> j) => AigcVideoJob(
        jobId: (j['job_id'] ?? '') as String,
        episodeId: (j['episode_id'] ?? '') as String,
        userId: (j['user_id'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        progress: ((j['progress'] ?? 0) as num).toDouble(),
        triggerType: (j['trigger_type'] ?? '') as String,
        prompt: (j['prompt'] ?? '') as String,
        provider: (j['provider'] ?? '') as String,
        providerJobId: j['provider_job_id'] as String?,
        outputVideoUrl: (j['output_video_url'] ?? '') as String,
        hlsUrl: (j['hls_url'] ?? '') as String,
        coverUrl: (j['cover_url'] ?? '') as String,
        duration: ((j['duration'] ?? 0) as num).toDouble(),
        resumeAt: ((j['resume_at'] ?? 0) as num).toDouble(),
        insertMode: (j['insert_mode'] ?? 'pause_main_then_play_clip') as String,
        errorMessage: (j['error_message'] ?? '') as String,
        qualityScore: ((j['quality_score'] ?? 0) as num).toDouble(),
        qualityDecision: (j['quality_decision'] ?? '') as String,
        statusHistory: ((j['status_history'] ?? const []) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        reviewFrames: ((j['review_frames'] ?? const []) as List)
            .map((e) => e.toString())
            .toList(),
        pollUrl: (j['poll_url'] ?? '') as String,
      );
}

class AigcBoostPoint {
  final String id;
  final String episodeId;
  final double triggerTs;
  final double resumeAt;
  final String title;
  final String prompt;
  final String provider;
  final String sourceJobId;
  final String outputVideoUrl;
  final String hlsUrl;
  final String coverUrl;
  final double duration;
  final double qualityScore;
  final String status;

  const AigcBoostPoint({
    required this.id,
    required this.episodeId,
    required this.triggerTs,
    required this.resumeAt,
    required this.title,
    this.prompt = '',
    this.provider = '',
    this.sourceJobId = '',
    this.outputVideoUrl = '',
    this.hlsUrl = '',
    this.coverUrl = '',
    this.duration = 0,
    this.qualityScore = 0,
    this.status = 'published',
  });

  bool get isPlayable => status == 'published' && outputVideoUrl.isNotEmpty;

  String get qualityLabel {
    if (qualityScore <= 0) return '待评估';
    return '质检 ${(qualityScore * 100).round()}';
  }

  factory AigcBoostPoint.fromJson(Map<String, dynamic> j) => AigcBoostPoint(
        id: (j['id'] ?? '') as String,
        episodeId: (j['episode_id'] ?? '') as String,
        triggerTs: ((j['trigger_ts'] ?? 0) as num).toDouble(),
        resumeAt: ((j['resume_at'] ?? 0) as num).toDouble(),
        title: (j['title'] ?? '加速包') as String,
        prompt: (j['prompt'] ?? '') as String,
        provider: (j['provider'] ?? '') as String,
        sourceJobId: (j['source_job_id'] ?? '') as String,
        outputVideoUrl: (j['output_video_url'] ?? '') as String,
        hlsUrl: (j['hls_url'] ?? '') as String,
        coverUrl: (j['cover_url'] ?? '') as String,
        duration: ((j['duration'] ?? 0) as num).toDouble(),
        qualityScore: ((j['quality_score'] ?? 0) as num).toDouble(),
        status: (j['status'] ?? 'published') as String,
      );
}

class ClipAssetAdmin {
  final String id;
  final String episodeId;
  final String clipUrl;
  final double tsStart;
  final double tsEnd;
  final double duration;
  final List<String> actionTags;
  final List<String> emotionTags;
  final String transcript;
  final String source;
  final String status;
  final double qualityScore;

  const ClipAssetAdmin({
    required this.id,
    required this.episodeId,
    required this.clipUrl,
    required this.tsStart,
    required this.tsEnd,
    required this.duration,
    this.actionTags = const [],
    this.emotionTags = const [],
    this.transcript = '',
    this.source = '',
    this.status = '',
    this.qualityScore = 0,
  });

  factory ClipAssetAdmin.fromJson(Map<String, dynamic> j) => ClipAssetAdmin(
        id: (j['id'] ?? '') as String,
        episodeId: (j['episode_id'] ?? '') as String,
        clipUrl: (j['clip_url'] ?? '') as String,
        tsStart: ((j['ts_start'] ?? 0) as num).toDouble(),
        tsEnd: ((j['ts_end'] ?? 0) as num).toDouble(),
        duration: ((j['duration'] ?? 0) as num).toDouble(),
        actionTags:
            ((j['action_tags'] ?? const []) as List).map((e) => '$e').toList(),
        emotionTags:
            ((j['emotion_tags'] ?? const []) as List).map((e) => '$e').toList(),
        transcript: (j['transcript'] ?? '') as String,
        source: (j['source'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        qualityScore: ((j['quality_score'] ?? 0) as num).toDouble(),
      );
}

class AigcQualityCheckAdmin {
  final int id;
  final String jobId;
  final String candidateUrl;
  final double finalScore;
  final String finalDecision;
  final List<String> reasons;

  const AigcQualityCheckAdmin({
    required this.id,
    required this.jobId,
    required this.candidateUrl,
    this.finalScore = 0,
    this.finalDecision = '',
    this.reasons = const [],
  });

  factory AigcQualityCheckAdmin.fromJson(Map<String, dynamic> j) =>
      AigcQualityCheckAdmin(
        id: (j['id'] ?? 0) as int,
        jobId: (j['job_id'] ?? '') as String,
        candidateUrl: (j['candidate_url'] ?? '') as String,
        finalScore: ((j['final_score'] ?? 0) as num).toDouble(),
        finalDecision: (j['final_decision'] ?? '') as String,
        reasons: ((j['reasons'] ?? const []) as List).map((e) => '$e').toList(),
      );
}

class HighlightGoldLabel {
  final int id;
  final String episodeId;
  final double tsStart;
  final double tsEnd;
  final String type;
  final String interaction;
  final String description;
  final String annotatorId;
  final double confidence;

  const HighlightGoldLabel({
    required this.id,
    required this.episodeId,
    required this.tsStart,
    required this.tsEnd,
    required this.type,
    this.interaction = '',
    this.description = '',
    this.annotatorId = 'admin',
    this.confidence = 1.0,
  });

  factory HighlightGoldLabel.fromJson(Map<String, dynamic> j) =>
      HighlightGoldLabel(
        id: (j['id'] ?? 0) as int,
        episodeId: (j['episode_id'] ?? '') as String,
        tsStart: ((j['ts_start'] ?? 0) as num).toDouble(),
        tsEnd: ((j['ts_end'] ?? 0) as num).toDouble(),
        type: (j['type'] ?? '') as String,
        interaction: (j['interaction'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        annotatorId: (j['annotator_id'] ?? 'admin') as String,
        confidence: ((j['confidence'] ?? 1) as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'episode_id': episodeId,
        'ts_start': tsStart,
        'ts_end': tsEnd,
        'type': type,
        'interaction': interaction,
        'description': description,
        'annotator_id': annotatorId,
        'confidence': confidence,
      };
}

class HighlightEvalItem {
  final int? goldLabelId;
  final int? predHighlightId;
  final String matchType;
  final double iou;
  final bool typeMatch;
  final String note;

  const HighlightEvalItem({
    this.goldLabelId,
    this.predHighlightId,
    required this.matchType,
    this.iou = 0,
    this.typeMatch = false,
    this.note = '',
  });

  factory HighlightEvalItem.fromJson(Map<String, dynamic> j) =>
      HighlightEvalItem(
        goldLabelId: (j['gold_label_id'] as num?)?.toInt(),
        predHighlightId: (j['pred_highlight_id'] as num?)?.toInt(),
        matchType: (j['match_type'] ?? '') as String,
        iou: ((j['iou'] ?? 0) as num).toDouble(),
        typeMatch: j['type_match'] == true,
        note: (j['note'] ?? '') as String,
      );
}

class HighlightEvalRun {
  final String runId;
  final String episodeId;
  final double precision;
  final double recall;
  final double f1;
  final double typeAccuracy;
  final int truePositiveCount;
  final int falsePositiveCount;
  final int falseNegativeCount;
  final List<HighlightEvalItem> items;

  const HighlightEvalRun({
    required this.runId,
    required this.episodeId,
    required this.precision,
    required this.recall,
    required this.f1,
    required this.typeAccuracy,
    required this.truePositiveCount,
    required this.falsePositiveCount,
    required this.falseNegativeCount,
    this.items = const [],
  });

  factory HighlightEvalRun.fromJson(Map<String, dynamic> j) => HighlightEvalRun(
        runId: (j['run_id'] ?? '') as String,
        episodeId: (j['episode_id'] ?? '') as String,
        precision: ((j['precision'] ?? 0) as num).toDouble(),
        recall: ((j['recall'] ?? 0) as num).toDouble(),
        f1: ((j['f1'] ?? 0) as num).toDouble(),
        typeAccuracy: ((j['type_accuracy'] ?? 0) as num).toDouble(),
        truePositiveCount: (j['true_positive_count'] ?? 0) as int,
        falsePositiveCount: (j['false_positive_count'] ?? 0) as int,
        falseNegativeCount: (j['false_negative_count'] ?? 0) as int,
        items: ((j['items'] ?? const []) as List)
            .whereType<Map>()
            .map(
                (e) => HighlightEvalItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class EffectAnimationSpec {
  final String type;
  final String preset;
  final int durationMs;

  const EffectAnimationSpec({
    this.type = 'custom_painter',
    this.preset = 'ignition',
    this.durationMs = 900,
  });

  factory EffectAnimationSpec.fromJson(Map<String, dynamic> j) =>
      EffectAnimationSpec(
        type: (j['type'] ?? 'custom_painter') as String,
        preset: (j['preset'] ?? 'ignition') as String,
        durationMs: (j['duration_ms'] ?? 900) as int,
      );
}

class EffectSoundSpec {
  final String url;
  final double volume;

  const EffectSoundSpec({this.url = '', this.volume = .8});

  factory EffectSoundSpec.fromJson(Map<String, dynamic> j) => EffectSoundSpec(
        url: (j['url'] ?? '') as String,
        volume: ((j['volume'] ?? .8) as num).toDouble(),
      );
}

class InteractionEffectAsset {
  final String code;
  final String label;
  final List<String> actions;
  final String icon;
  final EffectAnimationSpec animation;
  final EffectSoundSpec? sound;
  final String haptic;
  final List<String> colors;

  const InteractionEffectAsset({
    required this.code,
    required this.label,
    this.actions = const [],
    this.icon = '',
    this.animation = const EffectAnimationSpec(),
    this.sound,
    this.haptic = 'light',
    this.colors = const [],
  });

  factory InteractionEffectAsset.fromJson(Map<String, dynamic> j) =>
      InteractionEffectAsset(
        code: (j['code'] ?? '') as String,
        label: (j['label'] ?? '') as String,
        actions: List<String>.from(j['actions'] ?? const []),
        icon: (j['icon'] ?? '') as String,
        animation: EffectAnimationSpec.fromJson(
          Map<String, dynamic>.from(j['animation'] ?? const {}),
        ),
        sound: j['sound'] is Map
            ? EffectSoundSpec.fromJson(
                Map<String, dynamic>.from(j['sound'] as Map),
              )
            : null,
        haptic: (j['haptic'] ?? 'light') as String,
        colors: List<String>.from(j['colors'] ?? const []),
      );
}

class InteractionEffectManifest {
  final String version;
  final List<InteractionEffectAsset> effects;

  const InteractionEffectManifest({
    required this.version,
    this.effects = const [],
  });

  factory InteractionEffectManifest.fromJson(Map<String, dynamic> j) =>
      InteractionEffectManifest(
        version: (j['version'] ?? '') as String,
        effects: ((j['effects'] ?? const []) as List)
            .whereType<Map>()
            .map((e) =>
                InteractionEffectAsset.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class VipProfile {
  final String userId;
  final String displayName;
  final int vipLevel;
  final String vipBadge;
  final int gooseCoins;
  final int diamonds;
  final List<VipBenefit> benefits;
  final List<Episode> vipEpisodes;

  VipProfile({
    required this.userId,
    required this.displayName,
    required this.vipLevel,
    required this.vipBadge,
    required this.gooseCoins,
    required this.diamonds,
    required this.benefits,
    required this.vipEpisodes,
  });

  factory VipProfile.fromJson(Map<String, dynamic> j) => VipProfile(
        userId: j['user_id'] ?? '',
        displayName: j['display_name'] ?? '',
        vipLevel: j['vip_level'] ?? 0,
        vipBadge: j['vip_badge'] ?? '',
        gooseCoins: j['goose_coins'] ?? 0,
        diamonds: j['diamonds'] ?? 0,
        benefits: ((j['benefits'] ?? []) as List)
            .map((e) => VipBenefit.fromJson(e as Map<String, dynamic>))
            .toList(),
        vipEpisodes: ((j['vip_episodes'] ?? []) as List)
            .map((e) => Episode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 剧目分组 —— 与 iOS DramaGroup 对齐
class DramaGroup {
  final String dramaId;
  final String dramaName;
  final List<String> genres;
  final String tagline;
  final bool isOngoing;
  final List<Episode> episodes;

  DramaGroup({
    required this.dramaId,
    required this.dramaName,
    required this.genres,
    required this.tagline,
    required this.isOngoing,
    required this.episodes,
  });

  int get totalCount => episodes.length;
  Episode? get heroEpisode => episodes.isEmpty ? null : episodes.first;
}

class DramaMeta {
  static const _registry = <String, Map<String, dynamic>>{
    'beipaixunbao': {
      'name': '北派寻宝笔记',
      'genres': ['冒险', '悬疑', '寻宝'],
      'tagline': '传承千年的秘密，一朝揭开',
      'ongoing': true,
    },
    'tianxiadyi': {
      'name': '天下第一纨绔',
      'genres': ['古装', '爽剧', '逆袭'],
      'tagline': '废柴少爷，一朝觉醒无敌',
      'ongoing': true,
    },
    'shibasuitainainai': {
      'name': '十八岁太奶奶驾到，重整家族荣耀第三部',
      'genres': ['家庭', '逆袭', '反转'],
      'tagline': '十八岁的身体，老太奶的手腕，回场重整家族荣耀',
      'ongoing': true,
    },
  };

  static Map<String, dynamic> info(String id) =>
      _registry[id] ??
      {'name': id, 'genres': const [], 'tagline': '', 'ongoing': false};
}
