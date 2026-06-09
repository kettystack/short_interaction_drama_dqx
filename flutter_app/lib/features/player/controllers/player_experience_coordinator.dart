import 'package:flutter/foundation.dart';

enum PlayerExperienceState {
  idle,
  highlight,
  branchChoice,
  branchGenerating,
  insertedClip,
  boost,
  storyChat,
}

class PlayerExperienceCoordinator extends ChangeNotifier {
  PlayerExperienceState state = PlayerExperienceState.idle;

  bool get blocksAmbientOverlays =>
      state == PlayerExperienceState.branchChoice ||
      state == PlayerExperienceState.branchGenerating ||
      state == PlayerExperienceState.insertedClip;

  bool get canShowBoost =>
      state == PlayerExperienceState.idle ||
      state == PlayerExperienceState.boost ||
      state == PlayerExperienceState.highlight;

  void sync({
    required bool insertedClip,
    required bool branchPending,
    required bool branchGenerating,
    required bool boostAvailable,
    required bool highlightVisible,
  }) {
    final next = insertedClip
        ? PlayerExperienceState.insertedClip
        : branchPending
            ? branchGenerating
                ? PlayerExperienceState.branchGenerating
                : PlayerExperienceState.branchChoice
            : boostAvailable
                ? PlayerExperienceState.boost
                : highlightVisible
                    ? PlayerExperienceState.highlight
                    : PlayerExperienceState.idle;
    if (next == state) return;
    state = next;
    notifyListeners();
  }
}
