import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class WebSessionService {
  // Presentation only, scoped by the caller to Railway's trip-info page.
  // Keep all official fields, terms, validation and payment handlers intact.
  static const checkoutAppearanceScript = r'''
    (() => {
      if (location.hostname !== 'eticket.railway.gov.bd' ||
          location.pathname !== '/booking/train/trip-info') return;
      let style = document.getElementById('rail-checkout-appearance');
      if (!style) {
        style = document.createElement('style');
        style.id = 'rail-checkout-appearance';
        document.head.appendChild(style);
      }
      style.textContent = `
        body { background:#f5f8f7 !important; font-family:system-ui,sans-serif !important; }
        #main_wrapper { padding-bottom:24px; }
        #content { max-width:860px; }
        input:not([type=checkbox]):not([type=radio]), select, textarea {
          min-height:46px; border-radius:10px !important; font-size:16px !important;
        }
        .passenger-info-box { border-radius:16px !important; padding:16px !important; }
        .payment-icon-holder { border-radius:12px !important; min-height:52px; }
        .selected_box { border:2px solid #009b78 !important; background-color:#ecfdf5 !important; }
        #payment_options { border-radius:16px; overflow:hidden; }
        button { border-radius:10px !important; }
        button:focus-visible, input:focus-visible, select:focus-visible {
          outline:2px solid #009b78; outline-offset:2px;
        }
      `;
    })();
  ''';
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

  static const loginUserAgent =
      'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

  /// The desktop Windows Chrome identity used for all Railway API calls.
  /// Using the same UA in WebViews prevents session-fingerprint mismatches
  /// that cause payment gateways (bKash, Nagad) to deny the request.
  static const checkoutUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36';

  /// Use Android mobile identity for visible login and session recovery.
  /// WKWebView must retain its native iOS identity throughout verification.
  static Future<void> configureLoginBrowser(
    WebViewController controller,
  ) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await controller.setUserAgent(loginUserAgent);
    }
  }

  /// Keep checkout identity (Windows Chrome/154) throughout payment and allow gateway cookies.
  static Future<void> configurePaymentBrowser(
    WebViewController controller,
  ) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await controller.setUserAgent(checkoutUserAgent);
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

  /// Returns true for Shohoz payment gateway URLs (train-pay.shohoz.com).
  /// These are now loaded inside the app WebView (which uses checkoutUserAgent)
  /// so that the browser fingerprint matches the reservation request.
  static bool isPaymentGatewayUrl(String? value) {
    final uri = Uri.tryParse(value ?? '');
    return uri?.scheme == 'https' && uri?.host == 'train-pay.shohoz.com';
  }

  /// Payment gateways (train-pay.shohoz.com) stay inside the app WebView
  /// using [checkoutUserAgent], allowing bKash / payment modals to pop up
  /// directly within the page instead of opening in a separate browser tab.
  static bool usesAndroidPaymentBrowser(String value) => false;

  static Future<void> clear() async {
    final controller = WebViewController();
    await WebViewCookieManager().clearCookies();
    await controller.clearCache();
    await controller.clearLocalStorage();
  }
}
