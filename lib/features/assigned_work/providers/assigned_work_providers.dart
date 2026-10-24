// lib/features/assigned_work/providers/assigned_work_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/profile.dart';
import '../../../core/models/user_role.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/assigned_work_repository.dart';
import '../models/assigned_work_item.dart';

// ─── REPOSITORY ──────────────────────────────────────────────────────────────

final assignedWorkRepositoryProvider = Provider<AssignedWorkRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return AssignedWorkRepository(supabase);
});

// ─── CALENDAR STATE PROVIDERS ────────────────────────────────────────────────

/// Currently selected date on the calendar (midnight normalized)
final assignedWorkSelectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Currently displayed month (year, month, 1)
final assignedWorkMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

/// Status filter: 'all', 'pending', 'completed'
final assignedWorkStatusFilterProvider = StateProvider<String>((ref) => 'all');

/// User filter: 'all', 'assigned_to_me', 'assigned_by_me'
final assignedWorkUserFilterProvider = StateProvider<String>((ref) => 'all');

/// Search query string
final assignedWorkSearchQueryProvider = StateProvider<String>((ref) => '');

// ─── MONTH TASKS PROVIDER ────────────────────────────────────────────────────

/// Fetches tasks for the active calendar month (with 7-day padding for calendar grid)
/// Visibility: Admin and Sales Head see all tasks; other roles see only tasks added by or assigned to them.
final assignedWorkMonthItemsProvider = FutureProvider<List<AssignedWorkItem>>((ref) async {
  final repo = ref.watch(assignedWorkRepositoryProvider);
  final month = ref.watch(assignedWorkMonthProvider);
  final currentProfile = ref.watch(currentProfileProvider);

  final startRange = DateTime(month.year, month.month, 1).subtract(const Duration(days: 7));
  final endRange = DateTime(month.year, month.month + 1, 0).add(const Duration(days: 14));

  final items = await repo.fetchWorkItems(startDate: startRange, endDate: endRange);

  if (currentProfile == null) return [];

  final roles = currentProfile.roles;
  final canSeeAll = roles.contains(UserRole.admin) || roles.contains(UserRole.salesHead);

  if (canSeeAll) {
    return items;
  }

  final uid = currentProfile.id;
  return items.where((it) => it.assignedToUserId == uid || it.assignedByUserId == uid).toList();
});

// ─── TASK ROLLOVER & TRACE MAPPING ──────────────────────────────────────────

/// Maps raw tasks to their representation on [targetDate].
/// If a task was not completed on its assigned day:
/// - It automatically moves forward day by day until today (or until the day it was completed).
/// - It leaves a trace (isTrace = true) in gray on each day it moved from.
/// - On today (or day of completion), it appears as the active (or completed) task with isRolledOver = true.
List<AssignedWorkItem> mapTasksForDate(List<AssignedWorkItem> rawItems, DateTime targetDate) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(targetDate.year, targetDate.month, targetDate.day);

  final List<AssignedWorkItem> result = [];

  for (final it in rawItems) {
    final orig = DateTime(it.taskDate.year, it.taskDate.month, it.taskDate.day);
    final isCompleted = it.status == WorkStatus.completed;
    final compDate = it.completedAt != null
        ? DateTime(it.completedAt!.year, it.completedAt!.month, it.completedAt!.day)
        : orig;
    final effectiveCompDate = compDate.isBefore(orig) ? orig : compDate;

    if (orig.isAfter(today)) {
      // Future task: only appears on original date
      if (target.isAtSameMomentAs(orig)) {
        result.add(it.copyWith(isTrace: false, isRolledOver: false, displayDate: target));
      }
    } else if (orig.isAtSameMomentAs(today)) {
      // Today's task: only appears on today
      if (target.isAtSameMomentAs(today)) {
        result.add(it.copyWith(isTrace: false, isRolledOver: false, displayDate: target));
      }
    } else {
      // Past task (orig.isBefore(today))
      if (!isCompleted) {
        // Pending task:
        if (target.isAfter(orig.subtract(const Duration(seconds: 1))) && target.isBefore(today)) {
          // On each past day between orig and yesterday: trace in gray!
          result.add(it.copyWith(isTrace: true, isRolledOver: true, displayDate: target));
        } else if (target.isAtSameMomentAs(today)) {
          // On today: actively moved forward!
          result.add(it.copyWith(isTrace: false, isRolledOver: true, displayDate: target));
        }
      } else {
        // Completed task:
        if (effectiveCompDate.isAfter(orig)) {
          if (target.isAfter(orig.subtract(const Duration(seconds: 1))) && target.isBefore(effectiveCompDate)) {
            // Trace in gray for days it was unfinished before completion
            result.add(it.copyWith(isTrace: true, isRolledOver: true, displayDate: target));
          } else if (target.isAtSameMomentAs(effectiveCompDate)) {
            // Completed on this day
            result.add(it.copyWith(isTrace: false, isRolledOver: true, displayDate: target));
          }
        } else {
          // Completed on the same day it was assigned
          if (target.isAtSameMomentAs(orig)) {
            result.add(it.copyWith(isTrace: false, isRolledOver: false, displayDate: target));
          }
        }
      }
    }
  }

  return result;
}

