import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const pixelFont = 'CantingPixel';

  static const forest = Color(0xFF39734A);
  static const forestDark = Color(0xFF214E3A);
  static const leaf = Color(0xFF6F9E4F);
  static const sky = Color(0xFFCBE7DF);
  static const skyDeep = Color(0xFF8FC5B8);
  static const paper = Color(0xFFFFF9E8);
  static const paperShade = Color(0xFFF1E6C7);
  static const sun = Color(0xFFF4C95D);
  static const tomato = Color(0xFFD9694C);
  static const wood = Color(0xFF795238);
  static const woodDark = Color(0xFF432E25);
  static const ink = Color(0xFF2A332B);
  static const muted = Color(0xFF647063);

  static ThemeData light() => _theme(Brightness.light);

  static ThemeData dark() => _theme(Brightness.dark);

  static TextStyle pixelText(
    BuildContext context, {
    double fontSize = 10,
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    return TextStyle(
      fontFamily: pixelFont,
      fontSize: fontSize,
      height: 1.4,
      letterSpacing: 0,
      fontWeight: fontWeight,
      color: color ?? Theme.of(context).colorScheme.onSurface,
    );
  }

  static ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: forest,
          brightness: brightness,
        ).copyWith(
          primary: isDark ? const Color(0xFF91C574) : forest,
          onPrimary: isDark ? const Color(0xFF18301E) : paper,
          primaryContainer: isDark
              ? const Color(0xFF38583F)
              : const Color(0xFFCFE5BE),
          onPrimaryContainer: isDark
              ? const Color(0xFFE8F2D5)
              : const Color(0xFF203C27),
          secondary: isDark ? const Color(0xFFE0B96C) : const Color(0xFF9A6B37),
          onSecondary: isDark ? const Color(0xFF2D2116) : paper,
          secondaryContainer: isDark
              ? const Color(0xFF5A472A)
              : const Color(0xFFF3D98C),
          onSecondaryContainer: isDark
              ? const Color(0xFFFFE8B0)
              : const Color(0xFF493516),
          tertiary: isDark ? const Color(0xFFF19978) : tomato,
          onTertiary: isDark ? const Color(0xFF4B2115) : Colors.white,
          tertiaryContainer: isDark
              ? const Color(0xFF673D31)
              : const Color(0xFFF4C6AA),
          onTertiaryContainer: isDark
              ? const Color(0xFFFFE0D0)
              : const Color(0xFF57291F),
          surface: isDark ? const Color(0xFF142521) : const Color(0xFFE5F0E6),
          surfaceContainerLowest: isDark ? const Color(0xFF1A2B25) : paper,
          surfaceContainerLow: isDark
              ? const Color(0xFF1D3028)
              : const Color(0xFFF7F1DC),
          surfaceContainer: isDark
              ? const Color(0xFF294033)
              : const Color(0xFFEEE5CA),
          surfaceContainerHigh: isDark
              ? const Color(0xFF334B3B)
              : const Color(0xFFD7E2CF),
          surfaceContainerHighest: isDark
              ? const Color(0xFF405845)
              : const Color(0xFFC6D4C1),
          onSurface: isDark ? const Color(0xFFF6ECCE) : ink,
          onSurfaceVariant: isDark ? const Color(0xFFC9C5AC) : muted,
          outline: isDark ? const Color(0xFF9B8058) : wood,
          outlineVariant: isDark
              ? const Color(0xFF66573F)
              : const Color(0xFFB6A47D),
          error: isDark ? const Color(0xFFFFB39E) : const Color(0xFFB8473D),
          errorContainer: isDark
              ? const Color(0xFF663830)
              : const Color(0xFFF7D2C2),
        );

    final platformTypography = Typography.material2021(
      platform: TargetPlatform.android,
      colorScheme: scheme,
    );
    final baseTextTheme =
        (isDark ? platformTypography.white : platformTypography.black).apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        );

    final textTheme = baseTextTheme.copyWith(
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w900,
        height: 1.22,
        letterSpacing: 0,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w900,
        height: 1.25,
        letterSpacing: 0,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w900,
        height: 1.3,
        letterSpacing: 0,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w900,
        height: 1.3,
        letterSpacing: 0,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        height: 1.35,
        letterSpacing: 0,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        height: 1.55,
        letterSpacing: 0,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        height: 1.5,
        letterSpacing: 0,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        height: 1.45,
        letterSpacing: 0,
      ),
    );

    final pixelShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(3),
      side: BorderSide(color: scheme.outline, width: 2),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      splashFactory: InkRipple.splashFactory,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: pixelShape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: BorderSide(color: scheme.outline, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: BorderSide(color: scheme.outline, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: BorderSide(color: scheme.primary, width: 3),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(color: scheme.primary, width: 2),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return textTheme.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
            size: 23,
          );
        }),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 46)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? scheme.primaryContainer
                : scheme.surfaceContainerLowest;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurface;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            return BorderSide(
              color: states.contains(WidgetState.selected)
                  ? scheme.primary
                  : scheme.outline,
              width: 2,
            );
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(3),
            side: BorderSide(color: scheme.outline, width: 2),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: BorderSide(color: scheme.outline, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size.square(44)),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark
            ? scheme.surfaceContainerLow.withValues(alpha: 0.94)
            : scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: pixelShape,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark
            ? scheme.surfaceContainerLow.withValues(alpha: 0.94)
            : scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outline,
        constraints: const BoxConstraints(maxWidth: 680),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          side: BorderSide(color: scheme.outline, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF304B39) : forestDark,
        contentTextStyle: const TextStyle(
          color: paper,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: const BorderSide(color: sun, width: 2),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        highlightElevation: 0,
        backgroundColor: scheme.tertiary,
        foregroundColor: scheme.onTertiary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: BorderSide(color: scheme.outline, width: 2),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: 54,
        iconColor: scheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        linearMinHeight: 8,
        borderRadius: BorderRadius.zero,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.secondaryContainer,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        valueIndicatorColor: scheme.primary,
        valueIndicatorTextStyle: TextStyle(color: scheme.onPrimary),
        trackHeight: 8,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.surfaceContainerLowest;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStatePropertyAll(scheme.outline),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
