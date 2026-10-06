import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/models/booking_intent.dart';
import 'package:rail_automation/services/credit_service.dart';
import 'package:rail_automation/services/language_service.dart';
import 'package:rail_automation/utils/app_theme.dart';
import 'package:rail_automation/views/watch_options_dialog.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'app_language_code': 'bn'});
    await LanguageService.instance.setLanguage(AppLanguage.bn);
    CreditService().setCreditsForTesting(5);
  });
  for (final dark in [false, true]) {
    testWidgets('Bangla booking sheet fits narrow screen, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        for (final family in ['Roboto', 'Ahem']) {
          final loader = FontLoader(family);
          for (final name in ['Nirmala.ttf', 'NirmalaB.ttf']) {
            final file = File('C:/Windows/Fonts/$name');
            if (await file.exists()) {
              loader.addFont(file.readAsBytes().then(ByteData.sublistView));
            }
          }
          await loader.load();
        }
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: (dark ? AppThemes.darkTheme : AppThemes.lightTheme).copyWith(
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                textStyle: const TextStyle(fontFamily: 'Roboto'),
              ),
            ),
          ),
          builder: (context, child) => RepaintBoundary(
            key: key,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              appBar: const GradientAppBar(
                title: 'Rail Pro',
                icon: Icons.train_rounded,
              ),
              body: Center(
                child: TextButton(
                  onPressed: () => showWatchOptions(
                    context,
                    trainName: 'SONAR BANGLA EXPRESS (788)',
                    seatClass: 'ALL',
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('অটো-বুকিং'), findsOneWidget);
      expect(find.text('যেকোনো শ্রেণি'), findsOneWidget);
      expect(find.text('স্বয়ংক্রিয় ওটিপি যাচাই'), findsOneWidget);
      expect(find.text('ওটিপি পাঠালে প্রতি ট্রেনে ১ ক্রেডিট'), findsOneWidget);
      expect(find.text('Start'), findsNothing);
      await tester.ensureVisible(find.text('শুরু করুন'));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'build/design-preview/watch-options-bn-${dark ? 'dark' : 'light'}.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      CreditService().setCreditsForTesting(0);
      await tester.pumpAndSettle();
      expect(find.text('ক্রেডিট যোগ করুন'), findsOneWidget);
      await tester.tap(find.byTooltip('বন্ধ করুন'));
      await tester.pumpAndSettle();
      expect(find.text('অটো-বুকিং'), findsNothing);
    });
  }

  testWidgets('language changes preserve seats, SMS choice and target trains', (
    tester,
  ) async {
    BookingIntent? result;
    const trains = ['SONAR BANGLA EXPRESS (788)', 'SUBARNA EXPRESS (702)'];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showWatchOptions(
                  context,
                  targetTrains: trains,
                  seatClass: 'SNIGDHA',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('স্নিগ্ধা'), findsOneWidget);
    await tester.tap(find.byTooltip('আসন বাড়ান'));
    await tester.pump();
    expect(find.text('২'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => LanguageService.instance.setLanguage(AppLanguage.en),
    );
    await tester.pumpAndSettle();
    expect(find.text('Auto-booking'), findsOneWidget);
    expect(find.text('Snigdha'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    await tester.runAsync(
      () => LanguageService.instance.setLanguage(AppLanguage.bn),
    );
    await tester.pumpAndSettle();
    expect(find.text('২'), findsOneWidget);
    expect(find.text('স্নিগ্ধা'), findsOneWidget);
    await tester.ensureVisible(find.text('শুরু করুন'));
    await tester.tap(find.text('শুরু করুন'));
    await tester.pumpAndSettle();
    expect(result?.quantity, 2);
    expect(result?.autoVerify, isFalse);
    expect(result?.autoReserve, isTrue);
    expect(result?.targetTrains, trains);
    expect(tester.takeException(), isNull);
  });
}
