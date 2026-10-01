import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:rail_automation/services/credit_service.dart';
import 'package:rail_automation/services/booking_service.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/views/reservation_screen.dart';
import 'package:rail_automation/views/monitor_dashboard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Reservation Flow & Zero-Credit Payment Verification', () {
    testWidgets('ReservationScreen does not show Mark as Paid and allows Pay Now', (tester) async {
      final creditService = CreditService();
      creditService.setCreditsForTesting(0); // 0 credits!

      final reservation = {
        'id': 'res_123',
        'status': 'readyForPayment',
        'train': {'trip_number': 'TURNA (741)', 'train_name': 'Turna Express'},
        'coach': {'floor_name': 'GA-LO-18'},
        'coach_names': 'GA-LO-18',
        'seats': [{'seat_number': '18'}],
        'seatClass': {'type': 'AC_B'},
        'from': 'Chattogram',
        'to': 'Dhaka',
        'date': '01-Oct-2026',
        'startedAt': DateTime.now().toIso8601String(),
        'expiresAt': DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
        'credit_deducted': true,
      };
      await BookingService.save(reservation);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: creditService),
              ChangeNotifierProvider.value(value: MonitorService(proService: ProService())),
            ],
            child: const ReservationScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Mark as Paid'), findsNothing);
      expect(find.textContaining('Mark as Paid & Confirmed'), findsNothing);

      expect(find.text('Pay Now'), findsOneWidget);
      expect(find.text('Clear record'), findsOneWidget);
    });

    testWidgets('Monitor Dashboard shows Pay Now when reservation is ready even with 0 credits', (tester) async {
      final creditService = CreditService();
      creditService.setCreditsForTesting(0); // 0 credits!
      final monitorService = MonitorService(proService: ProService());

      final reservation = {
        'id': 'res_123',
        'status': 'readyForPayment',
        'train': {'trip_number': 'TURNA (741)'},
        'coach': {'floor_name': 'GA-LO-18'},
        'coach_names': 'GA-LO-18',
        'seats': [{'seat_number': '18'}],
        'seatClass': {'type': 'AC_B'},
        'from': 'Chattogram',
        'to': 'Dhaka',
        'date': '01-Oct-2026',
        'startedAt': DateTime.now().toIso8601String(),
        'expiresAt': DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
        'credit_deducted': true,
      };
      await BookingService.save(reservation);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: creditService),
              ChangeNotifierProvider.value(value: monitorService),
            ],
            child: const MonitorDashboardScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Pay Now'), findsOneWidget);
      expect(find.text('SEATS RESERVED • READY TO PAY'), findsOneWidget);
    });

    test('After 5 minutes from startedAt, BookingService.pending() auto-clears', () async {
      final reservation = {
        'id': 'res_old',
        'status': 'readyForPayment',
        'train': {'trip_number': 'TURNA (741)'},
        'coach': {'floor_name': 'GA-LO-18'},
        'seats': [{'seat_number': '18'}],
        'from': 'Chattogram',
        'to': 'Dhaka',
        'date': '01-Oct-2026',
        'startedAt': DateTime.now().subtract(const Duration(minutes: 6)).toIso8601String(),
        'expiresAt': DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(),
        'credit_deducted': true,
      };
      await BookingService.save(reservation);

      final result = await BookingService.pending();
      expect(result, isNull, reason: 'Reservation older than 5 minutes must auto-clear');
    });

    test('BookingService.pending() deducts 1 credit if OTP was sent but credit_deducted was missing', () async {
      final creditService = CreditService();
      creditService.setCreditsForTesting(2);

      final reservation = {
        'id': 'res_undeducted',
        'status': 'awaitingOtp',
        'train': {'trip_number': 'TURNA (741)'},
        'coach': {'floor_name': 'GA-LO-18'},
        'coach_names': 'GA-LO-18',
        'seats': [{'seat_number': '18'}],
        'from': 'Chattogram',
        'to': 'Dhaka',
        'date': '01-Oct-2026',
        'startedAt': DateTime.now().toIso8601String(),
        'expiresAt': DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      };
      await BookingService.save(reservation);

      final pending = await BookingService.pending();
      expect(pending, isNotNull);
      expect(pending!['credit_deducted'], isTrue);
      expect(creditService.credits, 1, reason: '1 credit must be deducted when OTP was sent');
    });
  });
}
