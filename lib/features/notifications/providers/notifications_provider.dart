// lib/features/notifications/providers/notifications_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/app_config.dart';
import '../../../core/models/notification.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../auth/providers/auth_provider.dart';

// Notifications list with realtime subscription
class NotificationsNotifier
    extends StateNotifier<AsyncValue<List<AppNotification>>> {
  final SupabaseClient _supabase;
  final String? _userId;
  RealtimeChannel? _channel;

  NotificationsNotifier(this._supabase, this._userId)
      : super(const AsyncValue.loading()) {
    const supabaseUrl = AppConfig.supabaseUrl;
    if (supabaseUrl.contains('your-project-ref')) {
      state = const AsyncValue.data([]);
      return;
    }
    if (_userId != null) {
      _load();
      _subscribe();
    } else {
      state = const AsyncValue.data([]);
    }
  }

  Future<void> _load() async {
    try {
      final response = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', _userId!)
          .order('created_at', ascending: false)
          .limit(50);

      final seenKeys = <String>{};
      final notifications = <AppNotification>[];
      for (final json in (response as List<dynamic>)) {
        final item = AppNotification.fromJson(json as Map<String, dynamic>);
        final key = '${item.title}_${item.body}_${item.relatedPipelineId ?? ""}';
        if (seenKeys.add(key)) {
          notifications.add(item);
        }
      }

      if (mounted) state = AsyncValue.data(notifications);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _load();

  void _subscribe() {
    _channel = _supabase
        .channel('notifications_$_userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: _userId!,
          ),
          callback: (payload) {
            if (!mounted) return;
            final current = state.value ?? [];

            if (payload.eventType == PostgresChangeEvent.insert) {
              final newNotif = AppNotification.fromJson(payload.newRecord);
              final isDuplicate = current.any((n) =>
                  n.id == newNotif.id ||
                  (n.title == newNotif.title &&
                      n.body == newNotif.body &&
                      n.relatedPipelineId == newNotif.relatedPipelineId));
              if (!isDuplicate) {
                state = AsyncValue.data([newNotif, ...current]);
              }
            } else if (payload.eventType == PostgresChangeEvent.update) {
              final updated = AppNotification.fromJson(payload.newRecord);
              state = AsyncValue.data(
                current.map((n) => n.id == updated.id ? updated : n).toList(),
              );
            } else if (payload.eventType == PostgresChangeEvent.delete) {
              final oldId = payload.oldRecord['id'];
              state = AsyncValue.data(
                current.where((n) => n.id != oldId).toList(),
              );
            }
          },
        )
        .subscribe();
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true}).eq('id', notificationId);

      final current = state.value ?? [];
      state = AsyncValue.data(
        current
            .map((n) => n.id == notificationId ? n.copyWith(isRead: true) : n)
            .toList(),
      );
    } catch (_) {}
  }

  Future<void> markAllAsRead() async {
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', _userId!)
          .eq('is_read', false);

      final current = state.value ?? [];
      state = AsyncValue.data(
        current.map((n) => n.copyWith(isRead: true)).toList(),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

final notificationsNotifierProvider = StateNotifierProvider<
    NotificationsNotifier, AsyncValue<List<AppNotification>>>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  final profile = ref.watch(currentProfileProvider);
  return NotificationsNotifier(supabase, profile?.id);
});

// Unread count for bell icon badge
final unreadNotificationCountProvider = Provider<AsyncValue<int>>((ref) {
  return ref.watch(notificationsNotifierProvider).whenData(
        (notifications) => notifications.where((n) => !n.isRead).length,
      );
});
