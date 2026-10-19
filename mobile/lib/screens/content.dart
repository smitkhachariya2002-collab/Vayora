import 'package:flutter/material.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/post_card.dart';
import 'post.dart';
import 'channel_detail.dart';

class ContentList extends StatefulWidget {
  const ContentList({
    super.key,
    required this.state,
    this.feed = false,
    this.channel,
    this.creator,
    this.search = '',
    this.horizontal = false,
    this.onExploreChannels,
    this.intro,
  });
  final AppState state;
  final bool feed, horizontal;
  final String? channel, creator;
  final String search;
  final Widget? intro;
  final VoidCallback? onExploreChannels;
  @override
  State<ContentList> createState() => _ContentListState();
}

class _ContentListState extends State<ContentList> {
  final scroll = ScrollController();
  final posts = <Map<String, dynamic>>[];
  late Future<List<Map<String, dynamic>>> channels;
  bool loading = false, hasMore = true;
  String? failure;
  String category = 'All', fingerprint = '';
  int offset = 0, request = 0;
  bool get explore =>
      !widget.feed &&
      widget.channel == null &&
      widget.creator == null &&
      !widget.horizontal;
  String get accessKey =>
      '${widget.state.userId}:${widget.state.adsAccess}:${widget.state.status['source']}:${widget.state.status['is_admin']}:${widget.state.membershipRevision}';
  @override
  void initState() {
    super.initState();
    fingerprint = accessKey;
    channels = loadChannels();
    scroll.addListener(more);
    load(refresh: true);
  }

  @override
  void didUpdateWidget(covariant ContentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (fingerprint != accessKey ||
        oldWidget.feed != widget.feed ||
        oldWidget.channel != widget.channel ||
        oldWidget.creator != widget.creator ||
        oldWidget.search != widget.search) {
      fingerprint = accessKey;
      channels = loadChannels();
      load(refresh: true);
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void more() {
    if (scroll.hasClients && scroll.position.extentAfter < AppSizes.mediaHero) {
      load();
    }
  }

  Future<List<Map<String, dynamic>>> loadChannels() => widget.state.db
      .from('channels')
      .select()
      .eq('review_status', 'approved')
      .inFilter('status', ['published', 'active'])
      .order('created_at', ascending: false)
      .limit(AppSizes.pageSize);
  Future<void> load({bool refresh = false}) async {
    if (!refresh && (loading || !hasMore)) return;
    final current = ++request;
    setState(() {
      loading = true;
      failure = null;
      if (refresh) offset = 0;
    });
    try {
      List<String>? joined;
      if (widget.feed) {
        final memberships = await widget.state.db
            .from('channel_members')
            .select('channel_id')
            .eq('user_id', widget.state.userId);
        joined = memberships.map((row) => row['channel_id'] as String).toList();
      }
      List<Map<String, dynamic>> next = [];
      if (widget.search.trim().isNotEmpty || category != 'All') {
        final result = await widget.state.db.rpc(
          'search_posts',
          params: {
            'query_text': widget.search.trim(),
            'category_filter': category == 'All' ? null : category,
            'channel_filter': widget.channel,
            'creator_filter': widget.creator,
            'joined_only': widget.feed,
            'page_offset': offset,
            'page_size': AppSizes.pageSize,
          },
        );
        next = (result as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
      } else if (joined == null || joined.isNotEmpty) {
        var query = widget.state.db
            .from('posts')
            .select(
              '*,post_items(*),channels(audience,name,icon_url,category,tags)',
            );
        if (widget.channel != null) {
          query = query.eq('channel_id', widget.channel!);
        }
        if (widget.creator != null) {
          query = query.eq('created_by', widget.creator!);
        }
        if (joined != null) query = query.inFilter('channel_id', joined);
        next = await query
            .order('created_at', ascending: false)
            .range(offset, offset + AppSizes.pageSize - 1);
      }
      if (!mounted || current != request) return;
      setState(() {
        if (refresh) posts.clear();
        final ids = posts.map((post) => post['id']).toSet();
        posts.addAll(next.where((post) => ids.add(post['id'])));
        offset += next.length;
        hasMore = next.length == AppSizes.pageSize;
        loading = false;
      });
    } on Object {
      if (mounted && current == request) {
        setState(() {
          loading = false;
          failure = "Couldn't load. Check your connection.";
        });
      }
    }
  }

  List<Map<String, dynamic>> get visible {
    return posts.where((post) {
      if (widget.state.blocked.contains(post['channel_id'])) return false;
      final channel = post['channels'] as Map? ?? {};
      final owns =
          widget.state.status['is_admin'] == true ||
          post['created_by'] == widget.state.userId;
      if (!owns &&
          (!widget.state.canSee(post['audience'] as String? ?? 'all') ||
              !widget.state.canSee(channel['audience'] as String? ?? 'all'))) {
        return false;
      }
      return true;
    }).toList();
  }

  Widget card(Map<String, dynamic> post) {
    final items =
        List<Map<String, dynamic>>.from(post['post_items'] as List? ?? [])
          ..sort(
            (a, b) => ((a['position'] as num?) ?? 0).compareTo(
              (b['position'] as num?) ?? 0,
            ),
          );
    final thumbnail = items.isEmpty
        ? null
        : (items.first as Map)['thumbnail_key'] as String?;
    return PostCard(
      post: post,
      thumbnailUrl: thumbnail == null
          ? null
          : widget.state.db.storage.from('public').getPublicUrl(thumbnail),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => PostPage(state: widget.state, post: post),
          ),
        );
        if (mounted) setState(() {});
      },
    );
  }

