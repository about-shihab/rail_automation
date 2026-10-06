import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/widgets/station_autocomplete.dart';
import 'package:rail_automation/utils/app_theme.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({'app_language_code': 'en'}),
  );
  testWidgets(
    'editing a selected station clears stale selection; keyboard selects match',
    (tester) async {
      var selected = 'Dhaka';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Padding(
                padding: const EdgeInsets.all(24),
                child: StationAutocomplete(
                  label: 'From',
                  value: selected,
                  otherValue: 'Sylhet',
                  stations: const ['Dhaka', 'Chattogram', 'Sylhet'],
                  icon: Icons.trip_origin,
                  onSelected: (value) => setState(() => selected = value),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Cha');
      await tester.pump();
      expect(selected, '');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Cha',
      );
      expect(find.text('Chattogram', findRichText: true), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(selected, 'Chattogram');
      await tester.enterText(find.byType(TextField), 'Syl');
      await tester.pump();
      expect(selected, '');
      expect(find.text('Sylhet', findRichText: true), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'station suggestions fit narrow screen and keyboard, dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() async {
          final font = File('C:/Windows/Fonts/segoeui.ttf');
          if (await font.exists()) {
            await (FontLoader(
              'Roboto',
            )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
          }
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppThemes.darkTheme : AppThemes.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.2),
                viewInsets: const EdgeInsets.only(bottom: 260),
              ),
              child: RepaintBoundary(key: boundary, child: child!),
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
                child: Column(
                  children: [
                    StationAutocomplete(
                      label: 'From',
                      value: '',
                      otherValue: '',
                      stations: const [
                        'Dhaka',
                        'Dhaka Cantonment',
                        'Chattogram',
                      ],
                      icon: Icons.trip_origin,
                      onSelected: (_) {},
                    ),
                    const SizedBox(height: 16),
                    StationAutocomplete(
                      label: 'To',
                      value: 'Chattogram',
                      otherValue: '',
                      stations: const ['Dhaka', 'Chattogram'],
                      icon: Icons.location_on_outlined,
                      onSelected: (_) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.enterText(find.byType(TextField).first, 'Dha');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'build/design-preview/stations-${dark ? 'dark' : 'light'}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
