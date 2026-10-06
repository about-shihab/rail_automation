import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/credit_service.dart';
import 'package:rail_automation/services/firebase_user_service.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/theme_service.dart';
import 'package:rail_automation/services/trip_history_service.dart';
import 'package:rail_automation/utils/app_theme.dart';
import 'package:rail_automation/views/app_shell.dart';
import 'package:rail_automation/views/reservation_screen.dart';
import 'package:rail_automation/services/booking_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'app_language_code': 'bn',
      'rps_last_from_station': 'Dhaka',
      'rps_last_to_station': 'Chattogram',
    });
    FlutterSecureStorage.setMockInitialValues({});
    await LanguageService.instance.setLanguage(AppLanguage.bn);
    await AuthSession.save(
      AuthSession(
        token: 'promo-demo-session',
        deviceId: 'demo-device',
        deviceKey: 'demo-key',
      ),
    );
    CreditService().setCreditsForTesting(2);
  });
  testWidgets('capture native Bangla search and station dropdown for promo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      for (final family in ['Roboto', 'Ahem']) {
        final font = FontLoader(family);
        for (final name in ['Nirmala.ttf', 'NirmalaB.ttf']) {
          final file = File('C:/Windows/Fonts/$name');
          if (await file.exists()) {
            font.addFont(file.readAsBytes().then(ByteData.sublistView));
          }
        }
        await font.load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    final pro = ProService();
    final monitor = MonitorService(proService: pro);
    final key = GlobalKey();
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
          theme: AppThemes.lightTheme.copyWith(
            appBarTheme: AppThemes.lightTheme.appBarTheme.copyWith(
              titleTextStyle: const TextStyle(
                fontFamily: 'Roboto',
                color: Colors.white,
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                textStyle: const TextStyle(fontFamily: 'Roboto'),
              ),
            ),
          ),
          builder: (context, child) => RepaintBoundary(key: key, child: child!),
          home: const AppShell(initialTab: AppShell.tabSearch),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/icons/app_icon.jpg'),
        key.currentContext!,
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) => tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/design-preview/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await capture('promo-search-bn');
    await tester.enterText(find.byType(TextField).first, 'Dha');
    await tester.pumpAndSettle();
    await capture('promo-stations-bn');
    expect(find.text('Dhaka'), findsWidgets);
    expect(tester.takeException(), isNull);
    await BookingService.save({
      'id': 'promo-demo-reservation',
      'status': 'readyForPayment',
      'train': {'trip_number': 'SONAR BANGLA EXPRESS (788)'},
      'coach': {'floor_name': 'KA'},
      'coach_names': 'KA',
      'seatClass': {'type': 'SNIGDHA'},
      'seats': [
        {'seat_number': '12', 'fare': 820},
      ],
      'from': 'Dhaka',
      'to': 'Chattogram',
      'date': '08-Oct-2026',
      'startedAt': DateTime.now().toIso8601String(),
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 4))
          .toIso8601String(),
      'credit_deducted': true,
    });
    final context = key.currentContext!;
    final navigator = Navigator.of(find.byType(AppShell).evaluate().first);
    navigator.push(
      MaterialPageRoute(builder: (_) => const ReservationScreen()),
    );
    await tester.pumpAndSettle();
    await capture('promo-payment-bn');
    expect(context.mounted, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    monitor.dispose();
    pro.dispose();
  });
}
