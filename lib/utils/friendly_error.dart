import 'dart:convert';

import '../services/language_service.dart';
import '../services/rail_request_pacer.dart';
import '../services/seat_layout_challenge.dart';

/// Transforms raw API/network/runtime exceptions and Railway server responses
/// into clean, user-friendly messages.
String friendlyErrorMessage(dynamic raw, {bool? isBangla}) {
  if (raw == null) return '';
  final str = raw.toString().trim();
  if (str.isEmpty) return '';
  final bn = isBangla ?? LanguageService.instance.isBangla;

  String pick(String en, String bangla) => bn ? bangla : en;

  if (raw is SeatLayoutChallenge && raw.requiresForeground) {
    return pick(
      'Open Rail Pro to refresh verification and load your seats.',
      'নিরাপত্তা যাচাই হালনাগাদ করে আসন দেখতে Rail Pro খুলুন।',
    );
  }

  if (raw is RailwayRateLimited) {
    final seconds = raw.secondsRemaining();
    return pick(
      'Railway is receiving too many requests. Waiting $seconds seconds before trying again.',
      'রেলওয়েতে অতিরিক্ত অনুরোধ যাচ্ছে। আবার চেষ্টা করার আগে $seconds সেকেন্ড অপেক্ষা করুন।',
    );
  }

  // 1. Try to extract specific message from embedded JSON or map representations
  final extracted = _extractServerMessage(str);
  if (extracted != null && extracted.isNotEmpty) {
    final translated = _translateKnownMessage(extracted, bn);
    if (translated != null) return translated;
    return _cleanSentence(extracted);
  }

  // 2. Pattern matching on string contents
  final lower = str.toLowerCase();

  if (lower.contains('otp does not match') ||
      lower.contains('otpnotverified') ||
      lower.contains('invalid otp') ||
      lower.contains('wrong otp')) {
    return pick(
      'The OTP code you entered does not match. Please check your SMS and try again.',
      'আপনার দেওয়া ওটিপি কোডটি মেলেনি। অনুগ্রহ করে এসএমএস দেখে আবার চেষ্টা করুন।',
    );
  }

  if (lower.contains('otpexpired') ||
      lower.contains('otp expired') ||
      lower.contains('otp has expired')) {
    return pick(
      'The OTP code has expired. Please tap "Resend OTP" for a new code.',
      'ওটিপি কোডের মেয়াদ শেষ হয়ে গেছে। নতুন কোড পেতে "পুনরায় পাঠান" চাপুন।',
    );
  }

  if (lower.contains('turnstile') ||
      lower.contains('cft_response') ||
      lower.contains('human check') ||
      lower.contains('human verification') ||
      lower.contains('security verification')) {
    return pick(
      'To complete booking, proceed in app',
      'বুকিং সম্পন্ন করতে এগিয়ে যান',
    );
  }

  if (lower.contains('token_not_given') ||
      lower.contains('invalid access token') ||
      lower.contains('invalid user access token') ||
      lower.contains('session expired') ||
      lower.contains('unauthorized') ||
      lower.contains('401') ||
      lower.contains('sign in again')) {
    return pick(
      'Railway session expired • Please sign in again',
      'রেলওয়ে লগইন সেশনের মেয়াদ শেষ • অনুগ্রহ করে পুনরায় সাইন ইন করুন',
    );
  }

  if (lower.contains('429') ||
      lower.contains('rate limit') ||
      lower.contains('too many requests')) {
    return pick(
      'Railway server is busy • Please wait a moment and try again',
      'রেলওয়ে সার্ভার ব্যস্ত আছে • কিছুক্ষণ অপেক্ষা করে আবার চেষ্টা করুন',
    );
  }

  if (lower.contains('quota') ||
      lower.contains('maximum seat') ||
      lower.contains('exceeded')) {
    return pick(
      'Maximum seat quota limit reached for this journey.',
      'এই যাত্রার জন্য সর্বোচ্চ আসন কোটার সীমা পূর্ণ হয়েছে।',
    );
  }

  if (lower.contains('seat layout rejected') ||
      lower.contains('not acknowledged') ||
      lower.contains('seat taken') ||
      lower.contains('already booked') ||
      lower.contains('no longer available')) {
    return pick(
      'Selected seats are no longer available • Please select other seats',
      'নির্বাচিত আসনটি আর খালি নেই • অনুগ্রহ করে অন্য আসন নির্বাচন করুন',
    );
  }

  if (lower.contains('seats were reserved') ||
      lower.contains('held seats were released')) {
    return pick(
      'Seats were reserved, but OTP was not verified or payment was not completed within 5 minutes. Held seats were released by Bangladesh Railway.',
      'রেলওয়ে সিস্টেমে আসন সংরক্ষিত হয়েছিল, কিন্তু ৫ মিনিটের মধ্যে ওটিপি যাচাই বা পেমেন্ট না হওয়ায় আসনটি ছেড়ে দেওয়া হয়েছে।',
    );
  }

  if (lower.contains('timeout') ||
      lower.contains('timed out') ||
      lower.contains('reservation window expired') ||
      lower.contains('5 minutes')) {
    return pick(
      'Reservation window expired (5 minutes)',
      'আসন সংরক্ষণের ৫ মিনিটের সময়সীমা শেষ হয়েছে',
    );
  }

  if (lower.contains('500') ||
      lower.contains('502') ||
      lower.contains('503') ||
      lower.contains('bad gateway') ||
      lower.contains('server error')) {
    return pick(
      'Railway server is temporarily unavailable • Retrying shortly',
      'রেলওয়ে সার্ভার সাময়িকভাবে অনুপলব্ধ • কিছুক্ষণ পর পুনরায় চেষ্টা করা হচ্ছে',
    );
  }

  if (lower.contains('socket') ||
      lower.contains('network') ||
      lower.contains('connection') ||
      lower.contains('failed host lookup')) {
    return pick(
      'Network connection issue • Please check your internet',
      'ইন্টারনেট সংযোগ সমস্যা • আপনার নেটওয়ার্ক চেক করুন',
    );
  }

  // 3. Fallback: Strip technical artifacts, codes, and JSON blocks
  var clean = str
      .replaceAll(RegExp(r'\{.*?\}', dotAll: true), '')
      .replaceAll(RegExp(r'Bad state:\s*', caseSensitive: false), '')
      .replaceAll(
        RegExp(
          r'Railway request [^\s]+ failed \(\d+\):\s*',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'Exception:\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'StateError:\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'FormatException:\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'\(\d+\)'), '')
      .replaceAll(RegExp(r'[:\-–—]+$'), '')
      .trim();

  if (clean.isEmpty ||
      clean.length < 4 ||
      clean.contains('{') ||
      clean.contains('}')) {
    return pick(
      'Action could not be completed • Please try again',
      'অনুরোধটি সম্পন্ন করা সম্ভব হয়নি • অনুগ্রহ করে আবার চেষ্টা করুন',
    );
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
      if (firstVal is List && firstVal.isNotEmpty) {
        return firstVal.first.toString();
      }
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

  final msg =
      map['message']?.toString() ??
      map['detail']?.toString() ??
      map['msg']?.toString();
  if (msg != null && msg.isNotEmpty) return msg;

  return null;
}

/// Extracts from Dart Map toString output like:
/// `{code: 422, messages: {errorKey: OtpNotVerified, message: Otp does not match}}`
String? _extractFromDartMapString(String text) {
  final messageMatch = RegExp(
    r'''(?:message|msg)\s*[:=]\s*["']?([^,"'}]+)''',
    caseSensitive: false,
  ).firstMatch(text);
  if (messageMatch != null) {
    final val = messageMatch.group(1)?.trim();
    if (val != null && val.isNotEmpty && !val.startsWith('{')) return val;
  }

  final errorKeyMatch = RegExp(
    r'''errorKey\s*[:=]\s*["']?([a-zA-Z0-9_]+)''',
    caseSensitive: false,
  ).firstMatch(text);
  if (errorKeyMatch != null) {
    return errorKeyMatch.group(1)?.trim();
  }

  return null;
}

String? _translateKnownMessage(String msg, bool bn) {
  String pick(String en, String bangla) => bn ? bangla : en;
  final lower = msg.toLowerCase();
  if (lower.contains('otp does not match') ||
      lower.contains('otpnotverified') ||
      lower.contains('invalid otp') ||
      lower.contains('wrong otp')) {
    return pick(
      'The OTP code you entered does not match. Please check your SMS and try again.',
      'আপনার দেওয়া ওটিপি কোডটি মেলেনি। অনুগ্রহ করে এসএমএস দেখে আবার চেষ্টা করুন।',
    );
  }
  if (lower.contains('otpexpired') ||
      lower.contains('otp expired') ||
      lower.contains('otp has expired')) {
    return pick(
      'The OTP code has expired. Please tap "Resend OTP" to request a new code.',
      'ওটিপি কোডের মেয়াদ শেষ হয়ে গেছে। নতুন কোড পেতে "পুনরায় পাঠান" চাপুন।',
    );
  }
  if (lower.contains('token_not_given') ||
      lower.contains('invalid access token') ||
      lower.contains('invalid user access token') ||
      lower.contains('session expired') ||
      lower.contains('unauthorized') ||
      lower.contains('401')) {
    return pick(
      'Railway session expired • Please sign in again',
      'রেলওয়ে লগইন সেশনের মেয়াদ শেষ • অনুগ্রহ করে পুনরায় সাইন ইন করুন',
    );
  }
  if (lower.contains('turnstile') || lower.contains('human')) {
    return pick(
      'To complete booking, proceed in app',
      'বুকিং সম্পন্ন করতে এগিয়ে যান',
    );
  }
  if (lower.contains('429') ||
      lower.contains('too many requests') ||
      lower.contains('rate limit')) {
    return pick(
      'Railway is busy. Requests are paused; please wait before trying again.',
      'রেলওয়ে ব্যস্ত। অনুরোধ সাময়িক বন্ধ আছে; আবার চেষ্টা করার আগে অপেক্ষা করুন।',
    );
  }
  if (lower.contains('quota') ||
      lower.contains('maximum seat') ||
      lower.contains('limit')) {
    return pick(
      'Maximum seat quota limit reached for this journey.',
      'এই যাত্রার জন্য সর্বোচ্চ আসন কোটার সীমা পূর্ণ হয়েছে।',
    );
  }
  if (lower.contains('taken') ||
      lower.contains('not available') ||
      lower.contains('already booked') ||
      lower.contains('seat layout rejected')) {
    return pick(
      'Selected seats are no longer available • Please select other seats',
      'নির্বাচিত আসনটি আর খালি নেই • অনুগ্রহ করে অন্য আসন নির্বাচন করুন',
    );
  }
  if (lower.contains('seats were reserved') ||
      lower.contains('held seats were released') ||
      lower.contains('5 minutes')) {
    return pick(
      'Seats were reserved, but OTP was not verified or payment was not completed within 5 minutes. Held seats were released by Bangladesh Railway.',
      'রেলওয়ে সিস্টেমে আসন সংরক্ষিত হয়েছিল, কিন্তু ৫ মিনিটের মধ্যে ওটিপি যাচাই বা পেমেন্ট সম্পন্ন না হওয়ায় বাংলাদেশ রেলওয়ে আসনটি ছেড়ে দিয়েছে।',
    );
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
