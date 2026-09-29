import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rail_automation/widgets/train_navigation_bar.dart';

void main() {
  testWidgets('TrainNavigationBar renders tabs, handles taps and slides', (
    tester,
  ) async {
    int selectedTab = 0;

    final destinations = [
      const TrainDestination(label: 'Search'),
      const TrainDestination(label: 'Tickets', showBadge: true),
      const TrainDestination(label: 'Trips'),
      const TrainDestination(label: 'Profile'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              bottomNavigationBar: TrainNavigationBar(
                selectedIndex: selectedTab,
                destinations: destinations,
                onDestinationSelected: (index) {
                  setState(() {
                    selectedTab = index;
                  });
                },
              ),
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify all 4 tab labels are present
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Tickets'), findsOneWidget);
    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    // Tap on 'Trips'
    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();

    expect(selectedTab, 2);

    // Tap on 'Profile'
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(selectedTab, 3);
  });
}
