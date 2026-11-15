import 'package:flutter/material.dart';

import 'explore_screen.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});
  @override
  Widget build(BuildContext context) => const PostList(joinedOnly: true);
}
