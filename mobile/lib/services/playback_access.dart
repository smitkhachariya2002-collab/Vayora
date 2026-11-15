import '../models/status.dart';

enum PlaybackAccess { login, full, preview, subscribe }

PlaybackAccess playbackAccess(AppStatus status, {required bool premium, required bool hasTrailer}) {
  if (status.isGuest && status.source == 'organic') return PlaybackAccess.login;
  if (!premium || status.canPlayPremium) return PlaybackAccess.full;
  return hasTrailer ? PlaybackAccess.preview : PlaybackAccess.subscribe;
}

/// Emits once at completion, then rearms when a viewer replays the preview.
class PreviewEndTracker {
  bool _fired = false;
  void reset() => _fired = false;
  bool update({required Duration position, required Duration duration, required bool playing}) {
    if (playing && position < duration - const Duration(seconds: 1)) _fired = false;
    if (!_fired && duration > Duration.zero && position >= duration && !playing) {
      _fired = true;
      return true;
    }
    return false;
  }
}

