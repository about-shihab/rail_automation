import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/widgets/fancy_train_loader.dart';
import 'package:rail_automation/widgets/journey_search_button.dart';
import 'package:rail_automation/utils/app_theme.dart';
import 'package:rail_automation/services/language_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'app_language_code': 'en'});
    await LanguageService.instance.setLanguage(AppLanguage.en);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'booking stages and search action fit narrow screen, dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() async {
          final file = File('C:/Windows/Fonts/segoeui.ttf');
          if (await file.exists()) {
            for (final family in ['Roboto', 'Ahem']) {
              await (FontLoader(
                family,
              )..addFont(file.readAsBytes().then(ByteData.sublistView))).load();
            }
          }
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
        var presses = 0;
        var loading = false;
        final key = GlobalKey();
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            theme: (dark ? AppThemes.darkTheme : AppThemes.lightTheme).copyWith(
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFF004D3A),
                titleTextStyle: TextStyle(
                  fontFamily: 'Roboto',
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  textStyle: const TextStyle(fontFamily: 'Roboto'),
                ),
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            ),
            home: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return RepaintBoundary(
                  key: key,
                  child: Scaffold(
                    appBar: AppBar(
                      leading: const Padding(
                        padding: EdgeInsets.all(8),
                        child: AppBrandIcon(),
                      ),
                      title: const Text('Rail Pro'),
                    ),
                    body: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            for (final stage in [
                              JourneyAnimationStage.searching,
                              JourneyAnimationStage.verifying,
                              JourneyAnimationStage.payment,
                            ])
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.cardBg(dark),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: FancyTrainLoader(
                                  height: 176,
                                  stage: stage,
                                ),
                              ),
                            JourneySearchButton(
                              label: 'Search Trains',
                              icon: Icons.search_rounded,
                              loading: loading,
                              onPressed: () => presses++,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/icons/app_icon.jpg'),
            key.currentContext!,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Seats held · Ready to pay'), findsOneWidget);
        expect(find.text('Standing in reservation queue...'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Search Trains'));
        expect(presses, 1);
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'build/design-preview/booking-stages-${dark ? 'dark' : 'light'}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        update(() => loading = true);
        await tester.pump();
        await tester.tap(find.text('Search Trains'));
        expect(presses, 1);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
