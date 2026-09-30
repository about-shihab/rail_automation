import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rail_automation/views/search_screen.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/theme_service.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/services/credit_service.dart';

void main() {
  testWidgets('App renders SearchScreen with Rail Pro header',
      (WidgetTester tester) async {
    final proService = ProService();
    final themeService = ThemeService();
    final languageService = LanguageService();
    final creditService = CreditService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: proService),
          ChangeNotifierProvider.value(value: themeService),
          ChangeNotifierProvider.value(value: languageService),
          ChangeNotifierProvider.value(value: creditService),
          ChangeNotifierProvider(
            create: (_) => MonitorService(proService: proService),
          ),
        ],
        child: const MaterialApp(
          home: SearchScreen(),
        ),
      ),
    );

    expect(find.text('Rail Pro'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Class'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
