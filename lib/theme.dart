import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const background = Color(0xFFF7F5F1);
  static const foreground = Color(0xFF2B2D33);
  static const card = Color(0xFFFFFFFF);
  static const primary = Color(0xFFE36B24);
  static const primaryForeground = Color(0xFFFEFEFE);
  static const secondary = Color(0xFFF0EEEA);
  static const mutedForeground = Color(0xFF7A7D86);
  static const accent = Color(0xFFF7EDE3);
  static const accentForeground = Color(0xFFA85A28);
  static const border = Color(0xFFE5E2DC);
  static const panel = Color(0xFFF2F0EC);
  static const grid = Color(0xFFDFDBD5);
}

class AppTheme {
  static ThemeData light() {
    final inter = GoogleFonts.interTextTheme();
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        surface: AppColors.background,
        primary: AppColors.primary,
        onPrimary: AppColors.primaryForeground,
        onSurface: AppColors.foreground,
        secondary: AppColors.secondary,
        outline: AppColors.border,
      ),
      textTheme: inter.apply(
        bodyColor: AppColors.foreground,
        displayColor: AppColors.foreground,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }
}

TextStyle displayStyle({
  double size = 34,
  Color? color,
  FontWeight weight = FontWeight.w600,
  double tracking = 1,
}) {
  return GoogleFonts.oswald(
    fontSize: size,
    color: color ?? AppColors.foreground,
    fontWeight: weight,
    height: 1.0,
  );
}

TextStyle monoStyle({
  double size = 10,
  Color? color,
  FontWeight weight = FontWeight.w400,
  double tracking = 1,
  bool uppercase = true,
}) {
  return GoogleFonts.openSans(
    fontSize: size,
    color: color ?? AppColors.mutedForeground,
    fontWeight: weight,
    letterSpacing: tracking,
    height: 1.3,
  );
}

TextStyle labelMono({double size = 10, Color? color}) {
  return GoogleFonts.openSans(
    fontSize: size,
    color: color ?? AppColors.mutedForeground,
    fontWeight: FontWeight.w400,
    letterSpacing: 1.0,
    height: 1.3,
  );
}
