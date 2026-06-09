class InteractiveDramaState {
  final int reputation;
  final int disguise;
  final int power;
  final int suspicion;
  final int romance;
  final int justice;
  final int heroine;
  final int oldFriend;
  final int emperor;
  final int mastermind;
  final List<String> routeTags;
  final Map<String, bool> flags;

  const InteractiveDramaState({
    this.reputation = 0,
    this.disguise = 100,
    this.power = 0,
    this.suspicion = 0,
    this.romance = 0,
    this.justice = 0,
    this.heroine = 0,
    this.oldFriend = 0,
    this.emperor = 0,
    this.mastermind = 0,
    this.routeTags = const [],
    this.flags = const {},
  });

  factory InteractiveDramaState.fromJson(Map<String, dynamic> json) {
    final rawFlags = Map<String, dynamic>.from(json['flags'] ?? const {});
    return InteractiveDramaState(
      reputation: ((json['reputation'] ?? 0) as num).toInt(),
      disguise: ((json['disguise'] ?? 100) as num).toInt(),
      power: ((json['power'] ?? 0) as num).toInt(),
      suspicion: ((json['suspicion'] ?? 0) as num).toInt(),
      romance: ((json['romance'] ?? 0) as num).toInt(),
      justice: ((json['justice'] ?? 0) as num).toInt(),
      heroine: ((json['heroine'] ?? 0) as num).toInt(),
      oldFriend: ((json['old_friend'] ?? 0) as num).toInt(),
      emperor: ((json['emperor'] ?? 0) as num).toInt(),
      mastermind: ((json['mastermind'] ?? 0) as num).toInt(),
      routeTags: List<String>.from(json['route_tags'] ?? const []),
      flags: rawFlags.map((key, value) => MapEntry(key, value == true)),
    );
  }
}

class InteractiveOption {
  final String optionId;
  final String label;
  final String description;
  final Map<String, dynamic> condition;
  final Map<String, int> stateDelta;
  final Map<String, bool> flagsDelta;
  final List<String> routeTags;
  final String branchVideoUrl;
  final double branchStartAt;
  final double branchDuration;
  final String branchVideoSessionHint;

  const InteractiveOption({
    required this.optionId,
    required this.label,
    this.description = '',
    this.condition = const {},
    this.stateDelta = const {},
    this.flagsDelta = const {},
    this.routeTags = const [],
    this.branchVideoUrl = '',
    this.branchStartAt = 0,
    this.branchDuration = 0,
    this.branchVideoSessionHint = '',
  });

