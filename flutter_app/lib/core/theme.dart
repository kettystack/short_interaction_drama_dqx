// 与 iOS Theme.swift 完全对齐的设计 token
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // 背景三层
  static const bgDeep = Color(0xFF050308);
  static const bgPanel = Color(0xFF14101C);
  static const bgRaised = Color(0xFF1B1727);

  // 强调色
  static const accentHot = Color(0xFFFF5770); // 番茄主色
  static const accentGold = Color(0xFFFFB23F);
  static const accentMint = Color(0xFF3FFFB7);
  static const accentVio = Color(0xFF8A5BFF);

  // 文字层级
  static const textPrimary = Colors.white;
  static const textSecondary = Color(0xCCFFFFFF);
  static const textTertiary = Color(0x80FFFFFF);

  // 渐变
  static const ctaGradient = LinearGradient(
    colors: [Color(0xFFFF5770), Color(0xFFFFB23F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const posterScrim = LinearGradient(
    colors: [Colors.transparent, Color(0xE6000000)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const topScrim = LinearGradient(
    colors: [Color(0xCC000000), Colors.transparent],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const bottomScrim = LinearGradient(
    colors: [Colors.transparent, Color(0xE6000000)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class AppRadius {
  static const s = 8.0;
  static const m = 14.0;
  static const l = 22.0;
}

class AppTheme {
  static ThemeData darkTheme() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bgDeep,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accentHot,
        secondary: AppColors.accentGold,
        surface: AppColors.bgPanel,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
        fontFamily: 'PingFang SC',
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
