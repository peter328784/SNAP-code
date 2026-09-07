import 'package:flutter/widgets.dart';

import 'app/app_config.dart';
import 'app/snap_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SnapApp(config: AppConfig.fromEnvironment()));
}
