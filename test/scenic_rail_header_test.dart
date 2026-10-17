import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/utils/app_theme.dart';
import 'package:rail_automation/widgets/scenic_rail_header.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'app_language_code': 'en'});
    await LanguageService.instance.setLanguage(AppLanguage.en);
  });

  testWidgets('ScenicRailHeader renders in light mode without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemes.lightTheme,
        home: const Scaffold(
          body: SizedBox(
            height: 120,
            width: 380,
            child: ScenicRailHeader(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(ScenicRailHeader), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ScenicRailHeader renders in dark mode and handles interactive tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemes.darkTheme,
        home: const Scaffold(
          body: SizedBox(
            height: 100,
            width: 380,
            child: ScenicRailHeader(
              interactive: true,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(ScenicRailHeader), findsOneWidget);

    // Tap on the header to trigger the train toot badge
    await tester.tap(find.byType(ScenicRailHeader));
    await tester.pump(const Duration(milliseconds: 100));

    // Verify the toot badge appeared
    expect(find.textContaining('Express'), findsOneWidget);

    // Let the toot animation settle
    await tester.pump(const Duration(milliseconds: 1500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ScenicRailHeader renders compact mode with child overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 64,
            width: 360,
            child: ScenicRailHeader(
              compact: true,
              child: Center(child: Text('Overlay Title')),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Overlay Title'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
