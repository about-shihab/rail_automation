import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:rail_automation/views/app_shell.dart';
import 'package:rail_automation/services/credit_service.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/theme_service.dart';
import 'package:rail_automation/services/trip_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('Profile tab displays Developer Info, email, and Disclaimer', (tester) async {
    final credit = CreditService();
    final theme = ThemeService();
    final lang = LanguageService();
    final pro = ProService();
    final monitor = MonitorService(proService: pro);

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: credit),
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: lang),
          ChangeNotifierProvider.value(value: monitor),
          ChangeNotifierProvider.value(value: TripHistoryService()),
        ],
        child: const MaterialApp(
          home: ProfileTab(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Developer Information is present and collapsed initially
    expect(find.text('Developer Information'), findsOneWidget);
    expect(find.text('Lead Developer & Creator'), findsNothing);

    // Tap to expand
    await tester.tap(find.text('Developer Information'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify expanded details
    expect(find.text('Lead Developer & Creator'), findsOneWidget);
    expect(find.text('connect.abdulla@gmail.com'), findsOneWidget);

    // Verify Disclaimer
    expect(find.text('Disclaimer'), findsOneWidget);
    expect(find.textContaining('Rail Pro is an independent automation'), findsOneWidget);
    expect(find.textContaining('Bangladesh Railway (BR)'), findsOneWidget);

    // Verify Footer
    expect(find.textContaining('Developed by Abdulla Al Mamun'), findsOneWidget);
  });
}
