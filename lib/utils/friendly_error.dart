/// Transforms raw API/network/runtime exceptions into clean, user-friendly messages.
/// Strips out raw JSON errors like:
///   "Seat layout rejected (422): {code: 422, messages: {errorKey: TURNSTILE_VERIFICATION_FAILED...}}"
/// into a clear, helpful message:
///   "Human check needed • Tap to verify and book seats"
String friendlyErrorMessage(dynamic raw) {
  if (raw == null) return '';
  final str = raw.toString().trim();
  if (str.isEmpty) return '';
  final lower = str.toLowerCase();

  if (lower.contains('turnstile') ||
      lower.contains('cft_response') ||
      lower.contains('422') ||
      lower.contains('human check') ||
      lower.contains('human verification') ||
      lower.contains('security verification')) {
    return 'Human check needed • Tap to verify and book seats';
  }
  if (lower.contains('401') ||
      lower.contains('session expired') ||
      lower.contains('unauthorized') ||
      lower.contains('sign in again')) {
    return 'Railway session expired • Please sign in again';
  }
  if (lower.contains('429') ||
      lower.contains('rate limit') ||
      lower.contains('too many')) {
    return 'Railway server busy • Retrying in a moment';
  }
  if (lower.contains('500') ||
      lower.contains('502') ||
      lower.contains('503') ||
      lower.contains('server error') ||
      lower.contains('bad gateway')) {
    return 'Railway server temporarily busy • Retrying shortly';
  }
  if (lower.contains('timeout') ||
      lower.contains('timed out') ||
      lower.contains('5 minutes') ||
      lower.contains('reservation window expired')) {
    return 'Reservation window expired (5 minutes)';
  }
  if (lower.contains('seat layout rejected') ||
      lower.contains('not acknowledged') ||
      lower.contains('taken') ||
      lower.contains('already booked')) {
    return 'Selected seats were taken • Searching next train';
  }
  if (lower.contains('otp')) {
    return 'OTP verification not completed';
  }
  if (lower.contains('socket') || lower.contains('network') || lower.contains('connection')) {
    return 'Network connection issue • Retrying...';
  }

  // Strip out any remaining JSON blocks, codes, and exception wrappers
  var clean = str
      .replaceAll(RegExp(r'\{.*?\}', dotAll: true), '')
      .replaceAll('Exception: ', '')
      .replaceAll('StateError: ', '')
      .replaceAll(RegExp(r'\(\d+\)'), '')
      .replaceAll(RegExp(r'[:\-–—]+$'), '')
      .trim();

  if (clean.isEmpty || clean.length < 5) {
    return 'Reservation could not be completed • Retrying search';
  }
  return clean;
}
