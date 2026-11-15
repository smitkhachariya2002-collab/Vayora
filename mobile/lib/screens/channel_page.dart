import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../services/app_state.dart';
import '../services/measurement.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'explore_screen.dart';
import 'login_sheet.dart';

/// One channel: details, join/leave, its posts. The channel's creator can add posts once it is approved.
class ChannelPage extends StatefulWidget {
  const ChannelPage({super.key, required this.channelId, this.name = ''});
  final String channelId;
  final String name;
  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  Map<String, dynamic>? _ch;
  bool _joined = false, _loading = true, _busy = false;
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await sb.from('channels').select('id,name,description,members_count,review_status,created_by').eq('id', widget.channelId).maybeSingle();
      final uid = sb.auth.currentUser?.id;
      var joined = false;
      if (uid != null && c != null) {
        final m = await sb.from('channel_members').select('channel_id').eq('channel_id', widget.channelId).eq('user_id', uid);
        joined = m.isNotEmpty;
      }
      _ch = c;
      _joined = joined;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  bool get _mine => _ch != null && _ch!['created_by'] != null && _ch!['created_by'] == sb.auth.currentUser?.id;
  bool get _approved => _ch?['review_status'] == 'approved';

  Future<void> _toggle() async {
    if (_busy || !await requireAccount(context) || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final uid = sb.auth.currentUser!.id;
      if (_joined) {
        await sb.from('channel_members').delete().eq('channel_id', widget.channelId).eq('user_id', uid);
      } else {
        await sb.from('channel_members').insert({'channel_id': widget.channelId, 'user_id': uid});
        Measurement.instance.track('ChannelJoined');
      }
      await _load();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not update. Please try again.')));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _newPost() async {
    final done = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => NewPostScreen(channelId: widget.channelId)));
    if (done == true && mounted) {
      setState(() => _rev++);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video submitted for approval. The admin will choose who can see it.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _ch;
    final name = (c?['name'] as String?) ?? widget.name;
    return Scaffold(
      appBar: AppBar(title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      floatingActionButton: _mine && _approved ? FloatingActionButton.extended(key: const Key('new_post'), onPressed: _newPost, icon: const Icon(Icons.add), label: const Text('New post')) : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : c == null
              ? const Center(child: EmptyState(icon: Icons.tv_off_rounded, title: 'Channel not available', message: 'It may have been removed or is still being reviewed.'))
              : Column(children: [
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Tokens.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Tokens.border)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      InitialAvatar(name: name, size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(_approved ? '${c['members_count'] ?? 0} members' : (c['review_status'] == 'rejected' ? 'Not approved' : 'Waiting for approval'), style: const TextStyle(color: Tokens.muted, fontSize: 12)),
                          if (((c['description'] as String?) ?? '').isNotEmpty)
                            Padding(padding: const EdgeInsets.only(top: 6), child: Text(c['description'] as String, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Tokens.muted, fontSize: 13))),
                        ]),
                      ),
                      if (_approved && !_mine)
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 14)),
                          onPressed: _busy ? null : _toggle,
                          child: Text(_joined ? 'Leave' : 'Join'),
                        ),
                    ]),
                  ),
                  if (_mine && !_approved)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Tokens.warning.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
                      child: const Row(children: [
                        Icon(Icons.hourglass_top_rounded, size: 18, color: Tokens.warning),
                        SizedBox(width: 10),
                        Expanded(child: Text('You can add posts after this channel is approved.', style: TextStyle(color: Tokens.muted, fontSize: 13))),
                      ]),
                    ),
                  Expanded(child: PostList(key: ValueKey(_rev), channelId: widget.channelId)),
                ]),
    );
  }
}

String _mimeOf(String ext) => const {
      'mp4': 'video/mp4', 'm4v': 'video/mp4', 'mov': 'video/quicktime', 'mkv': 'video/x-matroska', 'webm': 'video/webm',
      '3gp': 'video/3gpp', 'avi': 'video/x-msvideo',
    }[ext] ?? 'video/mp4';

class NewPostScreen extends StatefulWidget {
  const NewPostScreen({super.key, required this.channelId});
  final String channelId;
  @override
  State<NewPostScreen> createState() => _NewPostScreenState();
}

