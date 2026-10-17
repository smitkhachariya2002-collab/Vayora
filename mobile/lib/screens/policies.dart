import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/common.dart';

class Policy extends StatelessWidget {
  const Policy({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => AppPage(
    title: name,
    body: SingleChildScrollView(
      child: Padding(
        padding: Gap.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$name · v1',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: Gap.l),
            Text(switch (name) {
              'Privacy' =>
                'Vayora stores account details, install attribution, consent, uploaded content and payment records to provide the service. Contact help.vayora@gmail.com to request access or deletion.',
              'Refund' =>
                'Plans do not renew automatically. If a verified payment does not unlock your plan, contact help.vayora@gmail.com with your order reference. Refund requests are reviewed by support.',
              'Community rules' =>
                'Upload only content you have permission to share. Illegal, abusive or infringing content is prohibited. Report content from its post or channel page. User channels require review.',
              _ =>
                'Use Vayora lawfully and respect other users and creators. Account access follows the current service mode. Contact help.vayora@gmail.com for assistance.',
            }),
            const SizedBox(height: Gap.xl),
            const Text('Contact: help.vayora@gmail.com'),
          ],
        ),
      ),
    ),
  );
}
