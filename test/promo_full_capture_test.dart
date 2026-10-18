import 'dart:convert';
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
import 'package:rail_automation/models/purchased_ticket.dart';
import 'package:rail_automation/models/trip_record.dart';
import 'package:rail_automation/services/api_service.dart';
import 'package:rail_automation/services/booking_service.dart';
import 'package:rail_automation/services/credit_service.dart';
import 'package:rail_automation/services/firebase_user_service.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/theme_service.dart';
import 'package:rail_automation/services/trip_history_service.dart';
import 'package:rail_automation/utils/app_theme.dart';
import 'package:rail_automation/views/app_shell.dart';
import 'package:rail_automation/views/monitor_dashboard_screen.dart';
import 'package:rail_automation/views/reservation_screen.dart';
import 'package:rail_automation/views/train_selection_screen.dart';
import 'package:rail_automation/views/trips_screen.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'app_language_code': 'bn',
      'rps_last_from_station': 'Dhaka',
      'rps_last_to_station': 'Chattogram',
      MonitorService.preferenceKey: jsonEncode({
        'id': 'promo-live-monitor',
        'from': 'Dhaka',
        'to': 'Cox’s Bazar',
        'date': '24-Oct-2026',
        'train': 'COXS BAZAR EXPRESS (814)',
        'seat': 'SNIGDHA',
        'active': true,
        'expires': DateTime.now().add(const Duration(hours: 3)).toIso8601String(),
        'bookingIntent': {'autoReserve': true, 'quantity': 2},
      }),
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
    CreditService().setCreditsForTesting(5);
  });

  testWidgets('capture all app features with mock data for promo video', (
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
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
        '/usr/share/fonts/truetype/freefont/FreeSans.ttf',
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
    await monitor.restore(startTimers: false);

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

    // 1. Capture Search Screen
    await capture('promo-search-bn');

    // 2. Capture Station dropdown
    if (find.byType(TextField).evaluate().isNotEmpty) {
      await tester.enterText(find.byType(TextField).first, 'Dha');
      await tester.pumpAndSettle();
    }
    await capture('promo-stations-bn');

    final context = key.currentContext!;
    final appShells = find.byType(AppShell).evaluate();
    if (appShells.isNotEmpty) {
      final navigator = Navigator.of(appShells.first);

      // 3. Capture Train Selection Screen
      final mockResponse = ApiService.getMockResponse();
      navigator.push(
        MaterialPageRoute(
          builder: (_) => TrainSelectionScreen(
            searchResponse: mockResponse,
            fromCity: 'Dhaka',
            toCity: 'Chattogram',
            dateOfJourney: '24-Oct-2026',
            initialClass: 'SNIGDHA',
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.takeException();
      await capture('promo-trains-bn');
      navigator.pop();
      await tester.pumpAndSettle();
      tester.takeException();

      // 4. Capture Live Monitoring Dashboard Screen
      navigator.push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: const Text('আসন মনিটরিং ড্যাশবোর্ড'),
              backgroundColor: const Color(0xFF0C493B),
            ),
            body: const MonitorDashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.takeException();
      await capture('promo-monitoring-bn');
      navigator.pop();
      await tester.pumpAndSettle();
      tester.takeException();

      // 5. Capture Reservation / Hold & Payment Screen
      await BookingService.save({
        'id': 'promo-demo-reservation',
        'status': 'readyForPayment',
        'train': {'trip_number': 'SONAR BANGLA EXPRESS (788)'},
        'coach': {'floor_name': 'KA'},
        'coach_names': 'KA',
        'seatClass': {'type': 'SNIGDHA'},
        'seats': [
          {'seat_number': '12', 'fare': 820},
          {'seat_number': '13', 'fare': 820},
        ],
        'from': 'Dhaka',
        'to': 'Chattogram',
        'date': '24-Oct-2026',
        'startedAt': DateTime.now().toIso8601String(),
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 4, seconds: 58))
            .toIso8601String(),
        'credit_deducted': true,
      });

      navigator.push(
        MaterialPageRoute(builder: (_) => const ReservationScreen()),
      );
      await tester.pumpAndSettle();
      await capture('promo-payment-bn');
      navigator.pop();
      await tester.pumpAndSettle();
    }

    // 6. Capture Trips / Confirmed Tickets Screen
    // Construct a beautiful mock ticket view
    final mockPurchasedTicket = PurchasedTicket.fromJson({
      'order_id': 1380682290,
      'journey_date': '24 Oct 2026, 07:00 AM',
      'booking_date': '18 Oct 2026, 11:30 AM',
      'trip_number': 'SONAR BANGLA EXPRESS (788) [SNIGDHA]',
      'pnr': '6ABA11BBCF03D',
      'order_status': 1,
      'print_date': null,
      'trip_id': 8611622,
      'origin_city_id': 47,
      'user_id': 1287535,
      'refund_validity_info': {
        'is_applicable': true,
        'is_in_progress': false,
        'is_printed': false,
        'is_refunded': false,
      },
    });

    final tripsKey = GlobalKey();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: monitor),
          ChangeNotifierProvider.value(value: LanguageService()),
          ChangeNotifierProvider.value(value: ThemeService()),
          ChangeNotifierProvider.value(value: CreditService()),
          ChangeNotifierProvider.value(value: TripHistoryService()),
        ],
        child: MaterialApp(
          theme: AppThemes.lightTheme,
          home: RepaintBoundary(
            key: tripsKey,
            child: Scaffold(
              backgroundColor: const Color(0xFFF8FAFC),
              appBar: AppBar(
                title: const Text('ট্রিপস ও ডিজিটাল টিকেট', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                backgroundColor: const Color(0xFF0C493B),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                    onPressed: () {},
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F766E), Color(0xFF047857)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF047857).withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'টিকেট সফলভাবে নিশ্চিত হয়েছে',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'অফিসিয়াল বাংলাদেশ রেলওয়ে পিএনআর নম্বর',
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(17)),
                            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00B48B).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.train_rounded, color: Color(0xFF00B48B), size: 22),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'SONAR BANGLA EXPRESS (788)',
                                      style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    Text(
                                      'শ্রেণি: স্নিগ্ধা (SNIGDHA) · আসন: ১২, ১৩ (KA)',
                                      style: TextStyle(color: Color(0xFF00B48B), fontWeight: FontWeight.w600, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                ),
                                child: const Text(
                                  'CONFIRMED',
                                  style: TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: const [
                                      Text('যাত্রা শুরুর স্টেশন', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                      SizedBox(height: 2),
                                      Text('ঢাকা (Dhaka)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      Text('০৭:০০ AM', style: TextStyle(color: Color(0xFF00B48B), fontWeight: FontWeight.w600, fontSize: 12)),
                                    ],
                                  ),
                                  const Icon(Icons.arrow_forward_rounded, color: Color(0xFF94A3B8)),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: const [
                                      Text('গন্তব্য স্টেশন', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                      SizedBox(height: 2),
                                      Text('চট্টগ্রাম (Chattogram)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      Text('১২:১০ PM', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: const [
                                      Text('পিএনআর নম্বর (PNR)', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                      SizedBox(height: 2),
                                      Text('6ABA11BBCF03D', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1.2, color: Color(0xFF0F172A))),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: const [
                                      Text('যাত্রার তারিখ', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                      SizedBox(height: 2),
                                      Text('২৪ অক্টোবর ২০২৬', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00B48B),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.download_rounded, size: 18),
                                  label: const Text('অফিসিয়াল টিকেট ডাউনলোড (PDF)', style: TextStyle(fontWeight: FontWeight.bold)),
                                  onPressed: () {},
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      try {
        final boundary =
            tripsKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) return;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) {
          image.dispose();
          return;
        }
        final file = File('build/design-preview/promo-trips-bn.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes.buffer.asUint8List());
        image.dispose();
      } catch (_) {}
    });

    tester.takeException();
    expect(File('build/design-preview/promo-trips-bn.png').existsSync(), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.takeException();
    monitor.dispose();
    pro.dispose();
  });
}
