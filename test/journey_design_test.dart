import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/views/monitor_dashboard_screen.dart';
import 'package:rail_automation/widgets/train_navigation_bar.dart';
import 'package:rail_automation/utils/app_theme.dart';

void main() {
  var fontsLoaded = false;
  for (final dark in [false, true]) {
    testWidgets('journey dashboard fits a narrow screen, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        if (fontsLoaded) return;
        final font = File('C:/Windows/Fonts/segoeui.ttf');
        if (await font.exists()) {
          final loader = FontLoader('Roboto')
            ..addFont(font.readAsBytes().then((b) => ByteData.sublistView(b)));
          await loader.load();
          final fallback = FontLoader('Ahem')
            ..addFont(font.readAsBytes().then((b) => ByteData.sublistView(b)));
          await fallback.load();
        }
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        fontsLoaded = true;
      });
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({
        MonitorService.preferenceKey: jsonEncode({
          'id': 'design',
          'from': 'Dhaka',
          'to': "Cox’s Bazar",
          'date': '30-Sep-2026',
          'train': 'COXS BAZAR EXPRESS (814)',
          'seat': 'SNIGDHA',
          'active': true,
          'expires': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'bookingIntent': {'autoReserve': true, 'quantity': 2},
        }),
      });
      final pro = ProService();
      final monitor = MonitorService(proService: pro);
      await monitor.restore(startTimers: false);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: monitor,
          child: MaterialApp(
            theme: dark ? AppThemes.darkTheme : AppThemes.lightTheme,
            home: RepaintBoundary(
              key: boundaryKey,
              child: Scaffold(
                body: const MonitorDashboardScreen(),
                bottomNavigationBar: TrainNavigationBar(
                  selectedIndex: 1,
                  onDestinationSelected: (_) {},
                  destinations: [
                    const TrainDestination(
                      label: 'Search',
                    ),
                    TrainDestination(
                      label: 'Tickets',
                      showBadge: monitor.isMonitoring,
                      badgeColor: AppColors.primary,
                    ),
                    TrainDestination(
                      label: 'Trips',
                      showBadge: monitor.needsTurnstile,
                      badgeColor: AppColors.error,
                    ),
                    const TrainDestination(
                      label: 'Profile',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rail Ticket'), findsOneWidget);
      expect(find.text('Dhaka'), findsOneWidget);
      expect(find.text('Logs'), findsNothing);
      expect(tester.takeException(), isNull);
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'build/design-preview/journey-${dark ? 'dark' : 'light'}.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      monitor.dispose();
      pro.dispose();
    });
  }
}
