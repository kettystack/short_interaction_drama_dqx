import 'dart:async';

import 'package:canvas_danmaku/canvas_danmaku.dart' hide DanmakuItem;
import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';

import '../../../data/api_client.dart';
import '../../../data/models.dart';
import 'danmaku_text.dart';

class DanmakuDisplayMode {
  static const standard = 'standard';
  static const compact = 'compact';

  static String normalize(String value) {
    return value == compact ? compact : standard;
  }
}

/// 仿 Kazumi `PlayerDanmakuController`：封装 canvas_danmaku 引擎。
/// 关注：拉取数据 / tick 时机投递 / 屏蔽词 / 节流 / 字体大小
class DanmakuPlayerController extends ChangeNotifier {
  DanmakuPlayerController(this._api) {
    _loadSettings();
  }

  final ApiClient _api;
  DanmakuController? engine;
  List<DanmakuItem> _items = const [];
  int _emitIndex = 0;
  bool enabled = true;
  String displayMode = DanmakuDisplayMode.standard;
  double fontSize = 16;
  double opacity = .85;
  double speed = 1.0;
  double area = 1.0;
  double duration = 8.0;
  double timeOffset = 0.0;
  bool showTop = true;
  bool showBottom = true;
  bool showScroll = true;
  bool followSpeed = true;
  double lineHeight = 1.6;
  bool _remoteLoaded = false;
  bool _disposed = false;
  bool _shouldRun = false;
  double _playbackRate = 1.0;
  Duration _lastTickPosition = Duration.zero;
  Timer? _remoteSyncDebounce;

  /// Kazumi 同款屏蔽词集合
  final Set<String> blockedWords = {};

  Box get _settingsBox => Hive.box('danmaku_settings');

  void _loadSettings() {
    enabled = _settingsBox.get('enabled', defaultValue: true) == true;
    displayMode = DanmakuDisplayMode.normalize(
      _settingsBox
          .get('display_mode', defaultValue: DanmakuDisplayMode.standard)
          .toString(),
    );
    fontSize =
        (_settingsBox.get('font_size', defaultValue: 16.0) as num).toDouble();
    opacity =
        (_settingsBox.get('opacity', defaultValue: .85) as num).toDouble();
    speed = (_settingsBox.get('speed', defaultValue: 1.0) as num).toDouble();
    area = (_settingsBox.get('area', defaultValue: 1.0) as num).toDouble();
    duration =
        (_settingsBox.get('duration', defaultValue: 8.0) as num).toDouble();
    timeOffset =
        (_settingsBox.get('time_offset', defaultValue: 0.0) as num).toDouble();
    showTop = _settingsBox.get('show_top', defaultValue: true) == true;
    showBottom = _settingsBox.get('show_bottom', defaultValue: true) == true;
    showScroll = _settingsBox.get('show_scroll', defaultValue: true) == true;
    followSpeed = _settingsBox.get('follow_speed', defaultValue: true) == true;
    lineHeight =
        (_settingsBox.get('line_height', defaultValue: 1.6) as num).toDouble();
    final words = _settingsBox.get('blocked_words', defaultValue: const []);
    if (words is List) blockedWords.addAll(words.map((e) => e.toString()));
  }

  DanmakuSettings get settings => DanmakuSettings(
        enabled: enabled,
        displayMode: displayMode,
        fontSize: fontSize,
        opacity: opacity,
        speed: speed,
        area: area,
        duration: duration,
        timeOffset: timeOffset,
        showTop: showTop,
        showBottom: showBottom,
        showScroll: showScroll,
        followSpeed: followSpeed,
        lineHeight: lineHeight,
        blockedWords: blockedWords.toList(),
      );

  bool get compactMode => displayMode == DanmakuDisplayMode.compact;

