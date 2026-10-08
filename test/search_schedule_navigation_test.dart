import 'package:intl/intl.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/credit_service.dart';
import 'package:rail_automation/services/firebase_user_service.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/notification_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/theme_service.dart';
import 'package:rail_automation/services/trip_history_service.dart';
import 'package:rail_automation/views/app_shell.dart';
import 'package:rail_automation/widgets/booking_activity_overlay.dart';

void main() {
  late MonitorService monitor;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'app_language_code': 'en',
      'rps_last_from_station': 'Dhaka',
      'rps_last_to_station': 'Chattogram',
    });
    FlutterSecureStorage.setMockInitialValues({});
    await LanguageService.instance.setLanguage(AppLanguage.en);
    await AuthSession.save(
      AuthSession(
        token: 'test-session',
        deviceKey: 'key',
        phoneNumber: '01700000000',
      ),
    );
    CreditService().setCreditsForTesting(5);
    monitor = MonitorService(proService: ProService());
    const channel = MethodChannel('com.example.rail_automation/sms');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);
  });
  tearDown(() {
    monitor.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.example.rail_automation/sms'),
          null,
        );
  });

  Future<void> showApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
          builder: (_, child) => BookingActivityOverlay(child: child!),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets(
    'future journey schedules auto-booking without calling search API',
    (tester) async {
      var requests = 0;
      await http.runWithClient(
        () async {
          await showApp(tester);
          await tester.tap(find.byIcon(Icons.calendar_month_rounded).first);
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(find.byTooltip('Switch to input'));
          await tester.pump(const Duration(milliseconds: 200));
          await tester.enterText(
            find.byType(TextFormField),
            DateFormat('MM/dd/yyyy')
                .format(DateTime.now().add(const Duration(days: 20))),
          );
          await tester.tap(find.text('OK'));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(find.text('Schedule Search'));
          await tester.pump(const Duration(milliseconds: 500));
          expect(
            find.textContaining('when your journey is within 10 days'),
            findsOneWidget,
          );
          await tester.ensureVisible(find.text('Schedule'));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(find.text('Schedule'));
          await tester.pump(const Duration(milliseconds: 500));
          expect(monitor.isMonitoring, isTrue);
          expect(monitor.isScheduled, isTrue);
          expect(monitor.bookingIntent.autoReserve, isTrue);
          expect(AppShell.tab.value, AppShell.tabMonitor);
          expect(find.text('Search scheduled'), findsOneWidget);
          expect(requests, 0);
          monitor.suspendForegroundTimers();
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('search-trips-v2')) requests++;
          return http.Response('{"data":{"trains":[]}}', 200);
        }),
      );
    },
  );
}
