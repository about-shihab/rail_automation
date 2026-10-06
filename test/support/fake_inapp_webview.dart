import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class FakeInAppWebViewPlatform extends InAppWebViewPlatform {
  late FakeInAppWebViewController controller;
  int creations = 0;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    creations++;
    controller = FakeInAppWebViewController();
    return _FakeInAppWebViewWidget(params, controller);
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
  int get executions =>
      scripts.where((s) => s.startsWith('window.__railBegin(')).length;

  void send(String message) {
    final data = jsonDecode(message) as Map<String, dynamic>;
    data.putIfAbsent('requestId', () => requestId);
    callback(
      JavaScriptHandlerFunctionData(
        args: [data],
        isMainFrame: true,
        origin: WebUri('https://eticket.railway.gov.bd/'),
        requestUrl: WebUri('https://eticket.railway.gov.bd/'),
      ),
    );
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    scripts.add(source);
    if (source.contains('window.__railPrepared = true')) {
      send('{"status":"READY"}');
    }
    final match = RegExp(r'^window\.__railBegin\((\d+)\)').firstMatch(source);
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
  _FakeInAppWebViewWidget(super.params, this.controller)
    : super.implementation();
  final FakeInAppWebViewController controller;

  @override
  Widget build(BuildContext context) =>
      _FakeBrowser(params: params, controller: controller);
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;
  @override
  void dispose() {}
}

class _FakeBrowser extends StatefulWidget {
  const _FakeBrowser({required this.params, required this.controller});
  final PlatformInAppWebViewWidgetCreationParams params;
  final FakeInAppWebViewController controller;
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
      widget.params.onLoadStop?.call(
        controller,
        widget.params.initialData?.baseUrl,
      );
    });
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xfff1f5f4),
    child: Center(child: Text('Human verification')),
  );
}