  factory InteractiveOption.fromJson(Map<String, dynamic> json) {
    final rawDelta = Map<String, dynamic>.from(json['state_delta'] ?? const {});
    final rawFlags = Map<String, dynamic>.from(json['flags_delta'] ?? const {});
    final rawCondition =
        Map<String, dynamic>.from(json['condition'] ?? const {});
    return InteractiveOption(
      optionId: (json['option_id'] ?? '') as String,
      label: (json['label'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      condition: rawCondition,
      stateDelta:
          rawDelta.map((key, value) => MapEntry(key, (value as num).toInt())),
      flagsDelta: rawFlags.map((key, value) => MapEntry(key, value == true)),
      routeTags: List<String>.from(json['route_tags'] ?? const []),
      branchVideoUrl: (json['branch_video_url'] ?? '') as String,
      branchStartAt: ((json['branch_start_at'] ?? 0) as num).toDouble(),
      branchDuration: ((json['branch_duration'] ?? 0) as num).toDouble(),
      branchVideoSessionHint:
          (json['branch_video_session_hint'] ?? '') as String,
    );
  }
}

class InteractiveNode {
  final String nodeId;
  final String episodeId;
  final double tsInVideo;
  final double resumeAt;
  final String question;
  final String context;
  final List<InteractiveOption> options;

  const InteractiveNode({
    required this.nodeId,
    required this.episodeId,
    required this.question,
    this.tsInVideo = 0,
    this.resumeAt = 0,
    this.context = '',
    this.options = const [],
  });

  factory InteractiveNode.fromJson(Map<String, dynamic> json) {
    return InteractiveNode(
      nodeId: (json['node_id'] ?? '') as String,
      episodeId: (json['episode_id'] ?? '') as String,
      tsInVideo: ((json['ts_in_video'] ?? 0) as num).toDouble(),
      resumeAt: ((json['resume_at'] ?? 0) as num).toDouble(),
      question: (json['question'] ?? '') as String,
      context: (json['context'] ?? '') as String,
      options: ((json['options'] ?? const []) as List)
          .whereType<Map>()
          .map((item) =>
              InteractiveOption.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}

class InteractiveEnding {
  final String endingId;
  final String title;
  final String summary;
  final String category;

  const InteractiveEnding({
    required this.endingId,
    required this.title,
    required this.summary,
    this.category = '通关结局',
  });

  factory InteractiveEnding.fromJson(Map<String, dynamic> json) {
    return InteractiveEnding(
      endingId: (json['ending_id'] ?? '') as String,
      title: (json['title'] ?? '') as String,
      summary: (json['summary'] ?? '') as String,
      category: (json['category'] ?? '通关结局') as String,
    );
  }
}

class InteractiveRun {
  final String runId;
  final String dramaId;
  final String title;
  final String version;
  final String userId;
  final String currentEpisodeId;
  final String? currentNodeId;
  final InteractiveDramaState state;
  final List<Map<String, dynamic>> selectedPath;
  final InteractiveNode? activeNode;
  final InteractiveEnding? ending;
  final String status;

  const InteractiveRun({
    required this.runId,
    required this.dramaId,
    required this.title,
    required this.version,
    required this.userId,
    required this.currentEpisodeId,
    this.currentNodeId,
    required this.state,
    this.selectedPath = const [],
    this.activeNode,
    this.ending,
    this.status = 'active',
  });

  factory InteractiveRun.fromJson(Map<String, dynamic> json) {
    final activeNode = json['active_node'];
    final ending = json['ending'];
    return InteractiveRun(
      runId: (json['run_id'] ?? '') as String,
      dramaId: (json['drama_id'] ?? '') as String,
      title: (json['title'] ?? '') as String,
      version: (json['version'] ?? '') as String,
      userId: (json['user_id'] ?? '') as String,
      currentEpisodeId: (json['current_episode_id'] ?? '') as String,
      currentNodeId: json['current_node_id'] as String?,
      state: InteractiveDramaState.fromJson(
        Map<String, dynamic>.from(json['state'] ?? const {}),
      ),
      selectedPath: ((json['selected_path'] ?? const []) as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      activeNode: activeNode is Map
          ? InteractiveNode.fromJson(Map<String, dynamic>.from(activeNode))
          : null,
      ending: ending is Map
          ? InteractiveEnding.fromJson(Map<String, dynamic>.from(ending))
          : null,
      status: (json['status'] ?? 'active') as String,
    );
  }
}

class InteractiveChooseResult {
  final InteractiveRun run;
  final String storyText;
  final Map<String, int> stateChanges;
  final InteractiveNode? nextNode;
  final InteractiveEnding? ending;

  const InteractiveChooseResult({
    required this.run,
    required this.storyText,
    this.stateChanges = const {},
    this.nextNode,
    this.ending,
  });

  factory InteractiveChooseResult.fromJson(Map<String, dynamic> json) {
    final rawChanges =
        Map<String, dynamic>.from(json['state_changes'] ?? const {});
    final nextNode = json['next_node'];
    final ending = json['ending'];
    return InteractiveChooseResult(
      run: InteractiveRun.fromJson(
          Map<String, dynamic>.from(json['run'] as Map)),
      storyText: (json['story_text'] ?? '') as String,
      stateChanges:
          rawChanges.map((key, value) => MapEntry(key, (value as num).toInt())),
      nextNode: nextNode is Map
          ? InteractiveNode.fromJson(Map<String, dynamic>.from(nextNode))
          : null,
      ending: ending is Map
          ? InteractiveEnding.fromJson(Map<String, dynamic>.from(ending))
          : null,
    );
  }
}
