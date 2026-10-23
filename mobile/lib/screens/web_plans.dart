import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme.dart';
import '../widgets/common.dart';

const webPlansHost = 'vayora-eta.vercel.app';

/// The website plans page, opened inside the direct/ads app only.
Uri webPlansUri({Set<String> free = const {}, bool paused = false}) =>
    Uri.https(webPlansHost, '/subscribe', {
      'app': '1',
      if (free.isNotEmpty) 'free': (free.toList()..sort()).join(','),
      if (paused) 'paused': '1',
    });

/// Plan ID from a page message, or null for anything else.
String? webPlansPurchase(String raw) {
  try {
    final data = jsonDecode(raw);
    if (data is Map && data['type'] == 'buy' && data['plan_id'] is String) {
      final id = (data['plan_id'] as String).trim();
      return id.isEmpty ? null : id;
    }
  } catch (_) {}
  return null;
}

/// Only our own plans page may load; everything else is blocked.
bool webPlansAllowed(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host == webPlansHost &&
    (uri.path == '/subscribe' || uri.path == '/d');

class WebPlans extends StatefulWidget {
  const WebPlans({super.key, required this.uri, required this.onBuy});
  final Uri uri;

  /// Runs the app's own checkout (UPI or free claim) for the chosen plan.
  final Future<void> Function(String planId) onBuy;
  @override
  State<WebPlans> createState() => _WebPlansState();
}

class _WebPlansState extends State<WebPlans> {
  late final WebViewController controller;
  bool loading = true, failed = false, buying = false;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.background)
      ..addJavaScriptChannel(
        'VayoraApp',
        onMessageReceived: (message) => buy(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              webPlansAllowed(Uri.parse(request.url))
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageStarted: (_) {
            if (mounted) setState(() => loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != false && mounted) {
              setState(() {
                loading = false;
                failed = true;
              });
            }
          },
        ),
      )
      ..loadRequest(widget.uri);
  }

  @override
  void didUpdateWidget(WebPlans old) {
    super.didUpdateWidget(old);
    if (old.uri != widget.uri) reload();
  }

  void reload() {
    setState(() {
      failed = false;
      loading = true;
    });
    controller.loadRequest(widget.uri);
  }

  Future<void> buy(String raw) async {
    final id = webPlansPurchase(raw);
    if (id == null || buying) return;
    buying = true;
    try {
      await widget.onBuy(id);
    } finally {
      buying = false;
      if (mounted) reload();
    }
  }

  @override
  Widget build(BuildContext context) => failed
      ? ErrorRetry(onRetry: reload)
      : Stack(
          children: [
            WebViewWidget(controller: controller),
            if (loading) const LinearProgressIndicator(),
          ],
        );
}
