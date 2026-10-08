import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/auth_session.dart';
import 'app_config.dart';
import 'login_recovery_required.dart';
import 'notification_service.dart';
import 'railway_credentials_rejected.dart';
import 'secure_store.dart';

/// One pending silent login. The UI side ([SessionRecoveryHost]) renders the
/// loading screen and drives a hidden WebView through it.
class RecoveryJob {
  RecoveryJob({
    required this.id,
    required this.phone,
    required this.password,
    required this.rejectedToken,
    required this.previous,
  });

  final int id;
  final String phone;
  final String password;
  final String rejectedToken;
  final AuthSession? previous;
  final Completer<AuthSession> completer = Completer<AuthSession>();
}

/// Re-logs in with the saved credentials by driving the real Railway login
/// page in a background WebView, so Cloudflare / Angular behave exactly as
/// they do for a person. The user only sees a loading screen.
///
/// Anything that can't be finished silently is reported as:
///  * [RailwayCredentialsRejected] – Railway said the username/password is wrong
///  * [LoginRecoveryRequired]      – everything else (timeout, no network,
///                                   Cloudflare challenge, no saved login…)
/// Callers answer both by showing the visible login WebView.
class SessionRecovery extends ChangeNotifier {
  SessionRecovery._();
  static final SessionRecovery instance = SessionRecovery._();

  /// Overall limit for one silent login.
  static const timeout = Duration(seconds: 45);

  RecoveryJob? _job;
  Future<AuthSession>? _running;
  Timer? _timer;
  int _nextId = 0;

  /// Set by the host widget while it is part of the widget tree.
  bool hostAttached = false;

  RecoveryJob? get job => _job;
  bool get active => _job != null;

  /// A WebView can only exist in the foreground UI isolate. The foreground
  /// service isolate (background searching) has no navigator.
  bool get canRunWebView {
    if (!hostAttached) return false;
    final nav = NotificationService.navigatorKey.currentState;
    if (nav == null || !nav.mounted) return false;
    final life = WidgetsBinding.instance.lifecycleState;
    return life == null || life == AppLifecycleState.resumed;
  }

  static String _bare(String token) =>
      token.startsWith('Bearer ') ? token.substring(7) : token;

  /// Silently signs in again. Concurrent callers share one attempt.
  Future<AuthSession> recover({AuthSession? previous, String? rejectedToken}) {
    final running = _running;
    if (running != null) return running;
    final f = _recover(previous, rejectedToken ?? previous?.token ?? '')
        .whenComplete(() => _running = null);
    _running = f;
    return f;
  }

  Future<AuthSession> _recover(AuthSession? previous, String rejected) async {
    // Never hammer Railway after a failed attempt; the user takes over instead.
    final last = int.tryParse(
      await SecureStore.read('rail_login_attempt_at') ?? '',
    );
    final interval =
        AppConfig.instance.number('login_retry_interval_seconds') * 1000;
    if (last != null) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - last;
      if (elapsed >= 0 && elapsed < interval) {
        final seconds = ((interval - elapsed) / 1000).ceil();
        throw LoginRecoveryRequired(
          'Automatic login can retry in $seconds seconds. Please sign in again.',
        );
      }
    }

    final credentials = await AuthSession.getSavedUserCredentials();
    final phone = credentials['phone'] ?? '';
    final password = credentials['password'] ?? '';
    if (phone.isEmpty || password.isEmpty) {
      throw const LoginRecoveryRequired(
        'No saved Railway login. Please sign in again.',
      );
    }
    if (!canRunWebView) {
      throw const LoginRecoveryRequired(
        'Open Rail Pro to sign in to Railway again.',
      );
    }

    await SecureStore.write(
      'rail_login_attempt_at',
      '${DateTime.now().millisecondsSinceEpoch}',
    );
    final job = RecoveryJob(
      id: ++_nextId,
      phone: phone,
      password: password,
      rejectedToken: _bare(rejected),
      previous: previous,
    );
    _job = job;
    _timer = Timer(timeout, () {
      fail(
        job,
        const LoginRecoveryRequired(
          'Railway login took too long. Please sign in again.',
        ),
      );
    });
    notifyListeners();

    try {
      return await job.completer.future;
    } on RailwayCredentialsRejected {
      // The stored password is known to be wrong: never auto-submit it again.
      await AuthSession.clearSavedPassword();
      rethrow;
    } finally {
      _timer?.cancel();
      _timer = null;
      if (identical(_job, job)) {
        _job = null;
        notifyListeners();
      }
    }
  }

  void complete(RecoveryJob job, AuthSession session) {
    if (!job.completer.isCompleted) job.completer.complete(session);
  }

  void fail(RecoveryJob job, Object error) {
    if (!job.completer.isCompleted) job.completer.completeError(error);
  }
}
