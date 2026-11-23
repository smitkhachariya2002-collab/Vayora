import 'package:flutter/material.dart';

import '../services/app_scope.dart';
import '../services/app_state.dart';
import '../services/measurement.dart';
import '../services/bunny_media.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'post_page.dart';
import 'premium_screen.dart';

/// Shared post list used by Explore (all) and Feed (joined channels).
class PostList extends StatefulWidget {
  const PostList({super.key, this.joinedOnly = false, this.category, this.query = '', this.channelId});
  final bool joinedOnly;
  final String? channelId;
  final String? category;
  final String query;
  @override
  State<PostList> createState() => _PostListState();
}

class _PostListState extends State<PostList> {
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
        _thumbs.clear();
        _load(reset: true);
      });
    }
  }

  final _rows = <Map<String, dynamic>>[];
  final _thumbs = <String, String>{};
  bool _loading = true, _more = true, _fetching = false;
  int _gen = 0;
  static const _page = 20;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void didUpdateWidget(PostList old) {
    super.didUpdateWidget(old);
    if (old.category != widget.category || old.query != widget.query || old.channelId != widget.channelId) _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_fetching && !reset) return;
    _fetching = true;
    final gen = ++_gen;
    if (reset) { _rows.clear(); _more = true; }
    if (mounted) setState(() => _loading = true);
    try {
      // Hidden / wrong-audience rows are never returned: that is enforced by RLS, not here.
      List<String>? joined;
      if (widget.joinedOnly) {
        final uid = sb.auth.currentUser?.id;
        final m = uid == null ? [] : await sb.from('channel_members').select('channel_id').eq('user_id', uid);
        joined = [for (final r in m) r['channel_id'] as String];
        if (joined.isEmpty) { _more = false; _fetching = false; if (mounted) setState(() => _loading = false); return; }
      }
      // !inner so a category filter really filters the posts (not just the embedded channel).
      final ch = widget.category != null ? 'channels!inner(name,category)' : 'channels(name,category)';
      var q = sb.from('posts').select('id,title,description,created_at,channel_id,$ch,post_items(id,thumbnail_key,is_premium,duration_s,position,bunny_video_id,processing_status)');
      if (widget.channelId != null) q = q.eq('channel_id', widget.channelId!);
      if (widget.category != null) q = q.eq('channels.category', widget.category!);
      if (joined != null) q = q.inFilter('channel_id', joined);
      if (widget.query.trim().isNotEmpty) q = q.ilike('title', '%${widget.query.trim().replaceAll('%', '')}%');
      final data = await q.order('created_at', ascending: false).range(_rows.length, _rows.length + _page - 1);
      if (gen != _gen) return; // a newer search/filter replaced this one
      final fresh = List<Map<String, dynamic>>.from(data);
      _rows.addAll(fresh);
      await _signThumbs(fresh);
      if (gen != _gen) return;
      _more = data.length == _page;
    } catch (_) {
      if (gen == _gen) _more = false;
    }
    if (gen != _gen) return;
    _fetching = false;
    if (mounted) setState(() => _loading = false);
  }

  Map? _first(Map<String, dynamic> r) {
    final items = (r['post_items'] as List?) ?? const [];
    if (items.isEmpty) return null;
    final sorted = [...items]..sort((a, b) => ((a as Map)['position'] as int? ?? 0).compareTo((b as Map)['position'] as int? ?? 0));
    return sorted.first as Map;
  }

  /// Short-lived links for the thumbnails on this page. Posts without a thumbnail just show the placeholder.
  Future<void> _signThumbs(List<Map<String, dynamic>> rows) async {
    final keys = <String>{
      for (final r in rows)
        if (_first(r)?['thumbnail_key'] is String) _first(r)!['thumbnail_key'] as String,
    }..removeAll(_thumbs.keys);
    for(final row in rows) {
      final item=_first(row);
      if(item?['bunny_video_id']!=null && item?['thumbnail_key']==null) {
        try {final url=await BunnyMedia.playback(item!['id'] as String,thumbnail:true);if(url!=null)_thumbs['bunny:${item['id']}']=url;}catch(_){/* Processing thumbnail not ready. */}
      }
    }
    if (keys.isEmpty) return;
    try {
      final res = await sb.storage.from('media').createSignedUrls(keys.toList(), 3600);
      for (final e in res) {
        final k = e.path as String?;
        if (k != null && e.signedUrl.isNotEmpty) _thumbs[k] = e.signedUrl;
      }
    } catch (_) {/* cards fall back to the placeholder */}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _rows.isEmpty) {
      return VideoGrid(itemCount: 6, itemBuilder: (_, __) => const _Skeleton());
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: _rows.isEmpty
          ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [const SizedBox(height: 40), EmptyState(icon: Icons.video_library_outlined, title: widget.query.isNotEmpty ? 'No results' : 'No posts yet', message: widget.query.isNotEmpty ? 'Try a different word.' : 'New videos will show up here.')])
          : VideoGrid(
              itemCount: _rows.length + (_more ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _rows.length) {
                  WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _load(); });
                  return const Center(child: CircularProgressIndicator());
                }
                final post = _rows[i];
                final first = _first(post);
                return VideoCard(
                  title: post['title'] as String? ?? '',
                  channel: widget.joinedOnly ? ((post['channels'] as Map?)?['name'] as String? ?? '') : '',
                  url: _thumbs[first?['thumbnail_key']] ?? _thumbs['bunny:${first?['id']}'],
                  seconds: first?['duration_s'] as int?,
                  premium: ((post['post_items'] as List?) ?? []).any((item) => item['is_premium'] == true),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostPage(postId: post['id'] as String))),
                );
              },
            ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) => AspectRatio(aspectRatio: 2 / 3, child: Container(decoration: BoxDecoration(color: Tokens.surface, borderRadius: BorderRadius.circular(14))));
}

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  String? _cat;
  String _q = '';
  static const cats = ['Movies', 'Music', 'Education', 'Gaming', 'Lifestyle', 'Tech', 'Other'];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
        child: Row(children: [
          const Expanded(child: Text('Explore', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
          if (app.showPremiumEntry)
            IconButton(
              tooltip: 'Premium',
              icon: const Icon(Icons.workspace_premium, color: Tokens.gold),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen())),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: TextField(
          key: const Key('explore_search'),
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: 'Search videos', prefixIcon: Icon(Icons.search), isDense: true),
          onSubmitted: (v) {setState(() => _q = v);if(v.trim().isNotEmpty)Measurement.instance.track('SearchUsed');},
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          for (final c in [null, ...cats])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              child: ChoiceChip(visualDensity: VisualDensity.compact, label: Text(c ?? 'All', style: const TextStyle(fontSize: 13)), selected: _cat == c, onSelected: (_) => setState(() => _cat = c)),
            ),
        ]),
      ),
      Expanded(child: PostList(category: _cat, query: _q)),
    ]);
  }
}


