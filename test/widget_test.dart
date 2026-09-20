import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rail_automation/views/search_screen.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/theme_service.dart';

void main() {
  testWidgets('App renders SearchScreen with টিকেট আছে header',
      (WidgetTester tester) async {
    final proService = ProService();
    final themeService = ThemeService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: proService),
          ChangeNotifierProvider.value(value: themeService),
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
    expect(find.text('টিকেট আছে কিনা দেখুন'), findsOneWidget);
    expect(find.text('কোথায় যাবেন (To Station)'), findsOneWidget);
    expect(find.text('আসন শ্রেণি (Seat Class)'), findsOneWidget);
  });
}
