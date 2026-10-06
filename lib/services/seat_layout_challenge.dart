/// Only the seat-layout read may request a booking verification retry.
class SeatLayoutChallenge implements Exception {
  const SeatLayoutChallenge({this.verificationAttempted = false});

  /// A fresh token was submitted, or the user already saw this attempt.
  /// Leave retry to the user rather than opening another automatic challenge.
  final bool verificationAttempted;

  @override
  String toString() =>
      'Human check needed to load seats. Tap to continue booking.';
}
