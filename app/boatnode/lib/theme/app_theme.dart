import 'package:flutter/material.dart';

// --- THEME CONSTANTS (Tailwind Mappings) ---
const kZinc950 = Color(0xFF09090B);
const kZinc900 = Color(0xFF18181B);
const kZinc800 = Color(0xFF27272A);
const kZinc700 = Color(0xFF3F3F46);
const kZinc500 = Color(0xFF71717A);
const kZinc400 = Color(0xFFA1A1AA);
const kBlue600 = Color(0xFF2563EB);
const kRed600 = Color(0xFFDC2626);
const kRed700 = Color(0xFFB91C1C);
const kRed900 = Color(0xFF7F1D1D);
const kRed500 = Color(0xFFEF4444);
const kGreen500 = Color(0xFF22C55E);

final appTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: kZinc950,
  primaryColor: kBlue600,
  useMaterial3: true,
  fontFamily: 'Inter', // Ensure you add Google Fonts or assets
  colorScheme: const ColorScheme.dark(
    primary: kBlue600,
    surface: kZinc900,
  ),
);
