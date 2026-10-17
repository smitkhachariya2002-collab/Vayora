import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class NewPost extends StatefulWidget {
  const NewPost({super.key, required this.state, required this.channel});
  final AppState state;
  final Map<String, dynamic> channel;
  @override
  State<NewPost> createState() => _NewPostState();
}
class _NewPostState extends State<NewPost> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(), description = TextEditingController();
  Uint8List? photo;
  bool busy = false, picking = false, premium = false;
  String? failure;
  @override
  void dispose() { title.dispose(); description.dispose(); super.dispose(); }
  Future<void> pick() async {
    setState(() => picking = true);
    try {
      final bytes = await const MethodChannel('app/photo').invokeMethod<Uint8List>('pick');
      if (bytes != null && bytes.length > 5 * 1024 * 1024) throw StateError('Image too large');
      if (bytes != null && mounted) setState(() => photo = bytes);
    } on Object {
      if (mounted) setState(() => failure = 'Could not open that photo. Please choose another.');
    } finally { if (mounted) setState(() => picking = false); }
  }
  Future<void> save() async {
    if (busy || picking || !form.currentState!.validate()) return;
    if (photo == null) { setState(() => failure = 'Choose a photo for your post.'); return; }
    setState(() { busy = true; failure = null; });
    final state = widget.state, id = const Uuid().v4();
    final key = '${state.userId}/$id/${const Uuid().v4()}.jpg';
    bool draftCreated = false, committed = false;
    String? thumbnail;
    try {
      final channel = await state.db.from('channels').select('id,created_by,review_status,status,audience')
        .eq('id', widget.channel['id']).eq('created_by', state.userId).single();
      if (state.guest || channel['review_status'] != 'approved' || channel['status'] != 'active') {
        throw StateError('Channel is not available for upload');
      }
      await state.db.from('posts').insert({'id': id, 'channel_id': channel['id'], 'created_by': state.userId,
        'title': title.text.trim(), 'description': description.text.trim(), 'audience': channel['audience'], 'status': 'draft'});
      draftCreated = true;
      await state.db.storage.from('media').uploadBinary(key, photo!, fileOptions: const FileOptions(contentType: 'image/jpeg'));
      final codec = await ui.instantiateImageCodec(photo!, targetWidth: 320);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose(); codec.dispose();
      if (data == null) throw StateError('Thumbnail unavailable');
      thumbnail = '${state.userId}/$id/thumbnail.png';
      await state.db.storage.from('public').uploadBinary(thumbnail, data.buffer.asUint8List(),
        fileOptions: const FileOptions(contentType: 'image/png'));
      await state.db.from('post_items').insert({'post_id': id, 'media_key': key, 'thumbnail_key': thumbnail, 'mime': 'image/jpeg', 'is_premium': premium, 'position': 0});
      await state.db.from('posts').update({'status': 'published'}).eq('id', id).eq('created_by', state.userId).select('id').single();
      committed = true;
      if (mounted) { showFeedback(context, 'Your post is published.'); Navigator.maybePop(context); }
    } on Object {
      if (!committed && draftCreated) {
        // Keep the draft if media cleanup fails so a retry can still be managed.
        try {
          await state.db.storage.from('media').remove([key]);
          if (thumbnail != null) await state.db.storage.from('public').remove([thumbnail]);
          await state.db.from('posts').delete().eq('id', id).eq('created_by', state.userId);
        } on Object { /* Failed uploads remain unpublished. */ }
      }
      if (mounted) setState(() => failure = 'Could not publish. Your details are still here. Check your connection and channel status, then retry.');
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !busy, child: AppPage(title: 'New post',
    body: PageWidth(form: true, child: Form(key: form, child: ListView(padding: Gap.page, children: [
      Text(widget.channel['name'] as String, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      if (photo != null) ClipRRect(borderRadius: Radii.cardRadius, child: Image.memory(photo!, height: 200, fit: BoxFit.cover)),
      OutlinedButton.icon(onPressed: busy || picking ? null : pick, icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(picking ? 'Opening photos…' : photo == null ? 'Choose photo' : 'Change photo')),
      const Text('Photo posts use the existing device photo picker.'),
      const SizedBox(height: 16),
      TextFormField(controller: title, enabled: !busy, maxLength: 160, decoration: const InputDecoration(labelText: 'Title'),
        validator: (v) => v == null || v.trim().isEmpty ? 'Enter a title' : null),
      const SizedBox(height: 16),
      TextFormField(controller: description, enabled: !busy, minLines: 3, maxLines: 5, maxLength: 2000,
        decoration: const InputDecoration(labelText: 'Description (optional)')),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Premium post'), value: premium,
        onChanged: busy ? null : (v) => setState(() => premium = v)),
      if (failure != null) NoticeCard(title: 'Please try again', message: failure!, tone: NoticeTone.danger),
      const SizedBox(height: 24),
      GradientButton(label: busy ? 'Publishing…' : 'Publish post', busy: busy, onPressed: busy || picking ? null : save),
    ])))));
}
