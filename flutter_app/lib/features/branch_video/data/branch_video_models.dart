class PersonalizedBranchOption {
  final String id;
  final String optionKey;
  final String label;
  final String description;
  final Map<String, dynamic> intent;
  final String status;
  final int orderIndex;
  final String storyText;
  final String videoUrl;
  final double duration;
  final double qualityScore;
  final String qualityLabel;
  final String variantId;
  final String errorMessage;

  const PersonalizedBranchOption({
    required this.id,
    required this.optionKey,
    required this.label,
    required this.description,
    required this.intent,
    required this.status,
    required this.orderIndex,
    this.storyText = '',
    this.videoUrl = '',
    this.duration = 0,
    this.qualityScore = 0,
    this.qualityLabel = '',
    this.variantId = '',
    this.errorMessage = '',
  });

  bool get isReady => status == 'ready' && videoUrl.isNotEmpty;

  bool get canSelect =>
      status != 'review_required' &&
      status != 'submitting' &&
      status != 'downloading' &&
      status != 'transcoding' &&
      status != 'quality_checking';

  factory PersonalizedBranchOption.fromJson(Map<String, dynamic> json) {
    return PersonalizedBranchOption(
      id: (json['id'] ?? '') as String,
      optionKey: (json['option_key'] ?? '') as String,
      label: (json['label'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      intent: Map<String, dynamic>.from(json['intent'] ?? const {}),
      status: (json['status'] ?? 'planned') as String,
      orderIndex: ((json['order_idx'] ?? 0) as num).toInt(),
      storyText: (json['story_text'] ?? '') as String,
      videoUrl: (json['video_url'] ?? '') as String,
      duration: ((json['duration'] ?? 0) as num).toDouble(),
      qualityScore: ((json['quality_score'] ?? 0) as num).toDouble(),
      qualityLabel: (json['quality_label'] ?? '') as String,
      variantId: (json['variant_id'] ?? '') as String,
      errorMessage: (json['error_message'] ?? '') as String,
    );
  }
}

class PersonalizedBranchSession {
  final String sessionId;
  final String episodeId;
  final int? forkId;
  final int? highlightId;
  final String triggerSource;
  final double triggerTs;
  final double resumeAt;
  final String question;
  final String status;
  final List<PersonalizedBranchOption> options;

  const PersonalizedBranchSession({
    required this.sessionId,
    required this.episodeId,
    required this.triggerSource,
    required this.triggerTs,
    required this.resumeAt,
    required this.question,
    required this.status,
    required this.options,
    this.forkId,
    this.highlightId,
  });

  bool get isGenerating =>
      status == 'planned' ||
      status == 'generating' ||
      status == 'partially_ready';

  PersonalizedBranchOption? optionById(String optionId) {
    for (final option in options) {
      if (option.id == optionId) return option;
    }
    return null;
  }

  factory PersonalizedBranchSession.fromJson(Map<String, dynamic> json) {
    return PersonalizedBranchSession(
      sessionId: (json['session_id'] ?? '') as String,
      episodeId: (json['episode_id'] ?? '') as String,
      forkId: (json['fork_id'] as num?)?.toInt(),
      highlightId: (json['highlight_id'] as num?)?.toInt(),
      triggerSource: (json['trigger_source'] ?? 'highlight') as String,
      triggerTs: ((json['trigger_ts'] ?? 0) as num).toDouble(),
      resumeAt: ((json['resume_at'] ?? 0) as num).toDouble(),
      question: (json['question'] ?? '') as String,
      status: (json['status'] ?? 'planned') as String,
      options: ((json['options'] ?? const []) as List)
          .whereType<Map>()
          .map((item) => PersonalizedBranchOption.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(),
    );
  }
}

class BranchPlaybackTicket {
  final String sessionId;
  final String optionId;
  final String variantId;
  final String videoUrl;
  final double duration;
  final String mainVideoUrl;
  final double resumeAt;
  final String label;
  final String storyText;

  const BranchPlaybackTicket({
    required this.sessionId,
    required this.optionId,
    required this.variantId,
    required this.videoUrl,
    required this.duration,
    required this.mainVideoUrl,
    required this.resumeAt,
    required this.label,
    this.storyText = '',
  });

  factory BranchPlaybackTicket.fromJson(Map<String, dynamic> json) {
    return BranchPlaybackTicket(
      sessionId: (json['session_id'] ?? '') as String,
      optionId: (json['option_id'] ?? '') as String,
      variantId: (json['variant_id'] ?? '') as String,
      videoUrl: (json['video_url'] ?? '') as String,
      duration: ((json['duration'] ?? 0) as num).toDouble(),
      mainVideoUrl: (json['main_video_url'] ?? '') as String,
      resumeAt: ((json['resume_at'] ?? 0) as num).toDouble(),
      label: (json['label'] ?? '') as String,
      storyText: (json['story_text'] ?? '') as String,
    );
  }
}

class BranchSelectionResult {
  final String status;
  final PersonalizedBranchOption option;
  final BranchPlaybackTicket? playbackTicket;

  const BranchSelectionResult({
    required this.status,
    required this.option,
    this.playbackTicket,
  });

  factory BranchSelectionResult.fromJson(Map<String, dynamic> json) {
    final ticket = json['playback_ticket'];
    return BranchSelectionResult(
      status: (json['status'] ?? '') as String,
      option: PersonalizedBranchOption.fromJson(
        Map<String, dynamic>.from(json['option'] as Map),
      ),
      playbackTicket: ticket is Map
          ? BranchPlaybackTicket.fromJson(Map<String, dynamic>.from(ticket))
          : null,
    );
  }
}
