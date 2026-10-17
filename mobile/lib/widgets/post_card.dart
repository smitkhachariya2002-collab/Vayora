import 'package:flutter/material.dart';
import '../theme.dart';
import 'common.dart';

class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post, required this.onTap, this.thumbnailUrl});
  final Map<String, dynamic> post;
  final VoidCallback onTap;
  final String? thumbnailUrl;
  @override
  Widget build(BuildContext context) {
    final items = List<Map<String, dynamic>>.from(post['post_items'] as List? ?? [])
      ..sort((a,b) => ((a['position'] as num?) ?? 0).compareTo((b['position'] as num?) ?? 0));
    final item = items.isEmpty ? <String, dynamic>{} : items.first;
    final channel = post['channels'] as Map? ?? {};
    final premium = items.any((item) => item['is_premium'] == true);
    return Semantics(button: true, label: post['title'] as String? ?? 'Open post',
      child: PressScale(onTap: onTap, child: Card(clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        NetThumb(url: thumbnailUrl, overlays: [
          Center(child: PlayOverlay(onPressed: onTap)),
          if (premium) const Positioned(top: Gap.m, right: Gap.m, child: PremiumBadge()),
          Positioned(left: Gap.m, bottom: Gap.m, child: ThumbPill('${compactNumber(post['view_count'] as num?)} views', icon: Icons.visibility_outlined)),
          Positioned(right: Gap.m, bottom: Gap.m, child: ThumbPill(durationLabel(item['duration_s'] as num?))),
        ]),
        Padding(padding: const EdgeInsets.all(Gap.l), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(post['title'] as String? ?? 'Untitled', maxLines: 2, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Gap.s),
          Text(channel['name'] as String? ?? AppBrand.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall),
        ])),
      ]))));
  }
}
