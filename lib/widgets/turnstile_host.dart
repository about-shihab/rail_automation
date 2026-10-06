import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/turnstile_session.dart';
import '../services/web_session_service.dart';

/// Keep the platform view mounted and rendered at its real challenge size.
/// Opacity hides it while idle; Offstage and rebuilding at booking time would
/// lose the advantage of a warm browser. The follower exposes this SAME view
/// at the processing overlay's challenge slot when interaction is required.
class TurnstileHost extends StatefulWidget {
  const TurnstileHost({super.key, required this.child});
  final Widget child;

  @override
  State<TurnstileHost> createState() => _TurnstileHostState();
}

class _TurnstileHostState extends State<TurnstileHost> {
  final session = TurnstileSession.instance;
  late final Widget browser = InAppWebView(
    initialData: InAppWebViewInitialData(
      data: TurnstileSession.html,
      baseUrl: WebUri('https://eticket.railway.gov.bd/'),
      historyUrl: WebUri('https://eticket.railway.gov.bd/'),
    ),
    initialSettings: InAppWebViewSettings(
      javaScriptEnabled: true,
      transparentBackground: true,
      useShouldOverrideUrlLoading: true,
      javaScriptBridgeForMainFrameOnly: true,
    ),
    onWebViewCreated: (controller) {
      session.attach((source) async {
        await controller.evaluateJavascript(source: source);
      });
      controller.addJavaScriptHandler(
        handlerName: 'TurnstileBridge',
        callback: (JavaScriptHandlerFunctionData data) {
          if (!data.isMainFrame ||
              !WebSessionService.isRailwayUrl(data.origin.toString())) {
            return;
          }
          final arguments = data.args;
          if (arguments.isNotEmpty && arguments.first is Map) {
            session.receive(Map<String, dynamic>.from(arguments.first as Map));
          }
        },
      );
    },
    onLoadStop: (controller, url) async {
      if (WebSessionService.isRailwayUrl(url?.toString())) {
        await controller.evaluateJavascript(source: TurnstileSession.bootstrap);
      }
    },
    shouldOverrideUrlLoading: (controller, action) async =>
        !action.isForMainFrame ||
            WebSessionService.isRailwayUrl(action.request.url?.toString())
        ? NavigationActionPolicy.ALLOW
        : NavigationActionPolicy.CANCEL,
    onReceivedError: (controller, request, error) {
      if (request.isForMainFrame == true) {
        session.fail('No connection to Railway. Please retry.');
      }
    },
  );

  @override
  void dispose() {
    session.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      Positioned.fill(
        child: ListenableBuilder(
          listenable: session,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 150, height: 170, child: browser),
          ),
          builder: (context, child) {
            final visible = session.phase == TurnstilePhase.interactive;
            return IgnorePointer(
              ignoring: !visible,
              child: ExcludeSemantics(
                excluding: !visible,
                child: Opacity(
                  opacity: visible ? 1 : 0,
                  child: CompositedTransformFollower(
                    link: session.challengeLink,
                    showWhenUnlinked: false,
                    child: child,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}
