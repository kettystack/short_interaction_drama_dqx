import 'package:flutter/foundation.dart';

import '../../data/api_client.dart';
import '../../data/models.dart';

class HomeController extends ChangeNotifier {
  HomeController(this._api);

  final ApiClient _api;
  static const _dramaOrder = [
    'beipaixunbao',
    'tianxiadyi',
    'shibasuitainainai',
  ];

  List<DramaGroup> groups = [];
  bool isLoading = false;
  String? errorMessage;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final all = await _api.getEpisodes();
      final grouped = <String, List<Episode>>{};
      for (final e in all) {
        grouped.putIfAbsent(e.dramaId, () => []).add(e);
      }
      final sortedKeys = grouped.keys.toList()
        ..sort((a, b) {
          final ia = _dramaOrder.indexOf(a);
          final ib = _dramaOrder.indexOf(b);
          return (ia == -1 ? 1 << 30 : ia) - (ib == -1 ? 1 << 30 : ib);
        });
      groups = sortedKeys.map((id) {
        final eps = grouped[id]!
          ..sort((a, b) => a.episodeNo.compareTo(b.episodeNo));
        final meta = DramaMeta.info(id);
        return DramaGroup(
          dramaId: id,
          dramaName: meta['name'] as String,
          genres: List<String>.from(meta['genres'] as List),
          tagline: meta['tagline'] as String,
          isOngoing: meta['ongoing'] as bool,
          episodes: eps,
        );
      }).toList();
    } catch (e) {
      errorMessage = e.toString();
    }
    isLoading = false;
    notifyListeners();
  }
}
