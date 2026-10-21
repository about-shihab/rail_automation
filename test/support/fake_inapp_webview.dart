import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class FakeInAppWebViewPlatform extends InAppWebViewPlatform {
  late FakeInAppWebViewController controller;
  late PlatformInAppWebViewWidgetCreationParams parameters;
  bool autoFinishLoad = true;
  bool autoReady = true;
  String userAgent = 'test-webview-user-agent';
  String origin = 'https://eticket.railway.gov.bd/';
  String loadUrl = 'https://eticket.railway.gov.bd/';
  int creations = 0;

  void finishLoad() {
    parameters.onLoadStop?.call(
      parameters.controllerFromPlatform!(controller),
      WebUri(loadUrl),
    );
  }

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    creations++;
    parameters = params;
    controller = FakeInAppWebViewController()
      ..origin = origin
      ..requestUrl = loadUrl
      ..userAgent = userAgent
      ..autoReady = autoReady;
    return _FakeInAppWebViewWidget(params, controller, this);
  }
}

class FakeInAppWebViewController extends PlatformInAppWebViewController {
  FakeInAppWebViewController()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 1),
      );
  final scripts = <String>[];
  late Function callback;
  int? requestId;
  String? bridgeId;
  String origin = 'https://eticket.railway.gov.bd/';
  String requestUrl = 'https://eticket.railway.gov.bd/';
  bool autoReady = true;
  String userAgent = 'test-webview-user-agent';
  int get executions =>
      scripts.where((s) => s.startsWith('window.__railBegin(')).length;

  void send(String message, {bool isMainFrame = true}) {
    final data = jsonDecode(message) as Map<String, dynamic>;
    data.putIfAbsent('requestId', () => requestId);
    data.putIfAbsent('bridgeId', () => bridgeId);
    callback(
      JavaScriptHandlerFunctionData(
        args: [data],
        isMainFrame: isMainFrame,
        origin: WebUri(origin),
        requestUrl: WebUri(requestUrl),
      ),
    );
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    scripts.add(source);
    final bridge = RegExp(r'var bridgeId = ("[^"]*");').firstMatch(source);
    if (bridge != null) bridgeId = jsonDecode(bridge[1]!) as String;
    if (source.contains('window.__railPrepared = true')) {
      if (autoReady) {
        send(jsonEncode({'status': 'READY', 'userAgent': userAgent}));
      }
    }
    final match = RegExp(r'^window\.__railBegin\((\d+)[,)]').firstMatch(source);
    if (match != null) requestId = int.parse(match[1]!);
  }

  @override
  void addJavaScriptHandler({
    required String handlerName,
    required Function callback,
  }) {
    this.callback = callback;
  }
}

class _FakeInAppWebViewWidget extends PlatformInAppWebViewWidget {
  _FakeInAppWebViewWidget(super.params, this.controller, this.platform)
    : super.implementation();
  final FakeInAppWebViewController controller;
  final FakeInAppWebViewPlatform platform;

  @override
  Widget build(BuildContext context) =>
      _FakeBrowser(params: params, controller: controller, platform: platform);
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;
  @override
  void dispose() {}
}

class _FakeBrowser extends StatefulWidget {
  const _FakeBrowser({
    required this.params,
    required this.controller,
    required this.platform,
  });
  final PlatformInAppWebViewWidgetCreationParams params;
  final FakeInAppWebViewController controller;
  final FakeInAppWebViewPlatform platform;
  @override
  State<_FakeBrowser> createState() => _FakeBrowserState();
}

class _FakeBrowserState extends State<_FakeBrowser> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = widget.params.controllerFromPlatform!(
        widget.controller,
      );
      widget.params.onWebViewCreated?.call(controller);
      if (widget.platform.autoFinishLoad) widget.platform.finishLoad();
    });
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xfff1f5f4),
    child: Center(child: Text('Human verification')),
  );
}
