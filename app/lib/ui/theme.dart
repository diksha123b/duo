import 'package:flutter/material.dart';

/// Duo's "cozy & soft" look: warm cream backgrounds, dusty-rose accents,
/// a soft serif for headings (Fraunces) and a rounded sans for text (Nunito).
class DuoTheme {
  static const _rose = Color(0xFFC9707D);
  static const _roseDark = Color(0xFFE8A6AF);

  static ThemeData light() => _build(
    ColorScheme.fromSeed(seedColor: _rose, brightness: Brightness.light).copyWith(
      primary: _rose,
      surface: const Color(0xFFFBF6F1),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFFFFCF9),
      surfaceContainer: const Color(0xFFF6EEE7),
      surfaceContainerHigh: const Color(0xFFF1E7DF),
      surfaceContainerHighest: const Color(0xFFEADFD6),
      onSurface: const Color(0xFF3D3438),
      outline: const Color(0xFFBBA9A3),
      outlineVariant: const Color(0xFFE6D9D1),
    ),
  );

  static ThemeData dark() => _build(
    ColorScheme.fromSeed(seedColor: _rose, brightness: Brightness.dark).copyWith(
      primary: _roseDark,
      surface: const Color(0xFF1E1A1C),
      surfaceContainerLowest: const Color(0xFF191517),
      surfaceContainerLow: const Color(0xFF241F22),
      surfaceContainer: const Color(0xFF2A2427),
      surfaceContainerHigh: const Color(0xFF332C30),
      surfaceContainerHighest: const Color(0xFF3C3438),
      onSurface: const Color(0xFFF1E6E8),
    ),
  );

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: 'Nunito');
    TextStyle? serif(TextStyle? s, {FontWeight weight = FontWeight.w600}) =>
        s?.copyWith(fontFamily: 'Fraunces', fontWeight: weight, letterSpacing: -0.3);
    final text = base.textTheme;

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text.copyWith(
        displaySmall: serif(text.displaySmall),
        headlineLarge: serif(text.headlineLarge),
        headlineMedium: serif(text.headlineMedium),
        headlineSmall: serif(text.headlineSmall),
        titleLarge: serif(text.titleLarge, weight: FontWeight.w500),
        labelMedium: text.labelMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.1),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: serif(text.titleLarge)?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: const StadiumBorder())),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surfaceContainerLowest,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Fades and gently lifts its child into place, optionally after [delay].
/// Used for staggered entrances on the home and results screens.
class FadeIn extends StatelessWidget {
  const FadeIn({super.key, required this.child, this.delay = Duration.zero, this.offset = 12});

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final total = delay + const Duration(milliseconds: 450);
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * offset), child: child),
      ),
    );
  }
}
