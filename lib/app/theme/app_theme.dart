import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const brand = Color(0xFF2F6BFF);
  static const _darkBackground = Color(0xFF09131B);
  static const _darkSurface = Color(0xFF121F29);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: brand,
          brightness: brightness,
          surface: dark ? _darkSurface : Colors.white,
        ).copyWith(
          primary: brand,
          outline: dark ? const Color(0xFF33424D) : const Color(0xFFD5DCE3),
          outlineVariant: dark
              ? const Color(0xFF263640)
              : const Color(0xFFE5E9ED),
        );
    final apple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final radius = apple ? 12.0 : 8.0;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? _darkBackground : const Color(0xFFF4F6F8),
      fontFamily: apple ? '.SF Pro Text' : null,
      visualDensity: defaultTargetPlatform == TargetPlatform.windows
          ? VisualDensity.compact
          : VisualDensity.standard,
      dividerColor: scheme.outlineVariant,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: dark ? _darkBackground : const Color(0xFFF4F6F8),
        surfaceTintColor: Colors.transparent,
        centerTitle: defaultTargetPlatform == TargetPlatform.iOS,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      cardTheme: CardThemeData(
        color: dark ? _darkSurface : Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor: dark ? const Color(0xFF0D1821) : Colors.white,
        indicatorColor: brand.withValues(alpha: .18),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: dark ? const Color(0xFF0D1821) : Colors.white,
        indicatorColor: brand,
        selectedIconTheme: const IconThemeData(color: Colors.white),
        selectedLabelTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF172630) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FadeOnlyPageTransitionsBuilder(),
          TargetPlatform.iOS: _FadeOnlyPageTransitionsBuilder(),
          TargetPlatform.macOS: _FadeOnlyPageTransitionsBuilder(),
          TargetPlatform.windows: _FadeOnlyPageTransitionsBuilder(),
          TargetPlatform.linux: _FadeOnlyPageTransitionsBuilder(),
        },
      ),
    );
  }
}

class _FadeOnlyPageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeOnlyPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
    child: child,
  );
}
