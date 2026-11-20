import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

const kEspresso = Color(0xFF33221A);
const kRoast = Color(0xFF6B4A34);
const kCaramel = Color(0xFFC68B59);
const kCream = Color(0xFFFAF3E9);
const kMilk = Color(0xFFFFFCF7);
const kLatte = Color(0xFFF1E4D3);
const kLine = Color(0xFFEADCCB);

const kLabelStyle = TextStyle(
  fontSize: 10.5,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.3,
  color: kRoast,
);

const appBackground = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFEFAF4), kCream],
  ),
);

const appOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: kCream,
  systemNavigationBarDividerColor: kCream,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: false,
  systemStatusBarContrastEnforced: false,
);

ThemeData buildAppTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: kRoast,
        brightness: Brightness.light,
      ).copyWith(
        primary: kEspresso,
        onPrimary: kCream,
        secondary: kCaramel,
        onSecondary: kEspresso,
        surface: kMilk,
        onSurface: kEspresso,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kCream,
  );
}
