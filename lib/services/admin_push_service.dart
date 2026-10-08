import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'notification_service.dart';
import 'app_config.dart';

@pragma('vm:entry-point')
Future<void> adminPushBackgroundHandler(RemoteMessage message) async {
  if (message.data['kind'] != 'admin_announcement') return;
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  final notifications = NotificationService();
  // Notification payloads are displayed by Android while the app is closed.
  // Never display a second local notification for the same remote message.
  if (message.notification == null) {
    await notifications.initialize(background: true);
  }
  await AdminPushService.deliver(
    message,
    alreadyDisplayed: message.notification != null,
  );
}

/// FCM is used only for announcements created by administrators.
class AdminPushService {
  AdminPushService._();
  static final instance = AdminPushService._();
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool _initialized = false;
  bool _pushConfigured = false;
  String? _phone;
  String? _token;
  Future<void> _registration = Future.value();

  static String normalizePhone(String? raw) {
    var phone = (raw ?? '').replaceAll(RegExp(r'\D'), '');
    if (phone.startsWith('880') && phone.length == 13) {
      phone = phone.substring(2);
    }
    return RegExp(r'^01[3-9]\d{8}$').hasMatch(phone) ? phone : '';
  }

  static Future<void> deliver(
    RemoteMessage message, {
    bool alreadyDisplayed = false,
  }) async {
    if (message.data['kind'] != 'admin_announcement') return;
    final id = message.data['notification_id'];
    if (id is! String || id.isEmpty || id.contains('/')) return;
    final title = message.notification?.title ?? message.data['title'];
    final body = message.notification?.body ?? message.data['body'];
    if (title is! String || body is! String || title.trim().isEmpty) return;
    await NotificationService().deliverAdminAnnouncement(
      documentId: id,
      title: title,
      body: body,
      alreadyDisplayed: alreadyDisplayed,
    );
  }

  static String? tapPayload(RemoteMessage message) {
    if (message.data['kind'] != 'admin_announcement') return null;
    final id = message.data['notification_id'];
    if (id is! String || id.isEmpty || id.contains('/')) return null;
    return Uri(
      scheme: 'rail',
      host: 'announcement',
      pathSegments: [id],
    ).toString();
  }

  Future<void> initialize({String? phone}) async {
    if (!supported || Firebase.apps.isEmpty || _initialized) return;
    _phone = normalizePhone(phone);
    _initialized = true;
    _pushConfigured = AppConfig.instance.boolean('admin_push_enabled');
    AppConfig.instance.addListener(_configurationChanged);
    FirebaseMessaging.onBackgroundMessage(adminPushBackgroundHandler);
    FirebaseMessaging.onMessage.listen((message) {
      unawaited(deliver(message));
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      unawaited(deliver(message, alreadyDisplayed: true));
      NotificationService().openBooking(tapPayload(message));
    });
    FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) {
        _token = token;
        unawaited(_register());
      },
      onError: (Object error) {
        debugPrint(
          '[AdminPush] Token refresh unavailable: ${error.runtimeType}',
        );
      },
    );
    try {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      if (message != null) {
        await deliver(message, alreadyDisplayed: true);
        NotificationService().openBooking(tapPayload(message));
      }
      await refresh();
    } catch (error) {
      debugPrint(
        '[AdminPush] Initialization unavailable: ${error.runtimeType}',
      );
    }
  }

  /// Also retries failed/offline registration when the app resumes.
  Future<void> refresh() async {
    if (!_initialized || !AppConfig.instance.boolean('admin_push_enabled')) {
      return;
    }
    try {
      final permission = await FirebaseMessaging.instance.requestPermission();
      if (permission.authorizationStatus == AuthorizationStatus.denied) return;
      _token = await FirebaseMessaging.instance.getToken();
      await _register();
    } catch (error) {
      debugPrint('[AdminPush] Registration unavailable: ${error.runtimeType}');
    }
  }

  void _configurationChanged() {
    final enabled = AppConfig.instance.boolean('admin_push_enabled');
    if (enabled == _pushConfigured) return;
    _pushConfigured = enabled;
    if (enabled) unawaited(refresh());
  }

  Future<void> bindPhone(String? phone) async {
    final normalized = normalizePhone(phone);
    if (_phone == normalized) return;
    _phone = normalized;
    if (_initialized) await _register();
  }

  Future<void> signOut() async {
    if (!_initialized) return;
    _phone = '';
    try {
      // Disassociate first; retiring the token also stops queued private pushes.
      await _register();
      await FirebaseMessaging.instance.deleteToken();
      _token = null;
      await refresh();
    } catch (error) {
      debugPrint(
        '[AdminPush] Sign-out update unavailable: ${error.runtimeType}',
      );
    }
  }

  Future<void> _register() {
    _registration = _registration
        .then((_) async {
          if (!AppConfig.instance.boolean('admin_push_enabled')) return;
          final token = _token;
          if (token == null || token.isEmpty) return;
          final prefs = await SharedPreferences.getInstance();
          var installation = prefs.getString('admin_push_installation');
          if (installation == null) {
            final random = Random.secure();
            installation = List.generate(
              24,
              (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
            ).join();
            await prefs.setString('admin_push_installation', installation);
          }
          await FirebaseFirestore.instance
              .collection('push_devices')
              .doc(installation)
              .set({
                'token': token,
                'phone': _phone?.isNotEmpty == true ? _phone : null,
                'platform': 'android',
                'updatedAt': FieldValue.serverTimestamp(),
              });
        })
        .catchError((Object error) {
          debugPrint(
            '[AdminPush] Device update unavailable: ${error.runtimeType}',
          );
        });
    return _registration;
  }
}
