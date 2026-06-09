import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/config.dart';

typedef InteractionMessageHandler = void Function(Map<String, dynamic> message);
typedef PresenceHandler = void Function(int onlineCount);
typedef SocketStateHandler = void Function(String state);

class InteractionSocketClient {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  String? _episodeId;
  bool _closedByOwner = true;
  int _attempt = 0;

  PresenceHandler? onPresence;
  InteractionMessageHandler? onInteraction;
  SocketStateHandler? onState;

  void connect(
    String episodeId, {
    PresenceHandler? onPresence,
    InteractionMessageHandler? onInteraction,
    SocketStateHandler? onState,
  }) {
    close();
    _episodeId = episodeId;
    this.onPresence = onPresence;
    this.onInteraction = onInteraction;
    this.onState = onState;
    _closedByOwner = false;
    _attempt = 0;
    _open();
  }

  void _open() {
    final episodeId = _episodeId;
    if (episodeId == null || _closedByOwner) return;
    _clearConnection();
    onState?.call('connecting');

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse(AppConfig.interactionSocketUrl(episodeId)),
      );
      onState?.call('open');
      _attempt = 0;
      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _channel?.sink.add('ping');
        } catch (_) {}
      });
      _subscription = _channel!.stream.listen(
        _handleRawMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _handleRawMessage(dynamic raw) {
    try {
      final decoded = jsonDecode('$raw');
      if (decoded is! Map<String, dynamic>) return;
      final type = decoded['type'];
      if (type == 'presence') {
        final count = decoded['online_count'];
        onPresence
            ?.call(count is num ? count.toInt().clamp(1, 999999).toInt() : 1);
        return;
      }
      if (type == 'interaction') {
        onInteraction?.call(decoded);
      }
    } catch (_) {}
  }

  void _scheduleReconnect() {
    if (_closedByOwner) return;
    _clearConnection();
    onState?.call('closed');
    final delayMs = (1000 * (1 << _attempt)).clamp(1000, 10000).toInt();
    _attempt = (_attempt + 1).clamp(0, 6);
    _reconnectTimer ??= Timer(Duration(milliseconds: delayMs), () {
      _reconnectTimer = null;
      _open();
    });
  }

  void _clearConnection() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void close() {
    _closedByOwner = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _clearConnection();
    onState?.call('closed');
  }
}