  DanmakuOption get option {
    final durationScale = (speed * (followSpeed ? _playbackRate : 1.0))
        .clamp(0.25, 4.0)
        .toDouble();
    final effectiveArea = compactMode ? area.clamp(0.1, 0.42).toDouble() : area;
    return DanmakuOption(
      fontSize: fontSize,
      opacity: opacity,
      area: effectiveArea,
      duration: (duration / durationScale).clamp(2.0, 16.0).toDouble(),
      hideTop: !showTop,
      hideBottom: compactMode || !showBottom,
      hideScroll: !showScroll,
      lineHeight: lineHeight,
    );
  }

  void _applyRuntimeSettings({bool resetTimeline = true}) {
    final current = engine;
    if (current == null) return;
    current.updateOption(option);
    current.clear();
    if (!enabled) {
      current.pause();
      return;
    }
    if (resetTimeline) {
      resetTo(_lastTickPosition, lookBehindSeconds: .6);
    }
    if (_shouldRun) {
      current.resume();
    } else {
      current.pause();
    }
  }

  void _commitSettings({bool syncRemote = true, bool resetTimeline = true}) {
    _saveSettings(syncRemote: syncRemote);
    _applyRuntimeSettings(resetTimeline: resetTimeline);
    _safeNotify();
  }

  void _saveSettings({bool syncRemote = true}) {
    _settingsBox.putAll({
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
      'blocked_words': blockedWords.toList(),
    });
    if (!syncRemote) return;
    // 用户在面板上拖滑块/连点屏蔽词会高频触发；这里做 500ms debounce，
    // 避免对后端 PUT /api/danmaku/settings/* 造成洪流式调用。
    _remoteSyncDebounce?.cancel();
    _remoteSyncDebounce = Timer(const Duration(milliseconds: 500), () {
      if (_disposed) return;
      final snapshot = settings;
      unawaited(
        _api.saveDanmakuSettings(snapshot).then((_) {}).catchError((_) {}),
      );
    });
  }

  void _applySettings(DanmakuSettings value) {
    enabled = value.enabled;
    displayMode = DanmakuDisplayMode.normalize(value.displayMode);
    fontSize = value.fontSize;
    opacity = value.opacity;
    speed = value.speed;
    area = value.area;
    duration = value.duration;
    timeOffset = value.timeOffset;
    showTop = value.showTop;
    showBottom = value.showBottom;
    showScroll = value.showScroll;
    followSpeed = value.followSpeed;
    lineHeight = value.lineHeight;
    blockedWords
      ..clear()
      ..addAll(value.blockedWords);
  }

  Future<void> _syncRemoteSettingsOnce() async {
    if (_disposed || _remoteLoaded) return;
    _remoteLoaded = true;
    try {
      final remote = await _api.getDanmakuSettings();
      if (_disposed) return;
      _applySettings(remote);
      _saveSettings(syncRemote: false);
      _applyRuntimeSettings();
      _safeNotify();
    } catch (_) {}
  }

  void attach(DanmakuController c) {
    if (_disposed) return;
    engine = c;
    c.updateOption(option);
    if (!enabled) {
      c.clear();
      c.pause();
      return;
    }
    if (_shouldRun) {
      c.resume();
    } else {
      c.pause();
    }
  }

  Future<void> loadFor(String episodeId) async {
    await _syncRemoteSettingsOnce();
    if (_disposed) return;
    final list = await _api.getDanmaku(episodeId);
    if (_disposed) return;
    list.sort((a, b) => a.ts.compareTo(b.ts));
    _items = list;
    _emitIndex = 0;
  }

  /// 由 PlaybackController.position 触发
  void onTick(Duration now) {
    if (_disposed) return;
    _lastTickPosition = now;
    if (!enabled || engine == null) return;
    final secs = now.inMilliseconds / 1000.0 + timeOffset;
    if (secs < 0) return;
    while (_emitIndex < _items.length && _items[_emitIndex].ts <= secs) {
      _emit(_items[_emitIndex++]);
    }
  }

