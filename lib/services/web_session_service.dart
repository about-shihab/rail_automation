import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

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

  /// Payment checkout browser. Gateways (bKash, SSLCommerz, banks) reject
  /// requests that look like an embedded WebView or whose User-Agent does not
  /// match the real engine version. Use the device's real WebView UA with the
  /// WebView markers removed, and allow the third-party cookies that payment
  /// redirects depend on. Login/session recovery keep using
  /// [configureLoginBrowser] unchanged.
  static Future<void> configurePaymentBrowser(
    WebViewController controller,
  ) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final native = await controller.getUserAgent();
        if (native != null && native.isNotEmpty) {
          await controller.setUserAgent(
            native
                .replaceAll('; wv)', ')')
                .replaceAll(RegExp(r'Version/\d+\.\d+\s'), ''),
          );
        }
      } catch (_) {}
    }
    try {
      final platform = controller.platform;
      final cookies = WebViewCookieManager().platform;
      if (platform is AndroidWebViewController &&
          cookies is AndroidWebViewCookieManager) {
        await cookies.setAcceptThirdPartyCookies(platform, true);
      }
    } catch (_) {}
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
