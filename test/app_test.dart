import 'package:coffee_timer/brew_math.dart';
import 'package:coffee_timer/brew_settings.dart';
import 'package:coffee_timer/main.dart';
import 'package:coffee_timer/native_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

List<MethodCall> _installNativeMock({
  Map<String, Object?>? state,
  bool startTimerResult = true,
  bool canScheduleExactAlarms = true,
}) {
  final calls = <MethodCall>[];
  const channel = MethodChannel('coffee_timer/native');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    calls.add(call);
    if (call.method == 'timerState') {
      return state ?? const <String, Object?>{};
    }
    if (call.method == 'startTimer') return startTimerResult;
    if (call.method == 'canScheduleExactAlarms') {
      return canScheduleExactAlarms;
    }
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return calls;
}

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

    test('timer shows elapsed time as negative', () {
      expect(formatTimer(const Duration(seconds: 5)), '00:05');
      expect(formatTimer(const Duration(seconds: -5)), '-00:05');
      expect(formatTimer(const Duration(seconds: -65)), '-01:05');
    });
  });

  test('timer preset defaults to 2:25', () {
    final presets = BrewSettings().presets;
    expect(presets.map((preset) => preset.inSeconds).toList(), [145]);
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
    expect(find.text('- 5 s'), findsOneWidget);
    expect(find.text('+ 5 s'), findsOneWidget);
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

    expect(find.text('TIMER DURATION'), findsOneWidget);
    expect(find.text('02:25'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Timer, 5 seconds longer'));
    await tester.pumpAndSettle();

    expect(find.text('02:30'), findsOneWidget);
    expect(settings.presets.first, const Duration(minutes: 2, seconds: 30));

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('02:30'), findsOneWidget);
  });

  testWidgets('notification actions stop or extend the timer', (tester) async {
    _installNativeMock();
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

  testWidgets('start hands the deadline to the native timer service', (
    tester,
  ) async {
    final calls = _installNativeMock();
    final settings = BrewSettings(presets: [const Duration(seconds: 5)]);

    await tester.pumpWidget(CoffeeTimerApp(settings: settings));
    await tester.tap(find.text('Start brewing'));
    await tester.pump();

    final start = calls.singleWhere((call) => call.method == 'startTimer');
    final args = start.arguments as Map<Object?, Object?>;
    expect(args['totalMs'], 5000);
    expect(args['alarmUri'], kBundledAlarmUri);
    final expected = DateTime.now().millisecondsSinceEpoch + 5000;
    expect(((args['endAt'] as int) - expected).abs(), lessThan(1000));
  });

  testWidgets('pause cancels the native timer', (tester) async {
    final calls = _installNativeMock();
    final settings = BrewSettings(presets: [const Duration(seconds: 5)]);

    await tester.pumpWidget(CoffeeTimerApp(settings: settings));
    await tester.tap(find.text('Start brewing'));
    await tester.pump();
    await tester.tap(find.text('Pause'));
    await tester.pump();

    expect(calls.any((call) => call.method == 'cancelTimer'), isTrue);
  });

  testWidgets('a refused native start returns the timer to idle', (
    tester,
  ) async {
    _installNativeMock(startTimerResult: false);
    final settings = BrewSettings(presets: [const Duration(seconds: 5)]);

    await tester.pumpWidget(CoffeeTimerApp(settings: settings));
    await tester.tap(find.text('Start brewing'));
    await tester.pump();
    await tester.pump();

    expect(find.text('READY TO BREW'), findsOneWidget);
    expect(find.text('Start brewing'), findsOneWidget);
  });

  testWidgets('offers to enable exact alarms when they are unavailable', (
    tester,
  ) async {
    final calls = _installNativeMock(canScheduleExactAlarms: false);
    final settings = BrewSettings(presets: [const Duration(seconds: 5)]);

    await tester.pumpWidget(CoffeeTimerApp(settings: settings));
    await tester.tap(find.text('Start brewing'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Allow exact alarms?'), findsOneWidget);

    await tester.tap(find.text('Open settings'));
    await tester.pump();

    expect(calls.any((call) => call.method == 'requestExactAlarms'), isTrue);
  });

  testWidgets('a native timer is picked up when the app resumes', (
    tester,
  ) async {
    _installNativeMock(
      state: {
        'running': true,
        'finished': false,
        'endAt': DateTime.now()
            .add(const Duration(seconds: 90))
            .millisecondsSinceEpoch,
        'totalMs': const Duration(minutes: 2).inMilliseconds,
        'alarmUri': kBundledAlarmUri,
        'alarmTitle': kBundledAlarmTitle,
      },
    );

    await tester.pumpWidget(CoffeeTimerApp(settings: BrewSettings()));
    expect(find.text('READY TO BREW'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('BREWING'), findsOneWidget);
  });

  testWidgets('the +15 action schedules fifteen seconds natively', (
    tester,
  ) async {
    final calls = _installNativeMock();
    addTearDown(() => NativeBridge.notificationActions.value = null);

    await tester.pumpWidget(CoffeeTimerApp(settings: BrewSettings()));
    NativeBridge.notificationActions.value = 'add15';
    await tester.pump();

    final start = calls.lastWhere((call) => call.method == 'startTimer');
    final args = start.arguments as Map<Object?, Object?>;
    expect(args['totalMs'], 15000);
  });

  testWidgets('leaving the screen keeps the native timer running', (
    tester,
  ) async {
    final calls = _installNativeMock();
    final settings = BrewSettings(presets: [const Duration(seconds: 5)]);

    await tester.pumpWidget(CoffeeTimerApp(settings: settings));
    await tester.tap(find.text('Start brewing'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    expect(calls.any((call) => call.method == 'cancelTimer'), isFalse);
  });

  testWidgets('a running native timer is restored when the app reopens', (
    tester,
  ) async {
    _installNativeMock();
    final timer = NativeTimerState(
      running: true,
      finished: false,
      endAtMillis: DateTime.now()
          .add(const Duration(seconds: 90))
          .millisecondsSinceEpoch,
      totalMillis: const Duration(minutes: 2).inMilliseconds,
    );

    await tester.pumpWidget(
      CoffeeTimerApp(settings: BrewSettings(), timer: timer),
    );
    await tester.pump();

    expect(find.text('BREWING'), findsOneWidget);
    expect(find.text('02:25'), findsNothing);
    expect(find.text('Start brewing'), findsNothing);
  });

  testWidgets('a finished native timer is restored as time is up', (
    tester,
  ) async {
    _installNativeMock();
    final timer = NativeTimerState(
      running: true,
      finished: true,
      endAtMillis: DateTime.now()
          .subtract(const Duration(seconds: 5))
          .millisecondsSinceEpoch,
      totalMillis: const Duration(minutes: 1).inMilliseconds,
    );

    await tester.pumpWidget(
      CoffeeTimerApp(settings: BrewSettings(), timer: timer),
    );
    await tester.pump();

    expect(find.text("TIME'S UP"), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });

  test('reads a running timer state from the native bridge', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _installNativeMock(
      state: {
        'running': true,
        'finished': false,
        'endAt': 123456,
        'totalMs': 5000,
        'alarmUri': kBundledAlarmUri,
        'alarmTitle': kBundledAlarmTitle,
      },
    );

    final state = await NativeBridge.timerState();

    expect(state?.running, isTrue);
    expect(state?.finished, isFalse);
    expect(state?.endAtMillis, 123456);
    expect(state?.totalMillis, 5000);
    expect(state?.alarmUri, kBundledAlarmUri);
  });
}
