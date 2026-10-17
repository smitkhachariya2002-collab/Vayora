import 'package:flutter/material.dart';
import '../app_state.dart';
import '../theme.dart';
import 'common.dart';

Future<void> reportContent(
  BuildContext context,
  AppState state, {
  String? postId,
  required String channelId,
}) async {
  final details = TextEditingController();
  var reason = 'Copyright';
  final send = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, update) => AlertDialog(
        icon: const Icon(
          Icons.flag_outlined,
          size: AppSizes.dialogIcon,
          color: AppColors.primary,
        ),
        title: const Text('Report content', textAlign: TextAlign.center),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Tell us what needs a closer look.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Gap.l),
              DropdownButtonFormField<String>(
                initialValue: reason,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: const ['Copyright', 'Abuse', 'Illegal content', 'Other']
                    .map(
                      (reason) =>
                          DropdownMenuItem(value: reason, child: Text(reason)),
                    )
                    .toList(),
                onChanged: (value) => update(() => reason = value ?? reason),
              ),
              const SizedBox(height: Gap.l),
              TextField(
                controller: details,
                maxLength: 4000,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Details'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    ),
  );
  final text = details.text;
  details.dispose();
  if (send != true || !context.mounted) return;
  try {
    await state.db.rpc(
      'report_content_in_app',
      params: {
        'post_id': postId,
        'channel_id': channelId,
        'reason': reason,
        'details': text,
      },
    );
    if (context.mounted) showFeedback(context, 'Report submitted.');
  } on Object {
    if (context.mounted) {
      showFeedback(context, 'Could not send your report. Please try again.');
    }
  }
}
