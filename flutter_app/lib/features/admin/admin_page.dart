import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/models.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _tokenController = TextEditingController(text: 'local-admin-token');
  final _episodeController = TextEditingController(text: 'ep_063');
  List<Highlight> _highlights = const [];
  List<HighlightGoldLabel> _goldLabels = const [];
  List<AigcVideoJob> _aigcJobs = const [];
  List<AigcBoostPoint> _boostPoints = const [];
  List<ClipAssetAdmin> _clipAssets = const [];
  List<AigcQualityCheckAdmin> _qualityChecks = const [];
  HighlightEvalRun? _evalRun;
  String? _error;
  bool _loading = false;

  ApiClient get _api => Modular.get<ApiClient>();

  @override
  void dispose() {
    _tokenController.dispose();
    _episodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgDeep,
        title: const Text('运营后台'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Expanded(
                child: _field(_episodeController, 'episode_id'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(_tokenController, 'admin token'),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _loading ? null : _load,
                child: Text(_loading ? '加载中' : '加载'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _loading ? null : _runEval,
                child: const Text('运行评测'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.accentHot)),
          ],
          const SizedBox(height: 18),
          _sectionTitle('预生成加速包 ${_boostPoints.length}'),
          if (_boostPoints.isEmpty)
            const Text('暂无已发布加速包',
                style: TextStyle(color: AppColors.textTertiary))
          else
            ..._boostPoints.take(12).map(
                  (point) => _row(
                    '${point.triggerTs.toStringAsFixed(1)}s',
                    '${point.title} · ${point.provider} · Q ${(point.qualityScore * 100).toStringAsFixed(0)}',
                    '回正片 ${point.resumeAt.toStringAsFixed(1)}s\n${point.outputVideoUrl}',
                  ),
                ),
          const SizedBox(height: 18),
          _sectionTitle('同集 Clip Assets ${_clipAssets.length}'),
          if (_clipAssets.isEmpty)
            const Text('暂无同集插片素材',
                style: TextStyle(color: AppColors.textTertiary))
          else
            ..._clipAssets.take(10).map(
                  (clip) => _row(
                    '${clip.tsStart.toStringAsFixed(1)}-${clip.tsEnd.toStringAsFixed(1)}s',
                    '${clip.source} · ${clip.status} · Q ${(clip.qualityScore * 100).toStringAsFixed(0)}',
                    '${[
                      ...clip.actionTags,
                      ...clip.emotionTags
                    ].join(' / ')}\n${clip.clipUrl}',
                  ),
                ),
          const SizedBox(height: 18),
          _sectionTitle('AIGC 插片任务 ${_aigcJobs.length}'),
          if (_aigcJobs.isEmpty)
            const Text('暂无插片任务',
                style: TextStyle(color: AppColors.textTertiary))
          else
            ..._aigcJobs.take(12).map(
                  _aigcJobRow,
                ),
          const SizedBox(height: 18),
          _sectionTitle('质量闸门 ${_qualityChecks.length}'),
          if (_qualityChecks.isEmpty)
            const Text('暂无质量校验记录',
                style: TextStyle(color: AppColors.textTertiary))
          else
            ..._qualityChecks.take(10).map(
                  (check) => _row(
                    check.finalDecision,
                    'Score ${(check.finalScore * 100).toStringAsFixed(0)} · ${check.jobId}',
                    check.reasons.join(' / '),
                  ),
                ),
          const SizedBox(height: 18),
          _sectionTitle('AI 高光 ${_highlights.length}'),
          ..._highlights.take(20).map(
                (h) => _row(
                  '${h.tsStart.toStringAsFixed(1)}-${h.tsEnd.toStringAsFixed(1)}s',
                  '${h.type} / ${h.interaction}',
                  h.summary,
                ),
              ),
          const SizedBox(height: 18),
          _sectionTitle('Gold Labels ${_goldLabels.length}'),
          ..._goldLabels.map(
            (g) => _row(
              '${g.tsStart.toStringAsFixed(1)}-${g.tsEnd.toStringAsFixed(1)}s',
              '${g.type} / ${g.interaction}',
              g.description,
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle('评测结果'),
          if (_evalRun == null)
            const Text('暂无评测结果',
                style: TextStyle(color: AppColors.textTertiary))
          else
            _row(
              'F1 ${(_evalRun!.f1 * 100).toStringAsFixed(1)}%',
              'P ${(_evalRun!.precision * 100).toStringAsFixed(1)}% / R ${(_evalRun!.recall * 100).toStringAsFixed(1)}%',
              'TP ${_evalRun!.truePositiveCount} / FP ${_evalRun!.falsePositiveCount} / FN ${_evalRun!.falseNegativeCount}',
            ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textTertiary),
        filled: true,
        fillColor: Colors.white.withValues(alpha: .08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _row(String lead, String title, String body) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child:
                Text(lead, style: const TextStyle(color: AppColors.accentGold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                if (body.isNotEmpty)
                  Text(body,
                      style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aigcJobRow(AigcVideoJob job) {
    final needsReview = job.status == 'review_required';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              job.status,
              style: TextStyle(
                color: needsReview
                    ? AppColors.accentGold
                    : AppColors.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${job.triggerType} · ${(job.progress * 100).toStringAsFixed(0)}% · '
                  'Q ${(job.qualityScore * 100).toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (job.prompt.isNotEmpty)
                  Text(
                    job.prompt,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                if (job.outputVideoUrl.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _previewJob(job),
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('预览'),
                      ),
                      if (needsReview)
                        FilledButton.icon(
                          onPressed:
                              _loading ? null : () => _reviewJob(job, true),
                          icon: const Icon(Icons.check),
                          label: const Text('通过'),
                        ),
                      if (needsReview)
                        OutlinedButton.icon(
                          onPressed:
                              _loading ? null : () => _reviewJob(job, false),
                          icon: const Icon(Icons.close),
                          label: const Text('拒绝'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _previewJob(AigcVideoJob job) {
    return showDialog<void>(
      context: context,
      builder: (_) => _AigcReviewDialog(job: job),
    );
  }

  Future<void> _reviewJob(AigcVideoJob job, bool approve) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.reviewAigcVideoJob(
        jobId: job.jobId,
        approve: approve,
        adminToken: _tokenController.text.trim(),
        reason: approve ? '运营后台人工确认通过' : '运营后台人工审核拒绝',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? '已通过候选视频' : '已拒绝候选视频')),
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final episodeId = _episodeController.text.trim();
      final adminToken = _tokenController.text.trim();
      final results = await Future.wait([
        _api.getHighlights(episodeId),
        _api.getGoldLabels(episodeId, adminToken: adminToken),
        _api.listAigcVideoJobs(
          episodeId: episodeId,
          adminToken: adminToken,
        ),
        _api.listAigcBoostPointsAdmin(
          episodeId: episodeId,
          adminToken: adminToken,
        ),
        _api.listClipAssets(
          episodeId: episodeId,
          adminToken: adminToken,
        ),
        _api.listAigcQualityChecks(
          adminToken: adminToken,
          limit: 20,
        ),
      ]);
      _highlights = results[0] as List<Highlight>;
      _goldLabels = results[1] as List<HighlightGoldLabel>;
      _aigcJobs = results[2] as List<AigcVideoJob>;
      _boostPoints = results[3] as List<AigcBoostPoint>;
      _clipAssets = results[4] as List<ClipAssetAdmin>;
      _qualityChecks = results[5] as List<AigcQualityCheckAdmin>;
    } catch (e) {
      _error = e.toString();
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _runEval() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _evalRun = await _api.runHighlightEvaluation(
        episodeId: _episodeController.text.trim(),
        adminToken: _tokenController.text.trim(),
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      setState(() => _loading = false);
    }
  }
}

class _AigcReviewDialog extends StatefulWidget {
  const _AigcReviewDialog({required this.job});

  final AigcVideoJob job;

  @override
  State<_AigcReviewDialog> createState() => _AigcReviewDialogState();
}

class _AigcReviewDialogState extends State<_AigcReviewDialog> {
  late final Player _player;
  late final VideoController _videoController;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    unawaited(
      _player.open(
        Media(AppConfig.absoluteUrl(widget.job.outputVideoUrl)),
        play: true,
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'AIGC 候选预览 · ${widget.job.status}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Video(
                            controller: _videoController,
                            controls: NoVideoControls,
                            fit: BoxFit.contain,
                          ),
                        ),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: IconButton.filledTonal(
                            tooltip: '播放或暂停',
                            onPressed: _player.playOrPause,
                            icon: const Icon(Icons.play_arrow),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '质量 ${(widget.job.qualityScore * 100).toStringAsFixed(0)} · '
                '${widget.job.qualityDecision} · ${widget.job.duration.toStringAsFixed(1)}s',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