  /// seek 后重新定位下一条
  void resetTo(Duration now, {double lookBehindSeconds = 0}) {
    if (_disposed) return;
    _lastTickPosition = now;
    final secs = now.inMilliseconds / 1000.0 + timeOffset - lookBehindSeconds;
    engine?.clear();
    _emitIndex = _items.indexWhere((d) => d.ts > secs);
    if (_emitIndex < 0) _emitIndex = _items.length;
  }

  void _emit(DanmakuItem item) {
    if (_disposed) return;
    final displayText = normalizeDanmakuDisplayText(item.content);
    if (blockedWords.any(item.content.contains) ||
        blockedWords.any(displayText.contains)) {
      return;
    }
    engine?.addDanmaku(DanmakuContentItem(
      displayText,
      color: Color(item.color),
      type: item.mode == 0
          ? DanmakuItemType.scroll
          : item.mode == 1
              ? DanmakuItemType.top
              : DanmakuItemType.bottom,
    ));
  }

  void sendSelf(String text, {int color = 0xFFFFFFFF}) {
    if (_disposed) return;
    engine?.addDanmaku(DanmakuContentItem(
      normalizeDanmakuDisplayText(text),
      color: Color(color),
      selfSend: true,
    ));
  }

  void setPlaybackRunning(bool running) {
    if (_disposed) return;
    _shouldRun = running;
    final current = engine;
    if (current == null) return;
    if (!enabled || !running) {
      current.pause();
      return;
    }
    current.resume();
  }

  void setPlaybackRate(double rate) {
    if (_disposed) return;
    _playbackRate = rate.clamp(0.25, 4.0).toDouble();
    _applyRuntimeSettings(resetTimeline: false);
    _safeNotify();
  }

  void setEnabled(bool v) {
    if (_disposed) return;
    enabled = v;
    _commitSettings(resetTimeline: v);
  }

  void setDisplayMode(String mode) {
    if (_disposed) return;
    displayMode = DanmakuDisplayMode.normalize(mode);
    _commitSettings();
  }

  void setStyle({double? fontSize, double? opacity, double? speed}) {
    if (_disposed) return;
    if (fontSize != null) this.fontSize = fontSize;
    if (opacity != null) this.opacity = opacity;
    if (speed != null) this.speed = speed;
    _commitSettings();
  }

  void setDisplay({double? area, double? duration, double? lineHeight}) {
    if (_disposed) return;
    if (area != null) this.area = area;
    if (duration != null) this.duration = duration;
    if (lineHeight != null) this.lineHeight = lineHeight;
    _commitSettings();
  }

  void setTimeline({double? timeOffset, bool? followSpeed}) {
    if (_disposed) return;
    if (timeOffset != null) this.timeOffset = timeOffset;
    if (followSpeed != null) this.followSpeed = followSpeed;
    _commitSettings();
  }

  void setVisibility({bool? top, bool? bottom, bool? scroll}) {
    if (_disposed) return;
    if (top != null) showTop = top;
    if (bottom != null) showBottom = bottom;
    if (scroll != null) showScroll = scroll;
    _commitSettings();
  }

  void addBlockedWord(String word) {
    if (_disposed) return;
    final value = word.trim();
    if (value.isEmpty) return;
    blockedWords.add(value);
    _commitSettings();
  }

  void removeBlockedWord(String word) {
    if (_disposed) return;
    blockedWords.remove(word);
    _commitSettings();
  }

  void resetSettings() {
    if (_disposed) return;
    enabled = true;
    displayMode = DanmakuDisplayMode.standard;
    fontSize = 16;
    opacity = .85;
    speed = 1.0;
    area = 1.0;
    duration = 8.0;
    timeOffset = 0.0;
    showTop = true;
    showBottom = true;
    showScroll = true;
    followSpeed = true;
    lineHeight = 1.6;
    blockedWords.clear();
    _remoteSyncDebounce?.cancel();
    _applyRuntimeSettings();
    _saveSettings(syncRemote: false);
    unawaited(_api.resetDanmakuSettings().then((_) {}).catchError((_) {}));
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _remoteSyncDebounce?.cancel();
    engine?.clear();
    engine = null;
    super.dispose();
  }
}
