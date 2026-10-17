import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'account_page.dart';
import 'app_state.dart';

List<String> parseChannelTags(String raw) => raw.split(',').map((tag) =>
  tag.trim().replaceFirst(RegExp(r'^#+'), '').trim().toLowerCase()).where((tag) => tag.isNotEmpty).toSet().toList();

class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({super.key, required this.channel, this.radius = 26});
  final Map<String, dynamic> channel;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final url = channel['icon_url'] as String?;
    return CircleAvatar(radius: radius, child: url != null && url.isNotEmpty
      ? ClipOval(child: Image.network(url, width: radius * 2, height: radius * 2, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.groups_outlined)))
      : const Icon(Icons.groups_outlined));
  }
}

class ChannelList extends StatefulWidget {
  const ChannelList({super.key, required this.state, required this.onOpen});
  final AppState state;
  final void Function(Map<String, dynamic>) onOpen;
  @override
  State<ChannelList> createState() => _ChannelListState();
}
class _ChannelListState extends State<ChannelList> {
  late Future<List<Map<String, dynamic>>> rows;
  bool mine = false;
  @override
  void initState() { super.initState(); rows = load(); }
  @override
  void didUpdateWidget(covariant ChannelList oldWidget) { super.didUpdateWidget(oldWidget); rows = load(); }
  Future<List<Map<String, dynamic>>> load() {
    var query = widget.state.db.from('channels').select();
    if (mine) { query = query.eq('created_by', widget.state.userId); }
    else { query = query.eq('review_status', 'approved').eq('status', 'active'); }
    return query.order('created_at', ascending: false).limit(100);
  }
  Future<void> refresh() async {
    final next = load();
    setState(() => rows = next);
    await next;
  }
  Future<void> edit([Map<String, dynamic>? channel]) async {
    if (!await ensureSignedIn(context, widget.state) || !mounted) return;
    final saved = await Navigator.push<bool>(context, MaterialPageRoute<bool>(
      builder: (_) => ChannelEditor(state: widget.state, channel: channel)));
    if (saved == true && mounted) {
      setState(() { mine = true; rows = load(); });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(channel == null ? 'Channel created.' : 'Channel updated.')));
    }
  }
  String statusLabel(Map<String, dynamic> row) => row['review_status'] == 'pending' ? 'Under review' :
    row['review_status'] == 'rejected' ? 'Not published' : row['status'] == 'hidden' ? 'Hidden' : 'Live';
  @override
  Widget build(BuildContext context) => RefreshIndicator(onRefresh: refresh,
    child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(20), children: [
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.campaign_outlined, size: 36),
        const SizedBox(height: 12),
        Text('Your community starts here', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Share what you love. Give your channel a name, a photo and a personality.'),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: () => edit(), icon: const Icon(Icons.add), label: const Text('Create channel')),
      ]))),
      const SizedBox(height: 20),
      SegmentedButton<bool>(segments: const [
        ButtonSegment(value: false, label: Text('Discover')),
        ButtonSegment(value: true, label: Text('My channels')),
      ], selected: {mine}, showSelectedIcon: false, onSelectionChanged: (values) async {
        if (values.single && !await ensureSignedIn(context, widget.state)) return;
        if (mounted) setState(() { mine = values.single; rows = load(); });
      }),
      const SizedBox(height: 16),
      FutureBuilder(future: rows, builder: (context, snapshot) {
        if (snapshot.hasError) return TextButton(onPressed: refresh, child: const Text('Could not load channels. Retry'));
        if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
        final channels = snapshot.data!.where((row) => !widget.state.blocked.contains(row['id'])).toList();
        if (channels.isEmpty) { return Padding(padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(children: [const Icon(Icons.groups_outlined, size: 48), const SizedBox(height: 12),
            Text(mine ? 'You haven’t created a channel yet.' : 'There are no channels to discover yet.'),
            const SizedBox(height: 8), const Text('Create a channel to get started.', textAlign: TextAlign.center)])); }
        return Column(children: channels.map((row) => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16), leading: ChannelAvatar(channel: row),
            title: Text(row['name'] as String),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if ((row['description'] as String? ?? '').isNotEmpty)
                Text(row['description'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
              if ((row['tags'] as List? ?? []).isNotEmpty)
                Text((row['tags'] as List).map((tag) => '#$tag').join(' '), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (mine) Padding(padding: const EdgeInsets.only(top: 6), child: Text(statusLabel(row))),
            ]),
            trailing: row['created_by'] == widget.state.userId
              ? IconButton(tooltip: 'Edit channel', icon: const Icon(Icons.edit_outlined), onPressed: () => edit(row))
              : const Icon(Icons.chevron_right),
            onTap: () => widget.onOpen(row),
          )))).toList());
      }),
    ]),
  );
}

