import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

enum TurnstilePhase { idle, connecting, interactive, success, error }

/// One rendered browser, kept by the UI engine while the foreground monitor
/// runs. The service isolate requests tokens through ForegroundMonitor's bridge;
/// it must never construct another browser or share a token between bookings.
class TurnstileSession extends ChangeNotifier {
  static const defaultSiteKey = '0x4AAAAAACNkZ_TxQr_zpcZW';
  static final instance = TurnstileSession();
  final challengeLink = LayerLink();
  TurnstilePhase phase = TurnstilePhase.idle;
  String? error;
  Future<void> Function(String source)? _evaluate;
  Completer<void>? _ready;
  Completer<void>? _attachmentWaiter;
  Completer<String?>? _pending;
  Timer? _timeout;
  int _requestId = 0;
  String? userAgent;
  String _siteKey = defaultSiteKey;

  bool get attached => _evaluate != null;
  bool get generating => _pending != null;

  void attach(Future<void> Function(String source) evaluate) {
    _evaluate = evaluate;
    userAgent = null;
    _ready = Completer<void>();
    final waiter = _attachmentWaiter;
    _attachmentWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  void detach() {
    cancel();
    _evaluate = null;
    _ready = null;
    userAgent = null;
  }

  Future<String?> generate([String? siteKey]) {
    final target = siteKey ?? defaultSiteKey;
    if (_pending != null) {
      if (target == _siteKey) return _pending!.future;
      return _pending!.future.then((_) => generate(target));
    }
    if (!attached) return Future.value(null);
    final pending = Completer<String?>();
    _pending = pending;
    _siteKey = target;
    final id = ++_requestId;
    phase = TurnstilePhase.connecting;
    error = null;
    notifyListeners();
    _armTimeout();
    unawaited(_execute(id, target));
    return pending.future;
  }

  /// A cold notification launch may reach the booking UI before Android has
  /// attached its platform view. Keep loading instead of dropping the request.
  Future<String?> generateWhenAttached([String? siteKey]) async {
    if (!attached) {
      final id = _requestId;
      final waiter = _attachmentWaiter ??= Completer<void>();
      try {
        await waiter.future.timeout(const Duration(seconds: 15));
      } catch (_) {
        fail('Could not prepare the security check. Please retry.');
        return null;
      } finally {
        if (identical(_attachmentWaiter, waiter)) _attachmentWaiter = null;
      }
      if (!attached || id != _requestId) return null;
    }
    return generate(siteKey);
  }

  /// An explicit Retry keeps the purpose of the challenge being displayed.
  Future<String?> retryWhenAttached() => generateWhenAttached(_siteKey);

  Future<void> _execute(int id, [String? siteKey]) async {
    try {
      final pending = _pending!;
      if (!_ready!.isCompleted) await _evaluate!(bootstrap);
      await Future.any<void>([
        _ready!.future,
        pending.future.then<void>((_) {}),
      ]).timeout(const Duration(seconds: 30));
      if (_pending == null || id != _requestId) return;
      if (siteKey != null && siteKey.isNotEmpty) {
        await _evaluate!('window.__railBegin($id, ${jsonEncode(siteKey)});');
      } else {
        await _evaluate!('window.__railBegin($id);');
      }
    } catch (_) {
      if (_pending != null && id == _requestId) {
        fail('Security check unavailable. Please retry.');
      }
    }
  }

  void _armTimeout() {
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 30), () {
      fail('The security check is taking too long.');
    });
  }

  void receive(Map<String, dynamic> data) {
    if (data['status'] == 'READY') {
      final agent = data['userAgent'];
      if (agent is String && agent.trim().isNotEmpty) userAgent = agent;
      if (_ready != null && !_ready!.isCompleted) _ready!.complete();
      return;
    }
    if (data['status'] == 'PRELOAD_ERROR') {
      fail('Could not prepare the security check. Please retry.');
      return;
    }
    // Ignore late callbacks from a cancelled or consumed challenge.
    if (_pending == null || data['requestId'] != _requestId) return;
    switch (data['status']) {
      case 'INTERACTIVE':
        _timeout?.cancel();
        phase = TurnstilePhase.interactive;
        notifyListeners();
      case 'SOLVING':
        phase = TurnstilePhase.connecting;
        _armTimeout();
        notifyListeners();
      case 'SUCCESS':
        final token = data['token'];
        if (token is! String || token.isEmpty) return;
        _timeout?.cancel();
        phase = TurnstilePhase.success;
        final pending = _pending!;
        _pending = null;
        notifyListeners();
        pending.complete(token);
      case 'ERROR':
        fail('Verification failed (${data['message'] ?? 'unknown'}).');
    }
  }

  void fail(String message) {
    _timeout?.cancel();
    error = message;
    phase = TurnstilePhase.error;
    final pending = _pending;
    _pending = null;
    notifyListeners();
    if (pending != null && !pending.isCompleted) pending.complete(null);
  }

  void cancel() {
    _timeout?.cancel();
    ++_requestId;
    final waiter = _attachmentWaiter;
    _attachmentWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(null);
    final evaluate = _evaluate;
    if (evaluate != null) {
      unawaited(
        evaluate('window.__railCancel && window.__railCancel();')
            .catchError((Object _) {}),
      );
    }
    phase = TurnstilePhase.idle;
    error = null;
    // Cancellation also runs during route/host disposal, while Flutter locks
    // the widget tree. Publish the state after that disposal completes.
    scheduleMicrotask(notifyListeners);
  }

  static const html = '''<!doctype html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;background:transparent;overflow:hidden}
#challenge{display:flex;justify-content:center}</style>
</head><body><div id="challenge"></div></body></html>''';

  /// Render once, without running a challenge. No timer, automatic retry or
  /// refresh may generate tokens while the monitor is waiting for tickets.
  static final bootstrap =
      '''
(function () {
  if (window.__railPrepared) return;
  window.__railPrepared = true;
  var defaultSiteKey = ${jsonEncode('0x4AAAAAACNkZ_TxQr_zpcZW')};
  var currentSiteKey = defaultSiteKey;
  var widget = null, active = null, used = false;
  function post(status, extra, id) {
    window.flutter_inappwebview.callHandler('TurnstileBridge',
      Object.assign({status: status, requestId: id, userAgent: navigator.userAgent}, extra || {}));
  }
  function render(key) {
    try {
    currentSiteKey = key || defaultSiteKey;
    widget = turnstile.render('#challenge', {
      sitekey: currentSiteKey,
      size: 'compact', theme: 'auto', appearance: 'interaction-only',
      execution: 'execute', retry: 'never',
      'refresh-expired': 'manual', 'refresh-timeout': 'manual',
      'before-interactive-callback': function () { post('INTERACTIVE', {}, active); },
      'after-interactive-callback': function () { post('SOLVING', {}, active); },
      callback: function (token) {
        var id = active; active = null; post('SUCCESS', {token: token}, id);
      },
      'error-callback': function (code) {
        post('ERROR', {message: String(code)}, active); return true;
      },
      'expired-callback': function () { post('ERROR', {message: 'Check expired'}, active); },
      'timeout-callback': function () { post('ERROR', {message: 'Check timed out'}, active); }
    });
    post('READY');
    } catch (error) {
      window.__railPrepared = false;
      post('PRELOAD_ERROR');
    }
  }
  window.__railCancel = function () { active = null; };
  window.__railBegin = function (id, sitekey) {
    active = null;
    var target = sitekey || defaultSiteKey;
    if (widget !== null && currentSiteKey !== target) {
      try { turnstile.remove(widget); } catch (e) {}
      widget = null;
      used = false;
    }
    if (widget === null) {
      active = id;
      render(target);
      used = true;
      turnstile.execute(widget);
    } else {
      if (used) turnstile.reset(widget);
      used = true;
      active = id;
      turnstile.execute(widget);
    }
  };
  var script = document.createElement('script');
  script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
  script.onload = function() { render(defaultSiteKey); };
  script.onerror = function () {
    window.__railPrepared = false;
    script.remove();
    post('PRELOAD_ERROR');
  };
  document.head.appendChild(script);
})();
''';

  /// iOS-only variant; the original Android script remains unchanged.
  ///
  /// Key iOS difference: `turnstile.reset()` does not reliably produce a fresh
  /// token on WKWebView when the previous widget was already used or expired
  /// (the expired-callback fires instead of the success-callback). To guarantee
  /// a new token on every booking attempt, the iOS build always removes the old
  /// widget and calls `render()` again. The extra DOM work is negligible because
  /// the widget is hidden until an interaction is required.
  static String bootstrapForBridge(String bridgeId) => bootstrap
      .replaceFirst(
        'var defaultSiteKey',
        'var bridgeId = ${jsonEncode(bridgeId)};\n  var defaultSiteKey',
      )
      .replaceFirst(
        'Object.assign({status:',
        'Object.assign({bridgeId: bridgeId, status:',
      )
      // Replace the reset-or-execute branch with a remove-and-re-render so that
      // every call to __railBegin starts from a clean widget on iOS. The
      // `widget === null` branch (first call or after site-key change) is
      // already correct; only the `else` path needs changing.
      .replaceFirst(
        '    } else {\n'
        '      if (used) turnstile.reset(widget);\n'
        '      used = true;\n'
        '      active = id;\n'
        '      turnstile.execute(widget);\n'
        '    }',
        '    } else {\n'
        '      // iOS: always re-render for a fresh token instead of reset.\n'
        '      try { turnstile.remove(widget); } catch (e) {}\n'
        '      widget = null;\n'
        '      used = false;\n'
        '      active = id;\n'
        '      render(target);\n'
        '      used = true;\n'
        '      turnstile.execute(widget);\n'
        '    }',
      );
}
