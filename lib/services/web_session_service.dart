import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebSessionService {
  // Railway waits for location before submitting checkout. Its Promise catches
  // errors, but getCurrentPosition has an infinite default timeout in WKWebView.
  static const iosCheckoutLocationScript = r'''
    (() => {
      const geo = navigator.geolocation;
      if (!geo || geo.__railCheckoutBounded) return;
      const original = geo.getCurrentPosition.bind(geo);
      geo.getCurrentPosition = function(success, failure, options) {
        let settled = false;
        let timer;
        const finish = (callback, value) => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          if (typeof callback === 'function') callback(value);
        };
        const timeout = Math.min(Math.max(Number(options?.timeout) || 5000, 0), 5000);
        timer = setTimeout(() => finish(failure, {
          code: 3, message: 'Location lookup timed out',
          PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3
        }), timeout);
        try {
          original(value => finish(success, value),
            error => finish(failure, error), {...options, timeout});
        } catch (error) {
          finish(failure, error);
        }
      };
      geo.__railCheckoutBounded = true;
    })();
  ''';

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
