import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/auth_session.dart';
import 'app_config.dart';
import 'notification_service.dart';
import 'rail_api_config.dart';
import 'login_recovery_required.dart';
import 'secure_store.dart';
import 'session_recovery.dart';

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
        if (!SessionRecovery.instance.canRunWebView) {
          await NotificationService().showLoginRequired();
        }
        throw const LoginRecoveryRequired(
          'Session expired. Please sign in again.',
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

  /// Signs in again after the token expired or was rejected. This runs the real
  /// Railway login page in a background WebView with the saved credentials
  /// (the user only sees a loading screen) and stores the new session and
  /// credentials. If that cannot finish, [LoginRecoveryRequired] or
  /// [RailwayCredentialsRejected] is thrown and the caller shows the visible
  /// login WebView.
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
        return await SessionRecovery.instance.recover(
          previous: auth,
          rejectedToken: rejectedToken ?? auth.token,
        );
      } catch (_) {
        // In the foreground the app opens the login screen itself; the
        // notification is only for the background search service.
        if (!SessionRecovery.instance.canRunWebView) {
          await NotificationService().showLoginRequired();
        }
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
    if (settings['enabled'] == false) {
      throw StateError(
        'This Railway action is temporarily unavailable. Please try again later.',
      );
    }
    // The database may override the HTTP verb; the caller's verb is the default.
    final verb = (settings['method'] as String?) ?? method;
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
    if (verb == 'GET' && body.isNotEmpty) {
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
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36',
      'X-Requested-With': 'XMLHttpRequest',
      'sec-ch-ua':
          '"Chromium";v="154", "Google Chrome";v="154", "Not A(Brand";v="99"',
      'sec-ch-ua-mobile': '?0',
      'sec-ch-ua-platform': '"Windows"',
      'Accept-Language': 'en-US,en;q=0.9',
      'Sec-Fetch-Site': 'same-site',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Dest': 'empty',
      ...extra,
    };
    // Database overrides (allow-listed, non-secret): global first, then the
    // per-operation set. Matching is case-insensitive.
    for (final overrides in [
      AppConfig.instance.apiHeaders,
      Map<String, String>.from(settings['headers'] as Map? ?? const {}),
    ]) {
      for (final entry in overrides.entries) {
        headers.removeWhere(
          (key, _) => key.toLowerCase() == entry.key.toLowerCase(),
        );
        headers[entry.key] = entry.value;
      }
    }
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
    final timeout = Duration(
      seconds:
          settings['timeout_seconds'] as int? ??
          AppConfig.instance.number('request_timeout_seconds'),
    );
    // Only idempotent reads are retried; a mutation with an unknown outcome
    // must never be replayed.
    final retries = verb == 'GET' ? (settings['retries'] as int? ?? 0) : 0;
    final retryDelay = Duration(
      seconds: settings['retry_delay_seconds'] as int? ?? 2,
    );
    for (var attempt = 0; ; attempt++) {
      try {
        final pendingResponse = switch (verb) {
          'GET' => http.get(uri, headers: headers),
          'PATCH' => http.patch(uri, headers: headers, body: jsonEncode(body)),
          _ => http.post(uri, headers: headers, body: jsonEncode(body)),
        };
        final response = await pendingResponse.timeout(timeout);
        final transient =
            response.statusCode == 429 || response.statusCode >= 500;
        if (transient && attempt < retries) {
          await Future<void>.delayed(retryDelay * (attempt + 1));
          continue;
        }
        return response;
      } on TimeoutException {
        if (attempt >= retries) rethrow;
        await Future<void>.delayed(retryDelay * (attempt + 1));
      } on SocketException {
        if (attempt >= retries) rethrow;
        await Future<void>.delayed(retryDelay * (attempt + 1));
      } on http.ClientException {
        if (attempt >= retries) rethrow;
        await Future<void>.delayed(retryDelay * (attempt + 1));
      }
    }
  }
}
