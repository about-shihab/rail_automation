import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_session.dart';
import 'app_config.dart';
import 'notification_service.dart';
import 'login_recovery_required.dart';
import 'rail_api_config.dart';
import 'rail_request_pacer.dart';
import 'railway_credentials_rejected.dart';
import 'secure_store.dart';
import 'session_recovery.dart';
import 'turnstile_gate.dart';
import 'turnstile_session.dart';
import 'seat_layout_challenge.dart';

/// One bounded recovery for explicit auth rejections. Unknown mutation outcomes
/// and generic Cloudflare 403 responses are never replayed.
class RailApiClient {
  static final _refreshes = <String, Future<AuthSession>>{};
  static const _cooldownKey = 'rail_api_cooldown_until_v1';
  @visibleForTesting
  static RailRequestPacer requestPacer = RailRequestPacer();

  static Duration get cooldownRemaining => requestPacer.cooldownRemaining;

  /// Workers and foreground sessions keep the same server-directed pause,
  /// including after an app restart. Never start session recovery during it.
  static Future<void> ensureReady() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final saved = prefs.getInt(_cooldownKey);
    if (saved != null) {
      requestPacer.restoreCooldown(DateTime.fromMillisecondsSinceEpoch(saved));
    }
    requestPacer.checkCooldown();
  }

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
    await ensureReady();
    var session = await current(auth);
    if (!session.isValid) session = await refresh(session);
    var response = await _send(operation, method, payload, session, headers);
    if (_authRejected(response)) {
      session = await refresh(session, rejectedToken: session.token);
      if (operation == 'seat_layout' &&
          payload['cft_response'] is String &&
          (payload['cft_response'] as String).isNotEmpty) {
        // The rejected request may already have consumed the token. The next
        // guarded layout retry obtains a different token for the renewed session.
        throw const SeatLayoutChallenge(
          verificationAttempted: true,
          tokenRejected: true,
        );
      }
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
    // A CFT error can also say "invalid token". It needs a fresh challenge,
    // not a login that would consume a different site's verification token.
    if (SeatLayoutChallenge.isTokenRejection(
      response.statusCode,
      response.body,
    )) {
      return false;
    }
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
        if (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.iOS &&
            AuthSession.iosBackgroundExecution) {
          await NotificationService().showLoginRequired();
          throw const LoginRecoveryRequired(
            'Open Rail Pro to renew your Railway session.',
          );
        }
        if (SessionRecovery.instance.canRunWebView) {
          return await SessionRecovery.instance.recover(
            previous: auth,
            rejectedToken: rejectedToken ?? auth.token,
          );
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
        final token = data is Map
            ? (data['token'] ?? data['access_token'])
            : null;
        if (token is! String ||
            token.isEmpty ||
            (data is Map && data['success'] == false)) {
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
          displayName:
              user?['display_name']?.toString() ??
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
    if (operation == 'seat_layout' &&
        runtime['cft_response'] is String &&
        (runtime['cft_response'] as String).isNotEmpty) {
      // Remote payload templates must not drop or substitute this one-use value.
      body['cft_response'] = runtime['cft_response'];
    }
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
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        runtime['cft_response'] is String &&
        (runtime['cft_response'] as String).isNotEmpty) {
      final browserAgent = TurnstileSession.instance.userAgent;
      if (browserAgent != null && browserAgent.isNotEmpty) {
        // Submit the challenge with the WKWebView identity that produced it.
        // Desktop Chromium hints conflict with iOS's native browser identity.
        headers.removeWhere(
          (key, _) =>
              key.toLowerCase() == 'user-agent' ||
              key.toLowerCase().startsWith('sec-ch-'),
        );
        headers['User-Agent'] = browserAgent;
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
    final timeout = Duration(
      seconds:
          settings['timeout_seconds'] as int? ??
          AppConfig.instance.number('request_timeout_seconds'),
    );
    // Only idempotent reads are retried; a mutation with an unknown outcome
    // must never be replayed.
    // A layout contains a one-use verification token, even though it uses GET.
    final retries = verb == 'GET' && operation != 'seat_layout'
        ? (settings['retries'] as int? ?? 0)
        : 0;
    final retryDelay = Duration(
      seconds: settings['retry_delay_seconds'] as int? ?? 2,
    );
    for (var attempt = 0; ; attempt++) {
      try {
        final response = await requestPacer.run(
          operation: operation,
          paced: operation != 'search_trips',
          minInterval: Duration(
            seconds: settings['min_interval_seconds'] as int? ?? 0,
          ),
          send: () async {
            await ensureReady();
            if (authenticated && !AuthSession.useBackgroundStorage) {
              final action = await SecureStore.read('rail_action_token');
              headers.removeWhere(
                (key, _) => key.toLowerCase() == 'x-action-token',
              );
              if (action?.isNotEmpty == true) {
                headers['X-Action-Token'] = action!;
              }
            }
            final client = http.Client();
            late final http.Response result;
            try {
              final pendingResponse = switch (verb) {
                'GET' => client.get(uri, headers: headers),
                'PATCH' => client.patch(
                  uri,
                  headers: headers,
                  body: jsonEncode(body),
                ),
                _ => client.post(uri, headers: headers, body: jsonEncode(body)),
              };
              result = await pendingResponse.timeout(timeout);
            } finally {
              // Abort timed-out sockets before releasing the queue slot.
              client.close();
            }
            final nextAction = result.headers['x-action-token'];
            if (authenticated &&
                !AuthSession.useBackgroundStorage &&
                nextAction != null &&
                _validActionResponse(operation, result)) {
              await SecureStore.write('rail_action_token', nextAction);
            }
            if (result.statusCode == 429) {
              final until = requestPacer.rateLimited(result.headers);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt(_cooldownKey, until.millisecondsSinceEpoch);
              throw RailwayRateLimited(until);
            }
            if (result.statusCode >= 200 && result.statusCode < 300) {
              requestPacer.recordSuccess();
            }
            return result;
          },
        );
        final transient = response.statusCode >= 500;
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

  static bool _validActionResponse(String operation, http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) return false;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['data'] is! Map) return false;
      return operation != 'seat_layout' ||
          decoded['data']['seatLayout'] is List;
    } on FormatException {
      return false;
    }
  }
}
