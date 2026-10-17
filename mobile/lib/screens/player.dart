import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../app_state.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'premium.dart';

class Watch extends StatefulWidget {
  const Watch({
    super.key,
    required this.url,
    required this.trailer,
    required this.isPremium,
    required this.state,
    required this.audience,
    required this.channelAudience,
    required this.createdBy,
    this.title = 'Now playing',
    this.refreshUrl,
  });
  final Future<String> Function()? refreshUrl;
  final String url, title, audience, channelAudience, createdBy;
  final bool trailer, isPremium;
  final AppState state;
  @override
  State<Watch> createState() => _WatchState();
}

class _WatchState extends State<Watch> {
  late VideoPlayerController video;
  bool ended = false, ready = false;
  String? failure;
  int rotation = 0;
  @override
  void initState() {
    super.initState();
    video = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    widget.state.addListener(accessChanged);
    unawaited(prepare());
  }

  void accessChanged() {
    final allowed =
        widget.state.status['is_admin'] == true ||
        widget.state.userId == widget.createdBy ||
        (widget.state.canSee(widget.audience) &&
            widget.state.canSee(widget.channelAudience) &&
            (widget.trailer
                ? widget.state.adsAccess
                : !widget.state.guest &&
                      (!widget.isPremium || widget.state.premium)));
    if (!allowed && mounted) {
      unawaited(video.pause());
      if (ModalRoute.of(context)?.isCurrent == true) Navigator.pop(context);
    }
  }

  Future<void> prepare({Duration resumeAt = Duration.zero}) async {
    try {
      await video.initialize();
      if (!mounted) return;
      video.addListener(checkEnd);
      if (resumeAt > Duration.zero) await video.seekTo(resumeAt);
      await video.play();
      if (mounted) setState(() => ready = true);
    } on Object {
      if (mounted) setState(() => failure = 'Could not play this video.');
    }
  }

  Future<void> retry() async {
    final position = video.value.position;
    video.removeListener(checkEnd);
    unawaited(video.dispose());
    if (!mounted) return;
    setState(() { ready = false; failure = null; ended = false; });
    try {
      final fresh = widget.refreshUrl == null ? widget.url : await widget.refreshUrl!();
      if (!mounted) return;
      video = VideoPlayerController.networkUrl(Uri.parse(fresh));
      await prepare(resumeAt: position);
    } on Object {
      if (mounted) setState(() => failure = 'Could not play this video.');
    }
  }

  void checkEnd() {
    if (!mounted) return;
    if (video.value.hasError && failure == null) {
      setState(() {
        failure = 'Could not play this video.';
        ready = false;
      });
      return;
    }
    if (!widget.trailer || ended || !video.value.isInitialized) return;
    if (video.value.position >= video.value.duration &&
        video.value.duration > Duration.zero) {
      ended = true;
      unawaited(
        showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
            icon: const Icon(
              Icons.movie_outlined,
              size: AppSizes.dialogIcon,
              color: AppColors.primary,
            ),
            title: const Text(
              'Enjoyed the trailer?',
              textAlign: TextAlign.center,
            ),
            content: Text(
              widget.state.premium
                  ? 'You can now play the full video'
                  : widget.state.paidEnabled
                  ? 'Please subscribe to watch the full video'
                  : 'Log in to watch the full video free',
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(dialog);
                  if (await loginGate(context, widget.state) &&
                      mounted &&
                      widget.state.paidEnabled &&
                      !widget.state.premium) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => Plans(state: widget.state),
                      ),
                    );
                  }
                  if (mounted) {
                    await widget.state.refreshStatus();
                    if (mounted) Navigator.pop(context, !widget.state.guest && widget.state.premium);
                  }
                },
                child: const Text('Watch full video'),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> seek(int seconds) async {
    final next = (video.value.position + Duration(seconds: seconds))
        .inMilliseconds
        .clamp(0, video.value.duration.inMilliseconds);
    await video.seekTo(Duration(milliseconds: next));
  }

  Future<void> rotate() async {
    rotation = (rotation + 1) % 3;
    await runAction(context, () async {
      final mode = ['auto', 'landscape', 'portrait'][rotation];
      await const MethodChannel(
        'app/screen',
      ).invokeMethod<void>('rotation', {'mode': mode});
      if (mounted) {
        setState(() {});
        showFeedback(context, 'Rotation: $mode');
      }
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(accessChanged);
    video.removeListener(checkEnd);
    unawaited(video.dispose());
    unawaited(
      const MethodChannel(
        'app/screen',
      ).invokeMethod<void>('rotation', {'mode': 'auto'}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.black,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.s),
            child: Row(
              children: [
                BackButton(onPressed: () => Navigator.pop(context)),
                Expanded(
                  child: Text(
                    widget.trailer ? 'Trailer' : widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip:
                      'Rotation: ${['auto', 'landscape', 'portrait'][rotation]}',
                  onPressed: rotate,
                  icon: const Icon(Icons.screen_rotation),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: failure != null
                  ? SingleChildScrollView(child: ErrorRetry(onRetry: retry))
                  : !ready
                  ? const SkeletonBlock()
                  : AspectRatio(
                      aspectRatio: video.value.aspectRatio,
                      child: VideoPlayer(video),
                    ),
            ),
          ),
          if (ready)
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: video,
              builder: (context, value, _) => Padding(
                padding: const EdgeInsets.all(Gap.l),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (value.isBuffering) const LinearProgressIndicator(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Back 10 seconds',
                          icon: const Icon(Icons.replay_10),
                          onPressed: () => seek(-10),
                        ),
                        const SizedBox(width: Gap.xl),
                        IconButton.filled(
                          tooltip: value.isPlaying ? 'Pause' : 'Play',
                          iconSize: AppSizes.dialogIcon,
                          icon: Icon(
                            value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          onPressed: () =>
                              value.isPlaying ? video.pause() : video.play(),
                        ),
                        const SizedBox(width: Gap.xl),
                        IconButton(
                          tooltip: 'Forward 10 seconds',
                          icon: const Icon(Icons.forward_10),
                          onPressed: () => seek(10),
                        ),
                      ],
                    ),
                    Slider(
                      value: value.position.inMilliseconds
                          .clamp(0, value.duration.inMilliseconds)
                          .toDouble(),
                      max: value.duration.inMilliseconds > 0
                          ? value.duration.inMilliseconds.toDouble()
                          : 1,
                      semanticFormatterCallback: (value) =>
                          durationLabel(value / 1000),
                      onChanged: (value) =>
                          video.seekTo(Duration(milliseconds: value.round())),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(durationLabel(value.position.inSeconds)),
                        Text(durationLabel(value.duration.inSeconds)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
