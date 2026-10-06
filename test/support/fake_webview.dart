import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class FakeWebViewPlatform extends WebViewPlatform {
  late FakeWebViewController controller;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = FakeWebViewController(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => FakeWebViewWidget(params);
}

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params) : super.implementation();

  late JavaScriptChannelParams channel;
  FakeNavigationDelegate? delegate;
  String? script;
  final scripts = <String>[];
  String? htmlBaseUrl;
  int loads = 0;
  String? url;
  Object javascriptResult = '{}';

  @override
  Future<String?> currentUrl() async => url;

  @override
  Future<Object> runJavaScriptReturningResult(String script) async =>
      javascriptResult;

  void send(String message) =>
      channel.onMessageReceived(JavaScriptMessage(message: message));

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate value,
  ) async {
    delegate = value as FakeNavigationDelegate;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loads++;
    url = params.uri.toString();
    delegate?.pageStarted?.call(url!);
    delegate?.pageFinished?.call(params.uri.toString());
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    script = javaScript;
    scripts.add(javaScript);
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    htmlBaseUrl = baseUrl;
    url = baseUrl;
    delegate?.pageFinished?.call(baseUrl!);
  }
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();
  PageEventCallback? pageFinished;
  PageEventCallback? pageStarted;
  NavigationRequestCallback? navigationRequest;

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    pageFinished = callback;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {
    pageStarted = callback;
  }

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {
    navigationRequest = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class FakeWebViewWidget extends PlatformWebViewWidget {
  FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xfff1f5f4),
    child: Center(child: Text('Human verification')),
  );
}
