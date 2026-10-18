import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class TicketDownloadService {
  static const _channel = MethodChannel('com.example.rail_automation/overlay');

  /// Direct railway portal purchase history URL
  static const String purchaseHistoryUrl =
      'https://eticket.railway.gov.bd/purchase-history';

  /// Shohoz direct ticket download API URL
  static String directDownloadUrl(int orderId) =>
      'https://railspaapi.shohoz.com/v1.0/web/trips/download-ticket/$orderId';

  /// Opens any URL in the external system browser (e.g. Chrome)
  static Future<bool> openInBrowser(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        return await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Serves the PDF bytes over a local loopback HTTP server and opens it in the browser,
  /// triggering Chrome/system browser's native download manager to download and view the PDF.
  static Future<bool> downloadPdfViaBrowser({
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final timer = Timer(const Duration(minutes: 2), () {
        try {
          server.close(force: true);
        } catch (_) {}
      });

      server.listen((HttpRequest request) async {
        request.response.headers.contentType = ContentType(
          'application',
          'pdf',
        );
        request.response.headers.set(
          'Content-Disposition',
          'attachment; filename="$fileName"',
        );
        request.response.headers.set('Content-Length', bytes.length.toString());
        request.response.headers.set('Cache-Control', 'no-cache');
        request.response.add(bytes);
        await request.response.close();
        timer.cancel();
        Future.delayed(const Duration(seconds: 4), () {
          try {
            server.close(force: true);
          } catch (_) {}
        });
      });

      final url = 'http://127.0.0.1:${server.port}/$fileName';
      return await openInBrowser(url);
    } catch (_) {
      return false;
    }
  }

  /// Saves the PDF to Downloads on Android or app Documents on iOS and opens
  /// the native viewer, where the user can inspect, share or print the ticket.
  static Future<String?> saveAndOpenTicketPdf({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        final res = await _channel.invokeMethod<String>('saveAndOpenPdf', {
          'bytes': bytes,
          'fileName': fileName,
        });
        return res;
      } catch (e) {
        return null;
      }
    }
    return null;
  }
}
