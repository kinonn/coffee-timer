import 'dart:math' as math;

/// Water in millilitres for [coffeeGrams] at [ratio] grams of water per gram
/// of coffee. One millilitre of water weighs one gram, so the number doubles
/// as the water weight.
double waterFor(double coffeeGrams, int ratio) =>
    math.max(0.0, coffeeGrams) * ratio;

/// Formats a duration as mm:ss. Partial seconds are rounded up so a running
/// countdown shows 00:01 while there is still time left.
String formatClock(Duration duration) {
  final ms = duration.inMilliseconds;
  final totalSeconds = ms <= 0 ? 0 : (ms / 1000).ceil();
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Formats a timer value, showing -mm:ss once the timer has elapsed.
String formatTimer(Duration duration) =>
    duration < Duration.zero ? '-${formatClock(-duration)}' : formatClock(duration);
