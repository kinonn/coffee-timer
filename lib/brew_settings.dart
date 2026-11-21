import 'native_bridge.dart';

class BrewSettings {
  BrewSettings({
    this.ratio = defaultRatio,
    this.alarmUri = kBundledAlarmUri,
    this.alarmTitle = defaultAlarmTitle,
    List<Duration>? presets,
  }) : presets = List<Duration>.of(presets ?? defaultPresets);

  static const int defaultRatio = 16;
  static const int minRatio = 8;
  static const int maxRatio = 24;
  static const String defaultAlarmTitle = kBundledAlarmTitle;
  static const int minTimerSeconds = 5;
  static const int maxTimerSeconds = 30 * 60;

  static const List<Duration> defaultPresets = [
    Duration(minutes: 2, seconds: 25),
  ];

  int ratio;
  String? alarmUri;
  String alarmTitle;
  final List<Duration> presets;

  static Duration _clampPreset(int seconds) => Duration(
    seconds: seconds.clamp(minTimerSeconds, maxTimerSeconds).toInt(),
  );

  static Future<BrewSettings> load() async {
    final stored = await NativeBridge.loadSettings();
    final rawRatio = stored['ratio'];
    final storedRatio = rawRatio is int ? rawRatio : defaultRatio;
    final rawUri = stored['alarmUri'];
    final rawTitle = stored['alarmTitle'];
    final rawPresets = stored['presets'];
    final loadedPresets = <Duration>[];
    if (rawPresets is List) {
      for (final value in rawPresets) {
        if (value is int) loadedPresets.add(_clampPreset(value));
      }
    }

    return BrewSettings(
      ratio: storedRatio.clamp(minRatio, maxRatio).toInt(),
      alarmUri: rawUri is String && rawUri.isNotEmpty ? rawUri : null,
      alarmTitle: rawTitle is String ? rawTitle : defaultAlarmTitle,
      presets: loadedPresets.length == defaultPresets.length
          ? loadedPresets
          : null,
    );
  }

  Future<void> save() => NativeBridge.saveSettings(
    ratio: ratio,
    alarmUri: alarmUri,
    alarmTitle: alarmTitle,
    presetSeconds: presets.map((preset) => preset.inSeconds).toList(),
  );
}
