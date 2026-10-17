import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/services/booking_activity.dart';
import 'package:rail_automation/widgets/booking_activity_overlay.dart';
import 'package:rail_automation/widgets/fancy_train_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'nested and overlapping work stays busy until every request finishes',
    () async {
      final activity = BookingActivity();
      final outer = Completer<void>();
      final inner = Completer<void>();
      final first = activity.run(
        BookingActivityStage.reserving,
        () => outer.future,
      );
      final second = activity.run(
        BookingActivityStage.verifying,
        () => inner.future,
      );
      expect(activity.stage, BookingActivityStage.verifying);
      inner.complete();
      await second;
      expect(activity.busy, isTrue);
      expect(activity.stage, BookingActivityStage.reserving);
      outer.complete();
      await first;
      expect(activity.busy, isFalse);
    },
  );

  test(
    'failed requests release loading state and preserve the original error',
    () async {
      final activity = BookingActivity();
      await expectLater(
        activity.run(
          BookingActivityStage.layout,
          () async => throw StateError('server rejected'),
        ),
        throwsStateError,
      );
      expect(activity.busy, isFalse);
    },
  );

  test('worker activity cannot erase an in-progress UI booking', () async {
    final activity = BookingActivity();
    final pending = Completer<void>();
    activity.setWorkerStage(BookingActivityStage.layout);
    final task = activity.run(
      BookingActivityStage.reserving,
      () => pending.future,
    );
    activity.setWorkerStage(null);
    expect(activity.busy, isTrue);
    expect(activity.stage, BookingActivityStage.reserving);
    pending.complete();
    await task;
    expect(activity.busy, isFalse);
  });

  testWidgets(
    'actual request displays train loading and failure removes the barrier',
    (tester) async {
      final activity = BookingActivity();
      await tester.pumpWidget(
        MaterialApp(
          home: BookingActivityOverlay(
            activity: activity,
            child: const Scaffold(body: Text('Booking screen')),
          ),
        ),
      );
      final response = Completer<void>();
      final task = activity.run(
        BookingActivityStage.layout,
        () => response.future,
      );
      final checked = expectLater(task, throwsStateError);
      await tester.pump();
      expect(find.byType(FancyTrainLoader), findsOneWidget);
      expect(find.byKey(const ValueKey('booking-api-barrier')), findsOneWidget);
      response.completeError(StateError('Network failure'));
      await checked;
      await tester.pump();
      expect(find.byType(FancyTrainLoader), findsNothing);
      expect(find.byKey(const ValueKey('booking-api-barrier')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a request started during screen initialization does not rebuild an ancestor mid-build',
    (tester) async {
      final activity = BookingActivity();
      final response = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              BookingActivityOverlay(activity: activity, child: child!),
          home: _StartRequest(activity: activity, response: response.future),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(FancyTrainLoader), findsOneWidget);
      response.complete();
      await tester.pump();
      expect(find.byType(FancyTrainLoader), findsNothing);
    },
  );

  testWidgets(
    'BookingActivityOverlay never blocks with barrier or loader when isReservationActive is true',
    (tester) async {
      final activity = BookingActivity();
      activity.isReservationActive = true;
      final response = Completer<void>();
      unawaited(
        activity.run(BookingActivityStage.reserving, () => response.future),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BookingActivityOverlay(
            activity: activity,
            child: const Scaffold(
              body: Center(child: Text('OTP Enter Screen')),
            ),
          ),
        ),
      );
      await tester.pump();

      // Ensure no blocking barrier or loader covers the screen
      expect(find.byType(FancyTrainLoader), findsNothing);
      expect(find.byKey(const ValueKey('booking-api-barrier')), findsNothing);
      expect(find.text('OTP Enter Screen'), findsOneWidget);

      response.complete();
      await tester.pump();
    },
  );

  testWidgets(
    'BookingActivityOverlay does not block screen for background worker stage alone',
    (tester) async {
      final activity = BookingActivity();
      activity.setWorkerStage(BookingActivityStage.reserving);

      await tester.pumpWidget(
        MaterialApp(
          home: BookingActivityOverlay(
            activity: activity,
            child: const Scaffold(
              body: Center(child: Text('Active Screen')),
            ),
          ),
        ),
      );
      await tester.pump();

      // Background worker stage alone must never lock user UI with a barrier
      expect(find.byType(FancyTrainLoader), findsNothing);
      expect(find.byKey(const ValueKey('booking-api-barrier')), findsNothing);
      expect(find.text('Active Screen'), findsOneWidget);
    },
  );
}

class _StartRequest extends StatefulWidget {
  const _StartRequest({required this.activity, required this.response});
  final BookingActivity activity;
  final Future<void> response;
  @override
  State<_StartRequest> createState() => _StartRequestState();
}

class _StartRequestState extends State<_StartRequest> {
  @override
  void initState() {
    super.initState();
    unawaited(
      widget.activity.run(BookingActivityStage.layout, () => widget.response),
    );
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('Seat layout'));
}
