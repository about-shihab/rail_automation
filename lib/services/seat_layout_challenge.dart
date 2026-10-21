/// Only the seat-layout read may request a booking verification retry.
class SeatLayoutChallenge implements Exception {
  const SeatLayoutChallenge({
    this.verificationAttempted = false,
    this.tokenRejected = false,
    this.requiresForeground = false,
  });

  /// A fresh token was submitted, or the user already saw this attempt.
  /// The one automatic token refresh has already been attempted, or a human
  /// challenge was unavailable/cancelled. Further retries must be deliberate.
  final bool verificationAttempted;
  final bool tokenRejected;
  final bool requiresForeground;

  static final _tokenRejection = RegExp(
    r'turnstile|\bcft\b|cft[\s_-]*(?:response|token|verification)|captcha|human check|human verification|timeout-or-duplicate|(?:missing|invalid)-input-response',
    caseSensitive: false,
  );

  static bool isTokenRejection(int status, String body) =>
      const [200, 400, 403, 422].contains(status) &&
      _tokenRejection.hasMatch(body);

  @override
  String toString() =>
      'Human check needed to load seats. Tap to continue booking.';
}
