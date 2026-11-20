import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'brew_math.dart';
import 'brew_settings.dart';
import 'native_bridge.dart';
import 'theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings});

  final BrewSettings settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<AlarmSound>? _sounds;
  bool _loadingSounds = true;

  @override
  void initState() {
    super.initState();
    _loadSounds();
  }

  Future<void> _loadSounds() async {
    final sounds = await NativeBridge.alarms();
    if (!mounted) return;
    setState(() {
      _sounds = sounds;
      _loadingSounds = false;
    });
  }

  void _changeRatio(double value) {
    setState(() => widget.settings.ratio = value.round());
  }

  void _saveRatio(double _) {
    unawaited(widget.settings.save());
  }

  void _selectAlarm(AlarmSound sound) {
    setState(() {
      widget.settings.alarmUri = sound.uri;
      widget.settings.alarmTitle = sound.title;
    });
    unawaited(widget.settings.save());
    unawaited(NativeBridge.playPreview(sound.uri));
  }

  @override
  void dispose() {
    unawaited(NativeBridge.stopPreview());
    super.dispose();
  }

  void _changePreset(int index, int deltaSeconds) {
    final current = widget.settings.presets[index];
    final seconds = (current.inSeconds + deltaSeconds)
        .clamp(BrewSettings.minTimerSeconds, BrewSettings.maxTimerSeconds)
        .toInt();
    setState(() {
      widget.settings.presets[index] = Duration(seconds: seconds);
    });
    unawaited(widget.settings.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: appBackground,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 24, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back_rounded),
                      style: IconButton.styleFrom(foregroundColor: kEspresso),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: kEspresso,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 32),
                  children: [
                    _ratioCard(),
                    const SizedBox(height: 18),
                    _presetsCard(),
                    const SizedBox(height: 18),
                    _alarmCard(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ratioCard() {
    final ratio = widget.settings.ratio;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('COFFEE TO WATER', style: kLabelStyle),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '1 : $ratio',
                    style: const TextStyle(
                      fontSize: 38,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: kEspresso,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$ratio g water\nper 1 g coffee',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: kRoast,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: ratio.toDouble(),
            min: BrewSettings.minRatio.toDouble(),
            max: BrewSettings.maxRatio.toDouble(),
            divisions: BrewSettings.maxRatio - BrewSettings.minRatio,
            label: '1 : $ratio',
            activeColor: kCaramel,
            inactiveColor: kLatte,
            onChanged: _changeRatio,
            onChangeEnd: _saveRatio,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Stronger', style: TextStyle(fontSize: 11, color: kRoast)),
                Text('Lighter', style: TextStyle(fontSize: 11, color: kRoast)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Default is 16 grams of water for every gram of coffee.',
            style: TextStyle(fontSize: 12, height: 1.4, color: kRoast),
          ),
        ],
      ),
    );
  }

  Widget _presetsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TIMER PRESETS', style: kLabelStyle),
          const SizedBox(height: 6),
          const Text(
            'Quick timers shown on the main screen.',
            style: TextStyle(fontSize: 12, color: kRoast),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < widget.settings.presets.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: kLine),
            _presetRow(i),
          ],
        ],
      ),
    );
  }

  Widget _presetRow(int index) {
    final duration = widget.settings.presets[index];
    final canDecrease = duration.inSeconds > BrewSettings.minTimerSeconds;
    final canIncrease = duration.inSeconds < BrewSettings.maxTimerSeconds;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, size: 18, color: kRoast),
          const SizedBox(width: 12),
          Text(
            formatClock(duration),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: kEspresso,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          _presetAdjustButton(
            icon: Icons.remove_rounded,
            tooltip: 'Preset ${index + 1}, 5 seconds shorter',
            onPressed: canDecrease ? () => _changePreset(index, -5) : null,
          ),
          const SizedBox(width: 4),
          _presetAdjustButton(
            icon: Icons.add_rounded,
            tooltip: 'Preset ${index + 1}, 5 seconds longer',
            onPressed: canIncrease ? () => _changePreset(index, 5) : null,
          ),
        ],
      ),
    );
  }

  Widget _presetAdjustButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        backgroundColor: kLatte,
        foregroundColor: kEspresso,
        disabledBackgroundColor: kLatte.withValues(alpha: 0.4),
        disabledForegroundColor: kRoast.withValues(alpha: 0.3),
        fixedSize: const Size(40, 40),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
      ),
    );
  }

  Widget _alarmCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ALARM SOUND', style: kLabelStyle),
          const SizedBox(height: 6),
          const Text(
            'Tap a sound to preview it.',
            style: TextStyle(fontSize: 12, color: kRoast),
          ),
          const SizedBox(height: 8),
          if (_loadingSounds)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: kCaramel,
                  ),
                ),
              ),
            )
          else
            ..._soundRows(_sounds ?? const [kSystemAlarm]),
        ],
      ),
    );
  }

  List<Widget> _soundRows(List<AlarmSound> sounds) {
    final rows = <Widget>[];
    for (var i = 0; i < sounds.length; i++) {
      final sound = sounds[i];
      final selected = sound.uri == widget.settings.alarmUri;
      rows.add(
        Semantics(
          button: true,
          selected: selected,
          label: sound.title,
          excludeSemantics: true,
          onTap: () => _selectAlarm(sound),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _selectAlarm(sound),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      size: 20,
                      color: selected
                          ? kCaramel
                          : kRoast.withValues(alpha: 0.35),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        sound.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: kEspresso,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      if (i != sounds.length - 1) {
        rows.add(const Divider(height: 1, color: kLine));
      }
    }
    return rows;
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: kMilk,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: kEspresso.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}
