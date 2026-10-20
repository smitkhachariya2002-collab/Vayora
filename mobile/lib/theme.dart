import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppBrand {
  static const name = 'Vayora';
  static const support = 'help.vayora@gmail.com';
  static const font = 'Poppins';
  static const version = '0.3.7';
}

abstract final class AppColors {
  static const primary = Color(0xFF7C5CFF), primaryDark = Color(0xFF5B3FE0);
  static const primaryText = Color(0xFFA18AFF);
  static const accent = Color(0xFFFF5CA8), gold = Color(0xFFFFC94D);
  static const background = Color(0xFF0A0A14), surface = Color(0xFF141424);
  static const surfaceHigh = Color(0xFF1D1D33), bubble = surfaceHigh;
  static const border = Color(0xFF2A2A45), text = Color(0xFFF4F4FA);
  static const muted = Color(0xFF9C9CB8), ink = Color(0xFF120A24);
  static const success = Color(0xFF34D399), successBg = Color(0xFF10261D);
  static const warning = Color(0xFFFBBF24), warningBg = Color(0xFF2A1F10);
  static const danger = Color(0xFFFF5A5F), dangerBg = Color(0xFF2B1414);
  static const controlDanger = Color(0xFFB52F3B);
  static const navigation = Color(0xFF10101E), black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF), transparent = Color(0x00000000);
  static const pill = Color(0xD9141424), veil = Color(0x88000000);
  static const shimmer = surfaceHigh, softPrimary = Color(0x337C5CFF);
  static const selectedPlan = Color(0xFF1E1838);
  static const heroShadow = Color(0x337C5CFF),
      selectedShadow = Color(0x227C5CFF);
  // Owner-approved contrast adjustment for small white control labels.
  static const controlPrimary = Color(0xFF6D51E0), onAction = white;
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6A5CFF), Color(0xFF9B5CFF), accent],
  );
  // The same gradient under a 25% dark scrim: white text exceeds 4.5:1.
  static const actionGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5045BF), Color(0xFF7445BF), Color(0xFFBF457E)],
  );
  static const barGradient = RadialGradient(
    center: Alignment(1.1, -2.2),
    radius: 2.4,
    colors: [Color(0xFF241A4A), background],
  );
  static const profileGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C5CFF), Color(0xFF3B1F8A), Color(0xFF160E2E)],
  );
  static const profileFade = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x22000000), background],
    stops: [.45, 1],
  );
  static const softGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1C1830), surface],
  );
  static const glow = RadialGradient(colors: [Color(0x557C5CFF), transparent]);
  static const scrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [transparent, Color(0xB3000000)],
  );
  static const googleBlue = Color(0xFF4285F4), googleRed = Color(0xFFEA4335);
  static const googleYellow = Color(0xFFFBBC05),
      googleGreen = Color(0xFF34A853);
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
        onPrimary: AppColors.white,
        secondary: AppColors.accent,
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
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: AppColors.background,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarDividerColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
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
        backgroundColor: AppColors.controlPrimary,
        foregroundColor: AppColors.white,
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
        foregroundColor: AppColors.primaryText,
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
      selectedColor: AppColors.controlPrimary,
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
              ? AppColors.controlPrimary
              : AppColors.surfaceHigh,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.white
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
              ? AppColors.primaryText
              : AppColors.muted,
        ),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.primary,
      selectionColor: AppColors.softPrimary,
      selectionHandleColor: AppColors.primary,
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.primary
            : AppColors.muted,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.primary
            : AppColors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(AppColors.ink),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.primary
            : AppColors.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.softPrimary
            : AppColors.surfaceHigh,
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
      overlayColor: AppColors.softPrimary,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 0,
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.white,
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
