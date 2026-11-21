# AGENTS.md

Instructions for agents working in this repository. For user-facing docs, build instructions, and screenshots, see [README.md](README.md).

## What this is

A small Flutter app for French press coffee: a water calculator and a brew timer. The UI is Dart; native functionality (the timer service, alarm tones, notifications, settings storage) lives in a small Android method-channel bridge backed by a foreground service. There are no Flutter plugins in `pubspec.yaml`.

## Layout

- `lib/home_screen.dart` — main screen: calculator card, circular timer dial, start/pause/reset controls. Starts and restores the native timer; does not own the alarm.
- `lib/settings_screen.dart` — coffee ratio slider, single timer duration row, alarm-sound picker.
- `lib/brew_math.dart` — water/ratio math plus `formatClock` / `formatTimer`.
- `lib/brew_settings.dart` — persisted settings model; one timer duration, default 2:25.
- `lib/native_bridge.dart` — Dart side of the `coffee_timer/native` method channel.
- `lib/theme.dart` — palette, label style, background gradient, `ThemeData`.
- `android/app/src/main/kotlin/com/kinonn/coffee_timer/MainActivity.kt` — Android side of the channel: alarm list/preview, notification permission, settings, timer commands.
- `android/app/src/main/kotlin/com/kinonn/coffee_timer/TimerService.kt` — foreground service that owns the running timer, countdown notification, and alarm playback.
- `android/app/src/main/kotlin/com/kinonn/coffee_timer/TimerStore.kt` — persisted timer state (`endAt`, total, alarm).
- `android/app/src/main/kotlin/com/kinonn/coffee_timer/AlarmScheduler.kt` / `AlarmReceiver.kt` — exact-alarm backstop that restarts the service after process death.
- `android/app/src/main/kotlin/com/kinonn/coffee_timer/ExactAlarmPermissionReceiver.kt` — reschedules the backstop when exact-alarm access is granted or revoked.
- `android/app/src/main/kotlin/com/kinonn/coffee_timer/BootReceiver.kt` — clears persisted timer state after a reboot.
- `android/app/src/main/kotlin/com/kinonn/coffee_timer/BrewNotifications.kt` — notification channel and Brewing/Enjoy notifications.
- `android/app/src/main/kotlin/com/kinonn/coffee_timer/AlarmAudio.kt` — `MediaPlayer` setup for the bundled or system alarm.
- `assets/branding/` — master launcher icon (`app_icon.svg`, `app_icon.png`).
- `docs/screenshots/` — user-facing screenshots, cropped to remove the Android status bar.
- `docs/preview/` — static HTML mockups for reviewing UI changes before coding.
- `test/app_test.dart` — unit and widget tests.

## Commands

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter install -d <your-device-id>
```

With a single USB device connected, `adb -d install -r build/app/outputs/flutter-apk/app-release.apk` avoids needing a serial. On Windows, `adb` is usually at `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`.

## Native channel (`coffee_timer/native`)

- The channel controls a foreground `TimerService`; the service, not the Flutter isolate, owns a running timer.
- `startTimer` persists the end timestamp, total duration, and chosen alarm, starts the service, acquires a partial wake lock, and schedules an exact `AlarmManager` backstop when exact alarms are allowed.
- Lists the phone's alarm tones via `RingtoneManager` (`TYPE_ALARM`); Settings can preview any sound.
- Default alarm is the AOSP DeskClock timer sound, bundled as `timer_event.ogg` under Apache 2.0.
- Plays the chosen tone on the alarm audio stream, looping until stopped by Stop or Reset.
- Updates an ongoing **Brewing** notification once a second from the end timestamp; the notification timestamp is hidden.
- Posts an **Enjoy!** completion notification with **Stop** and **+15 s** actions. **Stop** stops the service directly, so it works without unlocking; **+15 s** opens `MainActivity` so Dart can restart the timer.
- `cancelTimer` cancels the alarm, stops the service, and clears persisted timer state and notifications.
- `timerState` lets the UI restore a running or finished timer after the Activity is recreated.
- On Android 12+, `canScheduleExactAlarms`/`requestExactAlarms` drive a one-time prompt that opens the system's exact-alarm access screen. `ExactAlarmPermissionReceiver` reschedules the backstop when the user grants or revokes access.
- Stores the ratio, timer duration, chosen alarm, and timer state in native `SharedPreferences`.
- Permissions: `POST_NOTIFICATIONS` (requested when the timer starts), `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `WAKE_LOCK`, `SCHEDULE_EXACT_ALARM`, and `RECEIVE_BOOT_COMPLETED`.

## Behavior to preserve

- Timer default 2:25; one editable duration in Settings; ±5 s controls only while idle.
- Ring starts full and drains to empty. Past zero the value counts into negative time (e.g. `-00:05`) and the ticker keeps running.
- The ±5 s buttons sit inside the ring and are hidden while running; they are absolutely positioned so the timer card never changes size.
- The main screen never scrolls; content is fitted with `LayoutBuilder` + `FittedBox`.
- WATER label on the left, droplet icon on the right, vertically aligned with the value.
- The timer keeps running through backgrounding, Back, screen lock, and task removal. It stops only on Pause, Reset, Stop, force-stop, or reboot.
- On launch, a running or finished native timer is restored instead of resetting to the default preset.
- Notifications: ongoing **Brewing** whenever a timer runs, **Enjoy!** at completion, both without a timestamp.

## Conventions and gotchas

- Prefer the standard library, Flutter widgets, and native platform features over new dependencies.
- For UI work, review a static HTML mockup in `docs/preview/` first when the user asks for a preview. Verify rendered output with a temporary golden test (`flutter test --update-goldens test/preview_test.dart`), then delete the temporary test and its PNGs.
- Screenshots in `docs/screenshots/` must have the status bar cropped; it contains personal identifiers.
- Never commit device serial numbers, tokens, or other personal identifiers to the repository. Use `<your-device-id>` or `adb -d` in examples.
- Release builds currently use debug signing. Replace with a real keystore before publishing.
- `android/local.properties`, IDE folders (`.idea/`, `.vscode/`, `.opencode/`), build output, and signing material (`key.properties`, `*.jks`, `*.keystore`) must remain gitignored.
- iOS has no native bridge: the alarm, notifications, and settings persistence will not work there without adding one in `AppDelegate.swift`.
- Do not fire the alarm from Dart. `_finishTimer` only updates the UI; `TimerService` owns playback and the completion notification.
- Do not call `TimerService.stop` from `MainActivity.onDestroy` or `HomeScreen.dispose`; leaving the screen must not kill the timer.
- Exact alarms are a special access on Android 12+. The first timer start offers to open the system grant screen; without the grant the `AlarmManager` backstop is inexact. The foreground service plus partial wake lock is the primary mechanism either way.
- Aggressive OEM battery savers can still kill a foreground service. If a device drops the alarm, ask the user to exempt the app from battery optimization.
- Android 14 requires the `mediaPlayback` foreground service type; changing the service type means updating the manifest and the matching permission.
- `BootReceiver` clears persisted timer state on reboot. Force-stop does not clear it; reopening the app can restore a running timer from the saved deadline.
- Keep architecture and implementation detail here; keep README user-facing.
