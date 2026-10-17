import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../app_state.dart';
import '../services/device_media.dart';
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
  final form = GlobalKey<FormState>(),
      title = TextEditingController(),
      description = TextEditingController();
  PickedMedia? main, trailer, thumbnail;
  bool busy = false, picking = false, premium = false;
  double progress = 0;
  String? failure, uploading;
  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> pick(String target) async {
    setState(() => picking = true);
    try {
      final file = await PickedMedia.pick(
        kind: target == 'thumbnail'
            ? 'image'
            : target == 'trailer'
            ? 'video'
            : 'media',
      );
      if (file != null && mounted) {
        setState(() {
          if (target == 'main') {
            main = file;
            trailer = null;
          } else if (target == 'trailer') {
            trailer = file;
          } else {
            thumbnail = file;
          }
          failure = null;
        });
      }
    } on Object {
      if (mounted) {
        setState(() => failure = 'Choose a supported file up to 50 MB.');
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> send(
    String bucket,
    String key,
    PickedMedia file,
    String label,
  ) async {
    if (mounted) {
      setState(() {
        uploading = label;
        progress = 0;
      });
    }
    await uploadMedia(widget.state, bucket, key, file, (value) {
      if (mounted) setState(() => progress = value);
    });
  }

  Future<void> save() async {
    if (busy || picking || !form.currentState!.validate()) return;
    final media = main;
    if (media == null) {
      setState(() => failure = 'Choose a video or photo.');
      return;
    }
    final posterPath = thumbnail?.thumbnailPath ?? media.thumbnailPath;
    if (posterPath == null) {
      setState(
        () => failure = 'Could not generate a thumbnail. Please choose one.',
      );
      return;
    }
    setState(() {
      busy = true;
      failure = null;
    });
    final state = widget.state, id = const Uuid().v4();
    var created = false;
    try {
      final channel = await state.db
          .from('channels')
          .select('id,created_by,review_status,status,audience')
          .eq('id', widget.channel['id'])
          .eq('created_by', state.userId)
          .single();
      if (state.guest ||
          channel['review_status'] != 'approved' ||
          channel['status'] != 'active') {
        throw StateError('Channel unavailable');
      }
      await state.db.from('posts').insert({
        'id': id,
        'channel_id': channel['id'],
        'created_by': state.userId,
        'title': title.text.trim(),
        'description': description.text.trim(),
        'audience': channel['audience'],
        'status': 'draft',
      });
      created = true;
      final mainKey = '${state.userId}/$id/main';
      final trailerKey = premium && media.video && trailer != null
          ? '${state.userId}/$id/trailer'
          : null;
      final thumbKey = '${state.userId}/$id/thumbnail.jpg';
      // Register every planned object before upload so cleanup can always find it.
      await state.db.from('post_items').insert({
        'post_id': id,
        'media_key': mainKey,
        'trailer_key': trailerKey,
        'thumbnail_key': thumbKey,
        'mime': media.mime,
        'duration_s': media.duration,
        'is_premium': premium,
        'position': 0,
      });
      await send('media', mainKey, media, 'Main media');
      if (trailerKey != null) {
        await send('media', trailerKey, trailer!, 'Trailer');
      }
      final poster = PickedMedia(
        posterPath,
        'thumbnail.jpg',
        'image/jpeg',
        await File(posterPath).length(),
      );
      await send('public', thumbKey, poster, 'Thumbnail');
      await state.db
          .from('posts')
          .update({'status': 'published'})
          .eq('id', id)
          .eq('created_by', state.userId)
          .select('id')
          .single();
      if (mounted) {
        showFeedback(context, 'Your post is published.');
        Navigator.maybePop(context);
      }
    } on Object {
      if (created) {
        try {
          await state.db.functions.invoke('post-delete', body: {'post_id': id});
        } on Object {
          /* Keep the draft and registered media keys for cleanup retry. */
        }
      }
      if (mounted) {
        setState(
          () => failure =
              'Could not publish. Your details are still here. Check your connection and channel status, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final poster =
        thumbnail?.thumbnailPath ?? thumbnail?.path ?? main?.thumbnailPath;
    return PopScope(
      canPop: !busy,
      child: AppPage(
        title: 'New post',
        body: PageWidth(
          form: true,
          child: Form(
            key: form,
            child: ListView(
              padding: Gap.page,
              children: [
                Text(
                  widget.channel['name'] as String,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                if (poster != null)
                  ClipRRect(
                    borderRadius: Radii.cardRadius,
                    child: Image.file(
                      File(poster),
                      height: 190,
                      fit: BoxFit.cover,
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: busy || picking ? null : () => pick('main'),
                  icon: const Icon(Icons.video_library_outlined),
                  label: Text(
                    main == null
                        ? 'Choose video or photo'
                        : 'Change main media',
                  ),
                ),
                if (main != null)
                  Text('${main!.name} · ${storageLabel(main!.size)}'),
                const SizedBox(height: 16),
                TextFormField(
                  controller: title,
                  enabled: !busy,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a title' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: description,
                  enabled: !busy,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Premium post'),
                  value: premium,
                  onChanged: busy ? null : (v) => setState(() => premium = v),
                ),
                if (premium && main?.video == true)
                  OutlinedButton.icon(
                    onPressed: busy || picking ? null : () => pick('trailer'),
                    icon: const Icon(Icons.movie_outlined),
                    label: Text(
                      trailer == null
                          ? 'Add trailer (optional)'
                          : 'Change trailer',
                    ),
                  ),
                if (premium && trailer != null) Text(trailer!.name),
                OutlinedButton.icon(
                  onPressed: busy || picking ? null : () => pick('thumbnail'),
                  icon: const Icon(Icons.image_outlined),
                  label: Text(
                    thumbnail == null
                        ? 'Choose thumbnail (optional)'
                        : 'Change thumbnail',
                  ),
                ),
                const Text(
                  'A thumbnail is generated automatically when none is chosen. Up to 50 MB per file.',
                ),
                if (busy) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: progress),
                  Text('$uploading · ${(progress * 100).round()}%'),
                ],
                if (failure != null)
                  NoticeCard(
                    title: 'Please try again',
                    message: failure!,
                    tone: NoticeTone.danger,
                  ),
                const SizedBox(height: 24),
                GradientButton(
                  label: busy ? 'Publishing…' : 'Publish post',
                  busy: busy,
                  onPressed: busy || picking ? null : save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
