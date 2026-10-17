import 'package:flutter/material.dart';
import 'app_state.dart';
import 'account_page.dart';
import 'widgets/common.dart';

Future<void> runAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } on Object {
    if (context.mounted) {
      showFeedback(context, 'Could not complete that. Please try again.');
    }
  }
}

Future<bool> loginGate(BuildContext context, AppState state) =>
    ensureSignedIn(context, state);
