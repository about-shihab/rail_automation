import 'dart:convert';

/// Transforms raw API/network/runtime exceptions and Railway server responses
/// into clean, user-friendly messages.
///
/// Prevents raw JSON errors like:
///   "Bad state: Railway request /bookings/verify-otp failed (422): {code: 422, messages: {errorKey: OtpNotVerified, message: Otp does not match}}"
/// from reaching the UI, replacing them with clear, meaningful feedback:
///   "The OTP code you entered does not match. Please check your SMS and try again."
String friendlyErrorMessage(dynamic raw) {
  if (raw == null) return '';
  final str = raw.toString().trim();
  if (str.isEmpty) return '';

  // 1. Try to extract specific message from embedded JSON or map representations
  final extracted = _extractServerMessage(str);
  if (extracted != null && extracted.isNotEmpty) {
    final translated = _translateKnownMessage(extracted);
    if (translated != null) return translated;
    return _cleanSentence(extracted);
  }

  // 2. Pattern matching on string contents
  final lower = str.toLowerCase();

  if (lower.contains('otp does not match') ||
      lower.contains('otpnotverified') ||
      lower.contains('invalid otp') ||
      lower.contains('wrong otp')) {
    return 'The OTP code you entered does not match. Please check your SMS and try again.';
  }

  if (lower.contains('otpexpired') ||
      lower.contains('otp expired') ||
      lower.contains('otp has expired')) {
    return 'The OTP code has expired. Please tap "Resend OTP" for a new code.';
  }

  if (lower.contains('turnstile') ||
      lower.contains('cft_response') ||
      lower.contains('human check') ||
      lower.contains('human verification') ||
      lower.contains('security verification')) {
    return 'Human verification required • Tap to verify and proceed';
  }

  if (lower.contains('token_not_given') ||
      lower.contains('invalid access token') ||
      lower.contains('invalid user access token') ||
      lower.contains('session expired') ||
      lower.contains('unauthorized') ||
      lower.contains('401') ||
      lower.contains('sign in again')) {
    return 'Railway session expired • Please sign in again';
  }

  if (lower.contains('429') ||
      lower.contains('rate limit') ||
      lower.contains('too many requests')) {
    return 'Railway server is busy • Please wait a moment and try again';
  }

  if (lower.contains('quota') ||
      lower.contains('maximum seat') ||
      lower.contains('exceeded')) {
    return 'Maximum seat quota limit reached for this journey.';
  }

  if (lower.contains('seat layout rejected') ||
      lower.contains('not acknowledged') ||
      lower.contains('seat taken') ||
      lower.contains('already booked') ||
      lower.contains('no longer available')) {
    return 'Selected seats are no longer available • Please select other seats';
  }

  if (lower.contains('timeout') ||
      lower.contains('timed out') ||
      lower.contains('reservation window expired') ||
      lower.contains('5 minutes')) {
    return 'Reservation window expired (5 minutes)';
  }

  if (lower.contains('500') ||
      lower.contains('502') ||
      lower.contains('503') ||
      lower.contains('bad gateway') ||
      lower.contains('server error')) {
    return 'Railway server is temporarily unavailable • Retrying shortly';
  }

  if (lower.contains('socket') ||
      lower.contains('network') ||
      lower.contains('connection') ||
      lower.contains('failed host lookup')) {
    return 'Network connection issue • Please check your internet';
  }

  // 3. Fallback: Strip technical artifacts, codes, and JSON blocks
  var clean = str
      .replaceAll(RegExp(r'\{.*?\}', dotAll: true), '')
      .replaceAll(RegExp(r'Bad state:\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'Railway request [^\s]+ failed \(\d+\):\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'Exception:\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'StateError:\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'FormatException:\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'\(\d+\)'), '')
      .replaceAll(RegExp(r'[:\-–—]+$'), '')
      .trim();

  if (clean.isEmpty || clean.length < 4 || clean.contains('{') || clean.contains('}')) {
    return 'Action could not be completed • Please try again';
  }
  return _cleanSentence(clean);
}

/// Parses JSON or key-value structures from API error bodies
String? _extractServerMessage(String str) {
  // Check for JSON block
  final jsonStart = str.indexOf('{');
  final jsonEnd = str.lastIndexOf('}');
  if (jsonStart != -1 && jsonEnd > jsonStart) {
    final candidate = str.substring(jsonStart, jsonEnd + 1);
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map) {
        return _extractFromMap(decoded);
      }
    } catch (_) {
      // If candidate is not valid JSON (e.g. Dart Map toString format: {code: 422, messages: ...})
      // Use regex to extract known keys
      return _extractFromDartMapString(candidate);
    }
  }

  // Regex extraction for `message: <value>` or `messages: <value>`
  return _extractFromDartMapString(str);
}

