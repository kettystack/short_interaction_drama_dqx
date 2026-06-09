import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/router.dart';
import 'core/user_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.adjustForPlatform();

  // 初始化 media_kit（同 Kazumi）
  MediaKit.ensureInitialized();

  // 初始化 Hive 用于追剧/进度本地缓存
  // 容错：若 lock 文件被旧进程占用（多实例/崩溃后快速重启），等待最多 2 秒后重试
  if (kIsWeb) {
    await Hive.initFlutter();
  } else {
    final dir = await getApplicationDocumentsDirectory();
    Hive.init(dir.path);
  }
  const boxes = [
    'favorites',
    'progress',
    'user',
    'danmaku_settings',
    'interaction_queue',
    'interaction_history',
    'interactive_drama_progress',
    'media_durations',
  ];
  for (final name in boxes) {
    await _openBoxWithRetry(name);
  }
  await UserSession.init();

  const initialRoute = String.fromEnvironment('INITIAL_ROUTE');
  if (initialRoute.isNotEmpty) {
    Modular.setInitialRoute(initialRoute);
  }

  runApp(ModularApp(module: AppModule(), child: const SdiApp()));
}

/// 最多重试 4 次（间隔 500ms），适应旧进程释放 lock 的延迟。
Future<void> _openBoxWithRetry(String name, {int retries = 4}) async {
  for (var i = 0; i <= retries; i++) {
    try {
      await Hive.openBox(name);
      return;
    } on FileSystemException catch (e) {
      if (i == retries) rethrow;
      // errno 35 = EAGAIN：锁被占用，稍后重试
      final errno = e.osError?.errorCode ?? 0;
      if (errno != 35 && errno != 11) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 500 * (i + 1)));
    }
  }
}
