import 'package:flutter/material.dart';

@immutable
class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  const AppThemeTokens({
    required this.onSurfaceIcon,
    required this.onSurfaceMuted,
    required this.primaryAccent,
    required this.dangerColor,
    required this.cardBackground,
  });

  final Color onSurfaceIcon;
  final Color onSurfaceMuted;
  final Color primaryAccent;
  final Color dangerColor;
  final Color cardBackground;

  static AppThemeTokens of(BuildContext context) =>
      Theme.of(context).extension<AppThemeTokens>()!;

  @override
  AppThemeTokens copyWith({
    Color? onSurfaceIcon,
    Color? onSurfaceMuted,
    Color? primaryAccent,
    Color? dangerColor,
    Color? cardBackground,
  }) {
    return AppThemeTokens(
      onSurfaceIcon: onSurfaceIcon ?? this.onSurfaceIcon,
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      primaryAccent: primaryAccent ?? this.primaryAccent,
      dangerColor: dangerColor ?? this.dangerColor,
      cardBackground: cardBackground ?? this.cardBackground,
    );
  }

  @override
  AppThemeTokens lerp(covariant AppThemeTokens? other, double t) {
    if (other == null) return this;
    return AppThemeTokens(
      onSurfaceIcon: Color.lerp(onSurfaceIcon, other.onSurfaceIcon, t)!,
      onSurfaceMuted: Color.lerp(onSurfaceMuted, other.onSurfaceMuted, t)!,
      primaryAccent: Color.lerp(primaryAccent, other.primaryAccent, t)!,
      dangerColor: Color.lerp(dangerColor, other.dangerColor, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
    );
  }
}

class AppTheme {
  static const seed = Color(0xFFA67B5B);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final foreground = dark ? Colors.white : Colors.black87;
    final tokens = AppThemeTokens(
      onSurfaceIcon: foreground,
      onSurfaceMuted: dark ? const Color(0xFFBDBDBD) : const Color(0xFF757575),
      primaryAccent: seed,
      dangerColor: dark ? const Color(0xFFFF5252) : const Color(0xFFD32F2F),
      cardBackground: dark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F0E8),
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    ).copyWith(
      primary: seed,
      surface: tokens.cardBackground,
      onSurface: dark ? Colors.white : const Color(0xFF1E1E1E),
      outline: dark ? Colors.white24 : Colors.black26,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[tokens],
      iconTheme: IconThemeData(
        color: dark ? Colors.white : Colors.black87,
      ),
      primaryIconTheme: IconThemeData(
        color: dark ? Colors.white : Colors.black87,
      ),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
            bodyColor: foreground,
            displayColor: foreground,
          ),
      hintColor: dark ? Colors.grey[400] : Colors.grey[600],
      scaffoldBackgroundColor: dark ? const Color(0xFF121212) : Colors.white,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? Colors.white10 : Colors.black12,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        thumbColor: scheme.primary,
      ),
      // Scrollbar общего scroll-контейнера: тонкая полоса, подходящая и для
      // тёмной, и для светлой темы; трек не рисуем, чтобы не перекрывать текст.
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll<double>(6),
        radius: const Radius.circular(3),
        crossAxisMargin: 2,
        mainAxisMargin: 2,
        trackVisibility: const WidgetStatePropertyAll<bool>(false),
        thumbColor: WidgetStatePropertyAll<Color>(
          dark
              ? Colors.white.withValues(alpha: 0.45)
              : Colors.black.withValues(alpha: 0.35),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      // Уведомления в цветах текущей темы (без M3-дефолта `inverseSurface`,
      // который в тёмной теме давал светлую плашку и не менялся вместе с
      // темой). Floating — чтобы хост мог поднять их над контролами карты.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: tokens.cardBackground,
        contentTextStyle: TextStyle(color: foreground, fontSize: 14),
        actionTextColor: scheme.primary,
        closeIconColor: tokens.onSurfaceMuted,
        elevation: 4,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outline),
        ),
      ),
    );
  }
}

class ThemeModeScope extends InheritedWidget {
  const ThemeModeScope({
    required this.mode,
    required this.onChanged,
    required super.child,
    super.key,
  });

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  static ThemeModeScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeModeScope>()!;

  @override
  bool updateShouldNotify(ThemeModeScope oldWidget) => mode != oldWidget.mode;
}
