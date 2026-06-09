import 'package:flutter_test/flutter_test.dart';
import 'package:sdi_flutter/features/branch_video/data/branch_video_models.dart';
import 'package:sdi_flutter/features/player/controllers/player_experience_coordinator.dart';

void main() {
  test('branch playback ticket keeps resume position', () {
    final ticket = BranchPlaybackTicket.fromJson({
      'session_id': 'pbs_1',
      'option_id': 'pbo_a',
      'variant_id': 'bvv_a',
      'video_url': '/generated/a.mp4',
      'duration': 12,
      'main_video_url': '/videos/main.mp4',
      'resume_at': 61,
      'label': '正面反击',
    });
    expect(ticket.videoUrl, '/generated/a.mp4');
    expect(ticket.mainVideoUrl, '/videos/main.mp4');
    expect(ticket.resumeAt, 61);
  });

  test('branch experience blocks boost and highlights', () {
    final coordinator = PlayerExperienceCoordinator();
    coordinator.sync(
      insertedClip: false,
      branchPending: true,
      branchGenerating: false,
      boostAvailable: true,
      highlightVisible: true,
    );
    expect(coordinator.state, PlayerExperienceState.branchChoice);
    expect(coordinator.blocksAmbientOverlays, isTrue);
    expect(coordinator.canShowBoost, isFalse);
    coordinator.dispose();
  });
}
