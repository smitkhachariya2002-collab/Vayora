import 'package:flutter/material.dart';

abstract final class AppBrand {
  static const name = 'Vayora';
  static const support = 'help.vayora@gmail.com';
  static const font = 'Poppins';
  static const version = '0.3.4';
}

abstract final class AppColors {
  static const primary = Color(0xFFFF7A1A), primaryDark = Color(0xFFE25A00);
  static const accent = Color(0xFFFFB347), gold = Color(0xFFFFC24D);
  static const background = Color(0xFF0B0B0D), surface = Color(0xFF16161A);
  static const surfaceHigh = Color(0xFF1F1F25),
      bubble = surfaceHigh,
      border = Color(0xFF2A2A31);
  static const text = Color(0xFFF5F5F7),
      muted = Color(0xFF9B9BA5),
      ink = Color(0xFF1A1005);
  static const success = Color(0xFF34D399), successBg = Color(0xFF10261D);
  static const warning = accent, warningBg = Color(0xFF2A1F10);
  static const danger = Color(0xFFFF5A5F), dangerBg = Color(0xFF2B1414);
  static const navigation = Color(0xFF111114),
      black = Color(0xFF000000),
      white = Color(0xFFFFFFFF);
  static const transparent = Color(0x00000000),
      pill = Color(0xD91B1B20),
      veil = Color(0x88000000);
  static const shimmer = Color(0xFF34343D), softOrange = Color(0x332A1F10);
  static const googleBlue = Color(0xFF4285F4), googleRed = Color(0xFFEA4335);
  static const googleYellow = Color(0xFFFBBC05),
      googleGreen = Color(0xFF34A853);
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF5F1F), Color(0xFFFF8A00), accent],
  );
  static const barGradient = RadialGradient(
    center: Alignment(1.1, -2.2),
    radius: 2.4,
    colors: [Color(0xFF3A1B08), background],
  );
  static const softGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF221A14), surface],
  );
  static const glow = RadialGradient(colors: [Color(0x55FF6A00), transparent]);
  static const scrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [transparent, Color(0xB3000000)],
  );
}

abstract final class Gap {
  static const double xs = 4,
      s = 8,
      m = 12,
      l = 16,
      xl = 24,
      xxl = 32,
      hero = 40;
  static const page = EdgeInsets.all(xl),
      list = EdgeInsets.symmetric(horizontal: l, vertical: m);
}

abstract final class Radii {
  static const double card = 16, button = 14, chip = 20;
  static const cardRadius = BorderRadius.all(Radius.circular(card));
  static const buttonRadius = BorderRadius.all(Radius.circular(button));
  static const chipRadius = BorderRadius.all(Radius.circular(chip));
}

abstract final class AppSizes {
  static const double button = 48, nav = 60, navAccessible = 88, toolbar = 64;
  static const double iconSmall = 18,
      icon = 24,
      dialogIcon = 36,
      emptyIcon = 64;
  static const double avatar = 28,
      avatarLarge = 48,
      avatarSmall = 20,
      logo = 64,
      logoLarge = 88;
  static const double logoLetter = 34,
      brandLetterSpacing = 1.2,
      avatarRail = 116;
  static const double contentWidth = 760, formWidth = 520, gridBreakpoint = 620;
  static const double videoRatio = 16 / 9,
      postCardWidth = 268,
      relatedHeight = 300;
  static const double progress = 8, stroke = 1, focusStroke = 1.5, spinner = 20;
  static const double mediaHero = 240, playerControl = 64, playerTouch = 48;
  static const double sheetGripWidth = 36, sheetGripHeight = 4;
  static const double body = 15, bodySmall = 14, label = 14, caption = 12;
  static const double headline = 22, title = 19, subtitle = 16, heroType = 32;
  static const double textHeight = 1.45,
      pulseScale = 1.06,
      pressedScale = .97,
      restingScale = 1,
      disabledOpacity = .45;
  static const int imageCacheWidth = 960,
      avatarCacheWidth = 192,
      imageCacheCount = 240;
  static const int imageCacheBytes = 96 * 1024 * 1024, pageSize = 20;
}

abstract final class AppMotion {
  static const press = Duration(milliseconds: 110),
      fade = Duration(milliseconds: 240);
  static const route = Duration(milliseconds: 280),
      shimmer = Duration(milliseconds: 1400);
}

