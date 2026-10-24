import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vayora/screens/web_plans.dart';

/// Plan IDs the fake website page offers as "Buy" buttons.
List<String> fakeWebPlanIds = [];

/// Tests have no platform WebView, so the website plans page is faked.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WebPlans.testView = (uri, onBuy) => ListView(
    key: const ValueKey('web-plans'),
    children: [
      const Text('Website plans page'),
      Text(uri.toString()),
      for (final id in fakeWebPlanIds)
        TextButton(onPressed: () => onBuy(id), child: Text('Buy $id')),
    ],
  );
  await testMain();
}
