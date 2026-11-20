import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'brew_math.dart';
import 'brew_settings.dart';
import 'native_bridge.dart';
import 'settings_screen.dart';
import 'theme.dart';

const _coffeeTextStyle = TextStyle(
  fontSize: 44,
  height: 1.15,
  fontWeight: FontWeight.w600,
  color: kEspresso,
  fontFeatures: [FontFeature.tabularFigures()],
);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.settings});

  final BrewSettings settings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _TimerStatus { idle, running, paused, finished }

class _HomeScreenState extends State<HomeScreen> {
  static const _defaultTimer = Duration(minutes: 2, seconds: 25);
  static const _minTimer = Duration(seconds: BrewSettings.minTimerSeconds);
  static const _maxTimer = Duration(seconds: BrewSettings.maxTimerSeconds);
  static final _coffeePattern = RegExp(r'^\d{0,3}([.,]\d{0,2})?$');

  final _coffeeController = TextEditingController(text: '14');
  final _coffeeFocus = FocusNode();
  final _coffeeFormatter = TextInputFormatter.withFunction((
    oldValue,
    newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    if (!_coffeePattern.hasMatch(newValue.text)) return oldValue;
    final parsed = double.tryParse(newValue.text.replaceAll(',', '.'));
    if (parsed != null && parsed > 200) return oldValue;
    return newValue;
  });

  late Duration _selected = _defaultTimer;
  late Duration _remaining = _defaultTimer;
  late Duration _total = _defaultTimer;
  DateTime? _endsAt;
  Timer? _ticker;
  _TimerStatus _status = _TimerStatus.idle;

  @override
  void initState() {
    super.initState();
    _coffeeFocus.addListener(_handleCoffeeFocus);
    NativeBridge.notificationActions.addListener(_handleNotificationAction);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _handleNotificationAction(),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    NativeBridge.notificationActions.removeListener(_handleNotificationAction);
    _coffeeFocus.removeListener(_handleCoffeeFocus);
    _coffeeFocus.dispose();
    _coffeeController.dispose();
    unawaited(NativeBridge.stopAlarm());
    super.dispose();
  }

  void _handleNotificationAction() {
    final action = NativeBridge.notificationActions.value;
    if (action == null) return;
    NativeBridge.notificationActions.value = null;
    if (action == 'stop') {
      _resetTimer();
    } else if (action == 'add15') {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      _addFifteenSeconds();
    }
  }

  void _handleCoffeeFocus() {
    if (!_coffeeFocus.hasFocus) _normalizeCoffee();
  }

  double get _coffeeGrams =>
      double.tryParse(_coffeeController.text.replaceAll(',', '.')) ?? 0;

  int get _waterMl => waterFor(_coffeeGrams, widget.settings.ratio).round();

  double get _progress {
    final total = _total.inMilliseconds;
    if (total <= 0) return 0;
    final left = _remaining.inMilliseconds.clamp(0, total).toInt();
    return 1 - left / total;
  }

  String _formatGrams(double grams) {
    final clamped = grams.clamp(1.0, 200.0).toDouble();
    return clamped == clamped.roundToDouble()
        ? clamped.toInt().toString()
        : clamped.toStringAsFixed(1);
  }

