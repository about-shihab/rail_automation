import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rail_automation/services/credit_service.dart';
import 'package:rail_automation/services/firebase_user_service.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/notification_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/theme_service.dart';
import 'package:rail_automation/services/trip_history_service.dart';
import 'package:rail_automation/views/app_shell.dart';
import 'package:rail_automation/views/monitor_dashboard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MonitorService monitor;

  setUp(() {
    SharedPreferences.setMockInitialValues({'app_language_code': 'en'});
    FlutterSecureStorage.setMockInitialValues({});
    monitor = MonitorService(proService: ProService());
    AppShell.tab.value = AppShell.tabSearch;
  });

  tearDown(() {
    monitor.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: monitor),
          ChangeNotifierProvider.value(value: LanguageService()),
          ChangeNotifierProvider.value(value: ThemeService()),
          ChangeNotifierProvider.value(value: CreditService()),
          ChangeNotifierProvider.value(value: TripHistoryService()),
          ChangeNotifierProvider.value(value: FirebaseUserService()),
        ],
        child: MaterialApp(
          navigatorKey: NotificationService.navigatorKey,
          home: const AppShell(initialTab: AppShell.tabSearch),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'clicking via notification opens monitor screen',
    (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await pumpApp(tester);
      expect(AppShell.tab.value, AppShell.tabSearch);

      const viaPayload =
          'rail://via-ticket?from=Dhaka&to=Chattogram&date=24-Oct-2026&train=SUBORNO&via=Feni&class=SNIGDHA';
      NotificationService().openBooking(viaPayload);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(AppShell.tab.value, AppShell.tabMonitor);
      expect(find.byType(MonitorDashboardScreen), findsOneWidget);
    },
  );

  testWidgets(
    'clicking via notification action or shortcut opens monitor screen',
    (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await pumpApp(tester);
      expect(AppShell.tab.value, AppShell.tabSearch);

      NotificationService().openBooking('rail://via-ticket');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(AppShell.tab.value, AppShell.tabMonitor);
      expect(find.byType(MonitorDashboardScreen), findsOneWidget);
    },
  );

  testWidgets(
    'rail://monitor payload opens monitor screen directly',
    (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await pumpApp(tester);
      expect(AppShell.tab.value, AppShell.tabSearch);

      NotificationService().openBooking('rail://monitor');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(AppShell.tab.value, AppShell.tabMonitor);
      expect(find.byType(MonitorDashboardScreen), findsOneWidget);
    },
  );
}

