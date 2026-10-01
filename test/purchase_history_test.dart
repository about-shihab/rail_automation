import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rail_automation/models/purchased_ticket.dart';
import 'package:rail_automation/services/credit_service.dart';
import 'package:rail_automation/services/firebase_user_service.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/theme_service.dart';
import 'package:rail_automation/utils/app_theme.dart';
import 'package:rail_automation/views/trips_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PurchasedTicket Model Tests', () {
    test('Correctly parses Shohoz purchase-history API response payload', () {
      final json = {
        'order_id': 1380682290,
        'journey_date': '08 Oct 2026, 15:00',
        'booking_date': '28 Sep 2026, 13:05',
        'trip_number': 'MAHANAGAR GODHULI (703) [F_SEAT]',
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
      };

      final ticket = PurchasedTicket.fromJson(json);

      expect(ticket.orderId, 1380682290);
      expect(ticket.journeyDate, '08 Oct 2026, 15:00');
      expect(ticket.bookingDate, '28 Sep 2026, 13:05');
      expect(ticket.tripNumber, 'MAHANAGAR GODHULI (703) [F_SEAT]');
      expect(ticket.trainName, 'MAHANAGAR GODHULI (703)');
      expect(ticket.seatClass, 'F_SEAT');
      expect(ticket.pnr, '6ABA11BBCF03D');
      expect(ticket.orderStatus, 1);
      expect(ticket.isConfirmed, isTrue);
      expect(ticket.tripId, 8611622);
      expect(ticket.originCityId, 47);
      expect(ticket.userId, 1287535);
      expect(ticket.isApplicableRefund, isTrue);
      expect(ticket.isRefunded, isFalse);
    });

    test('Correctly parses refunded status and fallback strings', () {
      final json = {
        'order_id': '1380682291',
        'journey_date': '10 Oct 2026, 07:00',
        'booking_date': '01 Oct 2026, 09:00',
        'trip_number': 'SUBARNA EXPRESS (701)',
        'pnr': 'ABC1234567890',
        'order_status': 2,
        'trip_id': '8611623',
        'origin_city_id': '1',
        'user_id': '1287535',
        'refund_validity_info': {
          'is_applicable': false,
          'is_in_progress': false,
          'is_printed': true,
          'is_refunded': true,
        },
      };

      final ticket = PurchasedTicket.fromJson(json);

      expect(ticket.orderId, 1380682291);
      expect(ticket.trainName, 'SUBARNA EXPRESS (701)');
      expect(ticket.seatClass, '');
      expect(ticket.isConfirmed, isFalse);
      expect(ticket.isRefunded, isTrue);
      expect(ticket.isPrinted, isTrue);
    });
  });

  group('TripsScreen UI Tests', () {
    testWidgets('Renders TripsScreen with Official Tickets and Auto-Book Logs tabs',
        (WidgetTester tester) async {
      final monitor = MonitorService(proService: ProService());

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MonitorService>.value(value: monitor),
            ChangeNotifierProvider<CreditService>.value(value: CreditService()),
            ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
            ChangeNotifierProvider<LanguageService>.value(value: LanguageService()),
            ChangeNotifierProvider<FirebaseUserService>.value(value: FirebaseUserService()),
          ],
          child: MaterialApp(
            theme: AppThemes.lightTheme,
            home: const TripsScreen(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Trips & Tickets'), findsOneWidget);
      expect(find.text('Official Tickets'), findsOneWidget);
      expect(find.text('Auto-Book Logs'), findsOneWidget);

      // Switch to Auto-Book Logs tab
      await tester.tap(find.text('Auto-Book Logs'));
      await tester.pumpAndSettle();

      expect(find.textContaining('All ('), findsOneWidget);
      expect(find.textContaining('Successful ('), findsOneWidget);
      expect(find.textContaining('Failed ('), findsOneWidget);
    });
  });
}
