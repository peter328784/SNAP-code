// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap_mobile/app/snap_theme.dart';
import 'package:snap_mobile/features/parking_lot/parking_views.dart';

void main() {
  group('SnapTheme', () {
    test('uses accessible mode-specific electric blue accents', () {
      final light = SnapTheme.light();
      final dark = SnapTheme.dark();

      expect(SnapColors.electricBlue, const Color(0xFF087CFA));
      expect(light.colorScheme.primary, SnapColors.electricBlueDeep);
      expect(light.colorScheme.secondary, SnapColors.electricBlueDeep);
      expect(dark.colorScheme.primary, SnapColors.electricBlueBright);
      expect(dark.colorScheme.secondary, SnapColors.electricBlueBright);
      expect(light.colorScheme.onPrimary, Colors.white);
      expect(dark.colorScheme.onPrimary, const Color(0xFF002C55));
      expect(
        _contrastRatio(
          light.colorScheme.primary,
          light.colorScheme.onPrimary,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(
          dark.colorScheme.primary,
          dark.colorScheme.onPrimary,
        ),
        greaterThanOrEqualTo(4.5),
      );

      for (final theme in <ThemeData>[light, dark]) {
        expect(
          theme.filledButtonTheme.style?.backgroundColor
              ?.resolve(<MaterialState>{}),
          SnapColors.electricBlueDeep,
        );
        expect(
          theme.navigationBarTheme.iconTheme
              ?.resolve(<MaterialState>{MaterialState.selected})?.color,
          theme.colorScheme.primary,
        );
        expect(
          theme.navigationBarTheme.labelTextStyle
              ?.resolve(<MaterialState>{MaterialState.selected})?.color,
          theme.colorScheme.primary,
        );
      }
    });

    test('keeps mode-specific surfaces and a non-red warning palette', () {
      final light = SnapTheme.light();
      final dark = SnapTheme.dark();

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.scaffoldBackgroundColor, SnapColors.lightBackground);
      expect(dark.scaffoldBackgroundColor, SnapColors.darkBackground);
      expect(light.colorScheme.surface, Colors.white);
      expect(dark.colorScheme.surface, SnapColors.darkSurface);
      expect(light.inputDecorationTheme.fillColor, Colors.white);
      expect(dark.inputDecorationTheme.fillColor, const Color(0xFF0B0D0F));

      expect(light.colorScheme.error, SnapColors.warningDeep);
      expect(dark.colorScheme.error, SnapColors.warning);
      expect(light.colorScheme.errorContainer, const Color(0xFFFFE8B0));
      expect(dark.colorScheme.errorContainer, const Color(0xFF382A06));
      expect(light.colorScheme.onError, Colors.white);
      expect(dark.colorScheme.onError, const Color(0xFF17130A));
      expect(light.colorScheme.onErrorContainer, const Color(0xFF4A3400));
      expect(dark.colorScheme.onErrorContainer, const Color(0xFFFFD56A));
      expect(
        _contrastRatio(light.colorScheme.error, light.colorScheme.onError),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(dark.colorScheme.error, dark.colorScheme.onError),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  testWidgets('theme mode selector reports the selected mode', (tester) async {
    var selectedMode = ThemeMode.system;

    await tester.pumpWidget(
      MaterialApp(
        theme: SnapTheme.light(),
        home: Scaffold(
          body: ThemeModeSelectorHarness(
            value: selectedMode,
            onChanged: (mode) => selectedMode = mode,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('theme-mode-dark')));

    expect(selectedMode, ThemeMode.dark);
  });
}

double _contrastRatio(Color first, Color second) {
  final lighter =
      first.computeLuminance() > second.computeLuminance() ? first : second;
  final darker = identical(lighter, first) ? second : first;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

class ThemeModeSelectorHarness extends StatelessWidget {
  const ThemeModeSelectorHarness({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return ThemeModeSelector(value: value, onChanged: onChanged);
  }
}
