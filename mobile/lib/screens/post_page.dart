import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config.dart';
import '../services/app_scope.dart';
import '../services/app_state.dart';
import '../services/playback_access.dart';
import '../services/measurement.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'login_sheet.dart';
import 'premium_screen.dart';

const reportReasons = ['Sexual/nude', 'Violence', 'Hate/harassment', 'Copyright', 'Spam/scam', 'Other'];

class PostPage extends StatefulWidget {
  const PostPage({super.key, required this.postId});
  final String postId;
  @override
  State<PostPage> createState() => _PostPageState();
}

class _PostPageState extends State<PostPage> {
  late String _postId = widget.postId;
  late final List<String> _history = [_postId];
  int _historyIndex = 0;
  List<Map<String, dynamic>> _suggestions = [];
  final Map<String, String> _suggestionThumbs = {};
  Map<String, dynamic>? _post;
  List<Map<String, dynamic>> _items = [];
  VideoPlayerController? _vc;
  String? _error, _poster, _imageUrl;
  bool _opening = false, _trailer = false, _uiFs = false;
  final _previewEnd = PreviewEndTracker();
  bool _premiumPromptOpen = false;
  final Set<int> _progressSent = {};
  bool _mediaPremium=false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _vc?.removeListener(_onPreviewTick);
    _vc?.dispose();
    try { WakelockPlus.disable(); } catch (_) {}
    try { ScreenBrightness().resetScreenBrightness(); } catch (_) {}
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Hides the status and navigation bars while the video fills the screen.
  void _syncUi(bool fs) {
    if (fs == _uiFs) return;
    _uiFs = fs;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(fs ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    });
  }

  /// Full-screen button / back button. The page also goes full screen by itself when the phone is turned sideways.
  Future<void> _toggleFullscreen() async {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (landscape) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    }
  }

  Future<void> _load() async {
    try {
      final p = await sb.from('posts').select('id,title,description,channel_id').eq('id', _postId).maybeSingle();
      final items = await sb.from('post_items').select('id,media_key,trailer_key,thumbnail_key,mime,is_premium,duration_s').eq('post_id', _postId).order('position');
      final tk = items.isEmpty ? null : items.first['thumbnail_key'] as String?;
      final poster = tk == null ? null : await _signed(tk);
      if (!mounted) return;
      setState(() {
        _poster = poster;
        _post = p;
        _items = List<Map<String, dynamic>>.from(items);
        if (p == null) _error = 'This post is not available.';
      });
      if (p != null) {
        Measurement.instance.track('ViewContent',{'screen':'Post'});
        try {
          // RLS enforces approval, channel visibility and audience for every suggestion.
          const fields = 'id,title,channel_id,status,hidden,channels(name),post_items(thumbnail_key,is_premium)';
          final same = await sb.from('posts').select(fields).eq('channel_id', p['channel_id']).neq('id', _postId).eq('status', 'published').eq('hidden', false).order('created_at', ascending: false).limit(6);
          final other = await sb.from('posts').select(fields).neq('channel_id', p['channel_id']).eq('status', 'published').eq('hidden', false).order('created_at', ascending: false).limit(6);
          final keys = <String>{
            for (final video in [...same, ...other])
              for (final item in (video['post_items'] as List? ?? []))
                if (item['thumbnail_key'] is String) item['thumbnail_key'] as String,
          };
          if (keys.isNotEmpty) {
            try {
              final urls = await sb.storage.from('media').createSignedUrls(keys.toList(), 3600);
              for (final url in urls) {
                final String path = url.path;
                _suggestionThumbs[path] = url.signedUrl;
              }
            } catch (_) { /* Poster placeholders remain usable. */ }
          }
          if (mounted) setState(() => _suggestions = List<Map<String, dynamic>>.from([...same, ...other]));
        } catch (_) { /* Recommendations never block playback. */ }
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load this post.');
    }
  }

  /// Signed URL, short-lived. The storage policy decides whether the full file is allowed.
  Future<String?> _signed(String key) async {
    try {
      return await sb.storage.from('media').createSignedUrl(key, 3600);
    } catch (_) {
      return null;
    }
  }

  Future<void> _play(Map<String, dynamic> it) async {
    final app = AppScope.of(context);
    final premium = it['is_premium'] == true;
    var access = playbackAccess(app.status, premium: premium, hasTrailer: it['trailer_key'] != null);
    if (access == PlaybackAccess.login) {
      if (!await requireAccount(context) || !mounted) return;
      access = playbackAccess(app.status, premium: premium, hasTrailer: it['trailer_key'] != null);
      if (access == PlaybackAccess.login) return;
    }
    final allowed = access == PlaybackAccess.full;
    // Ads users who are not premium get the trailer; everyone else without access sees the lock.
    final key = (allowed ? it['media_key'] : it['trailer_key']) as String?;
    if (key == null) {
      _lockedMessage(app);
      return;
    }
    if (_opening) return;
    setState(() => _opening = true);
    final url = await _signed(key);
    if (!mounted) return;
    if (url == null) {
      setState(() => _opening = false);
      _lockedMessage(app);
      return;
    }
    final old = _vc;
    if ((it['mime'] as String? ?? '').startsWith('image/')) {
      setState(() { _vc = null; _imageUrl = url; _opening = false; _trailer = false; });
      await old?.dispose();
      return;
    }
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      if (mounted) {
        setState(() => _opening = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not play this video. Please try again.')));
      }
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    old?.removeListener(_onPreviewTick);
    c.addListener(_onPreviewTick);
    _previewEnd.reset();
    _progressSent.clear();
    _mediaPremium=premium;
    Measurement.instance.track("VideoStart",{"media_type":"video","premium":premium,"preview":premium&&!allowed});
    c.play();
    setState(() { _vc = c; _imageUrl = null; _opening = false; _trailer = premium && !allowed; });
    await old?.dispose();
  }

  Future<void> _switchVideo(String id, {int? historyIndex}) async {
    if (_opening || id == _postId) return;
    final old = _vc;
    setState(() {
      if (historyIndex != null) {
        _historyIndex = historyIndex;
      } else {
        _history.removeRange(_historyIndex + 1, _history.length);
        _history.add(id);
        _historyIndex = _history.length - 1;
      }
      _postId = id;
      _vc = null;
      _post = null;
      _items = [];
      _suggestions = [];
      _poster = null;
      _imageUrl = null;
      _error = null;
      _trailer = false;
      _opening = true;
    });
    old?.removeListener(_onPreviewTick);
    await old?.dispose();
    await _load();
    if (!mounted) return;
    setState(() => _opening = false);
    if (_items.isNotEmpty) await _play(_items.first);
  }

  VoidCallback? get _previous => _historyIndex > 0 && !_opening
      ? () => _switchVideo(_history[_historyIndex - 1], historyIndex: _historyIndex - 1) : null;

  VoidCallback? get _next {
    if (_opening) return null;
    if (_historyIndex + 1 < _history.length) {
      return () => _switchVideo(_history[_historyIndex + 1], historyIndex: _historyIndex + 1);
    }
    final fresh = _suggestions.where((p) => !_history.contains(p['id'])).toList();
    return fresh.isEmpty ? null : () => _switchVideo(fresh.first['id'] as String);
  }

  void _onPreviewTick() {
    final controller = _vc;
    if (!mounted || controller == null) return;
    final duration=controller.value.duration.inMilliseconds;
    if(duration>0){final pct=controller.value.position.inMilliseconds*100/duration;for(final point in [25,50,75,100]){if(pct>=point&&_progressSent.add(point)){Measurement.instance.track("VideoProgress",{"progress":point,"premium":_mediaPremium,"preview":_trailer});}}}
    if(!_trailer)return;
    final value = controller.value;
    if (_previewEnd.update(position: value.position, duration: value.duration, playing: value.isPlaying)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _vc == controller && _trailer) unawaited(_showPremiumPrompt(previewFinished: true));
      });
    }
  }

  Future<void> _showPremiumPrompt({bool previewFinished = false}) async {
    if (!mounted || _premiumPromptOpen) return;
    _premiumPromptOpen = true;
    Measurement.instance.track(previewFinished?"PreviewComplete":"SubscriptionPrompt",{"preview":previewFinished});
    final app = AppScope.of(context);
    final subscribe = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.workspace_premium_rounded, color: Tokens.gold, size: 36),
          const SizedBox(height: 14),
          Text(previewFinished ? 'Preview finished' : 'Premium video', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text('Subscribe to Premium to watch the full video and enjoy uninterrupted viewing.', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          GradientButton(label: app.showPrices ? 'Subscribe to Premium' : 'View Premium', onPressed: () => Navigator.pop(context, true)),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        ]),
      ))),
    );
    _premiumPromptOpen = false;
    if (subscribe == true && mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen()));
      if (mounted) await app.refresh();
    }
  }

  void _lockedMessage(AppState app) {
    if (!mounted) return;
    unawaited(_showPremiumPrompt());
  }

  Future<void> _report() async {
    if (!await requireAccount(context) || !mounted) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('Report'), children: [
        for (final r in reportReasons) SimpleDialogOption(onPressed: () => Navigator.pop(c, r), child: Text(r)),
      ]),
    );
    if (reason == null) return;
    try {
      await sb.rpc('report_content', params: {'p_target_type': 'post', 'p_target_id': _postId, 'p_reason': reason, 'p_details': ''});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks, we will review it.')));
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _block() async {
    if (!await requireAccount(context) || _post == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await sb.from('blocked_channels').upsert({'user_id': sb.auth.currentUser!.id, 'channel_id': _post!['channel_id']});
      messenger.showSnackBar(const SnackBar(content: Text('Channel blocked. You will not see its posts.')));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not block this channel. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _post;
    final vc = _vc;
    final playing = vc != null && vc.value.isInitialized;
    final fs = playing && MediaQuery.orientationOf(context) == Orientation.landscape;
    _syncUi(fs);
    if (fs) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) { if (!didPop) _toggleFullscreen(); },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.expand(child: _Player(controller: vc, title: (p?['title'] as String?) ?? '', fullscreen: true, onFullscreen: _toggleFullscreen, onPrevious: _previous, onNext: _next)),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(p?['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis), actions: [
        IconButton(tooltip: 'Share', icon: const Icon(Icons.share), onPressed: () => Share.share('${Config.websiteUrl}/p/$_postId')),
        PopupMenuButton<String>(
          onSelected: (v) => v == 'report' ? _report() : _block(),
          itemBuilder: (_) => const [PopupMenuItem(value: 'report', child: Text('Report')), PopupMenuItem(value: 'block', child: Text('Block channel'))],
        ),
      ]),
      body: _error != null
          ? Center(child: Text(_error!))
          : p == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: [
                  if (_imageUrl != null)
                    ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(_imageUrl!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(24), child: Text('Could not load this image. Please try again.'))))
                  else if (_vc != null && _vc!.value.isInitialized) ...[
                    _Player(controller: _vc!, title: (p['title'] as String?) ?? '', fullscreen: false, onFullscreen: _toggleFullscreen, onPrevious: _previous, onNext: _next),
                    if (_trailer)
                      Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Tokens.gold.withValues(alpha: .1), borderRadius: BorderRadius.circular(10)),
                        child: const Row(children: [
                          Icon(Icons.workspace_premium, color: Tokens.gold, size: 16),
                          SizedBox(width: 8),
                          Expanded(child: Text('This is the trailer. Go Premium to watch the full video.', style: TextStyle(color: Tokens.gold, fontSize: 12))),
                        ]),
                      ),
                  ] else if (_items.isNotEmpty)
                    GestureDetector(
                      onTap: _opening ? null : () => _play(_items.first),
                      child: Stack(alignment: Alignment.center, children: [
                        VideoThumb(url: _poster, premium: _items.first['is_premium'] == true, seconds: _items.first['duration_s'] as int?),
                        if (_opening)
                          const CircularProgressIndicator()
                        else
                          Container(
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            padding: const EdgeInsets.all(12),
                            child: Icon((_items.first['mime'] as String? ?? '').startsWith('image/') ? Icons.image_outlined : Icons.play_arrow_rounded, size: 42, color: Colors.white, semanticLabel: (_items.first['mime'] as String? ?? '').startsWith('image/') ? 'View image' : 'Play'),
                          ),
                      ]),
                    ),
                  const SizedBox(height: 14),
                  Text((p['title'] as String?) ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  if (((p['description'] as String?) ?? '').isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text(p['description'] as String, style: const TextStyle(color: Tokens.muted, fontSize: 13, height: 1.4))),
                  const SizedBox(height: 14),
                  if (_items.isEmpty && ((p['description'] as String?) ?? '').isEmpty) const EmptyState(icon: Icons.hourglass_empty_rounded, title: 'No video yet', message: 'The creator has not added a video to this post.'),
                  if (_suggestions.isNotEmpty) ...[
                    const Text('Up next', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    VideoGrid(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(top: 8, bottom: 16),
                      itemCount: _suggestions.length,
                      itemBuilder: (_, index) {
                        final video = _suggestions[index];
                        final items = video['post_items'] as List? ?? [];
                        String? thumbnail;
                        for (final item in items) {
                          thumbnail ??= _suggestionThumbs[item['thumbnail_key']];
                        }
                        return VideoCard(
                          title: video['title'] as String? ?? 'Video',
                          channel: video['channel_id'] == p['channel_id'] ? 'From this channel' : ((video['channels'] as Map?)?['name'] as String? ?? 'Another channel'),
                          url: thumbnail,
                          premium: items.any((item) => item['is_premium'] == true),
                          onTap: () => _switchVideo(video['id'] as String),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_items.length > 1) ...[
                    const Text('In this post', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _items.length; i++)
                      Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
                        leading: Icon((_items[i]['mime'] as String? ?? '').startsWith('video') ? Icons.play_circle_outline : Icons.image_outlined, color: Tokens.primary),
                        title: Text('Part ${i + 1}${_items[i]['is_premium'] == true ? ' · Premium' : ''}'),
                        trailing: _items[i]['is_premium'] == true && !AppScope.of(context).status.canPlayPremium
                            ? const Icon(Icons.lock, color: Tokens.gold, semanticLabel: 'Locked')
                            : null,
                        onTap: () => _play(_items[i]),
                      )),
                  ],
                ]),
    );
  }
}

