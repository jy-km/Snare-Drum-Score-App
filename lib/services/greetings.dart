import 'dart:math';

/// The line the app greets the player with when it opens: one that fits
/// the time of day, or one that fits any time.
String pickGreeting(DateTime now, Random random) {
  final forNow = switch (now.hour) {
    >= 22 || < 5 => _lateNight,
    < 12 => _morning,
    < 17 => _afternoon,
    _ => _evening,
  };
  final choices = [...forNow, ..._anyTime];
  return choices[random.nextInt(choices.length)];
}

const _lateNight = [
  'Greetings, night owl.',
  'Burning the midnight oil?',
  'Late-night groove session?',
  'Practice pad time. The neighbours are asleep.',
  'Midnight metronome club, welcome.',
];

const _morning = [
  'Good morning! The early bird gets the groove.',
  'Coffee first, then paradiddles?',
  'Rise and rhythm.',
  'Fresh hands, fresh tempo. Good morning!',
];

const _afternoon = [
  'Good afternoon, drummer.',
  'Afternoon break? Perfect time for a few runs.',
  'Ten minutes now beats an hour someday.',
];

const _evening = [
  'Good evening! Time to lock in the groove.',
  'Wind down with some steady eighth notes.',
  'Evening session? Let\'s make it count.',
];

const _anyTime = [
  'Practicing instead of scrolling?',
  'Your sticks missed you.',
  'Slow is smooth, smooth is fast.',
  'Ready to beat yesterday\'s accuracy?',
  'The metronome is warmed up. Are you?',
  'Small steps, steady tempo.',
  'Every Perfect starts with a count-in.',
  'Welcome back. Let\'s find the pocket.',
];
