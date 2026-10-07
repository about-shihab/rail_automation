/// Public request contracts; runtime secrets are substituted on the device.
class RailApiConfig {
  static const baseUrl = 'https://railspaapi.shohoz.com/v1.0/web';
  static const paths = <String, String>{
    'sign_in': '/auth/sign-in',
    'search_trips': '/bookings/search-trips-v2',
    'seat_layout': '/bookings/seat-layout',
    'purchase_history': '/purchase-history',
    'download_ticket': '/trips/download-ticket/{order_id}',
    'handshake': '/handshake',
    'reserve_seat': '/bookings/reserve-seat',
    'passenger_details': '/bookings/passenger-details',
    'verify_otp': '/bookings/verify-otp',
    'resend_otp': '/bookings/resend-otp',
  };

  static Map<String, dynamic> validate(dynamic input) {
    final result = <String, dynamic>{};
    if (input is! Map) return result;
    for (final key in paths.keys) {
      final value = input[key];
      if (value is! Map) continue;
      final entry = <String, dynamic>{};
      final url = value['url'];
      if (url is String) {
        final uri = Uri.tryParse(url.replaceAll('{order_id}', '1'));
        if (uri != null &&
            uri.scheme == 'https' &&
            uri.host == 'railspaapi.shohoz.com' &&
            uri.userInfo.isEmpty &&
            uri.port == 443 &&
            !uri.hasFragment &&
            !uri.hasQuery) {
          entry['url'] = url;
        }
      }
      final interval = value['min_interval_seconds'];
      if (interval is int && interval >= 0 && interval <= 300) {
        entry['min_interval_seconds'] = interval;
      }
      // Templates must refer to secrets by placeholder, never by literal value.
      final payload = value['payload'];
      if (payload is Map && _publicTemplate(payload)) {
        entry['payload'] = Map<String, dynamic>.from(payload);
      }
      result[key] = entry;
    }
    return result;
  }

  static bool _publicTemplate(dynamic value, [String key = '']) {
    if (value is Map) {
      return value.entries.every(
        (e) => e.key is String && _publicTemplate(e.value, e.key as String),
      );
    }
    if (value is List) return value.every((e) => _publicTemplate(e, key));
    if (RegExp(
      r'password|token|otp|mobile_number|cft_response',
      caseSensitive: false,
    ).hasMatch(key)) {
      return value is String &&
          RegExp(r'^\{\{[a-zA-Z0-9_]+\}\}$').hasMatch(value);
    }
    return value == null || value is String || value is num || value is bool;
  }

  static dynamic render(dynamic value, Map<String, dynamic> runtime) {
    if (value is Map) {
      return value.map(
        (key, val) => MapEntry(key.toString(), render(val, runtime)),
      );
    }
    if (value is List) return value.map((v) => render(v, runtime)).toList();
    if (value is String) {
      final match = RegExp(r'^\{\{([a-zA-Z0-9_]+)\}\}$').firstMatch(value);
      if (match != null) {
        final key = match.group(1)!;
        if (!runtime.containsKey(key)) {
          throw StateError('Missing API payload field: $key');
        }
        return runtime[key];
      }
    }
    return value;
  }
}
