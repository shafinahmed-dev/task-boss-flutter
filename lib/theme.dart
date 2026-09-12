import 'package:flutter/material.dart';

class AppTheme {
  static const Color canvas = Color(0xFFF8FAFC);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color cardBorder = Color(0xFFE2E8F0);
  static const Color primaryText = Color(0xFF0F172A);
  static const Color secondaryText = Color(0xFF475569);
  static const Color mutedText = Color(0xFF94A3B8);

  static const Color primaryGradientFallback = Color(0xFF2563EB);
  static const Color primaryGradientStart = Color(0xFF1E3A8A);
  static const Color primaryGradientEnd = Color(0xFF3B82F6);

  static const Color pendingBg = Color(0xFFFFFBEB);
  static const Color pendingBorder = Color(0xFFFDE68A);
  static const Color pendingText = Color(0xFFB45309);
  static const Color pendingAccent = Color(0xFFD97706);

  static const Color confirmedBg = Color(0xFFF0FDF4);
  static const Color confirmedBorder = Color(0xFFBBF7D0);
  static const Color confirmedText = Color(0xFF16A34A);

  static const Color expenseBg = Color(0xFFFEF2F2);
  static const Color expenseBorder = Color(0xFFFECACA);
  static const Color expenseText = Color(0xFFDC2626);
  
  static const Color inflowBg = Color(0xFFF0FDF4);
  static const Color inflowBorder = Color(0xFFBBF7D0);
  static const Color inflowText = Color(0xFF16A34A);

  static const Color inputBg = Color(0xFFFFFFFF);
  static const Color inputBorder = Color(0xFFCBD5E1);

  static ThemeData get themeData {
    return ThemeData(
      scaffoldBackgroundColor: canvas,
      primaryColor: primaryGradientFallback,
      fontFamily: 'Roboto', // Default fallback
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        elevation: 0,
        iconTheme: IconThemeData(color: primaryText),
        titleTextStyle: TextStyle(
          color: primaryText,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      colorScheme: ColorScheme.fromSeed(seedColor: primaryGradientFallback),
    );
  }
}
