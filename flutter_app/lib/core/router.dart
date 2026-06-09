import 'package:flutter_modular/flutter_modular.dart';

import '../data/api_client.dart';
import '../features/admin/admin_page.dart';
import '../features/home/home_page.dart';
import '../features/interactive_drama/interactive_drama_page.dart';
import '../features/player/player_page.dart';

class AppModule extends Module {
  @override
  void binds(Injector i) {
    i.addSingleton<ApiClient>(ApiClient.create);
  }

  @override
  void routes(RouteManager r) {
    r.child('/', child: (_) => const HomePage());
    r.child('/admin', child: (_) => const AdminPage());
    r.child('/interactive-drama', child: (_) => const InteractiveDramaPage());
    r.child('/play/:episodeId',
        child: (ctx) => PlayerPage(episodeId: r.args.params['episodeId']!));
  }
}
