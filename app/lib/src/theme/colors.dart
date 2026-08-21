import 'package:flutter/material.dart';

/// Дизайн-система клиентского приложения (макеты mockups/client/v5):
/// белый фон, текст #191919/#757575, зелёный акцент #06C167 точечно,
/// CTA-кнопки — чёрные пилюли.
abstract final class AppColors {
  /// Зелёный акцент: бейджи, свитчи, таймеры, ссылки, спиннеры.
  static const Color accent = Color(0xFF06C167);

  /// Успех/«открыто»/онлайн — тот же зелёный, что и акцент (v5).
  static const Color secondary = Color(0xFF06C167);

  /// Чёрный CTA: кнопки-пилюли, активные чипы и табы.
  static const Color cta = Color(0xFF000000);

  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);

  /// Серая заливка полей, чипов и плиток (#F6F6F6 в макетах).
  static const Color fill = Color(0xFFF6F6F6);

  /// Тонкая обводка карточек (#EFEFEF в макетах).
  static const Color border = Color(0xFFEFEFEF);

  static const Color textPrimary = Color(0xFF191919);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textHint = Color(0xFF9C9C9C);
  static const Color star = Color(0xFFF0A22E);
  static const Color error = Color(0xFFD64545);
  static const Color successSurface = Color(0xFFE5F8EE);
  static const Color closedBadge = Color(0xD93C3C43);
}
