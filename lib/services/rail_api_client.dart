import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/auth_session.dart';
import 'app_config.dart';
import 'notification_service.dart';
import 'rail_api_config.dart';
import 'railway_credentials_rejected.dart';
import 'login_recovery_required.dart';
import 'secure_store.dart';
import 'turnstile_gate.dart';

/// One bounded recovery for explicit auth rejections. Unknown mutation outcomes
/// and generic Cloudflare 403 responses are never replayed.
class RailApiClient {
  static final _refreshes = <String, Future<AuthSession>>{};
  static final _queues = <String, Future<void>>{};
  static final _lastCalls = <String, DateTime>{};

  static Future<AuthSession> current(AuthSession auth) async {
    final saved = await AuthSession.load();
    if (saved != null &&
        saved.deviceId == auth.deviceId &&
        saved.phoneNumber == auth.phoneNumber &&
        saved.isValid) {
      return saved;
    }
    return auth;
  }

  static Future<http.Response> request({
    required String operation,
    required String method,
    required Map<String, dynamic> payload,
    required AuthSession auth,
    Map<String, String> headers = const {},
  }) async {
    var session = await current(auth);
    if (!session.isValid) session = await refresh(session);
    var response = await _send(operation, method, payload, session, headers);
    if (_authRejected(response)) {
      session = await refresh(session, rejectedToken: session.token);
      response = await _send(operation, method, payload, session, headers);
      if (_authRejected(response)) {
        await NotificationService().showLoginRequired();
        throw const LoginRecoveryRequired(
          'Session expired. Tap Log in to continue.',
        );
      }
    }
    return response;
  }

  static bool _authRejected(http.Response response) {
    if (response.statusCode == 401) return true;
    if (response.statusCode != 403) return false;
    try {
      final body = jsonDecode(response.body);
      if (body is! Map) return false;
      final message = '${body['message'] ?? ''} ${body['error'] ?? ''}';
      return RegExp(
        r'session (expired|invalid)|invalid (session|token)|token expired|unauthenticated',
        caseSensitive: false,
      ).hasMatch(message);
    } catch (_) {
      return false;
    }
  }

  static Future<AuthSession> refresh(
    AuthSession auth, {
    String? rejectedToken,
  }) {
    final key = '${auth.deviceId}:${auth.phoneNumber ?? ''}';
    return _refreshes.putIfAbsent(key, () async {
      try {
        final latest = await current(auth);
        if (latest.isValid && latest.token != (rejectedToken ?? auth.token)) {
          return latest;
        }
        final last = int.tryParse(
          await SecureStore.read('rail_login_attempt_at') ?? '',
        );
        if (last != null &&
            DateTime.now().millisecondsSinceEpoch - last <
                AppConfig.instance.number('login_retry_interval_seconds') *
                    1000) {
          final seconds =
              ((AppConfig.instance.number('login_retry_interval_seconds') *
                              1000 -
                          (DateTime.now().millisecondsSinceEpoch - last)) /
                      1000)
                  .ceil();
          throw LoginRecoveryRequired(
            'Automatic login can retry in $seconds seconds. Tap Log in to continue now.',
          );
        }
        final credentials = await AuthSession.getSavedUserCredentials();
        final phone = credentials['phone'] ?? '';
        final password = credentials['password'] ?? '';
        if (phone.isEmpty ||
            password.isEmpty ||
            (auth.phoneNumber?.isNotEmpty == true &&
                phone != auth.phoneNumber)) {
          throw const LoginRecoveryRequired(
            'Save your Railway credentials in Login to enable session recovery.',
          );
        }
        // Acquire fresh Cloudflare token for the sign-in endpoint.
        final cft = await TurnstileGate.instance.acquire(
          label: 'Railway login',
          forceFresh: true,
          siteKey: '0x4AAAAAAB5VTjZ90pUxRuXR',
        );
        if (cft == null || cft.isEmpty) {
          throw const LoginRecoveryRequired(
            'Tap Log in to verify Railway login.',
          );
        }
        await TurnstileGate.instance.invalidate();
        // A cancelled or unavailable human check is not a login API attempt.
        await SecureStore.write(
          'rail_login_attempt_at',
          '${DateTime.now().millisecondsSinceEpoch}',
        );
        final response = await _send(
          'sign_in',
          'POST',
          {'mobile_number': phone, 'password': password, 'cft_response': cft},
          auth,
          {},
          authenticated: false,
        );
        if (RailwayCredentialsRejected.isResponse(response.body)) {
          throw const RailwayCredentialsRejected();
        }
        if (response.statusCode != 200) {
          throw const LoginRecoveryRequired(
            'Railway login recovery failed. Please sign in again.',
          );
        }
        final decoded = jsonDecode(response.body);
        final data = decoded is Map ? decoded['data'] : null;
        final token = data is Map ? (data['token'] ?? data['access_token']) : null;
        if (token is! String || token.isEmpty || (data is Map && data['success'] == false)) {
          throw const LoginRecoveryRequired(
            'Railway login did not return a valid token. Tap Log in to continue.',
          );
        }
        final user = (data is Map && data['user'] is Map)
            ? Map<String, dynamic>.from(data['user'] as Map)
            : null;
        if (user != null && user.isNotEmpty) {
          await SecureStore.write('rail_user', jsonEncode(user));
        }
        final updated = AuthSession(
          token: token,
          deviceId: auth.deviceId,
          deviceKey: auth.deviceKey,
          phoneNumber: phone,
          displayName: user?['display_name']?.toString() ??
              user?['name']?.toString() ??
              auth.displayName,
          email: user?['email']?.toString() ?? auth.email,
          cookie: auth.cookie,
          isPro: auth.isPro,
        );
        if (!updated.isValid) {
          throw const LoginRecoveryRequired(
            'Railway returned an expired token. Tap Log in to continue.',
          );
        }
        await AuthSession.save(updated);
        await SecureStore.delete('rail_action_token');
        await NotificationService().clearLoginAlert();
        return updated;
      } catch (_) {
        await NotificationService().showLoginRequired();
        rethrow;
      } finally {
        _refreshes.remove(key);
      }
    });
  }

