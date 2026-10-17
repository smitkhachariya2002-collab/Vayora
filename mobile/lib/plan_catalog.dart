import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Re-fetch visible rows: never merge event payloads that might be stale or hidden.
class PlanCatalog extends ChangeNotifier {
  PlanCatalog(this.db, {this.changes});
  final SupabaseClient db;
  final Stream<void>? changes;
  List<Map<String, dynamic>> rows = [];
  String? selected;
  Object? error;
  bool loaded = false, enabled = true, _disposed = false;
  int _request = 0;
  RealtimeChannel? _channel;
  StreamSubscription<void>? _events;

  void start() {
    if (changes != null) {
      _events = changes!.listen((_) => unawaited(refresh()));
    } else {
      _channel = db
          .channel('premium-plans-${identityHashCode(this)}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'plans',
            callback: (_) => unawaited(refresh()),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'plan_catalog',
            callback: (_) => unawaited(refresh()),
          )
          .onSystemEvents((payload) {
            // Channel join can precede the PostgreSQL listener by a few seconds.
            // Refetch at database readiness to cover edits during that gap.
            if (payload is Map && payload['extension']=='postgres_changes' && payload['status']=='ok') {
              unawaited(refresh());
            }
          })
          .subscribe((status, error) {
            if (status == RealtimeSubscribeStatus.subscribed) {
              unawaited(refresh());
            }
          });
    }
  }

  Future<void> refresh() async {
    if (!enabled || _disposed) return;
    final request = ++_request;
    try {
      final data = await db
          .from('plans')
          .select()
          .eq('active', true)
          .order('position')
          .order('created_at');
      if (_disposed || request != _request) return;
      rows = data.where((p) => p['active'] != false).toList();
      if (!rows.any((p) => p['id'] == selected)) selected = null;
      error = null;
      loaded = true;
      notifyListeners();
    } catch (e) {
      if (_disposed || request != _request) return;
      error = e;
      loaded = true;
      notifyListeners();
    }
  }

  void select(String id) {
    if (rows.any((p) => p['id'] == id)) {
      selected = id;
      notifyListeners();
    }
  }

  void clear() {
    ++_request;
    rows = [];
    selected = null;
    loaded = false;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_request;
    unawaited(_events?.cancel());
    final channel = _channel;
    if (channel != null) unawaited(db.removeChannel(channel));
    super.dispose();
  }
}
