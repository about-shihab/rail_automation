import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/auth_session.dart';
import 'services/monitor_service.dart';
import 'services/notification_service.dart';
import 'services/pro_service.dart';
import 'services/theme_service.dart';
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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: proService),
        ChangeNotifierProvider.value(value: themeService),
        ChangeNotifierProvider(
          create: (_) => MonitorService(proService: proService),
        ),
      ],
      child: BangladeshRailApp(startLoggedIn: isLoggedIn),
    ),
  );
}

class BangladeshRailApp extends StatelessWidget {
  final bool startLoggedIn;

  const BangladeshRailApp({super.key, this.startLoggedIn = false});

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);

    return MaterialApp(
      title: 'টিকেট আছে',
      debugShowCheckedModeBanner: false,
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: themeService.themeMode,
      home: startLoggedIn ? const SearchScreen() : const WebviewLoginScreen(),
    );
  }
}
