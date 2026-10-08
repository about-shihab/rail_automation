import 'dart:math';

import 'app_config.dart';

/// Decides how long to wait before the next seat search.
///
/// All inputs come from [AppConfig] (Firestore `app_config`), and are re-read
/// on every call, so a change made in the database applies to a search that is
/// already running, with no restart:
///
///  * base interval  - `api_operations.search_trips.poll_interval_seconds`,
///                     falling back to `poll_interval_seconds`
///  * near departure - poll faster inside the last N minutes before departure
///  * backoff        - after errors (network, 429, 5xx, ...) wait longer,
///                     capped by `search_max_backoff_seconds`
///  * jitter         - +/- `search_jitter_percent` so requests are not
///                     perfectly periodic
class SearchScheduler {
  SearchScheduler({Random? random}) : _random = random ?? Random();

  final Random _random;
  int _failures = 0;

  int get consecutiveFailures => _failures;

  void recordSuccess() => _failures = 0;

  void reset() => _failures = 0;

  void recordFailure(Object error) {
    final text = error.toString().toLowerCase();
    // Rate limiting is a stronger signal than an ordinary network error.
    final limited = RegExp(r'429|too many requests|rate limit').hasMatch(text);
    _failures = min(_failures + (limited ? 2 : 1), 12);
  }

  /// Seconds between searches before backoff and jitter are applied.
  int baseIntervalSeconds({DateTime? departure, DateTime? now}) {
    final config = AppConfig.instance;
    var seconds = config.searchIntervalSeconds;
    final nearMinutes = config.number('search_near_departure_minutes');
    final nearInterval = config.number(
      'search_near_departure_interval_seconds',
    );
    if (departure != null && nearMinutes > 0 && nearInterval > 0) {
      final left = departure.difference(now ?? DateTime.now());
      if (!left.isNegative && left.inMinutes <= nearMinutes) {
        seconds = min(seconds, max(nearInterval, 10));
      }
    }
    return seconds;
  }

  Duration nextDelay({DateTime? departure, DateTime? now}) {
    final config = AppConfig.instance;
    final base = baseIntervalSeconds(departure: departure, now: now).toDouble();
    var seconds = base;
    if (_failures > 0) {
      final cap = config.number('search_max_backoff_seconds').toDouble();
      final backedOff =
          base * pow(config.decimal('search_backoff_multiplier'), _failures);
      seconds = max(base, min(cap, backedOff.toDouble()));
    }
    final jitter = config.number('search_jitter_percent') / 100;
    if (jitter > 0) {
      seconds *= 1 + (_random.nextDouble() * 2 - 1) * jitter;
    }
    return Duration(milliseconds: (max(seconds, 5) * 1000).round());
  }
}
