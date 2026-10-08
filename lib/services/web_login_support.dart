import 'dart:async';
import 'dart:convert';

import '../models/auth_session.dart';
import 'firebase_user_service.dart';
import 'notification_service.dart';
import 'secure_store.dart';

/// JavaScript shared by the visible login screen and the background recovery
/// runner, so both detect success / failure in exactly the same way.
class RailLoginScript {
  RailLoginScript._();

  static const loginUrl = 'https://eticket.railway.gov.bd/login';

  /// Hooks XHR / fetch / localStorage and reports to the `RailBridge` channel:
  ///  * HOLD_CONFIG   – seat hold duration
  ///  * CREDENTIALS   – what the user typed (fallback capture)
  ///  * AUTH_SUCCESS  – sign-in response carried a token (+ the submitted
  ///                    phone/password taken from the request body)
  ///  * AUTH_ERROR    – sign-in response had no token (status + body)
  ///  * STORAGE_TOKEN – token appeared in localStorage
  static const interceptors = r'''
(function() {
  if (window.__railInterceptorActive) return;
  window.__railInterceptorActive = true;
  try {
    var handshake = JSON.parse(localStorage.getItem('handshake_data') || '{}');
    var cfg = handshake.data || handshake;
    var hold = cfg.release_time_interval_in_minutes;
    if (hold > 0) window.RailBridge.postMessage(JSON.stringify({type: 'HOLD_CONFIG', seconds: Math.ceil(hold / 60) * 60}));
  } catch (_) {}

  function post(o) { try { if (window.RailBridge) window.RailBridge.postMessage(JSON.stringify(o)); } catch (_) {} }

  function captureCredentials() {
    var phone = document.querySelector('input[name="mobile_number"], input[type="tel"], #mobile_number');
    var pass = document.querySelector('input[type="password"]');
    if (phone && pass && phone.value && pass.value) {
      post({type: 'CREDENTIALS', phone: phone.value, password: pass.value});
    }
  }
  document.addEventListener('input', captureCredentials, true);
  document.addEventListener('submit', captureCredentials, true);

  function ls(keys) {
    for (var i = 0; i < keys.length; i++) {
      var v = localStorage.getItem(keys[i]);
      if (v) return v;
    }
    return '';
  }
  function getDeviceId() { return ls(['x-device-id','x_device_id','uudid','uuid','device_id','deviceId']); }
  function getDeviceKey() { return ls(['x-device-key','x_device_key','ss','ssdk','device_key','deviceKey']); }
  function getToken() { return ls(['token','user_token','access_token']); }

  function parseCreds(body) {
    try {
      if (!body || typeof body !== 'string') return {};
      var o = JSON.parse(body);
      return {phone: o.mobile_number || o.username || '', password: o.password || ''};
    } catch (_) { return {}; }
  }
  function isSignIn(url) { return (url || '').indexOf('sign-in') !== -1; }
  function isAuthUrl(url) {
    url = url || '';
    return url.indexOf('sign-in') !== -1 || url.indexOf('auth') !== -1 || url.indexOf('login') !== -1;
  }

  function handleAuthResponse(url, status, text, headers, reqBody) {
    var res = null;
    try { res = JSON.parse(text); } catch (_) {}
    var t = (res && res.data && res.data.token) || (res && res.token) || getToken();
    if (t) {
      var creds = parseCreds(reqBody);
      var usr = (res && res.data && res.data.user) || (res && res.user) || localStorage.getItem('user') || '{}';
      post({
        type: 'AUTH_SUCCESS',
        token: t,
        deviceId: headers['x-device-id'] || getDeviceId(),
        deviceKey: headers['x-device-key'] || getDeviceKey(),
        user: usr,
        cookie: document.cookie || '',
        phone: creds.phone || '',
        password: creds.password || ''
      });
    } else if (isSignIn(url) && (status >= 400 || (res && res.success === false))) {
      post({type: 'AUTH_ERROR', status: status, body: (text || '').substring(0, 1000)});
    }
  }

  // XHR
  var origOpen = XMLHttpRequest.prototype.open;
  var origSend = XMLHttpRequest.prototype.send;
  var origSetHeader = XMLHttpRequest.prototype.setRequestHeader;
  XMLHttpRequest.prototype.open = function(method, url) {
    this._reqUrl = url; this._reqHeaders = {};
    return origOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.setRequestHeader = function(h, v) {
    if (this._reqHeaders) this._reqHeaders[String(h).toLowerCase()] = v;
    return origSetHeader.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function(body) {
    var self = this;
    this.addEventListener('load', function() {
      try {
        if (isAuthUrl(self._reqUrl)) {
          handleAuthResponse(self._reqUrl, self.status, self.responseText, self._reqHeaders || {}, body);
        }
      } catch (_) {}
    });
    return origSend.apply(this, arguments);
  };

  // fetch
  var origFetch = window.fetch;
  window.fetch = async function() {
    var url = arguments[0];
    var opts = arguments[1] || {};
    var resp = await origFetch.apply(this, arguments);
    try {
      var strUrl = typeof url === 'string' ? url : (url && url.url) || '';
      if (isAuthUrl(strUrl)) {
        var text = await resp.clone().text();
        var h = new Headers(opts.headers || (typeof url !== 'string' && url.headers) || {});
        handleAuthResponse(strUrl, resp.status, text,
          {'x-device-id': h.get('x-device-id') || '', 'x-device-key': h.get('x-device-key') || ''},
          opts.body);
      }
    } catch (_) {}
    return resp;
  };

  function reportSession() {
    try {
      var t = getToken();
      if (t) {
        post({
          type: 'STORAGE_TOKEN', token: t,
          deviceId: getDeviceId(), deviceKey: getDeviceKey(),
          user: localStorage.getItem('user') || '{}',
          cookie: document.cookie || '',
          currentPath: window.location.pathname || ''
        });
      }
    } catch (_) {}
  }
  var originalSetItem = Storage.prototype.setItem;
  Storage.prototype.setItem = function(key, value) {
    originalSetItem.apply(this, arguments);
    if (this === localStorage) setTimeout(reportSession, 0);
  };
  setInterval(reportSession, 500);
  reportSession();
})();
''';

