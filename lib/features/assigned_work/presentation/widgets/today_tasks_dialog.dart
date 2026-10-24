// lib/features/assigned_work/presentation/widgets/today_tasks_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/router/app_router.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../models/assigned_work_item.dart';
import '../../providers/assigned_work_providers.dart';
import 'add_edit_work_dialog.dart';

class TodayTasksDialog extends ConsumerWidget {
  const TodayTasksDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const TodayTasksDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayTasksAsync = ref.watch(todayTasksForCurrentUserProvider);
    final now = DateTime.now();
    final todayStr = DateFormat('EEEE, dd MMMM yyyy').format(now);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 16, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF312E81)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.checklist_rtl_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Today's Assigned Tasks",
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          todayStr,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: todayTasksAsync.when(
                data: (rawTasks) {
                  final profile = ref.watch(currentProfileProvider);
                  final tasks = profile != null
                      ? rawTasks.where((t) => t.assignedToUserId == profile.id).toList()
                      : rawTasks;
                  if (tasks.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: const BoxDecoration(
                                color: Color(0xFFECFDF5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 48,
                                color: Color(0xFF10B981),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'All Clear for Today!',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'You have no pending tasks assigned for today.',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 18),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                AddEditWorkDialog.show(context, date: now);
                              },
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add Task for Today'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4F46E5),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final pendingCount = tasks.where((t) => t.status == WorkStatus.pending).length;
                  final completedCount = tasks.where((t) => t.status == WorkStatus.completed).length;

                  return Column(
                    children: [
                      // Status banner
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        color: const Color(0xFFF8FAFC),
                        child: Row(
                          children: [
                            Text(
                              '$pendingCount Pending',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: Color(0xFFF59E0B),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('•', style: TextStyle(color: Color(0xFF94A3B8))),
                            const SizedBox(width: 8),
                            Text(
                              '$completedCount Completed',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: Color(0xFF10B981),
                              ),
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: () {
                                AddEditWorkDialog.show(context, date: now);
                              },
                              child: const Row(
                                children: [
                                  Icon(Icons.add, size: 16, color: Color(0xFF4F46E5)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Add Task',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Color(0xFF4F46E5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),

                      // Task List
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: tasks.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, idx) {
                            final task = tasks[idx];
                            final isDone = task.status == WorkStatus.completed;

                            Color priorityColor;
                            switch (task.priority) {
                              case WorkPriority.low:
                                priorityColor = const Color(0xFF10B981);
                                break;
                              case WorkPriority.medium:
                                priorityColor = const Color(0xFF3B82F6);
                                break;
                              case WorkPriority.high:
                                priorityColor = const Color(0xFFF59E0B);
                                break;
                              case WorkPriority.urgent:
                                priorityColor = const Color(0xFFEF4444);
                                break;
                            }

                            final now = DateTime.now();
                            final today = DateTime(now.year, now.month, now.day);
                            final taskDay = DateTime(task.taskDate.year, task.taskDate.month, task.taskDate.day);
                            final isPastDayCompleted = isDone && (taskDay.isBefore(today) || (task.completedAt != null && DateTime(task.completedAt!.year, task.completedAt!.month, task.completedAt!.day).isBefore(today)));

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDone ? const Color(0xFFF8FAFC) : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDone ? const Color(0xFFE2E8F0) : const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Checkbox
                                  InkWell(
                                    onTap: isPastDayCompleted
                                        ? () {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Row(
                                                  children: [
                                                    Icon(Icons.lock_outline, color: Colors.white, size: 16),
                                                    SizedBox(width: 8),
                                                    Expanded(child: Text('Cannot undo tasks completed on a previous day.')),
                                                  ],
                                                ),
                                                backgroundColor: Color(0xFFB45309),
                                                behavior: SnackBarBehavior.floating,
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          }
                                        : () {
                                            ref.read(assignedWorkActionsProvider).toggleComplete(task.id, !isDone);
                                          },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      margin: const EdgeInsets.only(top: 2),
                                      decoration: BoxDecoration(
                                        color: isPastDayCompleted
                                            ? const Color(0xFFD1FAE5)
                                            : (isDone ? const Color(0xFF10B981) : Colors.white),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isPastDayCompleted
                                              ? const Color(0xFF6EE7B7)
                                              : (isDone ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
                                          width: 1.8,
                                        ),
                                      ),
                                      child: isDone
                                          ? Icon(isPastDayCompleted ? Icons.lock : Icons.check, size: 14, color: isPastDayCompleted ? const Color(0xFF047857) : Colors.white)
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          task.title,
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: isDone ? Colors.grey.shade400 : const Color(0xFF1E293B),
                                            decoration: isDone ? TextDecoration.lineThrough : null,
                                          ),
                                        ),
                                        if (task.description.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            task.description,
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 12,
                                              color: isDone ? Colors.grey.shade400 : const Color(0xFF64748B),
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            // Priority
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: priorityColor.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                task.priority.displayName,
                                                style: TextStyle(
                                                  fontFamily: 'Inter',
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: priorityColor,
                                                ),
                                              ),
                                            ),
                                            // Due Time
                                            if (task.dueTime != null && task.dueTime!.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF1F5F9),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.access_time, size: 11, color: Color(0xFF64748B)),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      task.dueTimeFormatted ?? task.dueTime!,
                                                      style: const TextStyle(
                                                        fontFamily: 'Inter',
                                                        fontSize: 10,
                                                        color: Color(0xFF475569),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            // Customer
                                            if (task.customerName != null && task.customerName!.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFDF2F8),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  task.customerName!,
                                                  style: const TextStyle(
                                                    fontFamily: 'Inter',
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFFBE185D),
                                                  ),
                                                ),
                                              ),
                                            // Assigned By
                                            if (task.assignedByUserName != task.assignedToUserName)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFEEF2FF),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'From: ${task.assignedByUserName}',
                                                  style: const TextStyle(
                                                    fontFamily: 'Inter',
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w500,
                                                    color: Color(0xFF4338CA),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        if (task.isRolledOver) ...[
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFFBEB),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: const Color(0xFFFDE68A)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.update_rounded, size: 11, color: Color(0xFFD97706)),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Auto-moved from ${DateFormat('dd MMM').format(task.taskDate)}',
                                                  style: const TextStyle(
                                                    fontFamily: 'Inter',
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFFB45309),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        if (isDone && task.completedAt != null) ...[
                                          const SizedBox(height: 6),
                                          Builder(
                                            builder: (context) {
                                              final completerName = (task.completedByUserName != null && task.completedByUserName!.trim().isNotEmpty)
                                                  ? task.completedByUserName!.trim()
                                                  : (task.assignedToUserName.trim().isNotEmpty ? task.assignedToUserName.trim() : task.assignedByUserName.trim());
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFECFDF5),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      isPastDayCompleted ? Icons.lock : Icons.check_circle,
                                                      size: 11,
                                                      color: const Color(0xFF059669),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Completed ${DateFormat('dd MMM, hh:mm a').format(task.completedAt!)}'
                                                      '${completerName.isNotEmpty ? ' by $completerName' : ''}',
                                                      style: const TextStyle(
                                                        fontFamily: 'Inter',
                                                        fontSize: 9.5,
                                                        fontWeight: FontWeight.w600,
                                                        color: Color(0xFF065F46),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(
                  child: Text('Error loading today\'s tasks: $err', style: const TextStyle(color: Colors.red)),
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.go(AppRoutes.assignedWork);
                    },
                    icon: const Icon(Icons.calendar_month, size: 16),
                    label: const Text('Open Calendar View'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF4F46E5),
                      textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Got it', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
