// lib/features/assigned_work/data/assigned_work_repository.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/assigned_work_item.dart';

class AssignedWorkRepository {
  final SupabaseClient _supabase;
  static const String _kLocalCacheKey = 'assigned_work_local_cache_v1';

  AssignedWorkRepository(this._supabase);

  // ─── FETCH FOR DATE RANGE (CALENDAR) ───────────────────────────────────────

  Future<List<AssignedWorkItem>> fetchWorkItems({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _supabase.from('assigned_work').select('*');

      if (startDate != null) {
        final startStr = DateFormat('yyyy-MM-dd').format(startDate);
        // Include tasks in range OR any pending tasks from the past (so they roll over into the active calendar)
        query = query.or('task_date.gte.$startStr,status.eq.pending');
      }
      if (endDate != null) {
        final endStr = DateFormat('yyyy-MM-dd').format(endDate);
        query = query.lte('task_date', endStr);
      }

      final res = await query.order('task_date', ascending: true).order('created_at', ascending: false);
      final List<dynamic> list = res as List<dynamic>;
      final items = list.map((e) => AssignedWorkItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();

      // Update local cache
      await _cacheLocal(items);
      return items;
    } catch (e) {
      debugPrint('AssignedWorkRepository.fetchWorkItems Supabase error: $e');
      // Graceful fallback to local cache
      return _readFromLocalCache();
    }
  }

  // ─── FETCH TODAY'S TASKS FOR A USER (POPUP ON OPEN) ────────────────────────

  Future<List<AssignedWorkItem>> fetchTodayTasksForUser(String userId) async {
    try {
      final res = await _supabase
          .from('assigned_work')
          .select('*')
          .eq('assigned_to_user_id', userId)
          .order('status', ascending: true)
          .order('priority', ascending: false);

      final List<dynamic> list = res as List<dynamic>;
      return list.map((e) => AssignedWorkItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (e) {
      debugPrint('AssignedWorkRepository.fetchTodayTasksForUser error: $e');
      final allLocal = await _readFromLocalCache();
      return allLocal.where((it) {
        return it.assignedToUserId == userId;
      }).toList();
    }
  }

  // ─── CREATE WORK ───────────────────────────────────────────────────────────

  Future<AssignedWorkItem> createWorkItem(AssignedWorkItem item) async {
    final payload = item.toJson();
    if (payload['id'] == null || payload['id'].toString().isEmpty) {
      payload.remove('id');
    }

    try {
      final res = await _supabase.from('assigned_work').insert(payload).select().single();
      final created = AssignedWorkItem.fromJson(Map<String, dynamic>.from(res));

      // Append to local cache
      final current = await _readFromLocalCache();
      await _cacheLocal([created, ...current.where((e) => e.id != created.id)]);

      // Send notification for assigned work to assignee (not if self-assigned)
      if (created.assignedToUserId.isNotEmpty && created.assignedToUserId != created.assignedByUserId) {
        try {
          final assigner = created.assignedByUserName.trim().isNotEmpty
              ? created.assignedByUserName.trim()
              : 'Team';
          final cust = (created.customerName != null && created.customerName!.trim().isNotEmpty)
              ? ' for ${created.customerName!.trim()}'
              : '';
          await _supabase.from('notifications').insert({
            'user_id': created.assignedToUserId,
            'title': 'New Work Assigned',
            'body': '$assigner assigned you a task: "${created.title}"$cust.',
            'type': 'assigned',
          });
        } catch (ne) {
          debugPrint('Error inserting notification for assigned work: $ne');
        }
      }

      return created;
    } catch (e) {
      debugPrint('AssignedWorkRepository.createWorkItem error: $e');
      // If offline/table not ready, persist to local cache with generated UUID
      final fallbackItem = item.id.isNotEmpty ? item : item.copyWith();
      final current = await _readFromLocalCache();
      await _cacheLocal([fallbackItem, ...current.where((e) => e.id != fallbackItem.id)]);
      return fallbackItem;
    }
  }

  // ─── UPDATE WORK ───────────────────────────────────────────────────────────

  Future<AssignedWorkItem> updateWorkItem(AssignedWorkItem item) async {
    final payload = item.toJson();
    payload['updated_at'] = DateTime.now().toUtc().toIso8601String();

    try {
      final res = await _supabase
          .from('assigned_work')
          .update(payload)
          .eq('id', item.id)
          .select()
          .single();
      final updated = AssignedWorkItem.fromJson(Map<String, dynamic>.from(res));

      final current = await _readFromLocalCache();
      await _cacheLocal(current.map((e) => e.id == updated.id ? updated : e).toList());
      return updated;
    } catch (e) {
      debugPrint('AssignedWorkRepository.updateWorkItem error: $e');
      final current = await _readFromLocalCache();
      await _cacheLocal(current.map((e) => e.id == item.id ? item : e).toList());
      return item;
    }
  }

  // ─── TOGGLE STATUS ─────────────────────────────────────────────────────────

  Future<AssignedWorkItem> toggleComplete(
    String id,
    bool completed, {
    String? completedByUserId,
    String? completedByUserName,
  }) async {
    final now = DateTime.now();
    final updateData = <String, dynamic>{
      'status': completed ? WorkStatus.completed.value : WorkStatus.pending.value,
      'completed_at': completed ? now.toUtc().toIso8601String() : null,
      'updated_at': now.toUtc().toIso8601String(),
    };
    if (completed) {
      if (completedByUserId != null) updateData['completed_by_user_id'] = completedByUserId;
      if (completedByUserName != null) updateData['completed_by_user_name'] = completedByUserName;
    } else {
      updateData['completed_by_user_id'] = null;
      updateData['completed_by_user_name'] = null;
    }

    try {
      final res = await _supabase
          .from('assigned_work')
          .update(updateData)
          .eq('id', id)
          .select()
          .single();
      final updated = AssignedWorkItem.fromJson(Map<String, dynamic>.from(res));

      final current = await _readFromLocalCache();
      await _cacheLocal(current.map((e) => e.id == updated.id ? updated : e).toList());
      return updated;
    } catch (e) {
      debugPrint('AssignedWorkRepository.toggleComplete error: $e');
      // If table doesn't have completed_by columns, fallback to basic update
      try {
        final basicData = <String, dynamic>{
          'status': completed ? WorkStatus.completed.value : WorkStatus.pending.value,
          'completed_at': completed ? now.toUtc().toIso8601String() : null,
          'updated_at': now.toUtc().toIso8601String(),
        };
        final res = await _supabase
            .from('assigned_work')
            .update(basicData)
            .eq('id', id)
            .select()
            .single();
        var updated = AssignedWorkItem.fromJson(Map<String, dynamic>.from(res));
        if (completed && completedByUserName != null) {
          updated = updated.copyWith(
            completedByUserId: completedByUserId,
            completedByUserName: completedByUserName,
          );
        }
        final current = await _readFromLocalCache();
        await _cacheLocal(current.map((e) => e.id == updated.id ? updated : e).toList());
        return updated;
      } catch (_) {}

      final current = await _readFromLocalCache();
      final existing = current.firstWhere((e) => e.id == id, orElse: () => throw e);
      final updated = existing.copyWith(
        status: completed ? WorkStatus.completed : WorkStatus.pending,
        completedAt: completed ? now : null,
        completedByUserId: completed ? completedByUserId : null,
        completedByUserName: completed ? completedByUserName : null,
        updatedAt: now,
      );
      await _cacheLocal(current.map((e) => e.id == updated.id ? updated : e).toList());
      return updated;
    }
  }

  // ─── DELETE WORK ───────────────────────────────────────────────────────────

  Future<void> deleteWorkItem(String id) async {
    try {
      await _supabase.from('assigned_work').delete().eq('id', id);
    } catch (e) {
      debugPrint('AssignedWorkRepository.deleteWorkItem error: $e');
    }
    final current = await _readFromLocalCache();
    await _cacheLocal(current.where((e) => e.id != id).toList());
  }

  // ─── LOCAL CACHING HELPERS ─────────────────────────────────────────────────

  Future<void> _cacheLocal(List<AssignedWorkItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
      await prefs.setString(_kLocalCacheKey, encoded);
    } catch (_) {}
  }

  Future<List<AssignedWorkItem>> _readFromLocalCache({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kLocalCacheKey);
      if (raw == null || raw.isEmpty) return [];

      final decoded = jsonDecode(raw) as List<dynamic>;
      var items = decoded.map((e) => AssignedWorkItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();

      if (startDate != null) {
        final startZero = DateTime(startDate.year, startDate.month, startDate.day);
        items = items.where((e) => !e.taskDate.isBefore(startZero)).toList();
      }
      if (endDate != null) {
        final endZero = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
        items = items.where((e) => !e.taskDate.isAfter(endZero)).toList();
      }
      return items;
    } catch (_) {
      return [];
    }
  }
}
