import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/auth_session.dart';
import 'services/monitor_service.dart';
import 'services/notification_service.dart';
import 'services/pro_service.dart';
import 'services/theme_service.dart';
import 'services/language_service.dart';
import 'services/background_monitor.dart';
import 'services/firebase_user_service.dart';
import 'views/monitor_dashboard_screen.dart';
import 'utils/app_theme.dart';
import 'views/search_screen.dart';
import 'views/webview_login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notifications
  final notificationService = NotificationService();
  await notificationService.initialize();
  await notificationService.requestPermissions();

  final session = await AuthSession.load();
  final isLoggedIn = session != null && session.isValid;

  final proService = ProService();
  final themeService = ThemeService();
  final languageService = LanguageService();
  final monitor = MonitorService(proService: proService);

  // Initialize Firebase User Service and sync active user
  final firebaseUserService = FirebaseUserService();
  await firebaseUserService.initialize(proService: proService);
  if (isLoggedIn) {
    unawaited(firebaseUserService.syncUserOnLogin(session));
  }

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
        ChangeNotifierProvider.value(value: proService),
        ChangeNotifierProvider.value(value: themeService),
        ChangeNotifierProvider.value(value: languageService),
        ChangeNotifierProvider.value(value: monitor),
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final monitor = context.read<MonitorService>();
    final firebaseUser = context.read<FirebaseUserService>();
    if (state == AppLifecycleState.resumed) {
      monitor.restore();
      firebaseUser.setUserActive(true);
    } else if (state == AppLifecycleState.paused) {
      monitor.suspendForegroundTimers();
      firebaseUser.setUserActive(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    final hasSearch = context.select<MonitorService, bool>(
      (monitor) => monitor.dateOfJourney.isNotEmpty,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().openPendingBooking();
    });

    return MaterialApp(
      title: 'টিকেট আছে',
      navigatorKey: NotificationService.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: themeService.themeMode,
      home: hasSearch
          ? const MonitorDashboardScreen()
          : widget.startLoggedIn
          ? const SearchScreen()
          : const WebviewLoginScreen(),
    );
  }
}
