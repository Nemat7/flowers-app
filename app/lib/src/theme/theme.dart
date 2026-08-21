import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

abstract final class AppTheme {
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      primary: AppColors.accent,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
    );

    // Inter везде (макеты v5), начертаний 400/600/700/800 достаточно.
    final inter = GoogleFonts.interTextTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: inter.copyWith(
        headlineSmall: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: AppColors.textPrimary,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.textPrimary,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.fill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textHint,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.cta,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.fill,
          disabledForegroundColor: AppColors.textHint,
          minimumSize: const Size.fromHeight(54),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// Тень плавающих кругов таббара и круглых кнопок: `0 4px 16px rgba(0,0,0,.10)`.
final List<BoxShadow> kFloatingShadow = [
  BoxShadow(
    color: Colors.black.withValues(alpha: 0.10),
    blurRadius: 16,
    offset: const Offset(0, 4),
  ),
];

/// Мягкая тень карточек: `0 4px 16px rgba(0,0,0,.06)`.
final List<BoxShadow> kCardShadow = [
  BoxShadow(
    color: Colors.black.withValues(alpha: 0.06),
    blurRadius: 16,
    offset: const Offset(0, 4),
  ),
];
