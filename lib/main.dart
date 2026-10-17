import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/auth_session.dart';
import 'services/monitor_service.dart';
import 'services/notification_service.dart';
import 'services/pro_service.dart';
import 'services/otp_verifier.dart';
import 'services/theme_service.dart';
import 'services/language_service.dart';
import 'services/background_monitor.dart';
import 'services/foreground_monitor.dart';
import 'services/firebase_user_service.dart';
import 'utils/app_theme.dart';
import 'services/credit_service.dart';
import 'services/trip_history_service.dart';
import 'services/app_config.dart';
import 'services/admin_push_service.dart';
import 'services/overlay_service.dart';
import 'views/app_shell.dart';
import 'views/webview_login_screen.dart';
import 'widgets/turnstile_host.dart';
import 'widgets/app_update_gate.dart';
import 'services/booking_activity.dart';
import 'widgets/booking_activity_overlay.dart';
import 'widgets/session_recovery_host.dart';
import 'services/login_flow.dart';
import 'services/app_update_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppUpdateService.instance.initialize();
  unawaited(AppUpdateService.instance.refresh());

  // Initialize notifications
  final notificationService = NotificationService();
  await notificationService.initialize();
  await notificationService.requestPermissions();
  // Request overlay (SYSTEM_ALERT_WINDOW) permission
  await OverlayService.requestPermission();

  final session = await AuthSession.load();
  final isLoggedIn = session != null && session.isLoggedIn;

  final proService = ProService();
  final themeService = ThemeService();
  final languageService = LanguageService();
  final monitor = MonitorService(proService: proService);
  final tripHistoryService = TripHistoryService();
  await tripHistoryService.initialize();

  // Initialize AppConfig early so configured default credits are loaded
  await AppConfig.instance.initialize();

  final creditService = CreditService();
  await creditService.initialize();

  // Initialize Firebase User Service and sync active user
  final firebaseUserService = FirebaseUserService();
  await firebaseUserService.initialize(proService: proService);
  await AppConfig.instance.initialize();
  unawaited(
    AdminPushService.instance.initialize(
      phone: isLoggedIn ? session.phoneNumber : null,
    ),
  );
  unawaited(creditService.syncPackagesFromFirestore());
  if (session != null && isLoggedIn) {
    unawaited(firebaseUserService.syncUserOnLogin(session));
  }
  notificationService.startListeningToFirebaseNotifications(
    session?.phoneNumber,
  );

  try {
    await BackgroundMonitor.initialize();
  } catch (_) {
    monitor.backgroundError =
        'অ্যাপ খোলা রাখুন • Keep the app open to continue searching';
  }
  await monitor.restore();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: AppConfig.instance),
        ChangeNotifierProvider.value(value: proService),
        ChangeNotifierProvider.value(value: themeService),
        ChangeNotifierProvider.value(value: languageService),
        ChangeNotifierProvider.value(value: monitor),
        ChangeNotifierProvider.value(value: creditService),
        ChangeNotifierProvider.value(value: tripHistoryService),
        ChangeNotifierProvider.value(value: firebaseUserService),
      ],
      child: BangladeshRailApp(startLoggedIn: isLoggedIn),
    ),
  );
}

class BangladeshRailApp extends StatefulWidget {
  final bool startLoggedIn;

  const BangladeshRailApp({super.key, this.startLoggedIn = false});

  @override
  State<BangladeshRailApp> createState() => _BangladeshRailAppState();
}

class _BangladeshRailAppState extends State<BangladeshRailApp>
    with WidgetsBindingObserver {
  StreamSubscription<Map<String, dynamic>?>? _monitorUpdates;
  bool _syncingMonitor = false;

  Future<void> _syncMonitor({bool startTimers = false}) async {
    if (!mounted || _syncingMonitor) return;
    _syncingMonitor = true;
    try {
      final monitor = context.read<MonitorService>();
      await monitor.restore(startTimers: startTimers);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !AppUpdateService.instance.required) {
          monitor.resumePendingTurnstile();
        }
      });
    } finally {
      _syncingMonitor = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.startLoggedIn) {
      // Token expired while the app was closed? Sign in again behind a
      // loading screen before the user hits an error.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(LoginFlow.ensureSession()),
      );
    }
    if (ForegroundMonitor.initialized) {
      ForegroundMonitor.connectVerificationUi();
      _monitorUpdates = ForegroundMonitor.updates.listen((_) {
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.resumed) {
          unawaited(_syncMonitor());
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final monitor = context.read<MonitorService>();
    final firebaseUser = context.read<FirebaseUserService>();
    if (state == AppLifecycleState.resumed) {
      BookingActivity.instance.reset();
      unawaited(AdminPushService.instance.refresh());
      unawaited(ForegroundMonitor.syncBookingActivity());
      unawaited(AppUpdateService.instance.refresh(force: true));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !AppUpdateService.instance.required) {
          NotificationService().openPendingBooking();
        }
      });
      unawaited(LoginFlow.ensureSession());
      unawaited(_syncMonitor(startTimers: true));
      unawaited(OtpVerifier.listen());
      firebaseUser.setUserActive(true);
      CreditService().syncFromFirestore();
      AppConfig.instance.syncFromFirestore();
    } else if (state == AppLifecycleState.paused) {
      monitor.suspendForegroundTimers();
      firebaseUser.setUserActive(false);
    }
  }

  @override
  void dispose() {
    _monitorUpdates?.cancel();
    unawaited(ForegroundMonitor.disconnectVerificationUi());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    final monitor = context.watch<MonitorService>();
    final hasSearch = monitor.dateOfJourney.isNotEmpty;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || AppUpdateService.instance.required) return;
      NotificationService().openPendingBooking();
      monitor.resumePendingTurnstile();
    });

    return MaterialApp(
      title: 'Rail Pro',
      navigatorKey: NotificationService.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: themeService.themeMode,
      builder: (context, child) => AppUpdateGate(
        child: TurnstileHost(
          child: SessionRecoveryHost(
            child: BookingActivityOverlay(child: child!),
          ),
        ),
      ),
      home: widget.startLoggedIn
          ? AppShell(
              initialTab: hasSearch ? AppShell.tabMonitor : AppShell.tabSearch,
            )
          : const WebviewLoginScreen(),
    );
  }
}