String? _extractFromMap(Map map) {
  // Look in messages map or list
  final messages = map['messages'];
  if (messages is Map) {
    final msg = messages['message']?.toString();
    if (msg != null && msg.isNotEmpty) return msg;
    final errKey = messages['errorKey']?.toString();
    if (errKey != null && errKey.isNotEmpty) return errKey;
    final errors = messages['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final firstVal = errors.values.first;
      if (firstVal is List && firstVal.isNotEmpty) return firstVal.first.toString();
      if (firstVal != null) return firstVal.toString();
    }
  } else if (messages is List && messages.isNotEmpty) {
    return messages.first.toString();
  } else if (messages is String && messages.isNotEmpty) {
    return messages;
  }

  // Look in error map
  final error = map['error'];
  if (error is Map) {
    return _extractFromMap(error);
  } else if (error is String && error.isNotEmpty) {
    return error;
  }

  final msg = map['message']?.toString() ??
      map['detail']?.toString() ??
      map['msg']?.toString();
  if (msg != null && msg.isNotEmpty) return msg;

  return null;
}

/// Extracts from Dart Map toString output like:
/// `{code: 422, messages: {errorKey: OtpNotVerified, message: Otp does not match}}`
String? _extractFromDartMapString(String text) {
  final messageMatch = RegExp(r'''(?:message|msg)\s*[:=]\s*["']?([^,"'}]+)''', caseSensitive: false).firstMatch(text);
  if (messageMatch != null) {
    final val = messageMatch.group(1)?.trim();
    if (val != null && val.isNotEmpty && !val.startsWith('{')) return val;
  }

  final errorKeyMatch = RegExp(r'''errorKey\s*[:=]\s*["']?([a-zA-Z0-9_]+)''', caseSensitive: false).firstMatch(text);
  if (errorKeyMatch != null) {
    return errorKeyMatch.group(1)?.trim();
  }

  return null;
}

String? _translateKnownMessage(String msg) {
  final lower = msg.toLowerCase();
  if (lower.contains('otp does not match') || lower.contains('otpnotverified')) {
    return 'The OTP code you entered does not match. Please check your SMS and try again.';
  }
  if (lower.contains('otpexpired') || lower.contains('otp expired')) {
    return 'The OTP code has expired. Please tap "Resend OTP" to request a new code.';
  }
  if (lower.contains('token_not_given') || lower.contains('invalid access token')) {
    return 'Railway session expired. Please log in again.';
  }
  if (lower.contains('turnstile') || lower.contains('human')) {
    return 'Security verification required. Tap to verify and proceed.';
  }
  if (lower.contains('quota') || lower.contains('limit')) {
    return 'Maximum seat quota exceeded for this journey.';
  }
  if (lower.contains('taken') || lower.contains('not available') || lower.contains('already booked')) {
    return 'Selected seats are no longer available. Please select other seats.';
  }
  return null;
}

String _cleanSentence(String s) {
  var t = s.trim();
  if (t.isEmpty) return t;
  // Capitalize first letter
  t = t[0].toUpperCase() + t.substring(1);
  // Ensure ending punctuation
  if (!t.endsWith('.') && !t.endsWith('!') && !t.endsWith('?')) {
    t = '$t.';
  }
  return t;
}
