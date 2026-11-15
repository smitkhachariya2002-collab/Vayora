import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/models/status.dart';
import 'package:vayora/services/playback_access.dart';

AppStatus viewer(String source, {bool guest = true, bool paid = false}) => AppStatus({
  'source': source, 'is_guest': guest, 'is_premium': paid, 'can_play_premium': paid,
});

void main() {
  test('ads guests watch free content and premium trailers without login', () {
    expect(playbackAccess(viewer('ads'), premium: false, hasTrailer: false), PlaybackAccess.full);
    expect(playbackAccess(viewer('ads'), premium: true, hasTrailer: true), PlaybackAccess.preview);
    expect(playbackAccess(viewer('ads'), premium: true, hasTrailer: false), PlaybackAccess.subscribe);
  });
  test('organic guests must log in even when they own a plan', () {
    for (final paid in [false, true]) {
      expect(playbackAccess(viewer('organic', paid: paid), premium: false, hasTrailer: false), PlaybackAccess.login);
      expect(playbackAccess(viewer('organic', paid: paid), premium: true, hasTrailer: true), PlaybackAccess.login);
    }
  });
  test('logged-in users can watch free media; full premium needs server entitlement', () {
    for (final source in ['ads', 'organic']) {
      expect(playbackAccess(viewer(source, guest: false), premium: false, hasTrailer: false), PlaybackAccess.full);
      expect(playbackAccess(viewer(source, guest: false, paid: true), premium: true, hasTrailer: true), PlaybackAccess.full);
    }
  });
  test('preview upgrade prompt emits once and rearms only after replay', () {
    final tracker = PreviewEndTracker();
    const end = Duration(seconds: 10);
    expect(tracker.update(position: Duration.zero, duration: Duration.zero, playing: false), false);
    expect(tracker.update(position: const Duration(seconds: 5), duration: end, playing: false), false);
    expect(tracker.update(position: end, duration: end, playing: false), true);
    expect(tracker.update(position: end, duration: end, playing: false), false);
    expect(tracker.update(position: Duration.zero, duration: end, playing: true), false);
    expect(tracker.update(position: end, duration: end, playing: false), true);
    tracker.reset();
    expect(tracker.update(position: end, duration: end, playing: false), true);
  });
}

