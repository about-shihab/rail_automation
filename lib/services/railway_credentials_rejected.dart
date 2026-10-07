import 'dart:convert';

/// Only an explicit credential rejection warrants an automatic login redirect.
class RailwayCredentialsRejected implements Exception {
  static const message = 'Railway username or password is incorrect.';
  const RailwayCredentialsRejected();

  static bool isError(Object? error) =>
      error is RailwayCredentialsRejected ||
      (error != null && error.toString().contains(message));

  static bool isResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return false;
      final text = jsonEncode(decoded).toLowerCase();
      return RegExp(
        r'(incorrect|invalid|wrong|mismatch)[^{}]{0,80}(password|username|user name|credentials|mobile number)|'
        r'(password|username|user name|credentials|mobile number)[^{}]{0,80}(incorrect|invalid|wrong|not match|mismatch)',
      ).hasMatch(text);
    } catch (_) {
      return false;
    }
  }

  @override
  String toString() => message;
}
