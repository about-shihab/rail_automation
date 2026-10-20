/// Public request contracts; runtime secrets are substituted on the device.
///
/// Everything here can be overridden from the `app_config` Firestore documents
/// (`workflow` / `settings`) under the `api_operations` key. Nothing in this
/// file ever accepts credentials from the database: auth headers, tokens and
/// passwords are always injected on the device.
class RailApiConfig {
  static const baseUrl = 'https://railspaapi.shohoz.com/v1.0/web';
  static const allowedHost = 'railspaapi.shohoz.com';
  static const allowedOrigin = 'https://eticket.railway.gov.bd';
  static const paths = <String, String>{
    'sign_in': '/auth/sign-in',
    'search_trips': '/bookings/search-trips-v2',
    'train_routes': '/train-routes',
    'seat_layout': '/bookings/seat-layout',
    'purchase_history': '/purchase-history',
    'download_ticket': '/trips/download-ticket/{order_id}',
    'handshake': '/handshake',
    'reserve_seat': '/bookings/reserve-seat',
    'passenger_details': '/bookings/passenger-details',
    'verify_otp': '/bookings/verify-otp',
    'resend_otp': '/bookings/resend-otp',
  };

  /// HTTP verbs the database may select for an operation.
  static const methods = <String>{'GET', 'POST', 'PATCH'};

  /// The only headers the database may set. Authorization, cookies, device
  /// identity and action tokens are deliberately absent.
  static const allowedHeaders = <String>{
    'accept',
    'accept-language',
    'user-agent',
    'origin',
    'referer',
    'sec-ch-ua',
    'sec-ch-ua-mobile',
    'sec-ch-ua-platform',
    'sec-fetch-site',
    'sec-fetch-mode',
    'sec-fetch-dest',
  };

  static final _siteKeyPattern = RegExp(r'^0x[A-Za-z0-9_-]{10,60}$');

  static Map<String, dynamic> validate(dynamic input) {
    final result = <String, dynamic>{};
    if (input is! Map) return result;
    for (final key in paths.keys) {
      final value = input[key];
      if (value is! Map) continue;
      final entry = <String, dynamic>{};

      // Remote kill switch for a single operation (e.g. pause auto-booking).
      if (value['enabled'] is bool) entry['enabled'] = value['enabled'];

      final url = value['url'];
      if (url is String) {
        final uri = Uri.tryParse(url.replaceAll('{order_id}', '1'));
        if (uri != null &&
            uri.scheme == 'https' &&
            uri.host == allowedHost &&
            uri.userInfo.isEmpty &&
            uri.port == 443 &&
            !uri.hasFragment &&
            !uri.hasQuery) {
          entry['url'] = url;
        }
      }

      final method = value['method'];
      if (method is String && methods.contains(method.trim().toUpperCase())) {
        entry['method'] = method.trim().toUpperCase();
      }

      final interval = _intIn(value['min_interval_seconds'], 0, 300);
      if (interval != null) entry['min_interval_seconds'] = interval;

      // Only meaningful for search_trips: how often the monitor polls.
      if (key == 'search_trips') {
        final poll = _intIn(value['poll_interval_seconds'], 10, 86400);
        if (poll != null) entry['poll_interval_seconds'] = poll;
      }

      final timeout = _intIn(value['timeout_seconds'], 5, 120);
      if (timeout != null) entry['timeout_seconds'] = timeout;

      // Retries are applied to GET operations only; a mutation with an
      // unknown outcome is never replayed.
      final retries = _intIn(value['retries'], 0, 3);
      if (retries != null) entry['retries'] = retries;
      final retryDelay = _intIn(value['retry_delay_seconds'], 1, 30);
      if (retryDelay != null) entry['retry_delay_seconds'] = retryDelay;

      final headers = validateHeaders(value['headers']);
      if (headers.isNotEmpty) entry['headers'] = headers;

      // Templates must refer to secrets by placeholder, never by literal value.
      final payload = value['payload'];
      if (payload is Map && _publicTemplate(payload)) {
        entry['payload'] = Map<String, dynamic>.from(payload);
      }
      result[key] = entry;
    }
    return result;
  }

  static int? _intIn(dynamic raw, int min, int max) {
    final value = raw is num
        ? raw.toInt()
        : (raw is String ? int.tryParse(raw) : null);
    if (value == null || value < min || value > max) return null;
    return value;
  }

  /// Returns only allow-listed, single-line header values.
  static Map<String, String> validateHeaders(dynamic input) {
    final out = <String, String>{};
    if (input is! Map) return out;
    for (final e in input.entries) {
      final name = '${e.key}'.trim();
      final value = e.value;
      if (value is! String) continue;
      final clean = value.trim();
      if (!allowedHeaders.contains(name.toLowerCase())) continue;
      if (clean.isEmpty || clean.length > 512) continue;
      if (clean.contains('\r') || clean.contains('\n')) continue;
      final lower = name.toLowerCase();
      if ((lower == 'origin' || lower == 'referer') &&
          !clean.startsWith(allowedOrigin)) {
        continue;
      }
      out[name] = clean;
    }
    return out;
  }

  /// Cloudflare Turnstile site keys by purpose (e.g. `sign_in`).
  static Map<String, String> validateSiteKeys(dynamic input) {
    final out = <String, String>{};
    if (input is! Map) return out;
    for (final e in input.entries) {
      final name = '${e.key}'.trim();
      final value = e.value;
      if (name.isEmpty || value is! String) continue;
      if (_siteKeyPattern.hasMatch(value.trim())) out[name] = value.trim();
    }
    return out;
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
