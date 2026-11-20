import 'package:coffee_timer/brew_math.dart';
import 'package:coffee_timer/brew_settings.dart';
import 'package:coffee_timer/main.dart';
import 'package:coffee_timer/native_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('brew math', () {
    test('water follows the coffee to water ratio', () {
      expect(waterFor(14, 16), 224);
      expect(waterFor(0, 16), 0);
      expect(waterFor(-5, 16), 0);
    });

    test('clock rounds partial seconds up and never goes negative', () {
      expect(formatClock(const Duration(minutes: 2, seconds: 25)), '02:25');
      expect(formatClock(const Duration(milliseconds: 150)), '00:01');
      expect(formatClock(const Duration(milliseconds: 1001)), '00:02');
      expect(formatClock(Duration.zero), '00:00');
      expect(formatClock(const Duration(milliseconds: -900)), '00:00');
    });
  });

  test('presets default to 2:15, 2:25 and 2:35', () {
    final presets = BrewSettings().presets;
    expect(presets.map((preset) => preset.inSeconds).toList(), [135, 145, 155]);
  });

  test('ships with the Timer Event alarm by default', () {
    final settings = BrewSettings();
    expect(settings.alarmUri, kBundledAlarmUri);
    expect(settings.alarmTitle, 'Timer Event');
  });

  testWidgets('opens with the requested coffee defaults', (tester) async {
    await tester.pumpWidget(CoffeeTimerApp(settings: BrewSettings()));

    expect(find.text('224'), findsOneWidget);
    expect(find.text('02:25'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('1 : 16'), findsOneWidget);
    expect(find.text('2:15'), findsOneWidget);
    expect(find.text('2:35'), findsOneWidget);
  });

  testWidgets('presets can be adjusted in settings on a phone screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const channel = MethodChannel('coffee_timer/native');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'alarms':
          return const <Map<String, String>>[];
        case 'loadSettings':
          return const <String, Object?>{};
        default:
          return null;
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final settings = BrewSettings();
    await tester.pumpWidget(CoffeeTimerApp(settings: settings));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('TIMER PRESETS'), findsOneWidget);
    expect(find.text('02:15'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Preset 1, 5 seconds longer'));
    await tester.pumpAndSettle();

    expect(find.text('02:20'), findsOneWidget);
    expect(settings.presets.first, const Duration(minutes: 2, seconds: 20));

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('2:20'), findsOneWidget);
  });

  testWidgets('notification actions stop or extend the timer', (tester) async {
    addTearDown(() => NativeBridge.notificationActions.value = null);

    await tester.pumpWidget(CoffeeTimerApp(settings: BrewSettings()));

    NativeBridge.notificationActions.value = 'add15';
    await tester.pump();
    expect(find.text('00:15'), findsOneWidget);
    expect(find.text('BREWING'), findsOneWidget);

    NativeBridge.notificationActions.value = 'stop';
    await tester.pump();
    expect(find.text('02:25'), findsOneWidget);
    expect(find.text('READY TO BREW'), findsOneWidget);
  });
}
