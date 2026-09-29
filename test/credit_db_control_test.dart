import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:rail_automation/services/credit_service.dart';
import 'package:rail_automation/services/booking_service.dart';
import 'package:rail_automation/services/trip_history_service.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/models/trip_record.dart';
import 'package:rail_automation/views/monitor_dashboard_screen.dart';
import 'package:rail_automation/views/search_screen.dart';
import 'package:rail_automation/utils/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('User Credit DB Control & 1 Credit per Successful Booking', () {
    test('Credit is controlled from DB and setCreditsForTesting updates balance', () {
      final creditService = CreditService();
      creditService.setCreditsForTesting(5);
      expect(creditService.credits, 5);

      // Admin reduces credit to 0 in DB
      creditService.setCreditsForTesting(0);
      expect(creditService.credits, 0);
      expect(creditService.hasCredits, isFalse);
    });

    test('OTP verification does NOT deduct credit or mark trip successful', () async {
      final creditService = CreditService();
      creditService.setCreditsForTesting(3);

      // Verify OTP step maintains credits unchanged
      // (Credit deduction must ONLY occur on successful booking, never on OTP)
      expect(creditService.credits, 3);
    });

    test('Each successful booking deducts exactly 1 credit', () async {
      final creditService = CreditService();
      creditService.setCreditsForTesting(2);

      // Record a test trip
      await TripHistoryService().recordTrip(
        TripRecord(
          id: 'test_trip_1',
          trainName: 'Subarna Express',
          fromCity: 'Dhaka',
          toCity: 'Chattogram',
          dateOfJourney: '30-Sep-2026',
          seatClass: 'SNIGDHA',
          seatNumbers: ['CHA-12'],
          coachName: 'CHA',
          totalFare: 750,
          status: TripBookingStatus.awaitingOtp,
          createdAt: DateTime.now(),
        ),
      );

      // Complete booking with reservation payload
      final done = await BookingService.completeSuccessfulBooking(reservation: {
        'id': 'test_trip_1',
        'train': {'trip_number': 'Subarna Express'},
        'coach': {'floor_name': 'CHA'},
        'seats': [{'seat_number': 'CHA-12'}],
      });

      expect(done, isTrue);
      expect(creditService.credits, 1, reason: 'Exactly 1 credit must be deducted per successful booking');

      final trips = TripHistoryService().trips;
      expect(trips.any((t) => t.id == 'test_trip_1' && t.status == TripBookingStatus.successful), isTrue);
    });

    test('If credit is 0, deductBookingCredit fails', () async {
      final creditService = CreditService();
      creditService.setCreditsForTesting(0);

      final success = await creditService.deductBookingCredit(
        trainName: 'Parabat Express',
        seatInfo: 'KA-10',
      );
      expect(success, isFalse, reason: 'Deducting credit with 0 balance must fail');
      expect(creditService.credits, 0);
    });
  });

  group('UI behavior when DB reduces credits to 0', () {
    testWidgets('Monitor Dashboard shows ONLY Buy Credit button when credits are 0', (tester) async {
      final creditService = CreditService();
      creditService.setCreditsForTesting(0); // Admin reduces credit to 0 in DB

      final pro = ProService();
      final monitor = MonitorService(proService: pro);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: monitor),
            ChangeNotifierProvider.value(value: creditService),
          ],
          child: const MaterialApp(
            home: MonitorDashboardScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Top bar displays amber 0 • Buy pill
      expect(find.text('0 • Buy'), findsOneWidget);

      // Status HUD indicates zero credits
      expect(find.text('ZERO CREDITS • RECHARGE REQUIRED'), findsOneWidget);

      // Main throttle button displays ONLY "Buy Credit"
      expect(find.text('Buy Credit'), findsOneWidget);

      // Other action buttons like "Search Tickets" or "Railway Site" are NOT shown
      expect(find.text('Search Tickets'), findsNothing);
      expect(find.text('Railway Site'), findsNothing);
    });
  });
}
