import 'package:flutter/material.dart';

class AppTheme {
  static const Color canvas = Color(0xFFF8FAFC);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color cardBorder = Color(0xFFE2E8F0);
  static const Color primaryText = Color(0xFF0F172A);
  static const Color secondaryText = Color(0xFF475569);
  static const Color mutedText = Color(0xFF94A3B8);

  static const Color slateDark = Color(0xFF111827);
  static const Color slateMid = Color(0xFF1E293B);
  static const Color slateAccent = Color(0xFF283548);
  
  // Rich primary card & top header gradient
  static const LinearGradient slateCardGradient = LinearGradient(
    colors: [
      Color(0xFF24334A), // Rich midnight slate highlight
      Color(0xFF161F2E), // Mid slate
      Color(0xFF0F172A), // Deep base slate
    ],
    stops: [0.0, 0.5, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // High-contrast button gradient with tactile depth
  static const LinearGradient slateButtonGradient = LinearGradient(
    colors: [
      Color(0xFF2C3E55),
      Color(0xFF1E293B),
      Color(0xFF131C2A),
    ],
    stops: [0.0, 0.6, 1.0],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Executive dock / segmented track gradient
  static const LinearGradient slateDockGradient = LinearGradient(
    colors: [
      Color(0xFF222F43),
      Color(0xFF121B27),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Color primaryGradientFallback = slateMid;
  static const Color primaryGradientStart = slateDark;
  static const Color primaryGradientEnd = slateMid;

  static const Color pendingBg = Color(0xFFFFFBEB);
  static const Color pendingBorder = Color(0xFFFDE68A);
  static const Color pendingText = Color(0xFFB45309);
  static const Color pendingAccent = Color(0xFFD97706);

  static const Color confirmedBg = Color(0xFFF0FDF4);
  static const Color confirmedBorder = Color(0xFFBBF7D0);
  static const Color confirmedText = Color(0xFF16A34A);

  static const Color outflowBg = Color(0xFFFEF2F2);
  static const Color outflowBorder = Color(0xFFFECACA);
  static const Color outflowText = Color(0xFFDC2626);
  
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
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          splashFactory: NoSplash.splashFactory,
        ),
      ),
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
