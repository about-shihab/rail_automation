import 'dart:async';
import 'dart:io';
import 'dart:math';

/// A rejected request is safe to report, but must not start a retry storm.
class RailwayRateLimited implements Exception {
  const RailwayRateLimited(this.retryAt);

  final DateTime retryAt;

  int secondsRemaining([DateTime? now]) => max(
    1,
    (retryAt.difference(now ?? DateTime.now()).inMilliseconds / 1000).ceil(),
  );

  @override
  String toString() =>
      'Too many requests (429). Please wait ${secondsRemaining()} seconds before trying again.';
}

/// Serializes Railway traffic across operations, including retries. A slot is
/// held until the response arrives, so a slow server cannot accumulate requests.
class RailRequestPacer {
  RailRequestPacer({
    this.minimumSpacing = const Duration(milliseconds: 1500),
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  }) : _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  final Duration minimumSpacing;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  Future<void>? _tail;
  DateTime? _lastStarted;
  final _lastOperations = <String, DateTime>{};
  DateTime? _blockedUntil;
  int _rateLimits = 0;

  DateTime? get blockedUntil => _blockedUntil;
  Duration get cooldownRemaining {
    final remaining = _blockedUntil?.difference(_now()) ?? Duration.zero;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void restoreCooldown(DateTime until) {
    if (_blockedUntil == null || until.isAfter(_blockedUntil!)) {
      _blockedUntil = until;
    }
  }

  void checkCooldown() {
    if (cooldownRemaining > Duration.zero) {
      throw RailwayRateLimited(_blockedUntil!);
    }
  }

  /// Supports both Retry-After formats. The server's Date avoids clock skew
  /// when Retry-After is an HTTP date. Missing/invalid values back off 30–300s.
  DateTime rateLimited(Map<String, String> headers) {
    final now = _now();
    final value = headers['retry-after']?.trim();
    Duration? wait;
    final seconds = int.tryParse(value ?? '');
    if (seconds != null && seconds >= 0) {
      wait = Duration(seconds: max(1, seconds));
    } else if (value != null) {
      try {
        var reference = now;
        final serverDate = headers['date'];
        if (serverDate != null) reference = HttpDate.parse(serverDate);
        wait = HttpDate.parse(value).difference(reference);
        if (wait < const Duration(seconds: 1)) {
          wait = const Duration(seconds: 1);
        }
      } on HttpException {
        // Fall back to bounded exponential backoff below.
      }
    }
    wait ??= Duration(
      seconds: min(300, 30 * pow(2, min(_rateLimits, 4)).toInt()),
    );
    _rateLimits++;
    restoreCooldown(now.add(wait));
    return _blockedUntil!;
  }

  void recordSuccess() => _rateLimits = 0;

  Future<T> run<T>({
    required String operation,
    Duration minInterval = Duration.zero,
    bool paced = true,
    required Future<T> Function() send,
  }) async {
    if (!paced) {
      checkCooldown();
      return await send();
    }
    final previous = _tail;
    final completed = Completer<void>();
    _tail = completed.future;
    if (previous != null) await previous;
    try {
      checkCooldown();
      var wait = Duration.zero;
      final last = _lastStarted;
      if (last != null) wait = minimumSpacing - _now().difference(last);
      final operationLast = _lastOperations[operation];
      if (operationLast != null) {
        final operationWait = minInterval - _now().difference(operationLast);
        if (operationWait > wait) wait = operationWait;
      }
      if (wait > Duration.zero) await _delay(wait);
      checkCooldown();
      _lastOperations[operation] = _lastStarted = _now();
      return await send();
    } finally {
      // Errors belong to the caller; the queue must remain usable.
      completed.complete();
    }
  }
}
