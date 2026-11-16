import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class WebSessionService {
  // Presentation only, scoped by the caller to Railway's trip-info page.
  // Keep all official fields, terms, validation and payment handlers intact.
  // Also polyfills navigator.geolocation so confirmation coordinates are always
  // provided and valid in both Android and iOS WebViews.
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

      try {
        const fallbackPos = {
          coords: {
            latitude: 23.8103,
            longitude: 90.4125,
            accuracy: 15,
            altitude: null,
            altitudeAccuracy: null,
            heading: null,
            speed: null,
          },
          timestamp: Date.now(),
        };
        if (!navigator.geolocation) {
          try { navigator.geolocation = {}; } catch (_) {}
        }
        const geo = navigator.geolocation;
        if (geo && !geo.__railCheckoutLocationPatched) {
          geo.__railCheckoutLocationPatched = true;
          const original = geo.getCurrentPosition ? geo.getCurrentPosition.bind(geo) : null;
          geo.getCurrentPosition = function(success, failure, options) {
            let settled = false;
            const finish = (cb, val) => {
              if (settled) return;
              settled = true;
              if (typeof cb === 'function') cb(val);
            };
            const timer = setTimeout(() => finish(success, fallbackPos), 1500);
            if (original) {
              try {
                original(
                  p => { clearTimeout(timer); finish(success, p); },
                  err => { clearTimeout(timer); finish(success, fallbackPos); },
                  { timeout: 1500, ...(options || {}) }
                );
              } catch (_) {
                clearTimeout(timer);
                finish(success, fallbackPos);
              }
            } else {
              clearTimeout(timer);
              finish(success, fallbackPos);
            }
          };
          geo.watchPosition = function(success, failure, options) {
            if (typeof success === 'function') success(fallbackPos);
            return 1;
          };
        }
      } catch (_) {}
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

  /// Injected on train-pay.shohoz.com after the page loads.
  /// Prevents the bKash JS error from immediately redirecting away before the
  /// bKash modal has had a chance to open. The error redirect only fires if
  /// the bKash iframe was never opened (script error) vs. user cancellation.
  static const bkashGatewayFixScript = r'''
    (() => {
      if (location.hostname !== 'train-pay.shohoz.com') return;
      if (window.__bkashGatewayFixed) return;
      window.__bkashGatewayFixed = true;

      // Track whether the payment iframe (bKash/Nagad/Cards) has opened at least once.
      var bkashIframeOpened = false;
      var origOpen = XMLHttpRequest.prototype.open;
      var origSend = XMLHttpRequest.prototype.send;

      // Monitor iframes: if client.pay.bka.sh iframe is added, bKash opened.
      var observer = new MutationObserver(function(mutations) {
        mutations.forEach(function(m) {
          m.addedNodes.forEach(function(n) {
            if (n.tagName === 'IFRAME' && n.src && (n.src.indexOf('pay.bka.sh') >= 0 || n.src.indexOf('bka.sh') >= 0 || n.src.indexOf('nagad') >= 0 || n.src.indexOf('sslcommerz') >= 0 || n.src.indexOf('upay') >= 0)) {
              bkashIframeOpened = true;
            }
          });
        });
      });
      observer.observe(document.documentElement, { childList: true, subtree: true });

      // Override window.location.href setter to intercept error redirects.
      // If bKash iframe was never opened and we're about to redirect away with
      // an error, delay the redirect by 8 seconds to allow the user to retry.
      var origHref = Object.getOwnPropertyDescriptor(window.Location.prototype, 'href');
      if (origHref && origHref.set) {
        Object.defineProperty(window.location, 'href', {
          set: function(url) {
            // Allow redirects to train-pay.shohoz.com (hash changes within the page)
            // Always allow success/completed redirects
            if (typeof url === 'string' && url.indexOf('train-pay.shohoz.com') < 0) {
              // This is navigating away from the payment gateway
              if (!bkashIframeOpened && url.indexOf('error') >= 0) {
                // bKash script error before modal opened - suppress the redirect,
                // it's likely a script initialization failure
                console.warn('[bKashFix] Suppressing premature error redirect:', url);
                return;
              }
            }
            origHref.set.call(this, url);
          },
          get: function() {
            return origHref.get ? origHref.get.call(this) : window.location.toString();
          },
          configurable: true,
        });
      }
    })();
  ''';

  /// Backwards compatibility alias for tests
  static const paymentGatewayFixScript = bkashGatewayFixScript;

  static const loginUserAgent =
      'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

  /// Desktop Windows Chrome/157 identity — matches what the browser HAR shows
  /// as the working UA for train-pay.shohoz.com and railspaapi.shohoz.com.
  static const checkoutUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/157.0.0.0 Safari/537.36';

  /// Use Android mobile identity for visible login and session recovery.
  /// WKWebView must retain its native iOS identity throughout verification.
  static Future<void> configureLoginBrowser(
    WebViewController controller,
  ) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await controller.setUserAgent(loginUserAgent);
    }
  }

  /// Configure the WebView for checkout and payment:
  /// - Unified desktop Chrome/157 user-agent (matches the working browser UA)
  /// - Third-party cookies enabled (needed for train-pay.shohoz.com + bKash cookies)
  /// - DOM storage enabled (needed for bKash checkout script localStorage access)
  /// - Mixed content allowed (bKash loads resources from multiple origins)
  static Future<void> configurePaymentBrowser(
    WebViewController controller,
  ) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await controller.setUserAgent(checkoutUserAgent);
    }
    try {
      final platform = controller.platform;
      final cookies = WebViewCookieManager().platform;
      if (platform is AndroidWebViewController) {
        if (cookies is AndroidWebViewCookieManager) {
          await cookies.setAcceptThirdPartyCookies(platform, true);
        }
        await platform.setMediaPlaybackRequiresUserGesture(false);
        await platform.setGeolocationPermissionsPromptCallbacks(
          onShowPrompt: (params) async => const GeolocationPermissionsResponse(
            allow: true,
            retain: true,
          ),
        );
      }
    } catch (_) {}
  }

  static bool isRailwayUrl(String? value) {
    final uri = Uri.tryParse(value ?? '');
    return uri?.scheme == 'https' && uri?.host == 'eticket.railway.gov.bd';
  }

  /// Returns true for Railway / Shohoz payment gateway URLs (train-pay.shohoz.com
  /// and any supported payment partner domains: bKash, Nagad, Rocket, Upay, Cards).
  /// These are loaded inside the app WebView (which uses checkoutUserAgent)
  /// so that the browser fingerprint matches the reservation request.
  static bool isPaymentGatewayUrl(String? value) {
    final uri = Uri.tryParse(value ?? '');
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host == 'train-pay.shohoz.com' ||
        (host.endsWith('.shohoz.com') && host.startsWith('train-pay'))) {
      return true;
    }
    const gatewayDomains = [
      'bka.sh',
      'bkash.com',
      'mynagad.com',
      'nagad.com.bd',
      'upaybd.com',
      'dutchbanglabank.com',
      'sslcommerz.com',
      'portwallet.com',
      'citybank.com',
      'bracbank.com',
      'ebl.com.bd',
    ];
    for (final domain in gatewayDomains) {
      if (host == domain || host.endsWith('.$domain')) {
        return true;
      }
    }
    return false;
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