  /// Reads whatever session the page currently holds.
  static const readSession = r'''
(function() {
  var t = localStorage.getItem('token') || localStorage.getItem('access_token') || localStorage.getItem('user_token') || '';
  var devId = localStorage.getItem('x-device-id') || localStorage.getItem('uudid') || '';
  var devKey = localStorage.getItem('x-device-key') || localStorage.getItem('ss') || localStorage.getItem('ssdk') || '';
  return JSON.stringify({
    token: t, deviceId: devId, deviceKey: devKey,
    user: localStorage.getItem('user') || '{}',
    cookie: document.cookie || ''
  });
})()
''';

  /// Fills the login form ONCE per field (so it never fights the user's own
  /// typing) and, when [submit] is set, clicks the sign-in button as soon as
  /// it becomes enabled (Cloudflare finished). Gives up after 30 s.
  static String autofill(String phone, String password, {required bool submit}) =>
      '''
(function() {
  var phoneVal = ${jsonEncode(phone)};
  var passVal = ${jsonEncode(password)};
  if (window.__railAutofillRunning) return;
  window.__railAutofillRunning = true;

  function setVal(el, val) {
    if (!el) return;
    el.focus();
    var proto = Object.getPrototypeOf(el);
    var desc = Object.getOwnPropertyDescriptor(proto, 'value');
    if (desc && desc.set) desc.set.call(el, val); else el.value = val;
    el.dispatchEvent(new Event('keydown', { bubbles: true }));
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('keyup', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.dispatchEvent(new Event('blur', { bubbles: true }));
  }

  function pick(sels) {
    for (var i = 0; i < sels.length; i++) {
      var e = document.querySelector(sels[i]);
      if (e) return e;
    }
    return null;
  }

  function checkTurnstileResponse() {
    try {
      var input = document.querySelector('input[name="cf-turnstile-response"], input[name="cft_response"], input[id*="cf-chl"]');
      if (input && input.value && input.value.trim().length > 10) return true;
      if (window.turnstile && typeof window.turnstile.getResponse === 'function') {
        var resp = window.turnstile.getResponse();
        if (resp && resp.length > 10) return true;
      }
    } catch (_) {}
    return false;
  }

  function tryTriggerTurnstile() {
    try {
      var ts = document.querySelector('.cf-turnstile, [data-sitekey], ngx-turnstile, #challenge, div[id*="turnstile"]');
      if (ts && !checkTurnstileResponse()) {
        ts.click();
      }
    } catch (_) {}
  }

  var filled = false, submitted = false;
  function tick() {
    if (submitted) return true;
    var phoneEl = pick(['#mobile_number','input[name="mobile_number"]','input[formcontrolname="mobile_number"]','input[type="tel"]','input[placeholder*="Mobile"]']);
    var passEl = pick(['#password','input[name="password"]','input[formcontrolname="password"]','input[type="password"]']);

    if (phoneEl && phoneVal && (!phoneEl.value || phoneEl.value !== phoneVal)) {
      setVal(phoneEl, phoneVal);
      filled = true;
    }
    if (passEl && passVal && (!passEl.value || passEl.value !== passVal)) {
      setVal(passEl, passVal);
      filled = true;
    }
    if (phoneEl && (phoneEl.value === phoneVal) && (!passVal || (passEl && passEl.value === passVal))) {
      filled = true;
    }

    tryTriggerTurnstile();

    if (filled && ${submit ? 'true' : 'false'}) {
      var btn = document.querySelector('button.login-form-submit-btn, button[type="submit"]');
      var cfVerified = checkTurnstileResponse();
      if (btn) {
        if (!btn.disabled || cfVerified) {
          if (btn.disabled) btn.disabled = false;
          submitted = true;
          btn.click();
          return true;
        }
      }
    }
    return filled && ${submit ? 'false' : 'true'};
  }

  if (tick()) return;
  var iv = setInterval(function() { if (tick()) clearInterval(iv); }, 250);
  setTimeout(function() { clearInterval(iv); window.__railAutofillRunning = false; }, 35000);
})();
''';
}

