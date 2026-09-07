// MaterialState aliases remain the compatibility API for Flutter 3.19, whose
// bundled Dart SDK is 3.3. They are deprecated, but still supported by newer
// Flutter releases after the WidgetState rename in Flutter 3.22.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

abstract final class SnapColors {
  static const electricBlue = Color(0xFF087CFA);
  static const electricBlueBright = Color(0xFF3DA8FF);
  static const electricBlueDeep = Color(0xFF0068DD);
  static const success = Color(0xFF20C875);
  static const successDeep = Color(0xFF087A47);
  static const warning = Color(0xFFFFB020);
  static const warningDeep = Color(0xFF9A5B00);

  static const lightBackground = Color(0xFFF7F7F8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceMuted = Color(0xFFF0F2F4);
  static const lightOutline = Color(0xFFAAB2BC);
  static const lightOutlineVariant = Color(0xFFDDE2E7);
  static const lightOnSurface = Color(0xFF15181B);
  static const lightOnSurfaceVariant = Color(0xFF626A73);

  static const darkBackground = Color(0xFF050607);
  static const darkSurface = Color(0xFF111315);
  static const darkSurfaceRaised = Color(0xFF171A1E);
  static const darkSurfaceMuted = Color(0xFF1B1F23);
  static const darkOutline = Color(0xFF626B75);
  static const darkOutlineVariant = Color(0xFF2A3036);
  static const darkOnSurface = Color(0xFFF4F6F8);
  static const darkOnSurfaceVariant = Color(0xFFA7AFB8);
}

abstract final class SnapTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final accent =
        isDark ? SnapColors.electricBlueBright : SnapColors.electricBlueDeep;
    final background =
        isDark ? SnapColors.darkBackground : SnapColors.lightBackground;
    final surface = isDark ? SnapColors.darkSurface : SnapColors.lightSurface;
    final surfaceMuted =
        isDark ? SnapColors.darkSurfaceMuted : SnapColors.lightSurfaceMuted;
    final onSurface =
        isDark ? SnapColors.darkOnSurface : SnapColors.lightOnSurface;
    final onSurfaceVariant = isDark
        ? SnapColors.darkOnSurfaceVariant
        : SnapColors.lightOnSurfaceVariant;
    final outline = isDark ? SnapColors.darkOutline : SnapColors.lightOutline;
    final outlineVariant =
        isDark ? SnapColors.darkOutlineVariant : SnapColors.lightOutlineVariant;
    final elevatedSurface =
        isDark ? SnapColors.darkSurfaceRaised : SnapColors.lightSurface;
    final surfaceShadow =
        isDark ? const Color(0xB3000000) : const Color(0x1A101820);

