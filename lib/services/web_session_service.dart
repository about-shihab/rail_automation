import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebSessionService {
  /// Use the same browser identity for visible login and session recovery.
  /// WKWebView must retain its native iOS identity throughout verification.
  static Future<void> configureLoginBrowser(
    WebViewController controller,
  ) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await controller.setUserAgent(
        'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36',
      );
    }
  }

  static bool isRailwayUrl(String? value) {
    final uri = Uri.tryParse(value ?? '');
    return uri?.scheme == 'https' && uri?.host == 'eticket.railway.gov.bd';
  }

  static Future<void> clear() async {
    final controller = WebViewController();
    await WebViewCookieManager().clearCookies();
    await controller.clearCache();
    await controller.clearLocalStorage();
  }
}
