import 'package:flutter/material.dart';

/// Duo's look: a warm "sticker book". Cream paper, ink outlines, bright
/// fills with solid offset shadows, a soft serif for headings (Fraunces) and
/// a rounded sans for text (Nunito).
class DuoColors {
  static const paper = Color(0xFFFFF7EC);
  static const ink = Color(0xFF2B2024);
  static const tomato = Color(0xFFFF6F61);
  static const tangerine = Color(0xFFFFB570);
  static const sunflower = Color(0xFFFFDE6E);
  static const mint = Color(0xFFA3E4C1);
  static const sky = Color(0xFFA4D8FF);
  static const grape = Color(0xFFCDB8FF);
  static const bubblegum = Color(0xFFFFA8C2);

  static const nightPaper = Color(0xFF1D1719);
  static const nightCard = Color(0xFF2B2327);
  static const nightInk = Color(0xFFF6E9DD);

  /// Outline and shadow colour for the current brightness.
  static Color line(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? nightInk.withValues(alpha: 0.85) : ink;
}

class DuoTheme {
  static ThemeData light() => _build(
    ColorScheme.fromSeed(seedColor: DuoColors.tomato, brightness: Brightness.light).copyWith(
      primary: DuoColors.tomato,
      onPrimary: DuoColors.ink,
      surface: DuoColors.paper,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFFFFBF5),
      surfaceContainer: const Color(0xFFFBEEDD),
      surfaceContainerHigh: const Color(0xFFF6E5D0),
      surfaceContainerHighest: const Color(0xFFF0DCC4),
      onSurface: DuoColors.ink,
      onSurfaceVariant: const Color(0xFF6B5A5F),
      outline: const Color(0xFF9C8A84),
      outlineVariant: const Color(0xFFE6D5C3),
    ),
  );

  static ThemeData dark() => _build(
    ColorScheme.fromSeed(seedColor: DuoColors.tomato, brightness: Brightness.dark).copyWith(
      primary: DuoColors.tomato,
      onPrimary: DuoColors.ink,
      surface: DuoColors.nightPaper,
      surfaceContainerLowest: DuoColors.nightCard,
      surfaceContainerLow: const Color(0xFF261F22),
      surfaceContainer: const Color(0xFF30282C),
      surfaceContainerHigh: const Color(0xFF3A3135),
      surfaceContainerHighest: const Color(0xFF44393E),
      onSurface: DuoColors.nightInk,
      onSurfaceVariant: const Color(0xFFCDBDB3),
    ),
  );

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: 'Nunito');
    TextStyle? serif(TextStyle? s, {FontWeight weight = FontWeight.w600}) =>
        s?.copyWith(fontFamily: 'Fraunces', fontWeight: weight, letterSpacing: -0.4, height: 1.1);
    final text = base.textTheme;
    final line = scheme.brightness == Brightness.dark ? DuoColors.nightInk : DuoColors.ink;

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text.copyWith(
        displayMedium: serif(text.displayMedium),
        displaySmall: serif(text.displaySmall),
        headlineLarge: serif(text.headlineLarge),
        headlineMedium: serif(text.headlineMedium),
        headlineSmall: serif(text.headlineSmall),
        titleLarge: serif(text.titleLarge, weight: FontWeight.w500),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        labelMedium: text.labelMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.2),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: serif(text.headlineSmall)?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: line, width: 2),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: line, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: line, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: DuoColors.tomato, width: 2.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DuoColors.tomato,
          foregroundColor: DuoColors.ink,
          shape: StadiumBorder(side: BorderSide(color: line, width: 2)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          shape: const StadiumBorder(),
          side: BorderSide(color: line, width: 2),
          textStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          textStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: StadiumBorder(side: BorderSide(color: line, width: 1.5)),
        side: BorderSide(color: line, width: 1.5),
        backgroundColor: scheme.surfaceContainerLowest,
        selectedColor: DuoColors.sunflower,
        labelStyle: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700, color: scheme.onSurface),
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
  const FadeIn({super.key, required this.child, this.delay = Duration.zero, this.offset = 14});

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
      curve: Interval(start, 1, curve: Curves.easeOutBack),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, (1 - t) * offset), child: child),
      ),
    );
  }
}
