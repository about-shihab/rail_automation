import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Keep the official booking flow (including login and payment) in its webview.
class BookingScreen extends StatefulWidget {
  final String url;
  const BookingScreen({super.key, required this.url});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  WebViewController? _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (mounted) setState(() => _loading = true);
            },
            onPageFinished: (_) {
              if (mounted) setState(() => _loading = false);
            },
            onWebResourceError: (error) {
              if (mounted && error.isForMainFrame == true) {
                setState(() {
                  _failed = true;
                  _loading = false;
                });
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.url));
    } catch (_) {
      _failed = true;
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('টিকেট বুক করুন • Book tickets')),
    body: Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _failed || _controller == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('পেজটি খোলা যায়নি\nUnable to open booking'),
                      TextButton(
                        onPressed: () {
                          if (_controller != null) {
                            setState(() {
                              _failed = false;
                              _loading = true;
                            });
                            _controller!.loadRequest(Uri.parse(widget.url));
                          }
                        },
                        child: const Text('আবার চেষ্টা করুন • Retry'),
                      ),
                    ],
                  ),
                )
              : WebViewWidget(controller: _controller!),
        ),
      ],
    ),
  );
}
