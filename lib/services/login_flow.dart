import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../views/webview_login_screen.dart';
import 'language_service.dart';
import 'login_recovery_required.dart';
import 'notification_service.dart';
import 'rail_api_client.dart';
import 'railway_credentials_rejected.dart';

/// The one place that decides how a login problem reaches the user:
///
///  1. token expired        → silent WebView login (loading screen only)
///  2. silent login failed  → visible login WebView ([openManualLogin])
///  3. new login succeeds   → saved credentials are replaced for next time
class LoginFlow {
  LoginFlow._();

  /// True for any failure that only the user can fix by signing in again.
  static bool needsLogin(Object? error) =>
      error is LoginRecoveryRequired || RailwayCredentialsRejected.isError(error);

  /// Returns a valid session, signing in silently first if the token expired.
  /// When that is impossible the visible login opens and `null` is returned
  /// (or the session after a successful manual login).
  static Future<AuthSession?> ensureSession() async {
    final session = await AuthSession.load();
    if (session == null || !session.isLoggedIn || session.isValid) {
      return session;
    }
    try {
      return await RailApiClient.refresh(session);
    } catch (e) {
      if (!needsLogin(e)) return null;
      final ok = await openManualLogin(
        credentialsRejected: RailwayCredentialsRejected.isError(e),
      );
      return ok ? await AuthSession.load() : null;
    }
  }

  /// For a "login required" prompt (e.g. notification tap): the token may
  /// look valid locally yet be rejected by Railway, so force a fresh silent
  /// login first and fall back to the visible login.
  static Future<void> recoverNow() async {
    final session = await AuthSession.load();
    if (session == null) {
      await openManualLogin();
      return;
    }
    try {
      await RailApiClient.refresh(session, rejectedToken: session.token);
    } catch (e) {
      if (needsLogin(e)) {
        await openManualLogin(
          credentialsRejected: RailwayCredentialsRejected.isError(e),
        );
      }
    }
  }

  /// Opens the visible Railway login on top of the current screen and returns
  /// true once the user has signed in. Does nothing when it is already open.
  static Future<bool> openManualLogin({
    bool credentialsRejected = false,
  }) async {
    if (WebviewLoginScreen.isShowing) return false;
    final nav = NotificationService.navigatorKey.currentState;
    if (nav == null || !nav.mounted) return false;
    final lang = LanguageService.instance;
    final ok = await nav.push<bool>(
      MaterialPageRoute(
        builder: (_) => WebviewLoginScreen(
          clearSession: true,
          popOnSuccess: true,
          notice: credentialsRejected
              ? lang.tr(
                  'Your Railway username or password was not accepted. '
                      'Please sign in again.',
                  'রেলওয়ের ইউজারনেম বা পাসওয়ার্ড গ্রহণ করা হয়নি। '
                      'অনুগ্রহ করে আবার সাইন ইন করুন।',
                )
              : lang.tr(
                  'Your session ended. Please sign in again.',
                  'আপনার সেশন শেষ হয়েছে। অনুগ্রহ করে আবার সাইন ইন করুন।',
                ),
        ),
      ),
    );
    return ok == true;
  }
}
