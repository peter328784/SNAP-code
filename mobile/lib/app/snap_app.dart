import 'package:flutter/material.dart';

import '../features/parking_lot/parking_application.dart';
import 'app_config.dart';
import 'snap_theme.dart';

class SnapApp extends StatefulWidget {
  const SnapApp({
    required this.config,
    this.initialThemeMode = ThemeMode.system,
    super.key,
  });

  final AppConfig config;
  final ThemeMode initialThemeMode;

  @override
  State<SnapApp> createState() => _SnapAppState();
}

class _SnapAppState extends State<SnapApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'S.N.A.P',
      debugShowCheckedModeBanner: false,
      theme: SnapTheme.light(),
      darkTheme: SnapTheme.dark(),
      themeMode: _themeMode,
      home: ParkingApplication(
        gatewayBaseUri: widget.config.gatewayBaseUri,
        lotId: widget.config.lotId,
        customerId: widget.config.customerId,
        themeMode: _themeMode,
        onThemeModeChanged: (mode) {
          if (mode != _themeMode) {
            setState(() => _themeMode = mode);
          }
        },
      ),
    );
  }
}