/// Vayora player with accessible transport controls and gesture shortcuts.
/// Swipe sideways to seek, swipe up/down on the left for brightness and on the right for volume,
/// double-tap the sides to skip 10 s, double-tap the middle to pause, hold to play at 2x, lock the controls.
class _Player extends StatefulWidget {
  const _Player({required this.controller, required this.title, required this.fullscreen, required this.onFullscreen, this.onPrevious, this.onNext});
  final VideoPlayerController controller;
  final String title;
  final bool fullscreen;
  final VoidCallback onFullscreen;
  final VoidCallback? onPrevious, onNext;
  @override
  State<_Player> createState() => _PlayerState();
}

enum _Drag { seek, brightness, volume }

class _PlayerState extends State<_Player> {
  bool _show = true, _locked = false, _wasPlaying = false;
  bool _holding = false;
  Timer? _hide, _hintTimer;
  IconData? _hintIcon;
  String? _hintText;
  Size _size = const Size(320, 180);
  Offset _acc = Offset.zero, _p0 = Offset.zero, _tapAt = Offset.zero;
  _Drag? _mode;
  Duration _from = Duration.zero, _target = Duration.zero;
  double _brightness = .5, _volume = 1, _prevSpeed = 1;
  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  VideoPlayerController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _volume = c.value.volume;
    _wasPlaying = c.value.isPlaying;
    _keepAwake(_wasPlaying);
    c.addListener(_onTick);
    _arm();
    _initBrightness();
  }

  @override
  void dispose() {
    c.removeListener(_onTick);
    _keepAwake(false);
    _hide?.cancel();
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _Player oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_onTick);
      c.addListener(_onTick);
      _volume = c.value.volume;
      _wasPlaying = c.value.isPlaying;
      _keepAwake(_wasPlaying);
      _show = true;
      _locked = false;
      _arm();
    }
  }

  Future<void> _initBrightness() async {
    try { _brightness = await ScreenBrightness().current; } catch (_) {}
  }

  void _keepAwake(bool on) {
    try { WakelockPlus.toggle(enable: on); } catch (_) {}
  }

  void _onTick() {
    final p = c.value.isPlaying;
    if (p != _wasPlaying) {
      _wasPlaying = p;
      _keepAwake(p);
    }
  }

  void _arm() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && c.value.isPlaying && !_locked) setState(() => _show = false);
    });
  }

  void _flash(IconData icon, String text, {int ms = 700}) {
    _hintTimer?.cancel();
    setState(() { _hintIcon = icon; _hintText = text; });
    _hintTimer = Timer(Duration(milliseconds: ms), () { if (mounted) setState(() { _hintIcon = null; _hintText = null; }); });
  }

  void _toggleControls() {
    setState(() => _show = !_show);
    if (_show) _arm();
  }

  void _playPause() {
    c.value.isPlaying ? c.pause() : c.play();
    setState(() => _show = true);
    _arm();
  }

  Duration _clamp(Duration t) {
    if (t < Duration.zero) return Duration.zero;
    final d = c.value.duration;
    return t > d ? d : t;
  }

  Future<void> _skip(int seconds) async {
    await c.seekTo(_clamp(c.value.position + Duration(seconds: seconds)));
    _flash(seconds < 0 ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded, '${seconds > 0 ? '+' : ''}$seconds s', ms: 600);
  }

  Future<void> _speed() async {
    _hide?.cancel();
    final next = await showModalBottomSheet<double>(
      context: context,
      builder: (context) => SafeArea(child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.all(20), child: Text('Playback speed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          for (final speed in _speeds)
            ListTile(title: Text(speed == 1 ? 'Normal · 1x' : '${speed}x'),
              trailing: c.value.playbackSpeed == speed ? const Icon(Icons.check_rounded, color: Tokens.accent) : null,
              onTap: () => Navigator.pop(context, speed)),
        ],
      ))),
    );
    if (!mounted) return;
    if (next != null) await c.setPlaybackSpeed(next);
    if (mounted) _arm();
  }

  // ---- gestures ----
  void _panStart(DragStartDetails d) {
    if (_locked) return;
    _p0 = d.localPosition;
    _acc = Offset.zero;
    _mode = null;
  }

  void _panUpdate(DragUpdateDetails d) {
    if (_locked) return;
    _acc += d.delta;
    if (_mode == null) {
      if (_acc.distance < 14) return;
      if (_acc.dx.abs() > _acc.dy.abs()) {
        _mode = _Drag.seek;
        _from = c.value.position;
      } else if (widget.fullscreen) {
        _mode = _p0.dx < _size.width / 2 ? _Drag.brightness : _Drag.volume;
      } else {
        return; // inline: vertical swipes keep scrolling the page
      }
    }
    switch (_mode!) {
      case _Drag.seek:
        final secs = (_acc.dx / _size.width * 90).round();
        _target = _clamp(_from + Duration(seconds: secs));
        final diff = (_target - _from).inSeconds;
        _hintTimer?.cancel();
        setState(() {
          _hintIcon = diff < 0 ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded;
          _hintText = '${diff >= 0 ? '+' : ''}$diff s\n${fmtDuration(_target)}';
        });
      case _Drag.brightness:
        _brightness = (_brightness - d.delta.dy / (_size.height * .8)).clamp(0.02, 1.0);
        try { ScreenBrightness().setScreenBrightness(_brightness); } catch (_) {}
        _flash(Icons.brightness_6_rounded, '${(_brightness * 100).round()}%', ms: 900);
      case _Drag.volume:
        _volume = (_volume - d.delta.dy / (_size.height * .8)).clamp(0.0, 1.0);
        c.setVolume(_volume);
        _flash(_volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, '${(_volume * 100).round()}%', ms: 900);
    }
  }

  void _panEnd(DragEndDetails d) {
    if (_mode == _Drag.seek) {
      c.seekTo(_target);
      _hintTimer?.cancel();
      _hintTimer = Timer(const Duration(milliseconds: 500), () { if (mounted) setState(() { _hintIcon = null; _hintText = null; }); });
    }
    _mode = null;
  }

  void _doubleTap() {
    if (_locked) return;
    final x = _tapAt.dx / _size.width;
    if (x < .35) {
      _skip(-10);
    } else if (x > .65) {
      _skip(10);
    } else {
      _playPause();
    }
  }

  void _holdStart() {
    if (_locked || !c.value.isPlaying) return;
    _holding = true;
    _prevSpeed = c.value.playbackSpeed;
    c.setPlaybackSpeed(2.0);
    _flash(Icons.fast_forward_rounded, '2x', ms: 60000);
  }

  void _holdEnd() {
    if (_holding) {
      _holding = false;
      c.setPlaybackSpeed(_prevSpeed);
      _hintTimer?.cancel();
      setState(() { _hintIcon = null; _hintText = null; });
    }
  }

  Widget _btn(IconData icon, VoidCallback? onTap, {double size = 26, String? label}) => IconButton(
        onPressed: onTap,
        tooltip: label,
        iconSize: size,
        color: Colors.white,
        icon: Icon(icon, semanticLabel: label),
      );

  Widget _controls(VideoPlayerValue v) {
    final ended = v.duration > Duration.zero && v.position >= v.duration && !v.isPlaying;
    return Stack(fit: StackFit.expand, children: [
      const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent, Colors.black87], stops: [0, .45, 1]))),
      if (widget.fullscreen)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Row(children: [
              _btn(Icons.arrow_back_rounded, widget.onFullscreen, label: 'Back'),
              Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))),
              _btn(Icons.lock_open_rounded, () => setState(() { _locked = true; _show = false; }), size: 22, label: 'Lock controls'),
            ]),
          ),
        ),
      Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _btn(Icons.skip_previous_rounded, widget.onPrevious, label: 'Previous video'),
          _btn(Icons.replay_10_rounded, () => _skip(-10), size: 34, label: 'Back 10 seconds'),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(color: Tokens.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
            child: _btn(ended ? Icons.replay_rounded : (v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded), ended ? () { c.seekTo(Duration.zero); c.play(); } : _playPause, size: 44, label: ended ? 'Replay' : (v.isPlaying ? 'Pause' : 'Play')),
          ),
          const SizedBox(width: 12),
          _btn(Icons.forward_10_rounded, () => _skip(10), size: 34, label: 'Forward 10 seconds'),
          _btn(Icons.skip_next_rounded, widget.onNext, label: 'Next video'),
        ]),
      ),
      Positioned(
        left: 4,
        right: 4,
        bottom: 0,
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const SizedBox(width: 8),
              Text('${fmtDuration(v.position)} / ${fmtDuration(v.duration)}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
              const Spacer(),
              TextButton(
                onPressed: _speed,
                style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(44, 32), padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text('${v.playbackSpeed == v.playbackSpeed.roundToDouble() ? v.playbackSpeed.toInt() : v.playbackSpeed}x', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              _btn(widget.fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, widget.onFullscreen, size: 24, label: widget.fullscreen ? 'Exit full screen' : 'Full screen'),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: VideoProgressIndicator(c, allowScrubbing: true, padding: const EdgeInsets.symmetric(vertical: 8), colors: const VideoProgressColors(playedColor: Tokens.primary, bufferedColor: Colors.white24, backgroundColor: Colors.white12)),
            ),
          ]),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        _size = box.biggest;
        return ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: c,
          builder: (context, v, _) {
            final showControls = !_locked && (_show || !v.isPlaying);
            final surface = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onDoubleTapDown: (d) => _tapAt = d.localPosition,
              onDoubleTap: _doubleTap,
              onLongPressStart: (_) => _holdStart(),
              onLongPressEnd: (_) => _holdEnd(),
              onLongPressCancel: _holdEnd,
              onPanStart: widget.fullscreen ? _panStart : null,
              onPanUpdate: widget.fullscreen ? _panUpdate : null,
              onPanEnd: widget.fullscreen ? _panEnd : null,
              onHorizontalDragStart: widget.fullscreen ? null : _panStart,
              onHorizontalDragUpdate: widget.fullscreen ? null : _panUpdate,
              onHorizontalDragEnd: widget.fullscreen ? null : _panEnd,
              child: ColoredBox(
                color: Colors.black,
                child: Stack(fit: StackFit.expand, children: [
                  Center(child: AspectRatio(aspectRatio: v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio, child: VideoPlayer(c))),
                  if (v.isBuffering) const Positioned(top: 12, right: 12, child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Tokens.accent))),
                  AnimatedOpacity(
                    opacity: showControls ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: IgnorePointer(ignoring: !showControls, child: _controls(v)),
                  ),
                  if (_locked)
                    Positioned(
                      left: 12,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: IconButton(onPressed: () { setState(() { _locked = false; _show = true; }); _arm(); }, icon: const Icon(Icons.lock_rounded, color: Colors.white), tooltip: 'Unlock'),
                        ),
                      ),
                    ),
                  if (_hintText != null)
                    Center(
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: .72), borderRadius: BorderRadius.circular(14)),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(_hintIcon, color: Colors.white, size: 28),
                            const SizedBox(height: 4),
                            Text(_hintText!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
            );
            if (widget.fullscreen) return surface;
            // Inline: 16:9 for landscape clips, taller (up to 1:1.2) for portrait clips.
            final double ratio = v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio.clamp(0.7, 2.4).toDouble();
            return ClipRRect(borderRadius: BorderRadius.circular(22), child: AspectRatio(aspectRatio: ratio < 1.2 ? 1.2 : ratio, child: surface));
          },
        );
      });
}


