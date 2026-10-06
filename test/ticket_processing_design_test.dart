import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:rail_automation/widgets/turnstile_host.dart';

import 'package:rail_automation/utils/app_theme.dart';
import 'package:rail_automation/widgets/ticket_processing_overlay.dart';

import 'support/fake_inapp_webview.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'Processing overlay fits narrow screens and larger text, dark=$dark',
      (tester) async {
        final webview = FakeInAppWebViewPlatform();
        InAppWebViewPlatform.instance = webview;
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() async {
          for (final path in [
            'C:/Windows/Fonts/segoeui.ttf',
            '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
          ]) {
            final font = File(path);
            if (await font.exists()) {
              final loader = FontLoader('Roboto')
                ..addFont(font.readAsBytes().then(ByteData.sublistView));
              await loader.load();
              break;
            }
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
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: TurnstileHost(child: child!),
            ),
            home: RepaintBoundary(
              key: boundary,
              child: const TicketProcessingOverlay(
                contextLabel: 'SUBARNA EXPRESS · SNIGDHA',
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
        expect(find.text('Checking access'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final repaint =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await repaint.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = File(
            'build/design-preview/processing-${dark ? 'dark' : 'light'}.png',
          );
          await output.parent.create(recursive: true);
          await output.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        webview.controller.send('{"status":"INTERACTIVE"}');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Verify to continue'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
