import 'package:webview_flutter/webview_flutter.dart';

class WebSessionService {
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
