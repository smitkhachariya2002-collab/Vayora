import 'package:flutter/material.dart';

import '../services/app_scope.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'channel_page.dart';
import 'post_page.dart';

/// Home: channels row + latest posts grid. Hidden / wrong-audience rows never come back (RLS).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onSearch, this.onProfile, this.onSeeAllChannels});
  final VoidCallback? onSearch, onProfile, onSeeAllChannels;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _accessKey;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    final status = app.status;
    final key = '${app.loaded}|${status.raw['user_id']}|${status.source}|${status.isGuest}|${status.hasAdsAccess}|${status.isPremium}|${status.accessStatus}';
    final previous = _accessKey;
    _accessKey = key;
    if (previous != null && previous != key) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _accessKey != key) return;
        setState(() { _channels = []; _posts = []; _thumbs.clear(); _loading = true; });
        _load();
      });
    }
  }

  List<Map<String, dynamic>> _channels = [];
  List<Map<String, dynamic>> _posts = [];
  final Map<String, String> _thumbs = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _loadGeneration = 0;
  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      final c = await sb.from('channels').select('id,name').order('created_at', ascending: false).limit(10);
      if (!mounted || generation != _loadGeneration) return;
      _channels = List<Map<String, dynamic>>.from(c);
      final p = await sb.from('posts').select('id,title,channels(name),post_items(thumbnail_key,position,is_premium,duration_s)').order('created_at', ascending: false).limit(12);
      if (!mounted || generation != _loadGeneration) return;
      _posts = List<Map<String, dynamic>>.from(p);
      final keys = <String>[
        for (final r in _posts)
          for (final it in ((r['post_items'] as List?) ?? const []))
            if ((it as Map)['thumbnail_key'] != null) it['thumbnail_key'] as String,
      ];
      if (keys.isNotEmpty) {
        try {
          final res = await sb.storage.from('media').createSignedUrls(keys, 3600);
          for (final r in res) {
            final String path = r.path;
            _thumbs[path] = r.signedUrl;
          }
        } catch (_) {/* thumbnails are optional */}
      }
    } catch (_) {}
    if (mounted && generation == _loadGeneration) setState(() => _loading = false);
  }

  String? _thumbFor(Map<String, dynamic> post) {
    for (final it in ((post['post_items'] as List?) ?? const [])) {
      final k = (it as Map)['thumbnail_key'] as String?;
      if (k != null && _thumbs[k] != null) return _thumbs[k];
    }
    return null;
  }

  String _initial(AppState app) {
    String? mail;
    try {
      mail = sb.auth.currentUser?.email;
    } catch (_) {}
    return (mail != null && mail.isNotEmpty ? mail[0] : (app.status.isGuest ? 'G' : 'U')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
        Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset('assets/icon.png', width: 44, height: 44)),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Vayora', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)), Text('Your cloud & channels', style: TextStyle(color: Tokens.muted, fontSize: 12))])),
          _SquareButton(key: const Key('home_search'), onTap: widget.onSearch, child: const Icon(Icons.search)),
          const SizedBox(width: 10),
          _SquareButton(key: const Key('home_avatar'), onTap: widget.onProfile, child: Text(_initial(app), style: const TextStyle(color: Tokens.primary, fontWeight: FontWeight.w700, fontSize: 16))),
        ]),
        const SizedBox(height: 12),
        TextButton.icon(onPressed: widget.onSearch, icon: const Icon(Icons.explore_outlined, color: Tokens.accent), label: const Text('Find your next watch', style: TextStyle(color: Tokens.accent))),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: Text('Channels', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
          TextButton(style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)), onPressed: widget.onSeeAllChannels, child: const Text('See all', style: TextStyle(color: Tokens.accent, fontSize: 13))),
        ]),
        SizedBox(
          height: 104 * (MediaQuery.textScalerOf(context).scale(12) / 12),
          child: _channels.isEmpty
              ? Center(child: Text(_loading ? '' : 'No channels yet', style: const TextStyle(color: Tokens.muted)))
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _channels.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final name = (_channels[i]['name'] as String?) ?? '';
                    return GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChannelPage(channelId: _channels[i]['id'] as String, name: name))),
                      child: SizedBox(width: 80, child: Column(children: [
                        InitialAvatar(name: name, size: 52),
                        const SizedBox(height: 4),
                        Text(name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Tokens.muted, fontSize: 12)),
                      ])),
                    );
                  },
                ),
        ),
        const SizedBox(height: 10),
        const Text('Latest', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else if (_posts.isEmpty)
          const EmptyState(icon: Icons.movie_outlined, title: 'No shows yet', message: 'New videos from channels will appear here.')
        else
          Padding(padding: const EdgeInsets.symmetric(horizontal: 0), child: VideoGrid(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            shrinkWrap: true,
            itemCount: _posts.length,
            itemBuilder: (_, i) {
              final post = _posts[i];
              final items = (post['post_items'] as List?) ?? const [];
              return VideoCard(
                title: post['title'] as String? ?? '',
                channel: (post['channels'] as Map?)?['name'] as String? ?? '',
                url: _thumbFor(post),
                premium: items.any((item) => item['is_premium'] == true),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostPage(postId: post['id'] as String))),
              );
            },
          )),
      ]),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(width: 44, height: 44, decoration: BoxDecoration(color: Tokens.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Tokens.border)), alignment: Alignment.center, child: child),
      );
}