  static Future<http.Response> _send(
    String operation,
    String method,
    Map<String, dynamic> runtime,
    AuthSession auth,
    Map<String, String> extra, {
    bool authenticated = true,
  }) async {
    final settings = AppConfig.instance.apiOperation(operation);
    var url =
        settings['url'] as String? ??
        '${RailApiConfig.baseUrl}${RailApiConfig.paths[operation]}';
    url = url.replaceAll('{order_id}', '${runtime['order_id']}');
    final body = settings.containsKey('payload')
        ? Map<String, dynamic>.from(
            RailApiConfig.render(settings['payload'], runtime),
          )
        : runtime;
    var uri = Uri.parse(url);
    if (method == 'GET' && body.isNotEmpty) {
      uri = uri.replace(
        queryParameters: {
          for (final e in body.entries)
            if (e.key != 'order_id' && e.value != null) e.key: '${e.value}',
        },
      );
    }
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Origin': 'https://eticket.railway.gov.bd',
      'Referer': 'https://eticket.railway.gov.bd/',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36',
      'X-Requested-With': 'XMLHttpRequest',
      'sec-ch-ua': '"Chromium";v="154", "Google Chrome";v="154", "Not A(Brand";v="99"',
      'sec-ch-ua-mobile': '?0',
      'sec-ch-ua-platform': '"Windows"',
      ...extra,
    };
    // Replace captured auth headers after recovery, irrespective of casing.
    headers.removeWhere(
      (key, _) => [
        'authorization',
        'x-device-id',
        'x-device-key',
        'cookie',
      ].contains(key.toLowerCase()),
    );
    headers.addAll({
      if (authenticated)
        'Authorization': auth.token.startsWith('Bearer ')
            ? auth.token
            : 'Bearer ${auth.token}',
      'X-Device-Id': auth.deviceId,
      'X-Device-Key': auth.deviceKey,
      if (auth.cookie?.isNotEmpty == true) 'Cookie': auth.cookie!,
    });
    if (authenticated) {
      final action = await SecureStore.read('rail_action_token');
      headers.removeWhere((key, _) => key.toLowerCase() == 'x-action-token');
      if (action?.isNotEmpty == true) headers['X-Action-Token'] = action!;
    }
    // Serialize interval allocation so concurrent requests respect DB settings.
    final previous = _queues[operation] ?? Future<void>.value();
    final slot = previous.then((_) async {
      final interval = settings['min_interval_seconds'] as int? ?? 0;
      final last = _lastCalls[operation];
      if (last != null) {
        final wait =
            Duration(seconds: interval) - DateTime.now().difference(last);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      _lastCalls[operation] = DateTime.now();
    });
    _queues[operation] = slot;
    await slot;
    final future = switch (method) {
      'GET' => http.get(uri, headers: headers),
      'PATCH' => http.patch(uri, headers: headers, body: jsonEncode(body)),
      _ => http.post(uri, headers: headers, body: jsonEncode(body)),
    };
    return future.timeout(
      Duration(seconds: AppConfig.instance.number('request_timeout_seconds')),
    );
  }
}