    final scheme = ColorScheme.fromSeed(
      seedColor: SnapColors.electricBlue,
      brightness: brightness,
    ).copyWith(
      primary: accent,
      onPrimary: isDark ? const Color(0xFF002C55) : Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF07325D) : const Color(0xFFE5F2FF),
      onPrimaryContainer:
          isDark ? const Color(0xFFD7EAFF) : const Color(0xFF002C55),
      secondary: accent,
      onSecondary: isDark ? const Color(0xFF002C55) : Colors.white,
      secondaryContainer:
          isDark ? const Color(0xFF12304D) : const Color(0xFFE8F2FC),
      onSecondaryContainer:
          isDark ? const Color(0xFFD7E9FA) : const Color(0xFF18344E),
      error: isDark ? SnapColors.warning : SnapColors.warningDeep,
      onError: isDark ? const Color(0xFF17130A) : Colors.white,
      errorContainer:
          isDark ? const Color(0xFF382A06) : const Color(0xFFFFE8B0),
      onErrorContainer:
          isDark ? const Color(0xFFFFD56A) : const Color(0xFF4A3400),
      background: background,
      onBackground: onSurface,
      surface: surface,
      onSurface: onSurface,
      surfaceVariant: surfaceMuted,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: outlineVariant,
      shadow: surfaceShadow,
      scrim: const Color(0xCC000000),
      inverseSurface:
          isDark ? SnapColors.lightOnSurface : SnapColors.darkOnSurface,
      onInverseSurface:
          isDark ? SnapColors.darkOnSurface : SnapColors.lightOnSurface,
      inversePrimary: SnapColors.electricBlueBright,
      surfaceTint: Colors.transparent,
    );

    final base = ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      fontFamilyFallback: const <String>['Apple SD Gothic Neo', 'Noto Sans KR'],
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    final textTheme = _textTheme(base.textTheme, scheme);
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    final surfaceShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(color: outlineVariant),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: outlineVariant),
    );

    return base.copyWith(
      canvasColor: background,
      cardColor: surface,
      shadowColor: surfaceShadow,
      splashColor: SnapColors.electricBlue.withOpacity(0.10),
      highlightColor: SnapColors.electricBlue.withOpacity(0.06),
      hoverColor: SnapColors.electricBlue.withOpacity(0.05),
      focusColor: SnapColors.electricBlue.withOpacity(0.16),
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(color: onSurfaceVariant, size: 24),
      primaryIconTheme: const IconThemeData(
        color: SnapColors.electricBlue,
        size: 24,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        toolbarHeight: 68,
        titleSpacing: 18,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: onSurface),
        actionsIconTheme: IconThemeData(color: onSurface),
      ),
      dividerTheme: DividerThemeData(
        color: outlineVariant.withOpacity(0.78),
        thickness: 1,
        space: 1,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: surfaceShadow,
        elevation: isDark ? 2 : 4,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: surfaceShape,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SnapColors.electricBlueDeep,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              isDark ? const Color(0xFF252A30) : const Color(0xFFDCE1E6),
          disabledForegroundColor:
              isDark ? const Color(0xFF747C85) : const Color(0xFF8A929B),
          minimumSize: const Size.fromHeight(56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: controlShape,
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1.2,
            letterSpacing: -0.15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          disabledForegroundColor: onSurfaceVariant.withOpacity(0.55),
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          side: BorderSide(color: outlineVariant),
          shape: controlShape,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          disabledForegroundColor: onSurfaceVariant.withOpacity(0.55),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: controlShape,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF0B0D0F) : Colors.white,
        isDense: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        labelStyle: TextStyle(color: onSurfaceVariant, fontSize: 15),
        floatingLabelStyle: TextStyle(
          color: accent,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(
          color: onSurfaceVariant.withOpacity(0.76),
          fontSize: 15,
        ),
        helperStyle: TextStyle(color: onSurfaceVariant, fontSize: 12),
        counterStyle: TextStyle(color: onSurfaceVariant, fontSize: 12),
        errorStyle: TextStyle(
          color: isDark ? SnapColors.warning : SnapColors.warningDeep,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: onSurfaceVariant,
        suffixIconColor: onSurfaceVariant,
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: outlineVariant.withOpacity(0.52)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: SnapColors.electricBlue,
            width: 1.6,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: SnapColors.warning),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: SnapColors.warning, width: 1.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: surface,
        elevation: isDark ? 8 : 10,
        shadowColor: surfaceShadow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        labelTextStyle: MaterialStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(MaterialState.selected)
                ? accent
                : onSurfaceVariant,
            fontSize: 11.5,
            letterSpacing: 0.1,
            fontWeight: states.contains(MaterialState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
          ),
        ),
        iconTheme: MaterialStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(MaterialState.selected)
                ? accent
                : onSurfaceVariant,
            size: states.contains(MaterialState.selected) ? 25 : 24,
          ),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent,
        unselectedItemColor: onSurfaceVariant,
        elevation: isDark ? 8 : 10,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: elevatedSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: surfaceShadow,
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: outlineVariant),
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: elevatedSurface,
        modalBackgroundColor: elevatedSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: surfaceShadow,
        elevation: 20,
        modalElevation: 24,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: elevatedSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: surfaceShadow,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: outlineVariant),
        ),
        textStyle: textTheme.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? SnapColors.darkSurfaceRaised : SnapColors.lightOnSurface,
        contentTextStyle: TextStyle(
          color: isDark ? SnapColors.darkOnSurface : Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: SnapColors.electricBlueBright,
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: SnapColors.electricBlue,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: SnapColors.electricBlue,
        selectionColor: SnapColors.electricBlue.withOpacity(0.28),
        selectionHandleColor: SnapColors.electricBlue,
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
    final foreground = scheme.onSurface;

    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        color: foreground,
        fontSize: 48,
        height: 1.06,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.5,
      ),
      displayMedium: base.displayMedium?.copyWith(
        color: foreground,
        fontSize: 40,
        height: 1.08,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
      ),
      displaySmall: base.displaySmall?.copyWith(
        color: foreground,
        fontSize: 34,
        height: 1.1,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        color: foreground,
        fontSize: 30,
        height: 1.14,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        color: foreground,
        fontSize: 26,
        height: 1.16,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.65,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        color: foreground,
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleLarge: base.titleLarge?.copyWith(
        color: foreground,
        fontSize: 20,
        height: 1.24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleMedium: base.titleMedium?.copyWith(
        color: foreground,
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.15,
      ),
      titleSmall: base.titleSmall?.copyWith(
        color: foreground,
        fontSize: 14,
        height: 1.32,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.05,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        color: foreground,
        fontSize: 17,
        height: 1.48,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.15,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        color: foreground,
        fontSize: 15,
        height: 1.48,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.1,
      ),
      bodySmall: base.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
        fontSize: 13,
        height: 1.46,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      labelLarge: base.labelLarge?.copyWith(
        color: foreground,
        fontSize: 16,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
      ),
      labelMedium: base.labelMedium?.copyWith(
        color: foreground,
        fontSize: 13,
        height: 1.24,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.12,
      ),
      labelSmall: base.labelSmall?.copyWith(
        color: scheme.onSurfaceVariant,
        fontSize: 11,
        height: 1.24,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.32,
      ),
    );
  }
}
