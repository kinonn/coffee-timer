# AGENTS.md

Instructions for agents working in this repository. For user-facing docs, build instructions, and screenshots, see [README.md](README.md).

## What this is

A small Flutter app for French press coffee: a water calculator and a brew timer. The UI is Dart; native functionality (alarm tones, notifications, settings storage) lives in a single Android method-channel bridge. There are no Flutter plugins in `pubspec.yaml`.

## Layout

- `lib/home_screen.dart` — main screen: calculator card, circular timer dial, start/pause/reset controls, app-lifecycle observer for the background notification.
- `lib/settings_screen.dart` — coffee ratio slider, single timer duration row, alarm-sound picker.
- `lib/brew_math.dart` — water/ratio math plus `formatClock` / `formatTimer`.
- `lib/brew_settings.dart` — persisted settings model; one timer duration, default 2:25.
- `lib/native_bridge.dart` — Dart side of the `coffee_timer/native` method channel.
- `lib/theme.dart` — palette, label style, background gradient, `ThemeData`.
- `android/app/src/main/kotlin/com/kinonn/coffee_timer/MainActivity.kt` — Android side of the channel: notifications, alarm playback, `SharedPreferences`.
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

- Lists the phone's alarm tones via `RingtoneManager` (`TYPE_ALARM`).
- Default alarm is the AOSP DeskClock timer sound, bundled as `timer_event.ogg` under Apache 2.0; Settings can preview any sound.
- Plays the chosen tone on the alarm audio stream, looping until stopped.
- Posts an ongoing **Brewing** notification with the live countdown when the app is backgrounded while the timer runs. Android updates it every second from an end timestamp because Flutter timers are throttled in the background; the notification timestamp is hidden.
- Posts an **Enjoy!** completion notification with **Stop** and **+15 s** actions.
- Stores the ratio, timer duration, and chosen alarm in native `SharedPreferences`.
- Only permission is Android 13's `POST_NOTIFICATIONS`, requested when the timer starts.

## Behavior to preserve

- Timer default 2:25; one editable duration in Settings; ±5 s controls only while idle.
- Ring starts full and drains to empty. Past zero the value counts into negative time (e.g. `-00:05`) and the ticker keeps running.
- The ±5 s buttons sit inside the ring and are hidden while running; they are absolutely positioned so the timer card never changes size.
- The main screen never scrolls; content is fitted with `LayoutBuilder` + `FittedBox`.
- WATER label on the left, droplet icon on the right, vertically aligned with the value.
- Notifications: **Brewing** while backgrounded, **Enjoy!** at completion, both without a timestamp.

## Conventions and gotchas

- Prefer the standard library, Flutter widgets, and native platform features over new dependencies.
- For UI work, review a static HTML mockup in `docs/preview/` first when the user asks for a preview. Verify rendered output with a temporary golden test (`flutter test --update-goldens test/preview_test.dart`), then delete the temporary test and its PNGs.
- Screenshots in `docs/screenshots/` must have the status bar cropped; it contains personal identifiers.
- Never commit device serial numbers, tokens, or other personal identifiers to the repository. Use `<your-device-id>` or `adb -d` in examples.
- Release builds currently use debug signing. Replace with a real keystore before publishing.
- `android/local.properties`, IDE folders (`.idea/`, `.vscode/`, `.opencode/`), build output, and signing material (`key.properties`, `*.jks`, `*.keystore`) must remain gitignored.
- iOS has no native bridge: the alarm, notifications, and settings persistence will not work there without adding one in `AppDelegate.swift`.
- Alarm, completion notification, and background countdown require the app process to stay alive. A foreground service is the upgrade path for surviving process death.
- Keep architecture and implementation detail here; keep README user-facing.
