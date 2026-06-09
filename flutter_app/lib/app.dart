import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'core/theme.dart';

class SdiApp extends StatelessWidget {
  const SdiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '短剧即时互动',
      theme: AppTheme.darkTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      routerConfig: Modular.routerConfig,
    );
  }
}