// ─── FILTERED TASKS FOR SELECTED DATE ────────────────────────────────────────

/// Returns the tasks specifically for the clicked date, matching active filters and rollover traces
final selectedDateTasksProvider = Provider<AsyncValue<List<AssignedWorkItem>>>((ref) {
  final monthItemsAsync = ref.watch(assignedWorkMonthItemsProvider);
  final selectedDate = ref.watch(assignedWorkSelectedDateProvider);
  final statusFilter = ref.watch(assignedWorkStatusFilterProvider);
  final userFilter = ref.watch(assignedWorkUserFilterProvider);
  final searchQuery = ref.watch(assignedWorkSearchQueryProvider).trim().toLowerCase();
  final currentProfile = ref.watch(currentProfileProvider);
  final currentUid = currentProfile?.id ?? '';

  return monthItemsAsync.whenData((rawItems) {
    // 1. Map raw tasks to selected date (including traces and rolled over active tasks)
    final dayItems = mapTasksForDate(rawItems, selectedDate);

    // 2. Filter tasks
    final filtered = dayItems.where((it) {
      // Status filter
      if (statusFilter == 'pending') {
        // In pending filter: show pending active tasks AND traces (which represent unfinished tasks)
        if (it.status != WorkStatus.pending) return false;
      } else if (statusFilter == 'completed') {
        // In completed filter: only show truly completed tasks (not traces)
        if (it.status != WorkStatus.completed || it.isTrace) return false;
      }

      // User filter
      if (userFilter == 'assigned_to_me' && it.assignedToUserId != currentUid) return false;
      if (userFilter == 'assigned_by_me' && it.assignedByUserId != currentUid) return false;

      // Search query
      if (searchQuery.isNotEmpty) {
        final titleMatches = it.title.toLowerCase().contains(searchQuery);
        final descMatches = it.description.toLowerCase().contains(searchQuery);
        final assignedToMatches = it.assignedToUserName.toLowerCase().contains(searchQuery);
        final customerMatches = (it.customerName ?? '').toLowerCase().contains(searchQuery);
        if (!titleMatches && !descMatches && !assignedToMatches && !customerMatches) {
          return false;
        }
      }

      return true;
    }).toList();

    // 3. Move completed tasks to bottom, arrange pending tasks on top as per priority
    return sortTasksByPriorityAndStatus(filtered);
  });
});

int _priorityWeight(WorkPriority priority) {
  switch (priority) {
    case WorkPriority.urgent:
      return 4;
    case WorkPriority.high:
      return 3;
    case WorkPriority.medium:
      return 2;
    case WorkPriority.low:
      return 1;
  }
}

List<AssignedWorkItem> sortTasksByPriorityAndStatus(List<AssignedWorkItem> items) {
  final list = List<AssignedWorkItem>.from(items);
  list.sort((a, b) {
    final aCompleted = a.status == WorkStatus.completed || a.status == WorkStatus.cancelled;
    final bCompleted = b.status == WorkStatus.completed || b.status == WorkStatus.cancelled;
    // 1. Move completed tasks to bottom
    if (aCompleted != bCompleted) {
      return aCompleted ? 1 : -1;
    }
    // 2. Arrange pending tasks on top as per priority (urgent -> high -> medium -> low)
    final pDiff = _priorityWeight(b.priority).compareTo(_priorityWeight(a.priority));
    if (pDiff != 0) return pDiff;

    // 3. Same priority: sort by taskDate
    return a.taskDate.compareTo(b.taskDate);
  });
  return list;
}

// ─── TODAY'S TASKS FOR CURRENT USER (STARTUP POPUP) ──────────────────────────

final todayTasksForCurrentUserProvider = FutureProvider<List<AssignedWorkItem>>((ref) async {
  final currentProfile = ref.watch(currentProfileProvider);
  if (currentProfile == null) return [];

  final repo = ref.watch(assignedWorkRepositoryProvider);
  final rawList = await repo.fetchTodayTasksForUser(currentProfile.id);
  // Map tasks for today so any uncompleted past tasks move to today
  final mapped = mapTasksForDate(rawList, DateTime.now());
  // Show active tasks for today (not traces) assigned strictly to current user
  final activeTasks = mapped.where((t) => !t.isTrace && t.assignedToUserId == currentProfile.id).toList();
  return sortTasksByPriorityAndStatus(activeTasks);
});

// ─── ASSIGNABLE USERS PROVIDER (RULE-BASED PERMISSIONS) ──────────────────────

