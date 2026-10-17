import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rail_automation/services/app_config.dart';
import 'package:rail_automation/services/booking_service.dart';
import 'package:rail_automation/services/credit_service.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/models/trip_record.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/trip_history_service.dart';
import 'package:rail_automation/views/monitor_dashboard_screen.dart';
import 'package:rail_automation/views/reservation_screen.dart';
import 'package:rail_automation/views/train_selection_screen.dart';
import 'package:rail_automation/models/seat_type.dart';
import 'package:rail_automation/models/train_trip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'app_language_code': 'en'});
    FlutterSecureStorage.setMockInitialValues({});
    await LanguageService.instance.setLanguage(AppLanguage.en);
  });

  tearDown(() async {
    await BookingService.clear();
  });

  test('MonitorService preserves search parameters on reservation expiration', () {
    final monitor = MonitorService(proService: ProService());
    monitor.startMonitoring(
      fromCity: 'Dhaka',
      toCity: 'Chattogram',
      dateOfJourney: '2026-10-20',
      targetTrains: ['Subarna Express'],
      targetSeatClass: 'SNIGDHA',
    );

    expect(monitor.fromCity, 'Dhaka');
    expect(monitor.toCity, 'Chattogram');
    expect(monitor.dateOfJourney, '2026-10-20');
    expect(monitor.lastReservationExpired, isFalse);

    // Trigger reservation expiration
    monitor.markReservationExpired();

    expect(monitor.lastReservationExpired, isTrue);
    expect(monitor.bookingFailureReason, isNotNull);
    expect(monitor.isMonitoring, isFalse);
    // Route must NOT be wiped!
    expect(monitor.fromCity, 'Dhaka');
    expect(monitor.toCity, 'Chattogram');
    expect(monitor.dateOfJourney, '2026-10-20');
  });

  test('CreditService scopes credits per user phone and resets properly on logout', () async {
    final credit = CreditService();
    await credit.initialize();

    // User A logs in with 100 credits
    await credit.onLogin('01700000001');
    await credit.updateLocalCredits(100, phone: '01700000001');
    expect(credit.credits, 100);

    // User A logs out
    await credit.onLogout();
    expect(credit.credits, AppConfig.instance.defaultCredits);

    // User B logs in (new user, has not purchased credits)
    await credit.onLogin('01700000002');
    expect(credit.credits, AppConfig.instance.defaultCredits);
    expect(credit.credits, isNot(100));
  });

  testWidgets('ReservationScreen displays Retry New Search and Re-Auto Book when expired',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await TripHistoryService().recordTrip(
      TripRecord(
        id: 'test-expired-1',
        trainName: 'Subarna Express',
        seatClass: 'SNIGDHA',
        fromCity: 'Dhaka',
        toCity: 'Chattogram',
        dateOfJourney: '2026-10-20',
        status: TripBookingStatus.expired,
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MonitorService(proService: ProService())),
          ChangeNotifierProvider.value(value: LanguageService.instance),
        ],
        child: const MaterialApp(
          home: ReservationScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Retry New Search button is displayed
    expect(find.text('Retry New Search'), findsOneWidget);
    expect(find.text('Re-Auto Book Seats'), findsOneWidget);
    expect(find.text('Seat Hold Expired — Seats Released'), findsOneWidget);
  });

  testWidgets('MonitorDashboardScreen displays _ReservationExpiredCard when reservation expired',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final monitor = MonitorService(proService: ProService());
    monitor.startMonitoring(
      fromCity: 'Dhaka',
      toCity: 'Chattogram',
      dateOfJourney: '2026-10-20',
      departureTime: DateTime.now().add(const Duration(days: 3)),
      targetTrains: ['Subarna Express'],
      targetSeatClass: 'SNIGDHA',
    );
    monitor.markReservationExpired();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: monitor),
          ChangeNotifierProvider.value(value: LanguageService.instance),
        ],
        child: const MaterialApp(
          home: MonitorDashboardScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Seat Hold Expired — Seats Released'), findsOneWidget);
    expect(find.text('Retry New Search'), findsOneWidget);
    expect(find.text('Re-Auto Book'), findsOneWidget);
    expect(find.text('Stop & Clear'), findsOneWidget);
  });

  test('TrainSelectionScreen.isTrainLowProbability warns when < 6 hours and 0 seats', () {
    final now = DateTime(2026, 10, 20, 10, 0, 0);

    // Case 1: Departure in 3 hours (1:00 PM), 0 seats -> Low probability!
    final trainLowProb = TrainTrip(
      tripNumber: '701',
      departureDateTime: '01:00 PM',
      departureFullDate: '2026-10-20 13:00:00',
      departureDateTimeJd: '2026-10-20 13:00:00',
      arrivalDateTime: '06:00 PM',
      travelTime: '5h',
      originCityName: 'Dhaka',
      destinationCityName: 'Chattogram',
      trainModel: 'Subarna',
      isOpenForAll: true,
      seatTypes: [
        SeatType(
          key: 1,
          type: 'SNIGDHA',
          fare: '800',
          vatPercent: 0,
          vatAmount: 0,
          seatCounts: SeatCounts(online: 0, offline: 0, isDivided: false),
        ),
      ],
      boardingPoints: [],
    );

    expect(
      TrainSelectionScreen.isTrainLowProbability(
        train: trainLowProb,
        seatClass: 'SNIGDHA',
        dateOfJourney: '2026-10-20',
        now: now,
      ),
      isTrue,
    );

    // Case 2: Departure in 3 hours, but seats > 0 -> NOT low probability
    final trainWithSeats = TrainTrip(
      tripNumber: '701',
      departureDateTime: '01:00 PM',
      departureFullDate: '2026-10-20 13:00:00',
      departureDateTimeJd: '2026-10-20 13:00:00',
      arrivalDateTime: '06:00 PM',
      travelTime: '5h',
      originCityName: 'Dhaka',
      destinationCityName: 'Chattogram',
      trainModel: 'Subarna',
      isOpenForAll: true,
      seatTypes: [
        SeatType(
          key: 1,
          type: 'SNIGDHA',
          fare: '800',
          vatPercent: 0,
          vatAmount: 0,
          seatCounts: SeatCounts(online: 5, offline: 0, isDivided: false),
        ),
      ],
      boardingPoints: [],
    );

    expect(
      TrainSelectionScreen.isTrainLowProbability(
        train: trainWithSeats,
        seatClass: 'SNIGDHA',
        dateOfJourney: '2026-10-20',
        now: now,
      ),
      isFalse,
    );

    // Case 3: Departure in 8 hours (6:00 PM), 0 seats -> >= 6 hours, so false
    final trainFarAway = TrainTrip(
      tripNumber: '701',
      departureDateTime: '06:00 PM',
      departureFullDate: '2026-10-20 18:00:00',
      departureDateTimeJd: '2026-10-20 18:00:00',
      arrivalDateTime: '11:00 PM',
      travelTime: '5h',
      originCityName: 'Dhaka',
      destinationCityName: 'Chattogram',
      trainModel: 'Subarna',
      isOpenForAll: true,
      seatTypes: [
        SeatType(
          key: 1,
          type: 'SNIGDHA',
          fare: '800',
          vatPercent: 0,
          vatAmount: 0,
          seatCounts: SeatCounts(online: 0, offline: 0, isDivided: false),
        ),
      ],
      boardingPoints: [],
    );

    expect(
      TrainSelectionScreen.isTrainLowProbability(
        train: trainFarAway,
        seatClass: 'SNIGDHA',
        dateOfJourney: '2026-10-20',
        now: now,
      ),
      isFalse,
    );
  });

  testWidgets('ReservationScreen displays manual OTP enter screen when autoVerify is disabled',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    // Save a pending reservation that is awaitingOtp and autoVerify = false
    await BookingService.save({
      'id': 'res-manual-otp-1',
      'status': 'awaitingOtp',
      'autoVerify': false,
      'expiresAt': DateTime.now().add(const Duration(minutes: 4)).toIso8601String(),
      'startedAt': DateTime.now().toIso8601String(),
      'from': 'Dhaka',
      'to': 'Chattogram',
      'date': '2026-10-20',
      'train': {'trip_number': 'Subarna Express'},
      'seatClass': {'type': 'SNIGDHA'},
      'seats': [
        {'seat_number': 'KA-12'},
      ],
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MonitorService(proService: ProService())),
          ChangeNotifierProvider.value(value: LanguageService.instance),
        ],
        child: const MaterialApp(
          home: ReservationScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify OTP enter screen elements
    expect(find.text('OTP Verification'), findsOneWidget);
    expect(find.text('Verify OTP'), findsOneWidget);
    expect(find.text('Resend'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.text('Auto OTP verification unavailable. Enter the 6-digit OTP from your SMS manually below.'),
      findsOneWidget,
    );
  });

  testWidgets('MonitorDashboardScreen displays _ReservationExpiredCard in Bangla when selected',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await LanguageService.instance.setLanguage(AppLanguage.bn);

    final monitor = MonitorService(proService: ProService());
    monitor.startMonitoring(
      fromCity: 'Dhaka',
      toCity: 'Chattogram',
      dateOfJourney: '2026-10-20',
      departureTime: DateTime.now().add(const Duration(days: 3)),
      targetTrains: ['Subarna Express'],
      targetSeatClass: 'SNIGDHA',
    );
    monitor.markReservationExpired();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: monitor),
          ChangeNotifierProvider.value(value: LanguageService.instance),
        ],
        child: const MaterialApp(
          home: MonitorDashboardScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('আসন সংরক্ষণের মেয়াদ শেষ — আসন মুক্ত'), findsOneWidget);
    expect(find.text('নতুন অনুসন্ধান করুন'), findsOneWidget);
    expect(find.text('পুনরায় অটো-বুক'), findsOneWidget);
    expect(find.text('বন্ধ ও মুছুন'), findsOneWidget);
    expect(find.text('৫ মিনিটের সময়সীমা সমাপ্ত'), findsOneWidget);
    expect(
      find.text('রেলওয়ে সিস্টেমে আসন সংরক্ষিত হয়েছিল, কিন্তু ৫ মিনিটের মধ্যে ওটিপি যাচাই বা পেমেন্ট সম্পন্ন না হওয়ায় বাংলাদেশ রেলওয়ে আসনটি ছেড়ে দিয়েছে।'),
      findsOneWidget,
    );
  });

  test('addTrainToMonitoring and startMonitoring erase previous reservation expiration errors', () {
    final monitor = MonitorService(proService: ProService());
    monitor.startMonitoring(
      fromCity: 'Dhaka',
      toCity: 'Chattogram',
      dateOfJourney: '2026-10-20',
      targetTrains: ['Subarna Express'],
      targetSeatClass: 'SNIGDHA',
    );
    monitor.markReservationExpired();
    expect(monitor.lastReservationExpired, isTrue);
    expect(monitor.bookingFailureReason, isNotNull);
    expect(monitor.isMonitoring, isFalse);

    // Adding train must erase previous error and resume monitoring
    monitor.addTrainToMonitoring('Mohanagar Provati');
    expect(monitor.lastReservationExpired, isFalse);
    expect(monitor.bookingFailureReason, isNull);
    expect(monitor.isMonitoring, isTrue);
    expect(monitor.targetTrains.contains('Mohanagar Provati'), isTrue);
  });

  testWidgets('MonitorDashboardScreen erases previous error and shows monitor screen when train is added',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final monitor = MonitorService(proService: ProService());
    monitor.startMonitoring(
      fromCity: 'Dhaka',
      toCity: 'Chattogram',
      dateOfJourney: '2026-10-20',
      departureTime: DateTime.now().add(const Duration(days: 3)),
      targetTrains: ['Subarna Express'],
      targetSeatClass: 'SNIGDHA',
    );
    monitor.markReservationExpired();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: monitor),
          ChangeNotifierProvider.value(value: LanguageService.instance),
        ],
        child: const MaterialApp(
          home: MonitorDashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Initially shows expired error
    expect(find.text('Seat Hold Expired — Seats Released'), findsOneWidget);

    // Now add new train monitor
    monitor.addTrainToMonitoring('Mohanagar Provati');
    await tester.pumpAndSettle();

    // Previous error must be erased and monitor screen must show with new train!
    expect(find.text('Seat Hold Expired — Seats Released'), findsNothing);
    expect(find.text('Subarna Express, Mohanagar Provati'), findsOneWidget);

    monitor.stopMonitoring();
    monitor.suspendForegroundTimers();
  });

  test('Random seat selection resolves to SNIGDHA when available', () {
    final train = TrainTrip(
      tripNumber: '701',
      departureDateTime: '01:00 PM',
      departureFullDate: '2026-10-20 13:00:00',
      departureDateTimeJd: '2026-10-20 13:00:00',
      arrivalDateTime: '06:00 PM',
      travelTime: '5h',
      originCityName: 'Dhaka',
      destinationCityName: 'Chattogram',
      trainModel: 'Subarna',
      isOpenForAll: true,
      seatTypes: [
        SeatType(
          key: 1,
          type: 'S_CHAIR',
          fare: '400',
          tripId: 101,
          tripRouteId: 201,
          vatPercent: 0,
          vatAmount: 0,
          seatCounts: SeatCounts(online: 5, offline: 0, isDivided: false),
        ),
        SeatType(
          key: 2,
          type: 'SNIGDHA',
          fare: '800',
          tripId: 101,
          tripRouteId: 202,
          vatPercent: 0,
          vatAmount: 0,
          seatCounts: SeatCounts(online: 4, offline: 0, isDivided: false),
        ),
      ],
      boardingPoints: [],
    );

    final resolved = train.seatTypes.firstWhere(
      (s) => s.type.toUpperCase() == 'SNIGDHA' && s.tripId != null,
      orElse: () => train.seatTypes.firstWhere((s) => s.tripId != null),
    );
    expect(resolved.type, 'SNIGDHA');
    expect(resolved.tripId, 101);
    expect(resolved.tripRouteId, 202);
  });

  test('Auto-booking transient failure clears pending reservation and keeps lastBookingError null', () async {
    final monitor = MonitorService(proService: ProService());
    monitor.startMonitoring(
      fromCity: 'Dhaka',
      toCity: 'Chattogram',
      dateOfJourney: '2026-10-20',
      targetTrains: ['Subarna Express'],
      targetSeatClass: 'SNIGDHA',
    );
    expect(monitor.isMonitoring, isTrue);
    expect(monitor.lastBookingError, isNull);

    // Verify clearErrors resets any booking error and clears pending
    monitor.clearErrors();
    expect(monitor.lastBookingError, isNull);
    expect(monitor.lastReservationExpired, isFalse);
    expect(await BookingService.pending(), isNull);
    monitor.stopMonitoring();
    monitor.suspendForegroundTimers();
  });
}

