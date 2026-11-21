import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'brew_settings.dart';
import 'home_screen.dart';
import 'native_bridge.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  NativeBridge.init();
  SystemChrome.setSystemUIOverlayStyle(appOverlayStyle);
  final settings = await BrewSettings.load();
  final timer = await NativeBridge.timerState();
  final pendingAction = await NativeBridge.takeNotificationAction();
  if (pendingAction != null) {
    NativeBridge.notificationActions.value = pendingAction;
  }
  runApp(CoffeeTimerApp(settings: settings, timer: timer));
}

class CoffeeTimerApp extends StatelessWidget {
  const CoffeeTimerApp({super.key, required this.settings, this.timer});

  final BrewSettings settings;
  final NativeTimerState? timer;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Coffee's Ready!",
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: appOverlayStyle,
        child: child ?? const SizedBox.shrink(),
      ),
      home: HomeScreen(settings: settings, timer: timer),
    );
  }
}