/// Returns list of profiles that the current user is authorized to assign tasks to:
/// - Admin & Manager: Can assign to ANY staff member.
/// - Sales Head: Can assign ONLY to Sales Persons.
/// - Others: Can only assign to themselves.
final assignableUsersProvider = FutureProvider<List<Profile>>((ref) async {
  final currentProfile = ref.watch(currentProfileProvider);
  if (currentProfile == null) return [];

  final supabase = ref.watch(supabaseClientProvider);
  final roles = currentProfile.roles;
  final isAdminOrManager = roles.contains(UserRole.admin) || roles.contains(UserRole.manager);
  final isSalesHead = roles.contains(UserRole.salesHead);

  if (!isAdminOrManager && !isSalesHead) {
    // Regular users can only assign to themselves
    return [currentProfile];
  }

  try {
    final res = await supabase
        .from('profiles')
        .select('*')
        .eq('is_active', true)
        .order('full_name');

    final List<dynamic> list = res as List<dynamic>;
    final allProfiles = list.map((e) => Profile.fromJson(Map<String, dynamic>.from(e as Map))).toList();

    if (isAdminOrManager) {
      // Admin and Manager can assign to anyone
      return allProfiles;
    }

    if (isSalesHead) {
      // Sales Head can assign ONLY to Sales Person (and Sales Head)
      return allProfiles.where((p) {
        return p.roles.contains(UserRole.sales) || p.roles.contains(UserRole.salesHead);
      }).toList();
    }

    return [currentProfile];
  } catch (e) {
    return [currentProfile];
  }
});

// ─── OPTIONAL CUSTOMER SEARCH PROVIDERS ──────────────────────────────────────

/// Fetches full list of customers according to role permissions:
/// - Admin & Sales Head: see ALL customers
/// - Other roles: see customers created by or assigned to them
final assignableCustomersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final currentProfile = ref.watch(currentProfileProvider);
  if (currentProfile == null) return [];

  final roles = currentProfile.roles;
  final canSeeAll = roles.contains(UserRole.admin) || roles.contains(UserRole.salesHead);

  try {
    var req = supabase.from('customers').select('id, customer_name, phone, address, company_name');
    req = req.isFilter('deleted_at', null);

    if (!canSeeAll) {
      req = req.or('created_by.eq.${currentProfile.id},assigned_to.eq.${currentProfile.id}');
    }

    final res = await req.order('customer_name');
    return List<Map<String, dynamic>>.from(res as List);
  } catch (e) {
    return [];
  }
});

final customerSearchFamilyProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, query) async {
  final supabase = ref.watch(supabaseClientProvider);
  final currentProfile = ref.watch(currentProfileProvider);
  final clean = query.trim();

  final roles = currentProfile?.roles ?? [];
  final canSeeAll = roles.contains(UserRole.admin) || roles.contains(UserRole.salesHead);

  try {
    var req = supabase.from('customers').select('id, customer_name, phone, address, company_name');
    req = req.isFilter('deleted_at', null);

    if (!canSeeAll && currentProfile != null) {
      req = req.or('created_by.eq.${currentProfile.id},assigned_to.eq.${currentProfile.id}');
    }

    if (clean.isNotEmpty) {
      req = req.or('customer_name.ilike.%$clean%,phone.ilike.%$clean%,company_name.ilike.%$clean%');
    }
    final res = await req.order('customer_name').limit(50);
    return List<Map<String, dynamic>>.from(res as List);
  } catch (_) {
    return [];
  }
});

// ─── ASSIGNED WORK ACTIONS / NOTIFIER ────────────────────────────────────────

class AssignedWorkActions {
  final Ref _ref;
  AssignedWorkActions(this._ref);

  Future<void> addWork(AssignedWorkItem item) async {
    final repo = _ref.read(assignedWorkRepositoryProvider);
    await repo.createWorkItem(item);
    _ref.invalidate(assignedWorkMonthItemsProvider);
    _ref.invalidate(todayTasksForCurrentUserProvider);
  }

  Future<void> updateWork(AssignedWorkItem item) async {
    final repo = _ref.read(assignedWorkRepositoryProvider);
    await repo.updateWorkItem(item);
    _ref.invalidate(assignedWorkMonthItemsProvider);
    _ref.invalidate(todayTasksForCurrentUserProvider);
  }

  Future<void> toggleComplete(String id, bool completed) async {
    final repo = _ref.read(assignedWorkRepositoryProvider);
    final profile = _ref.read(currentProfileProvider);
    await repo.toggleComplete(
      id,
      completed,
      completedByUserId: profile?.id,
      completedByUserName: profile?.fullName,
    );
    _ref.invalidate(assignedWorkMonthItemsProvider);
    _ref.invalidate(todayTasksForCurrentUserProvider);
  }

  Future<void> deleteWork(String id) async {
    final repo = _ref.read(assignedWorkRepositoryProvider);
    await repo.deleteWorkItem(id);
    _ref.invalidate(assignedWorkMonthItemsProvider);
    _ref.invalidate(todayTasksForCurrentUserProvider);
  }
}

final assignedWorkActionsProvider = Provider<AssignedWorkActions>((ref) {
  return AssignedWorkActions(ref);
});
