import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'theme_provider.dart';

/// In-app viewer for Instagram reels and other embeddable links.
class ReelViewer extends StatefulWidget {
  final String url;
  final String? title;

  const ReelViewer({super.key, required this.url, this.title});

  @override
  State<ReelViewer> createState() => _ReelViewerState();
}

class _ReelViewerState extends State<ReelViewer> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: c.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title ?? 'Reel',
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            Center(
              child: CircularProgressIndicator(color: c.accent),
            ),
        ],
      ),
    );
  }
}