ThemeData buildTheme() {
  const textTheme = TextTheme(
    headlineSmall: TextStyle(
      fontSize: AppSizes.headline,
      fontWeight: FontWeight.w700,
      color: AppColors.text,
    ),
    headlineMedium: TextStyle(
      fontSize: AppSizes.heroType,
      fontWeight: FontWeight.w700,
      color: AppColors.text,
    ),
    titleLarge: TextStyle(
      fontSize: AppSizes.title,
      fontWeight: FontWeight.w700,
      color: AppColors.text,
    ),
    titleMedium: TextStyle(
      fontSize: AppSizes.subtitle,
      fontWeight: FontWeight.w600,
      color: AppColors.text,
    ),
    bodyLarge: TextStyle(
      fontSize: AppSizes.body,
      height: AppSizes.textHeight,
      color: AppColors.text,
    ),
    bodyMedium: TextStyle(
      fontSize: AppSizes.bodySmall,
      height: AppSizes.textHeight,
      color: AppColors.text,
    ),
    bodySmall: TextStyle(
      fontSize: AppSizes.bodySmall,
      height: AppSizes.textHeight,
      color: AppColors.muted,
    ),
    labelLarge: TextStyle(
      fontSize: AppSizes.label,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: TextStyle(fontSize: AppSizes.label, color: AppColors.muted),
    labelSmall: TextStyle(
      fontSize: AppSizes.caption,
      fontWeight: FontWeight.w600,
    ),
  );
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
      ).copyWith(
        primary: AppColors.primary,
        onPrimary: AppColors.ink,
        secondary: AppColors.gold,
        onSecondary: AppColors.ink,
        surface: AppColors.surface,
        onSurface: AppColors.text,
        onSurfaceVariant: AppColors.muted,
        surfaceContainerHighest: AppColors.surfaceHigh,
        outline: AppColors.border,
        error: AppColors.danger,
      );
  final shape = RoundedRectangleBorder(borderRadius: Radii.buttonRadius);
  return ThemeData(
    useMaterial3: true,
    fontFamily: AppBrand.font,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: textTheme.apply(fontFamily: AppBrand.font),
    visualDensity: VisualDensity.standard,
    dividerColor: AppColors.border,
    iconTheme: const IconThemeData(color: AppColors.text, size: AppSizes.icon),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.transparent,
      surfaceTintColor: AppColors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: AppSizes.toolbar,
      titleTextStyle: TextStyle(
        fontFamily: AppBrand.font,
        fontSize: AppSizes.title,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.ink,
        minimumSize: const Size(0, AppSizes.button),
        shape: shape,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.xl,
          vertical: Gap.m,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        minimumSize: const Size(0, AppSizes.button),
        shape: shape,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: Gap.l, vertical: Gap.m),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(
          fontFamily: AppBrand.font,
          fontSize: AppSizes.label,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      contentPadding: const EdgeInsets.all(Gap.l),
      hintStyle: const TextStyle(color: AppColors.muted),
      labelStyle: const TextStyle(color: AppColors.muted),
      border: const OutlineInputBorder(
        borderRadius: Radii.buttonRadius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: Radii.buttonRadius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: Radii.buttonRadius,
        borderSide: BorderSide(
          color: AppColors.primary,
          width: AppSizes.focusStroke,
        ),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: Radii.buttonRadius,
        borderSide: BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: Radii.buttonRadius,
        borderSide: BorderSide(
          color: AppColors.danger,
          width: AppSizes.focusStroke,
        ),
      ),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: AppColors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.cardRadius,
        side: BorderSide(color: AppColors.border),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceHigh,
      selectedColor: AppColors.primary,
      labelStyle: const TextStyle(
        fontFamily: AppBrand.font,
        fontSize: AppSizes.bodySmall,
        color: AppColors.text,
      ),
      side: const BorderSide(color: AppColors.border),
      shape: const RoundedRectangleBorder(borderRadius: Radii.chipRadius),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.surfaceHigh,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.ink
              : AppColors.text,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: AppBrand.font,
            fontSize: AppSizes.bodySmall,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: AppColors.transparent,
      shape: RoundedRectangleBorder(borderRadius: Radii.chipRadius),
      alignment: Alignment.center,
      titleTextStyle: TextStyle(
        fontFamily: AppBrand.font,
        fontSize: AppSizes.title,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      contentTextStyle: TextStyle(
        fontFamily: AppBrand.font,
        fontSize: AppSizes.body,
        height: AppSizes.textHeight,
        color: AppColors.muted,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: TextStyle(
        fontFamily: AppBrand.font,
        fontSize: AppSizes.bodySmall,
        color: AppColors.text,
      ),
      shape: RoundedRectangleBorder(borderRadius: Radii.buttonRadius),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: AppColors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.chip)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: AppSizes.nav,
      backgroundColor: AppColors.navigation,
      indicatorColor: AppColors.transparent,
      surfaceTintColor: AppColors.transparent,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.muted,
          size: AppSizes.icon,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: AppBrand.font,
          fontSize: AppSizes.bodySmall,
          fontWeight: FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.muted,
        ),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.border,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.primary,
      inactiveTrackColor: AppColors.border,
      thumbColor: AppColors.primary,
      overlayColor: AppColors.softOrange,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 0,
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.ink,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: CinematicPageTransition()},
    ),
  );
}

class CinematicPageTransition extends PageTransitionsBuilder {
  const CinematicPageTransition();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .035),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