  void _setCoffeeText(String text) {
    _coffeeController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {});
  }

  void _normalizeCoffee() {
    _setCoffeeText(_formatGrams(_coffeeGrams <= 0 ? 1 : _coffeeGrams));
  }

  void _changeCoffee(double delta) {
    _setCoffeeText(_formatGrams(_coffeeGrams + delta));
  }

  void _setDuration(Duration duration) {
    if (_status == _TimerStatus.running) return;
    final seconds = duration.inSeconds
        .clamp(_minTimer.inSeconds, _maxTimer.inSeconds)
        .toInt();
    setState(() {
      _selected = Duration(seconds: seconds);
      _remaining = _selected;
      _total = _selected;
      _status = _TimerStatus.idle;
      _endsAt = null;
      _ticker?.cancel();
      _ticker = null;
    });
  }

  void _adjustDuration(int seconds) {
    if (_status != _TimerStatus.idle) return;
    _setDuration(_selected + Duration(seconds: seconds));
  }

  void _toggleTimer() {
    if (_status == _TimerStatus.running) {
      _pauseTimer();
    } else if (_status == _TimerStatus.finished) {
      _resetTimer();
    } else {
      _startTimer();
    }
  }

  void _startTimer() {
    final resuming = _status == _TimerStatus.paused;
    final base = resuming ? _remaining : _selected;
    if (base <= Duration.zero) return;
    unawaited(NativeBridge.requestNotificationPermission());
    unawaited(NativeBridge.stopAlarm());
    _ticker?.cancel();
    setState(() {
      if (!resuming) _total = _selected;
      _status = _TimerStatus.running;
      _remaining = base;
      _endsAt = DateTime.now().add(base);
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  void _pauseTimer() {
    _ticker?.cancel();
    final left = _endsAt?.difference(DateTime.now()) ?? _remaining;
    setState(() {
      _remaining = left > Duration.zero ? left : Duration.zero;
      _status = _TimerStatus.paused;
    });
  }

  void _tick() {
    final endsAt = _endsAt;
    if (endsAt == null) return;
    final left = endsAt.difference(DateTime.now());
    if (left <= Duration.zero) {
      _finishTimer();
    } else {
      setState(() => _remaining = left);
    }
  }

  void _finishTimer() {
    _ticker?.cancel();
    _ticker = null;
    setState(() {
      _remaining = Duration.zero;
      _status = _TimerStatus.finished;
    });
    unawaited(HapticFeedback.heavyImpact());
    unawaited(NativeBridge.playAlarm(widget.settings.alarmUri, loop: true));
    unawaited(NativeBridge.showTimerNotification());
  }

  void _addFifteenSeconds() {
    _ticker?.cancel();
    unawaited(NativeBridge.requestNotificationPermission());
    unawaited(NativeBridge.stopAlarm());
    const extension = Duration(seconds: 15);
    setState(() {
      _total = extension;
      _remaining = extension;
      _status = _TimerStatus.running;
      _endsAt = DateTime.now().add(extension);
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  void _resetTimer() {
    _ticker?.cancel();
    _ticker = null;
    unawaited(NativeBridge.stopAlarm());
    setState(() {
      _status = _TimerStatus.idle;
      _remaining = _selected;
      _total = _selected;
      _endsAt = null;
    });
  }

  Future<void> _openSettings() async {
    _coffeeFocus.unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(settings: widget.settings),
      ),
    );
    if (mounted) setState(() {});
  }

  String get _statusLabel {
    switch (_status) {
      case _TimerStatus.idle:
        return 'Ready to brew';
      case _TimerStatus.running:
        return 'Brewing';
      case _TimerStatus.paused:
        return 'Paused';
      case _TimerStatus.finished:
        return "Time's up";
    }
  }

  String get _buttonLabel {
    switch (_status) {
      case _TimerStatus.idle:
        return 'Start brewing';
      case _TimerStatus.running:
        return 'Pause';
      case _TimerStatus.paused:
        return 'Resume';
      case _TimerStatus.finished:
        return 'Stop';
    }
  }

  IconData get _buttonIcon {
    switch (_status) {
      case _TimerStatus.idle:
      case _TimerStatus.paused:
        return Icons.play_arrow_rounded;
      case _TimerStatus.running:
        return Icons.pause_rounded;
      case _TimerStatus.finished:
        return Icons.stop_rounded;
    }
  }

  Color get _dotColor {
    switch (_status) {
      case _TimerStatus.idle:
        return kCream.withValues(alpha: 0.3);
      case _TimerStatus.running:
        return kCaramel;
      case _TimerStatus.paused:
        return kCaramel.withValues(alpha: 0.55);
      case _TimerStatus.finished:
        return const Color(0xFFE8C08A);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: appBackground,
        child: SafeArea(
          child: Column(
            children: [
              _header(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 32),
                  child: Column(
                    children: [
                      _coffeeCard(),
                      const SizedBox(height: 18),
                      _timerCard(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 16, 10),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: kLatte,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.coffee_rounded, color: kRoast, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Coffee's Ready!",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: kEspresso,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _openSettings,
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            style: IconButton.styleFrom(
              backgroundColor: kMilk,
              foregroundColor: kEspresso,
            ),
          ),
        ],
      ),
    );
  }

  Widget _coffeeCard() {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('GROUND COFFEE', style: kLabelStyle),
              const Spacer(),
              _ratioChip(),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stepButton(
                icon: Icons.remove_rounded,
                tooltip: 'Remove one gram',
                onPressed: () => _changeCoffee(-1),
              ),
              _coffeeField(),
              _stepButton(
                icon: Icons.add_rounded,
                tooltip: 'Add one gram',
                onPressed: () => _changeCoffee(1),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: kLine),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: kLatte,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.water_drop_outlined,
                  color: kCaramel,
                  size: 22,
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$_waterMl',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        color: kEspresso,
                        height: 1.1,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Text(
                      ' ml',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: kRoast,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 46,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text('WATER', style: kLabelStyle),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _coffeeFieldWidth() {
    final text = _coffeeController.text.isEmpty ? '0' : _coffeeController.text;
    final painter = TextPainter(
      text: TextSpan(text: text, style: _coffeeTextStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width + 8;
    painter.dispose();
    return width.clamp(40.0, 120.0).toDouble();
  }

  Widget _coffeeField() {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: SizedBox(
              width: _coffeeFieldWidth(),
              child: Semantics(
                label: 'Coffee weight in grams',
                child: TextField(
                  controller: _coffeeController,
                  focusNode: _coffeeFocus,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  textAlign: TextAlign.center,
                  inputFormatters: [_coffeeFormatter],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _coffeeFocus.unfocus(),
                  onTapOutside: (_) => _coffeeFocus.unfocus(),
                  cursorColor: kCaramel,
                  style: _coffeeTextStyle,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: '0',
                    hintStyle: TextStyle(color: kLine),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 16),
            child: Text(
              'g',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: kRoast.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: kLatte,
        foregroundColor: kEspresso,
        minimumSize: const Size(46, 46),
        shape: const CircleBorder(),
      ),
    );
  }

  Widget _ratioChip() {
    return Material(
      color: kLatte,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openSettings,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '1 : ${widget.settings.ratio}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: kRoast,
                ),
              ),
              const SizedBox(width: 5),
              const Icon(Icons.tune_rounded, size: 13, color: kRoast),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timerCard() {
    final display = _status == _TimerStatus.idle ? _selected : _remaining;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: kEspresso,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: kEspresso.withValues(alpha: 0.22),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _statusLabel.toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: kCream.withValues(alpha: 0.72),
                ),
              ),
              const Spacer(),
              Icon(
                Icons.timer_outlined,
                size: 19,
                color: kCream.withValues(alpha: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatClock(display),
              style: const TextStyle(
                fontSize: 78,
                height: 1,
                fontWeight: FontWeight.w600,
                letterSpacing: -1.5,
                color: kCream,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 112),
            child: Center(child: _timerMiddle()),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _toggleTimer,
                  icon: Icon(_buttonIcon, size: 20),
                  label: Text(_buttonLabel),
                  style: FilledButton.styleFrom(
                    backgroundColor: _status == _TimerStatus.finished
                        ? kCaramel
                        : kCream,
                    foregroundColor: kEspresso,
                    minimumSize: const Size.fromHeight(56),
                    textStyle: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
              if (_status == _TimerStatus.finished) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addFifteenSeconds,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('15 s'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kCream,
                      backgroundColor: Colors.white.withValues(alpha: 0.06),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                      minimumSize: const Size.fromHeight(56),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ] else if (_status == _TimerStatus.running ||
                  _status == _TimerStatus.paused) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 56,
                  height: 56,
                  child: IconButton(
                    onPressed: _resetTimer,
                    tooltip: 'Reset timer',
                    icon: const Icon(Icons.replay_rounded, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      foregroundColor: kCream,
                      shape: const CircleBorder(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _timerMiddle() {
    if (_status == _TimerStatus.idle) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in widget.settings.presets) _presetChip(preset),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              _adjustButton(
                icon: Icons.remove_rounded,
                tooltip: '5 seconds shorter',
                onPressed: _selected > _minTimer
                    ? () => _adjustDuration(-5)
                    : null,
              ),
              _adjustButton(
                icon: Icons.add_rounded,
                tooltip: '5 seconds longer',
                onPressed: _selected < _maxTimer
                    ? () => _adjustDuration(5)
                    : null,
              ),
            ],
          ),
        ],
      );
    }

    final finished = _status == _TimerStatus.finished;
    final caption = finished
        ? 'Your coffee is ready'
        : _status == _TimerStatus.paused
        ? 'Paused'
        : 'of ${formatClock(_total)}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: finished ? 1 : _progress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(kCaramel),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          caption,
          style: TextStyle(fontSize: 12, color: kCream.withValues(alpha: 0.68)),
        ),
      ],
    );
  }

  Widget _presetChip(Duration duration) {
    final selected = _selected == duration;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Set timer to ${_presetLabel(duration)}',
      excludeSemantics: true,
      onTap: () => _setDuration(duration),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _setDuration(duration),
          borderRadius: BorderRadius.circular(99),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? kCaramel : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: selected
                    ? kCaramel
                    : Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Text(
              _presetLabel(duration),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? kEspresso : kCream.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _presetLabel(Duration duration) {
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '${duration.inMinutes}:$seconds';
  }

  Widget _adjustButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: const Text('5 s'),
        style: OutlinedButton.styleFrom(
          foregroundColor: kCream,
          disabledForegroundColor: kCream.withValues(alpha: 0.3),
          backgroundColor: Colors.white.withValues(alpha: 0.06),
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.03),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }
}