class _NewPostScreenState extends State<NewPostScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  PlatformFile? _file, _trailer, _thumb;
  bool _premium = false, _busy = false;
  String? _err, _stage;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<PlatformFile?> _choose(FileType type) async {
    try {
      final r = await FilePicker.platform.pickFiles(type: type, withData: false);
      final f = r?.files.single;
      return (f != null && f.path != null) ? f : null;
    } catch (_) {
      if (mounted) setState(() => _err = 'Could not open the file picker.');
      return null;
    }
  }

  Future<void> _pick() async {
    final f = await _choose(FileType.video);
    if (f != null && mounted) setState(() { _file = f; _err = null; });
  }

  Future<void> _pickTrailer() async {
    final f = await _choose(FileType.video);
    if (f != null && mounted) setState(() { _trailer = f; _err = null; });
  }

  Future<void> _pickThumb() async {
    final f = await _choose(FileType.image);
    if (f != null && mounted) setState(() { _thumb = f; _err = null; });
  }

  String _ext(PlatformFile f, String fallback) => f.name.contains('.') ? f.name.split('.').last.toLowerCase() : fallback;
  String _size(PlatformFile f) => '${f.name} · ${(f.size / (1 << 20)).toStringAsFixed(1)} MB';

  Future<void> _publish() async {
    final f = _file;
    if (_title.text.trim().isEmpty) return setState(() => _err = 'Add a title.');
    if (f == null || f.path == null) return setState(() => _err = 'Choose a video.');
    setState(() { _busy = true; _err = null; _stage = 'Uploading video…'; });
    final media = sb.storage.from('media');
    final ext = _ext(f, 'mp4');
    final key = '${widget.channelId}/${const Uuid().v4()}.$ext';
    final uploaded = <String>[];
    try {
      await sb.rpc('accept_consent', params: {'p_policy': 'v1'});
      await media.upload(key, File(f.path!), fileOptions: FileOptions(contentType: _mimeOf(ext)));
      uploaded.add(key);

      String? trailerKey;
      final t = _trailer;
      if (t != null && t.path != null) {
        if (mounted) setState(() => _stage = 'Uploading trailer…');
        final te = _ext(t, 'mp4');
        trailerKey = '${widget.channelId}/${const Uuid().v4()}.$te';
        await media.upload(trailerKey, File(t.path!), fileOptions: FileOptions(contentType: _mimeOf(te)));
        uploaded.add(trailerKey);
      }

      // Thumbnail: the chosen picture, or a frame from the video. A post still publishes if neither works.
      String? thumbKey;
      if (mounted) setState(() => _stage = 'Adding thumbnail…');
      final th = _thumb;
      try {
        if (th != null && th.path != null) {
          final ie = _ext(th, 'jpg');
          thumbKey = '${widget.channelId}/${const Uuid().v4()}.$ie';
          await media.upload(thumbKey, File(th.path!), fileOptions: FileOptions(contentType: ie == 'png' ? 'image/png' : ie == 'webp' ? 'image/webp' : 'image/jpeg'));
          uploaded.add(thumbKey);
        } else {
          // No picture chosen: take a frame from one second into the video.
          final bytes = await vt.VideoThumbnail.thumbnailData(video: f.path!, imageFormat: vt.ImageFormat.JPEG, maxWidth: 720, quality: 80, timeMs: 1000);
          if (bytes != null && bytes.isNotEmpty) {
            thumbKey = '${widget.channelId}/${const Uuid().v4()}.jpg';
            await media.uploadBinary(thumbKey, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
            uploaded.add(thumbKey);
          }
        }
      } catch (_) {
        thumbKey = null;
      }

      if (mounted) setState(() => _stage = 'Submitting…');
      final post = await sb.from('posts').insert({
        'channel_id': widget.channelId,
        'title': _title.text.trim(),
        'description': _desc.text.trim(),
        'status': 'draft',
      }).select('id').single();
      try {
        await sb.from('post_items').insert({
          'post_id': post['id'], 'media_key': key, 'mime': _mimeOf(ext), 'is_premium': _premium, 'size_bytes': f.size,
          'trailer_key': trailerKey, 'thumbnail_key': thumbKey,
        });
      } catch (_) {
        await sb.from('posts').delete().eq('id', post['id'] as String);
        rethrow;
      }
      Measurement.instance.track('VideoUploaded',{'media_type':'video'});
      if (mounted) Navigator.pop(context, true);
      return;
    } on StorageException catch (e) {
      _err = e.statusCode == '413' || e.message.toLowerCase().contains('size') ? 'This file is too large to upload.' : 'Upload failed. Please try again.';
    } on PostgrestException catch (e) {
      _err = e.message;
    } catch (_) {
      _err = 'Could not submit. Check your connection and try again.';
    }
    if (uploaded.isNotEmpty) {
      try { await media.remove(uploaded); } catch (_) {}
    }
    if (mounted) setState(() { _busy = false; _stage = null; });
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Text(t.toUpperCase(), style: const TextStyle(color: Tokens.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .8)),
      );

  @override
  Widget build(BuildContext context) {
    final f = _file, t = _trailer, th = _thumb;
    return Scaffold(
      appBar: AppBar(title: const Text('New post')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        _label('Details'),
        TextField(key: const Key('post_title'), controller: _title, maxLength: 120, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Title')),
        const SizedBox(height: 4),
        TextField(controller: _desc, minLines: 3, maxLines: 5, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Description (optional)', alignLabelWithHint: true)),
        _label('Video'),
        PickTile(
          key: const Key('pick_video'),
          icon: Icons.video_library_outlined,
          title: 'Main video',
          subtitle: f == null ? 'Choose the video to publish' : _size(f),
          chosen: f != null,
          onTap: _busy ? null : _pick,
          onClear: _busy ? null : () => setState(() => _file = null),
        ),
        const SizedBox(height: 8),
        PickTile(
          key: const Key('pick_trailer'),
          icon: Icons.movie_filter_outlined,
          title: 'Trailer / preview',
          badge: 'OPTIONAL',
          subtitle: t == null ? 'A short clip anyone can watch before they join' : _size(t),
          chosen: t != null,
          onTap: _busy ? null : _pickTrailer,
          onClear: _busy ? null : () => setState(() => _trailer = null),
        ),
        const SizedBox(height: 8),
        PickTile(
          key: const Key('pick_thumbnail'),
          icon: Icons.image_outlined,
          title: 'Thumbnail',
          badge: 'OPTIONAL',
          subtitle: th == null ? 'Leave empty and we pick a frame from the video' : th.name,
          chosen: th != null,
          onTap: _busy ? null : _pickThumb,
          onClear: _busy ? null : () => setState(() => _thumb = null),
        ),
        if (th != null && th.path != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(aspectRatio: 16 / 9, child: Image.file(File(th.path!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Tokens.surface))),
            ),
          ),
        _label('Access'),
        Container(
          decoration: BoxDecoration(color: Tokens.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Tokens.border)),
          child: SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(14, 2, 8, 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            secondary: const Icon(Icons.workspace_premium, color: Tokens.gold),
            value: _premium,
            onChanged: _busy ? null : (v) => setState(() => _premium = v),
            title: const Text('Premium video', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(_premium ? 'Only members with a plan can watch. Others see the trailer.' : 'Everyone can watch this video.', style: const TextStyle(color: Tokens.muted, fontSize: 12)),
          ),
        ),
        if (_err != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Tokens.danger.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
            child: Text(_err!, style: const TextStyle(color: Tokens.danger, fontSize: 13)),
          ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(borderRadius: BorderRadius.circular(4), child: const LinearProgressIndicator()),
              const SizedBox(height: 6),
              Text('${_stage ?? 'Working…'} Keep the app open.', style: const TextStyle(color: Tokens.muted, fontSize: 12)),
            ]),
          ),
        const SizedBox(height: 18),
        GradientButton(label: _busy ? 'Submitting…' : 'Submit for approval', onPressed: _busy ? null : _publish),
        const SizedBox(height: 10),
        const Text('Posts must follow the Community Guidelines. Content that breaks them is removed.', textAlign: TextAlign.center, style: TextStyle(color: Tokens.muted, fontSize: 12)),
      ]),
    );
  }
}


