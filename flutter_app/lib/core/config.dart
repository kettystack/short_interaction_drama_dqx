import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  /// 后端基址：模拟器走 10.0.2.2 / 真机请通过 env 注入
  static String apiBaseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static Map<String, String> get defaultHeaders {
    if (apiBaseUrl.contains('.ngrok-free.')) {
      return {'ngrok-skip-browser-warning': 'true'};
    }
    return const {};
  }

  static String absoluteUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    // 把 query 部分与 path 分开，只对 path segments 做 percent-encode
    // 以便中文文件名（如「第1集.mp4」）能被媒体播放器正常解析
    final qIdx = path.indexOf('?');
    final pathOnly = qIdx >= 0 ? path.substring(0, qIdx) : path;
    final query = qIdx >= 0 ? path.substring(qIdx) : '';
    final clean = pathOnly.startsWith('/') ? pathOnly.substring(1) : pathOnly;
    final encoded = clean.split('/').map(Uri.encodeComponent).join('/');
    final base = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    return '$base/$encoded$query';
  }

  static String get webSocketBaseUrl {
    final uri = Uri.parse(apiBaseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return uri
        .replace(scheme: scheme)
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
  }

  static String interactionSocketUrl(String episodeId) =>
      '$webSocketBaseUrl/api/interactions/ws/$episodeId';

  /// 在 Android 模拟器上 localhost 不可达
  static void adjustForPlatform() {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        apiBaseUrl.contains('127.0.0.1')) {
      apiBaseUrl = apiBaseUrl.replaceAll('127.0.0.1', '10.0.2.2');
    }
  }
}