/// A login observed in the Railway web page.
class WebLoginPayload {
  WebLoginPayload({
    required this.token,
    this.deviceId = '',
    this.deviceKey = '',
    this.cookie = '',
    this.user = const {},
    this.phone = '',
    this.password = '',
  });

  final String token;
  final String deviceId;
  final String deviceKey;
  final String cookie;
  final Map<String, dynamic> user;
  final String phone;
  final String password;

  static Map<String, dynamic> _user(Object? raw) {
    try {
      if (raw is String && raw.isNotEmpty) {
        final d = jsonDecode(raw);
        if (d is Map) return Map<String, dynamic>.from(d);
      } else if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } catch (_) {}
    return {};
  }

  factory WebLoginPayload.fromMap(Map<String, dynamic> m) => WebLoginPayload(
    token: m['token']?.toString() ?? '',
    deviceId: m['deviceId']?.toString() ?? '',
    deviceKey: m['deviceKey']?.toString() ?? '',
    cookie: m['cookie']?.toString() ?? '',
    user: _user(m['user']),
    phone: m['phone']?.toString() ?? '',
    password: m['password']?.toString() ?? '',
  );

  /// Parses the value returned by [RailLoginScript.readSession]. Android hands
  /// back a JSON-quoted string, iOS the bare string.
  static WebLoginPayload? fromJsResult(Object result) {
    try {
      final raw = result.toString();
      final inner = raw.startsWith('"') && raw.endsWith('"')
          ? jsonDecode(raw)
          : raw;
      final map = jsonDecode(inner.toString());
      if (map is! Map) return null;
      return WebLoginPayload.fromMap(Map<String, dynamic>.from(map));
    } catch (_) {
      return null;
    }
  }

  bool get hasUsableToken =>
      token.isNotEmpty &&
      !AuthSession.isDummyToken(token) &&
      !AuthSession.isJwtExpired(token);
}

class WebLoginPersistence {
  WebLoginPersistence._();

  /// Builds the session from a successful web login, stores it and refreshes
  /// the saved credentials so the next automatic login uses what just worked.
  ///
  /// [fallbackPhone] / [fallbackPassword] are used when the page did not expose
  /// what was submitted (e.g. the user was already signed in on the web view).
  static Future<AuthSession> save(
    WebLoginPayload p, {
    AuthSession? previous,
    String fallbackPhone = '',
    String fallbackPassword = '',
  }) async {
    final jwt = AuthSession.decodeJwtPayload(p.token);
    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = p.user[k]?.toString() ?? jwt?[k]?.toString() ?? '';
        if (v.isNotEmpty) return v;
      }
      return null;
    }

    // What the user actually typed is what the form accepts next time.
    var typedPhone = p.phone.trim().isNotEmpty
        ? p.phone.trim()
        : fallbackPhone.trim();
    var typedPassword = p.password.isNotEmpty ? p.password : fallbackPassword;

    final sessionPhone =
        pick(['mobile_number', 'phone_number', 'mobile', 'phone', 'username']) ??
        (typedPhone.isNotEmpty ? typedPhone : previous?.phoneNumber);

    // Never pair an old account's password with a different account's login.
    String tail(String v) {
      final d = v.replaceAll(RegExp(r'\D'), '');
      return d.length > 10 ? d.substring(d.length - 10) : d;
    }

    if (p.password.isEmpty &&
        sessionPhone != null &&
        typedPhone.isNotEmpty &&
        tail(sessionPhone) != tail(typedPhone)) {
      typedPhone = sessionPhone;
      typedPassword = '';
    }

    final session = AuthSession(
      token: p.token,
      deviceId: p.deviceId.isNotEmpty ? p.deviceId : previous?.deviceId,
      deviceKey: p.deviceKey.isNotEmpty
          ? p.deviceKey
          : (previous?.deviceKey ?? ''),
      cookie: p.cookie.isNotEmpty ? p.cookie : previous?.cookie,
      phoneNumber: sessionPhone,
      displayName:
          pick(['display_name', 'name', 'passenger_name']) ??
          previous?.displayName,
      email: pick(['email']) ?? previous?.email,
      isPro: previous?.isPro ?? false,
      isLoggedIn: true,
    );

    if (p.user.isNotEmpty) {
      await SecureStore.write('rail_user', jsonEncode(p.user));
    }
    await AuthSession.save(session);
    // Keep credentials current for the next silent login.
    if (typedPhone.isNotEmpty) {
      await AuthSession.saveUserCredentials(
        typedPhone,
        typedPassword.isNotEmpty ? typedPassword : null,
      );
    }
    await SecureStore.delete('rail_login_attempt_at');
    await SecureStore.delete('rail_action_token');
    try {
      await NotificationService().clearLoginAlert();
    } catch (_) {}
    try {
      unawaited(FirebaseUserService().syncUserOnLogin(session));
    } catch (_) {}
    return session;
  }
}
