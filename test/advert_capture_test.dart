import 'dart:convert';
import 'package:rail_automation/views/watch_options_dialog.dart';
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
      'app_language_code': 'en',
      'rps_last_from_station': 'Dhaka',
      'rps_last_to_station': 'Chattogram',
    });
    FlutterSecureStorage.setMockInitialValues({});
    await LanguageService.instance.setLanguage(AppLanguage.en);
    await AuthSession.save(
      AuthSession(
        token: 'ad-demo-session',
        deviceId: 'demo-device',
        deviceKey: 'demo-key',
      ),
    );
    CreditService().setCreditsForTesting(2);
  });
  testWidgets('capture native English search and station dropdown for promo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final fontCandidates = [
        'C:/Windows/Fonts/Nirmala.ttf',
        'C:/Windows/Fonts/NirmalaB.ttf',
        'C:/Windows/Fonts/segoeui.ttf',
        'C:/Windows/Fonts/seguisym.ttf',
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
        '/usr/share/fonts/truetype/freefont/FreeSans.ttf',
        '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
        '/System/Library/Fonts/Helvetica.ttc',
        '/Library/Fonts/Arial Unicode.ttf',
      ];
      for (final family in ['Roboto', 'Ahem', 'Hind Siliguri']) {
        final font = FontLoader(family);
        for (final path in fontCandidates) {
          final file = File(path);
          if (await file.exists()) {
            font.addFont(file.readAsBytes().then(ByteData.sublistView));
          }
        }
        try {
          await font.load();
        } catch (_) {}
      }
      try {
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      } catch (_) {}
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
        child: Consumer<ThemeService>(
          builder: (context, themes, _) => MaterialApp(
          themeMode: themes.themeMode,
          darkTheme: AppThemes.darkTheme,
          theme: AppThemes.lightTheme.copyWith(
            appBarTheme: AppThemes.lightTheme.appBarTheme.copyWith(
              titleTextStyle: const TextStyle(
                fontFamily: 'Roboto',
                color: Colors.white,
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(textStyle: const TextStyle(fontFamily: 'Roboto')),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(textStyle: const TextStyle(fontFamily: 'Roboto')),
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
      try {
        final boundary =
            key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) return;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) {
          image.dispose();
          return;
        }
        final file = File('build/design-preview/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes.buffer.asUint8List());
        image.dispose();
      } catch (_) {}
    });
    await capture('ad-search-en');
    await tester.tap(find.byIcon(Icons.calendar_month_rounded));
    await tester.pumpAndSettle();
    await capture('ad-calendar-en');
    await tester.tap(find.text('27').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await capture('ad-date-en');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await capture('ad-class-en');
    await tester.tap(find.text('SNIGDHA').last);
    await tester.pumpAndSettle();
    await capture('ad-preferences-en');
    for (final entry in ['', 'D', 'Dh', 'Dha']) {
      await tester.enterText(find.byType(TextField).first, entry);
      await tester.pumpAndSettle();
      await capture('ad-type-${entry.isEmpty ? 'empty' : entry}');
    }

    if (find.byType(TextField).evaluate().isNotEmpty) {
      await tester.enterText(find.byType(TextField).first, 'Dha');
      await tester.pumpAndSettle();
    }
    await capture('ad-stations-en');
    tester.takeException();

    Navigator.of(find.byType(AppShell).evaluate().first).popUntil((r) => r.isFirst);
    AppShell.tab.value = AppShell.tabMore;
    await tester.pumpAndSettle();
    await capture('ad-profile-en');
    await find.byType(AppShell).evaluate().first.read<ThemeService>().toggleTheme();
    await tester.pumpAndSettle();
    await capture('ad-profile-dark-en');
    await find.byType(AppShell).evaluate().first.read<ThemeService>().toggleTheme();
    await tester.pumpAndSettle();
    showWatchOptions(find.byType(AppShell).evaluate().first,
      trainName: 'SONAR BANGLA EXPRESS (788)', seatClass: 'SNIGDHA');
    await tester.pumpAndSettle();
    await capture('ad-watch-en');
    await tester.tap(find.byTooltip('More seats'));
    await tester.pumpAndSettle();
    await capture('ad-watch-two-en');
    Navigator.of(find.byType(AppShell).evaluate().first).pop();
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(MonitorService.preferenceKey, jsonEncode({
      'id': 'ad-demo-watch', 'from': 'Dhaka', 'to': 'Chattogram',
      'date': '27-Oct-2026', 'train': 'SONAR BANGLA EXPRESS (788)',
      'trains': ['SONAR BANGLA EXPRESS (788)', 'SUBARNA EXPRESS (702)'],
      'seat': 'SNIGDHA', 'active': true,
      'expires': DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
      'bookingIntent': {'autoReserve': true, 'quantity': 2},
    }));
    await monitor.restore(startTimers: false);
    AppShell.tab.value = AppShell.tabMonitor;
    await tester.pumpAndSettle();
    await capture('ad-monitor-en');
    await BookingService.save({
      'id': 'ad-demo-reservation',
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
      'date': '27-Oct-2026',
      'startedAt': DateTime.now().toIso8601String(),
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 4))
          .toIso8601String(),
      'credit_deducted': true,
    });
    final context = key.currentContext!;
    final appShells = find.byType(AppShell).evaluate();
    if (appShells.isNotEmpty) {
      final navigator = Navigator.of(appShells.first);
      navigator.push(
        MaterialPageRoute(builder: (_) => const ReservationScreen()),
      );
      await tester.pumpAndSettle();
      await capture('ad-payment-en');
    }
    expect(context.mounted, isTrue);
    tester.takeException();
    await tester.pumpWidget(const SizedBox.shrink());
    tester.takeException();
    monitor.dispose();
    pro.dispose();
  });
}
