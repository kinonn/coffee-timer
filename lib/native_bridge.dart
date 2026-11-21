import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AlarmSound {
  const AlarmSound({this.uri, required this.title});

  /// Null means the device's default alarm tone.
  final String? uri;
  final String title;
}

const kSystemAlarm = AlarmSound(title: 'System default');
const String kBundledAlarmUri = 'app:timer_event';
const String kBundledAlarmTitle = 'Timer Event';
const kTimerEventAlarm = AlarmSound(
  uri: kBundledAlarmUri,
  title: kBundledAlarmTitle,
);

/// The timer Android is currently running, if any. The native service owns
/// the alarm, so this is how the UI resumes after the Activity is recreated.
class NativeTimerState {
  const NativeTimerState({
    required this.running,
    required this.finished,
    required this.endAtMillis,
    required this.totalMillis,
    this.alarmUri,
    this.alarmTitle = kBundledAlarmTitle,
  });

  final bool running;
  final bool finished;
  final int endAtMillis;
  final int totalMillis;
  final String? alarmUri;
  final String alarmTitle;
}

/// Everything the app needs from the Android side: system alarm sounds,
/// the native timer service, and remembering the settings.
class NativeBridge {
  static const _channel = MethodChannel('coffee_timer/native');

  static final ValueNotifier<String?> notificationActions =
      ValueNotifier<String?>(null);
  static bool _initialized = false;

  /// Hooks up native-to-Dart calls. Call once before `runApp`.
  static void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'notificationAction') {
        notificationActions.value = call.arguments as String?;
      }
    });
  }

  static Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    } on PlatformException {
      // The timer still works; just no notification.
    } on MissingPluginException {
      // No notification bridge on this platform.
    }
  }

  static Future<bool?> startTimer({
    required int endAtMillis,
    required int totalMillis,
    required String? alarmUri,
    required String alarmTitle,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('startTimer', {
        'endAt': endAtMillis,
        'totalMs': totalMillis,
        'alarmUri': alarmUri,
        'alarmTitle': alarmTitle,
      });
    } on PlatformException {
      // The native service refused the start; the caller should reset.
      return false;
    } on MissingPluginException {
      // No native timer service on this platform; keep the Dart timer.
      return null;
    }
  }

  static Future<void> cancelTimer() async {
    try {
      await _channel.invokeMethod<void>('cancelTimer');
    } on PlatformException {
      // Nothing to cancel.
    } on MissingPluginException {
      // No native timer service on this platform.
    }
  }

  static Future<bool> canScheduleExactAlarms() async {
    try {
      return await _channel.invokeMethod<bool>('canScheduleExactAlarms') ?? true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      // No native alarm on this platform.
      return true;
    }
  }

  static Future<void> requestExactAlarms() async {
    try {
      await _channel.invokeMethod<void>('requestExactAlarms');
    } on PlatformException {
      // The user can still enable it from system settings.
    } on MissingPluginException {
      // No native alarm on this platform.
    }
  }

  static Future<NativeTimerState?> timerState() async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'timerState',
      );
      if (raw == null || raw.isEmpty) return null;
      return NativeTimerState(
        running: raw['running'] == true,
        finished: raw['finished'] == true,
        endAtMillis: (raw['endAt'] as num?)?.toInt() ?? 0,
        totalMillis: (raw['totalMs'] as num?)?.toInt() ?? 0,
        alarmUri: raw['alarmUri'] as String?,
        alarmTitle: raw['alarmTitle'] as String? ?? kBundledAlarmTitle,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<String?> takeNotificationAction() async {
    try {
      return await _channel.invokeMethod<String>('takeNotificationAction');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<List<AlarmSound>> alarms() async {
    try {
      final raw =
          await _channel.invokeListMethod<Object?>('alarms') ??
          const <Object?>[];
      return [
        kTimerEventAlarm,
        kSystemAlarm,
        for (final item in raw)
          if (item is Map &&
              item['uri'] is String &&
              (item['uri'] as String).isNotEmpty)
            AlarmSound(
              title: (item['title'] as String?) ?? 'Alarm',
              uri: item['uri'] as String,
            ),
      ];
    } on PlatformException {
      return const [kSystemAlarm];
    } on MissingPluginException {
      return const [kSystemAlarm];
    }
  }

  static Future<void> playPreview(String? uri) async {
    try {
      await _channel.invokeMethod<void>('playPreview', {'uri': uri});
    } on PlatformException {
      // Preview unavailable; selection still works.
    } on MissingPluginException {
      // No native alarm bridge on this platform.
    }
  }

  static Future<void> stopPreview() async {
    try {
      await _channel.invokeMethod<void>('stopPreview');
    } on PlatformException {
      // Nothing to stop.
    } on MissingPluginException {
      // No native alarm bridge on this platform.
    }
  }

  static Future<Map<Object?, Object?>> loadSettings() async {
    try {
      return await _channel.invokeMapMethod<Object?, Object?>('loadSettings') ??
          const <Object?, Object?>{};
    } on PlatformException {
      return const <Object?, Object?>{};
    } on MissingPluginException {
      return const <Object?, Object?>{};
    }
  }

  static Future<void> saveSettings({
    required int ratio,
    required String? alarmUri,
    required String alarmTitle,
    required List<int> presetSeconds,
  }) async {
    try {
      await _channel.invokeMethod<void>('saveSettings', {
        'ratio': ratio,
        'alarmUri': alarmUri,
        'alarmTitle': alarmTitle,
        'presets': presetSeconds,
      });
    } on PlatformException {
      // Keep working with the in-memory settings.
    } on MissingPluginException {
      // No native settings store on this platform.
    }
  }
}
