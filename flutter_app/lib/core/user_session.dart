import 'dart:math';

import 'package:hive_ce/hive.dart';

class UserSession {
  UserSession._();

  static const boxName = 'user';
  static const _clientIdKey = 'client_id';
  static String userId = 'anon';

  static Future<void> init() async {
    final box = Hive.box(boxName);
    final existing = box.get(_clientIdKey);
    if (existing is String && existing.isNotEmpty) {
      userId = existing;
      return;
    }
    userId = _generateClientId();
    await box.put(_clientIdKey, userId);
  }

  static String _generateClientId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random = Random().nextInt(0xFFFFFF).toRadixString(36).padLeft(4, '0');
    return 'flutter-$now-$random';
  }
}
