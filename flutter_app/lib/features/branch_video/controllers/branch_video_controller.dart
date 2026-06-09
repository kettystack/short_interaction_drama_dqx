import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../data/branch_video_api.dart';
import '../data/branch_video_models.dart';

class BranchVideoController extends ChangeNotifier {
  BranchVideoController(this._api);

  static const double prewarmLeadSeconds = 60;
  static const double triggerWindowSeconds = 12;

  final BranchVideoApi _api;
  final Set<String> _handledSessionIds = <String>{};
  final Set<String> _prewarmingSessionIds = <String>{};
  final Set<String> _refreshingSessionIds = <String>{};
  Timer? _pollTimer;
  bool _disposed = false;
  bool _checkingSelection = false;

  List<PersonalizedBranchSession> sessions = const [];
  PersonalizedBranchSession? pendingSession;
  String? selectedOptionId;
  BranchPlaybackTicket? pendingPlaybackTicket;
  bool isLoading = false;
  bool isSubmitting = false;
  String? error;

  bool get hasBlockingExperience => pendingSession != null;

  Future<void> loadFor(String episodeId) async {
    _pollTimer?.cancel();
    sessions = const [];
    pendingSession = null;
    selectedOptionId = null;
    pendingPlaybackTicket = null;
    error = null;
    isLoading = true;
    _handledSessionIds.clear();
    _prewarmingSessionIds.clear();
    _refreshingSessionIds.clear();
    _safeNotify();
    try {
      sessions = await _api.listEpisodeSessions(episodeId);
      sessions = [...sessions]
        ..sort((a, b) => a.triggerTs.compareTo(b.triggerTs));
    } catch (exception) {
      error = '个性化分支加载失败：$exception';
    } finally {
      isLoading = false;
      _safeNotify();
    }
  }

  void onTick(double seconds) {
    if (_disposed) return;
    for (final session in sessions) {
      final untilTrigger = session.triggerTs - seconds;
      if (untilTrigger <= prewarmLeadSeconds &&
          untilTrigger >= 0 &&
          !_prewarmingSessionIds.contains(session.sessionId) &&
          session.status != 'ready') {
        unawaited(_prewarm(session));
      }
    }
    if (pendingSession != null) return;
    for (final session in sessions) {
      if (_handledSessionIds.contains(session.sessionId)) continue;
      if (seconds >= session.triggerTs &&
          seconds <= session.triggerTs + triggerWindowSeconds) {
        pendingSession = session;
        selectedOptionId = null;
        error = null;
        _safeNotify();
        unawaited(_refreshSession(session.sessionId));
        return;
      }
    }
  }

  Future<void> selectOption(PersonalizedBranchOption option) async {
    final session = pendingSession;
    if (_disposed || session == null || isSubmitting) return;
    selectedOptionId = option.id;
    isSubmitting = true;
    error = null;
    _safeNotify();
    try {
      final result = await _api.selectOption(
        sessionId: session.sessionId,
        optionId: option.id,
        clientEventId:
            '${session.sessionId}:${option.id}:${DateTime.now().microsecondsSinceEpoch}',
      );
      _replaceOption(session.sessionId, result.option);
      pendingPlaybackTicket = result.playbackTicket;
      if (result.playbackTicket == null) {
        _startPolling();
      }
    } catch (exception) {
      error = '分支生成失败：$exception';
    } finally {
      isSubmitting = false;
      _safeNotify();
    }
  }

  Future<void> createCustomOption(String prompt) async {
    final value = prompt.trim();
    final session = pendingSession;
    if (_disposed || session == null || value.isEmpty || isSubmitting) return;
    isSubmitting = true;
    error = null;
    _safeNotify();
    try {
      final updated = await _api.createCustomOption(
        sessionId: session.sessionId,
        prompt: value,
      );
      _replaceSession(updated);
      pendingSession = updated;
      final custom = updated.options.isEmpty ? null : updated.options.last;
      if (custom != null) {
        selectedOptionId = custom.id;
        _startPolling();
      }
    } catch (exception) {
      error = '自定义剧情提交失败：$exception';
    } finally {
      isSubmitting = false;
      _safeNotify();
    }
  }