  Widget header() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final label in const [
              'All',
              'Entertainment',
              'Music',
              'Learning',
              'Travel',
              'Lifestyle',
            ])
              Padding(
                padding: const EdgeInsets.only(right: Gap.s),
                child: ChoiceChip(
                  label: Text(label),
                  selected: category == label,
                  showCheckmark: false,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: category == label ? AppColors.ink : AppColors.text,
                  ),
                  onSelected: (_) {
                    setState(() => category = label);
                    load(refresh: true);
                  },
                ),
              ),
          ],
        ),
      ),
      FutureBuilder(
        future: channels,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Padding(
              padding: const EdgeInsets.only(top: Gap.l),
              child: SkeletonBlock(
              height:
                  AppSizes.avatarRail *
                  MediaQuery.textScalerOf(context).scale(AppSizes.body) /
                  AppSizes.body,
              ),
            );
          }
          if (snapshot.hasError) {
            return TextButton(
              onPressed: () => setState(() => channels = loadChannels()),
              child: const Text('Try channels again'),
            );
          }
          final rows = (snapshot.data ?? [])
              .where((row) => !widget.state.blocked.contains(row['id']))
              .toList();
          if (rows.isEmpty) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(top: Gap.l),
            child: SizedBox(
            height:
                AppSizes.avatarRail *
                MediaQuery.textScalerOf(context).scale(AppSizes.body) /
                AppSizes.body,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(width: Gap.l),
              itemBuilder: (context, index) {
                final row = rows[index];
                return SizedBox(
                  width: AppSizes.logoLarge,
                  child: PressScale(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ChannelDetail(state: widget.state, channel: row),
                      ),
                    ),
                    child: Column(
                      children: [
                        ChannelAvatar(channel: row),
                        const SizedBox(height: Gap.s),
                        Text(
                          row['name'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            ),
          );
        },
      ),
      const SizedBox(height: Gap.xl),
      const SectionTitle('Latest'),
      const SizedBox(height: Gap.l),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final rows = visible;
    if (widget.horizontal) {
      if (loading && rows.isEmpty) return const SkeletonBlock();
      if (failure != null && rows.isEmpty) {
        return ErrorRetry(onRetry: () => load(refresh: true));
      }
      if (rows.isEmpty) {
        return const EmptyState(
          icon: Icons.movie_outlined,
          title: 'More stories soon',
          message: 'Keep exploring to find something you love.',
        );
      }
      return ListView.separated(
        controller: scroll,
        scrollDirection: Axis.horizontal,
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(width: Gap.l),
        itemBuilder: (context, index) => SizedBox(
          width: AppSizes.postCardWidth,
          child: Align(
            alignment: Alignment.topCenter,
            child: card(rows[index]),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        if (explore) setState(() => channels = loadChannels());
        await load(refresh: true);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= AppSizes.gridBreakpoint
              ? 2
              : 1;
          return CustomScrollView(
            controller: scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: explore
                    ? const EdgeInsets.fromLTRB(Gap.xl, Gap.l, Gap.xl, Gap.xl)
                    : Gap.page,
                sliver: SliverList.list(
                  children: [
                    if (widget.intro != null) widget.intro!,
                    if (explore) header(),
                    if (widget.feed) ...[
                      const SectionTitle('From your channels'),
                      const SizedBox(height: Gap.l),
                    ],
                    if (loading && rows.isEmpty)
                      const SkeletonList()
                    else if (failure != null && rows.isEmpty)
                      ErrorRetry(onRetry: () => load(refresh: true))
                    else if (rows.isEmpty)
                      EmptyState(
                        icon: widget.feed ? Icons.public : Icons.search,
                        title: widget.feed
                            ? 'Your feed starts here'
                            : 'Nothing here yet',
                        message: widget.feed
                            ? 'Join channels to see their posts here'
                            : widget.search.isNotEmpty
                            ? 'Try another search.'
                            : 'Discover a channel or create your own.',
                        actionLabel: widget.feed
                            ? 'Explore channels'
                            : hasMore
                            ? 'Load more'
                            : null,
                        onAction: widget.feed
                            ? widget.onExploreChannels
                            : hasMore
                            ? () => load()
                            : null,
                      ),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
                sliver: SliverList.builder(
                  itemCount: (rows.length / columns).ceil(),
                  itemBuilder: (context, rowIndex) {
                    final start = rowIndex * columns;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: Gap.l),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var column = 0; column < columns; column++) ...[
                            if (column > 0) const SizedBox(width: Gap.l),
                            Expanded(
                              child: start + column < rows.length
                                  ? card(rows[start + column])
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
              SliverPadding(
                padding: Gap.page,
                sliver: SliverToBoxAdapter(
                  child: loading && rows.isNotEmpty
                      ? const SkeletonBlock(height: AppSizes.button)
                      : failure != null
                      ? ErrorRetry(onRetry: () => load())
                      : hasMore && rows.isNotEmpty
                      ? OutlinedButton(
                          onPressed: () => load(),
                          child: const Text('Load more'),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
