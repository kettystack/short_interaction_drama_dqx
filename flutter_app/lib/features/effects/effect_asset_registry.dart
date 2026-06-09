import 'package:flutter/foundation.dart';

import '../../data/api_client.dart';
import '../../data/models.dart';

class EffectAssetRegistry extends ChangeNotifier {
  EffectAssetRegistry(this._api);

  final ApiClient _api;
  InteractionEffectManifest? manifest;
  final Map<String, InteractionEffectAsset> _byAction = {};

  Future<void> load() async {
    manifest = await _api.getEffectManifest();
    _byAction.clear();
    for (final effect
        in manifest?.effects ?? const <InteractionEffectAsset>[]) {
      for (final action in effect.actions) {
        _byAction[action] = effect;
      }
    }
    notifyListeners();
  }

  InteractionEffectAsset? resolve(String action) => _byAction[action];
}