  void skipPending() {
    final session = pendingSession;
    if (session != null) {
      _handledSessionIds.add(session.sessionId);
    }
    pendingSession = null;
    selectedOptionId = null;
    pendingPlaybackTicket = null;
    _pollTimer?.cancel();
    _safeNotify();
  }

  void markPlaybackStarted(BranchPlaybackTicket ticket) {
    _handledSessionIds.add(ticket.sessionId);
    pendingSession = null;
    selectedOptionId = null;
    pendingPlaybackTicket = null;
    _pollTimer?.cancel();
    _safeNotify();
  }

  Future<void> recordPlaybackEvent(
    BranchPlaybackTicket ticket,
    String eventType, {
    double clipPosition = 0,
  }) async {
    try {
      await _api.recordEvent(
        ticket: ticket,
        eventType: eventType,
        tsInMainVideo: ticket.resumeAt,
        clipPosition: clipPosition,
      );
    } catch (_) {}
  }

  Future<void> _prewarm(PersonalizedBranchSession session) async {
    if (!_prewarmingSessionIds.add(session.sessionId)) return;
    try {
      final updated = await _api.prewarm(session.sessionId);
      _replaceSession(updated);
      if (pendingSession?.sessionId == updated.sessionId) {
        pendingSession = updated;
      }
    } catch (_) {
      _prewarmingSessionIds.remove(session.sessionId);
    }
    _safeNotify();
  }

  Future<void> _refreshSession(String sessionId) async {
    if (!_refreshingSessionIds.add(sessionId)) return;
    try {
      final updated = await _api.getSession(sessionId);
      _replaceSession(updated);
      if (pendingSession?.sessionId == sessionId) {
        pendingSession = updated;
      }
      error = null;
      await _checkSelectedOption(updated);
    } catch (exception) {
      error = _friendlyRefreshError(exception);
    } finally {
      _refreshingSessionIds.remove(sessionId);
    }
    _safeNotify();
  }

  Future<void> _checkSelectedOption(
    PersonalizedBranchSession session,
  ) async {
    final optionId = selectedOptionId;
    if (optionId == null || _checkingSelection) return;
    final option = session.optionById(optionId);
    if (option == null) return;
    if (option.status == 'failed') {
      error =
          option.errorMessage.isEmpty ? '该分支生成失败，可重新选择' : option.errorMessage;
      _pollTimer?.cancel();
      return;
    }
    if (!option.isReady) {
      _startPolling();
      return;
    }
    _checkingSelection = true;
    try {
      final result = await _api.selectOption(
        sessionId: session.sessionId,
        optionId: option.id,
        clientEventId: '${session.sessionId}:${option.id}:ready',
      );
      pendingPlaybackTicket = result.playbackTicket;
      if (pendingPlaybackTicket != null) {
        _pollTimer?.cancel();
      }
    } finally {
      _checkingSelection = false;
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final session = pendingSession;
      if (session != null) {
        unawaited(_refreshSession(session.sessionId));
      }
    });
  }

  void _replaceOption(
    String sessionId,
    PersonalizedBranchOption updated,
  ) {
    final session = sessions
        .cast<PersonalizedBranchSession?>()
        .firstWhere((item) => item?.sessionId == sessionId, orElse: () => null);
    if (session == null) return;
    final options = session.options
        .map((item) => item.id == updated.id ? updated : item)
        .toList();
    final updatedSession = PersonalizedBranchSession(
      sessionId: session.sessionId,
      episodeId: session.episodeId,
      forkId: session.forkId,
      highlightId: session.highlightId,
      triggerSource: session.triggerSource,
      triggerTs: session.triggerTs,
      resumeAt: session.resumeAt,
      question: session.question,
      status: session.status,
      options: options,
    );
    _replaceSession(updatedSession);
    if (pendingSession?.sessionId == sessionId) {
      pendingSession = updatedSession;
    }
  }

  void _replaceSession(PersonalizedBranchSession updated) {
    sessions = sessions
        .map((item) => item.sessionId == updated.sessionId ? updated : item)
        .toList();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  String _friendlyRefreshError(Object exception) {
    if (exception is DioException) {
      final code = exception.response?.statusCode;
      if (code != null && code >= 500) {
        return '生成服务暂时繁忙，正在自动重试';
      }
      if (code == 429) {
        return '生成任务较多，正在排队处理';
      }
    }
    return '分支状态暂时无法更新，正在自动重试';
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }
}
