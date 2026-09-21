import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rail_automation/views/search_screen.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/theme_service.dart';
import 'package:rail_automation/services/language_service.dart';

void main() {
  testWidgets('App renders SearchScreen with টিকেট আছে header',
      (WidgetTester tester) async {
    final proService = ProService();
    final themeService = ThemeService();
    final languageService = LanguageService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: proService),
          ChangeNotifierProvider.value(value: themeService),
          ChangeNotifierProvider.value(value: languageService),
          ChangeNotifierProvider(
            create: (_) => MonitorService(proService: proService),
          ),
        ],
        child: const MaterialApp(
          home: SearchScreen(),
        ),
      ),
    );

    expect(find.text('টিকেট আছে'), findsOneWidget);
    expect(find.text(languageService.t('to_station')), findsOneWidget);
    expect(find.text(languageService.t('seat_class')), findsOneWidget);
  });
}