class ChannelEditor extends StatefulWidget {
  const ChannelEditor({super.key, required this.state, this.channel});
  final AppState state;
  final Map<String, dynamic>? channel;
  @override
  State<ChannelEditor> createState() => _ChannelEditorState();
}
class _ChannelEditorState extends State<ChannelEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, description, tags;
  Uint8List? photo;
  bool busy = false, picking = false, removePhoto = false;
  String? failure;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.channel?['name'] as String? ?? '');
    description = TextEditingController(text: widget.channel?['description'] as String? ?? '');
    tags = TextEditingController(text: (widget.channel?['tags'] as List? ?? []).join(', '));
  }
  @override
  void dispose() { name.dispose(); description.dispose(); tags.dispose(); super.dispose(); }
  Future<void> pickPhoto() async {
    setState(() { picking = true; failure = null; });
    try {
      final selected = await const MethodChannel('app/photo').invokeMethod<Uint8List>('pick');
      if (selected != null && mounted) {
        if (selected.length > 5 * 1024 * 1024) throw StateError('Photo too large');
        setState(() { photo = selected; removePhoto = false; });
      }
    } on Object {
      if (mounted) setState(() => failure = 'Could not open this photo. Try another image.');
    } finally { if (mounted) setState(() => picking = false); }
  }
  Future<void> save() async {
    if (busy || form.currentState?.validate() != true) return;
    if (widget.state.guest) { setState(() => failure = 'Log in before creating a channel.'); return; }
    setState(() { busy = true; failure = null; });
    final bucket = widget.state.db.storage.from('public');
    final id = widget.channel?['id'] as String? ?? const Uuid().v4();
    final ownerPrefix = '${widget.state.userId}/channel-photos/';
    String? uploaded;
    var committed = false;
    try {
      String? url = removePhoto ? null : widget.channel?['icon_url'] as String?;
      if (photo != null) {
        uploaded = '$ownerPrefix$id/${const Uuid().v4()}.jpg';
        await bucket.uploadBinary(uploaded, photo!, fileOptions: const FileOptions(contentType: 'image/jpeg', cacheControl: '31536000'));
        url = bucket.getPublicUrl(uploaded);
      }
      final values = {'name': name.text.trim(), 'description': description.text.trim(),
        'tags': parseChannelTags(tags.text), 'icon_url': url};
      if (widget.channel == null) {
        await widget.state.db.from('channels').insert({...values, 'id': id, 'created_by': widget.state.userId});
      } else {
        await widget.state.db.from('channels').update(values).eq('id', id).eq('created_by', widget.state.userId).select('id').single();
      }
      committed = true;
      final previous = widget.channel?['icon_url'] as String?;
      final publicPrefix = bucket.getPublicUrl(ownerPrefix);
      if (previous != null && previous != url && previous.startsWith(publicPrefix)) {
        try { await bucket.remove(['$ownerPrefix${previous.substring(publicPrefix.length)}']); } on Object { /* A saved channel must not fail because old-photo cleanup was unavailable. */ }
      }
      if (mounted) Navigator.pop(context, true);
    } on Object {
      if (uploaded != null && !committed) {
        try { await bucket.remove([uploaded]); } on Object { /* The channel was not saved; cleanup can be retried later. */ }
      }
      if (mounted) setState(() => failure = 'Could not save your channel. Your details are still here; please try again.');
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final preview = photo;
    final oldUrl = removePhoto ? null : widget.channel?['icon_url'] as String?;
    return Scaffold(appBar: AppBar(title: Text(widget.channel == null ? 'Create channel' : 'Edit channel')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600),
        child: Form(key: form, child: ListView(padding: const EdgeInsets.all(24), children: [
          Center(child: CircleAvatar(radius: 52, child: ClipOval(child: preview != null
            ? Image.memory(preview, width: 104, height: 104, fit: BoxFit.cover)
            : oldUrl != null ? Image.network(oldUrl, width: 104, height: 104, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.groups_outlined, size: 48))
            : const Icon(Icons.groups_outlined, size: 48)))),
          TextButton.icon(key: const ValueKey('channel-photo'), onPressed: busy || picking ? null : pickPhoto,
            icon: const Icon(Icons.add_a_photo_outlined), label: Text(picking ? 'Opening photos…' : 'Choose channel photo')),
          if (preview != null || oldUrl != null) TextButton(onPressed: busy ? null : () =>
            setState(() { photo = null; removePhoto = true; }), child: const Text('Remove photo')),
          const SizedBox(height: 16),
          TextFormField(key: const ValueKey('channel-name'), controller: name, enabled: !busy, maxLength: 120,
            textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Channel name'),
            validator: (value) => value == null || value.trim().isEmpty ? 'Enter a channel name' : value.trim().length > 120 ? 'Use 120 characters or fewer' : null),
          const SizedBox(height: 16),
          TextFormField(key: const ValueKey('channel-description'), controller: description, enabled: !busy, maxLength: 2000,
            minLines: 3, maxLines: 5, textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Description (optional)', hintText: 'What is your channel about?')),
          const SizedBox(height: 16),
          TextFormField(key: const ValueKey('channel-tags'), controller: tags, enabled: !busy,
            decoration: const InputDecoration(labelText: 'Tags', hintText: 'music, travel, food', helperText: 'Separate tags with commas. Add up to 10.'),
            onChanged: (_) => setState(() {}),
            validator: (value) { final parsed = parseChannelTags(value ?? '');
              return parsed.length > 10 ? 'Add up to 10 tags' : parsed.any((tag) => tag.length > 30) ? 'Keep each tag within 30 characters' : null; }),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: parseChannelTags(tags.text).take(10).map((tag) => Chip(label: Text('#$tag'))).toList()),
          if (failure != null) Padding(padding: const EdgeInsets.only(top: 16),
            child: Text(failure!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 24),
          FilledButton(key: const ValueKey('channel-submit'), onPressed: busy || picking ? null : save,
            child: Padding(padding: const EdgeInsets.all(12), child: Text(busy ? 'Saving…' : widget.channel == null ? 'Create channel' : 'Save changes'))),
        ])),
      )),
    );
  }
}
