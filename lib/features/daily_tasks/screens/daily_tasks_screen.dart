// lib/features/daily_tasks/screens/daily_tasks_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/user_role.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/daily_task_model.dart';
import '../providers/daily_tasks_provider.dart';
import '../widgets/task_form_dialog.dart';
import '../services/daily_tasks_pdf_service.dart';
import '../services/daily_tasks_excel_service.dart';

class DailyTasksScreen extends ConsumerStatefulWidget {
  const DailyTasksScreen({super.key});

  @override
  ConsumerState<DailyTasksScreen> createState() => _DailyTasksScreenState();
}

class _DailyTasksScreenState extends ConsumerState<DailyTasksScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentQuery = ref.read(dailyTaskFilterProvider).searchQuery;
      if (currentQuery.isNotEmpty) {
        ref.read(dailyTaskFilterProvider.notifier).update(
              (state) => state.copyWith(searchQuery: ''),
            );
        ref.read(dailyTasksProvider.notifier).loadTasks();
      }
    });
  }

  void _onSearchChanged() {
    ref.read(dailyTaskFilterProvider.notifier).update(
          (state) => state.copyWith(searchQuery: _searchController.text),
        );
    ref.read(dailyTasksProvider.notifier).loadTasks();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    try {
      ref.read(dailyTaskFilterProvider.notifier).update(
            (state) => state.copyWith(searchQuery: ''),
          );
    } catch (_) {}
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickSpecificDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1E1B4B),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      ref.read(dailyTaskFilterProvider.notifier).update(
            (state) => state.copyWith(dateFilter: 'specific_day', specificDate: picked),
          );
      ref.read(dailyTasksProvider.notifier).loadTasks();
    }
  }

  Future<void> _pickCustomRange(BuildContext context) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: DateTimeRange(
        start: now.subtract(const Duration(days: 7)),
        end: now,
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1E1B4B),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (range != null) {
      ref.read(dailyTaskFilterProvider.notifier).update(
            (state) => state.copyWith(
              dateFilter: 'custom',
              customStartDate: range.start,
              customEndDate: range.end,
            ),
          );
      ref.read(dailyTasksProvider.notifier).loadTasks();
    }
  }

  Future<void> _confirmDelete(BuildContext context, DailyTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('Delete Task?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete this task for "${task.customerName}"?\n\nThis action will be logged as deleted in the audit history.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(dailyTasksProvider.notifier).deleteTask(task.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task marked as deleted'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(dailyTasksProvider);
    final filter = ref.watch(dailyTaskFilterProvider);
    final profile = ref.watch(currentProfileProvider);
    final isWide = MediaQuery.of(context).size.width >= 800;

    final bool isAdmin = profile?.roles.contains(UserRole.admin) == true ||
        profile?.roles.contains(UserRole.manager) == true;
    final bool isSalesHead = profile?.roles.contains(UserRole.salesHead) == true;
    final bool canFilterByUser = isAdmin || isSalesHead;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1E1B4B),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_task_rounded),
        label: const Text(
          'Log Daily Task',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold),
        ),
        onPressed: () async {
          final added = await TaskFormDialog.show(context);
          if (added == true) {
            ref.read(dailyTasksProvider.notifier).loadTasks();
          }
        },
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(dailyTasksProvider.notifier).loadTasks(),
        child: CustomScrollView(
          slivers: [
            // Branded App Bar
            _buildAppBar(context, tasksAsync, filter, profile, canFilterByUser: canFilterByUser),

            // Filter Bar & KPIs
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isWide ? 32 : 16, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // KPI stats row
                    _buildMetricsRow(tasksAsync.value ?? []),
                    const SizedBox(height: 16),

                    // Date Filters Chips Row
                    _buildDateFilters(context, filter),
                    const SizedBox(height: 12),

                    // Search & User/Customer Filter Row
                    _buildSearchAndDropdowns(context, filter, canFilterByUser),
                  ],
                ),
              ),
            ),

            // Tasks List
            tasksAsync.when(
              data: (tasks) {
                if (tasks.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(context),
                  );
                }

                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    isWide ? 32 : 16,
                    4,
                    isWide ? 32 : 16,
                    80, // bottom padding for FAB
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final task = tasks[index];
                        return _buildTaskCard(context, task, profile, isWide);
                      },
                      childCount: tasks.length,
                    ),
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: ShimmerListLoader(itemCount: 4),
                ),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text('Error loading tasks: $e', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => ref.read(dailyTasksProvider.notifier).loadTasks(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    AsyncValue<List<DailyTask>> tasksAsync,
    DailyTaskFilter filter,
    dynamic profile, {
    bool canFilterByUser = false,
  }) {
    final tasks = tasksAsync.value ?? [];

    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      backgroundColor: const Color(0xFF0F172A),
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF1E1B4B),
                    Color(0xFF312E81),
                    Color(0xFF3730A3),
                    Color(0xFF1E3A8A),
                  ],
                ),
              ),
            ),
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: const Icon(Icons.fact_check_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Daily Tasks Completed',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${tasks.length} tasks recorded • ${DateFormat('EEEE, dd MMMM yyyy').format(DateTime.now())}',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        // Export PDF
        IconButton(
          icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
          tooltip: 'Generate PDF Report',
          onPressed: () {
            String? targetPersonName;
            String? targetPersonRole;

            if (filter.selectedUserId != null) {
              final users = ref.read(taskUsersListProvider).value ?? [];
              final target = users.firstWhere(
                (u) => u['id']?.toString() == filter.selectedUserId,
                orElse: () => {},
              );
              if (target.isNotEmpty) {
                targetPersonName = target['full_name']?.toString();
                targetPersonRole = target['role']?.toString().replaceAll('_', ' ');
              } else if (tasks.isNotEmpty) {
                final match = tasks.firstWhere(
                  (t) => t.userId == filter.selectedUserId,
                  orElse: () => tasks.first,
                );
                targetPersonName = match.userName;
                targetPersonRole = match.userRole;
              }
            } else if (!canFilterByUser && profile != null) {
              targetPersonName = profile.fullName;
              targetPersonRole = profile.primaryRole.displayName;
            }

            DailyTasksPdfService.generateAndPreviewPdf(
              context,
              tasks: tasks,
              filter: filter,
              currentUserName: profile?.fullName,
              targetPersonName: targetPersonName,
              targetPersonRole: targetPersonRole,
            );
          },
        ),
        // Export Excel
        IconButton(
          icon: const Icon(Icons.table_chart_outlined, color: Colors.white),
          tooltip: 'Export Excel',
          onPressed: () => DailyTasksExcelService.exportTasksExcel(
            context,
            tasks: tasks,
            filter: filter,
          ),
        ),
        // Refresh
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          tooltip: 'Refresh',
          onPressed: () => ref.read(dailyTasksProvider.notifier).loadTasks(),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildMetricsRow(List<DailyTask> tasks) {
    final now = DateTime.now();
    final todayTasks = tasks.where((t) {
      return t.completedAt.year == now.year &&
          t.completedAt.month == now.month &&
          t.completedAt.day == now.day &&
          !t.isDeleted;
    }).length;

    final uniqueCustomers = tasks
        .where((t) => !t.isDeleted)
        .map((t) => t.customerName.toLowerCase().trim())
        .toSet()
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 24) / 3;
        return Row(
          children: [
            _buildMetricCard(
              title: "Today's Tasks",
              value: todayTasks.toString(),
              icon: Icons.today_rounded,
              color: const Color(0xFF6366F1),
              width: itemWidth,
            ),
            const SizedBox(width: 12),
            _buildMetricCard(
              title: 'Total Tasks',
              value: tasks.where((t) => !t.isDeleted).length.toString(),
              icon: Icons.checklist_rtl_rounded,
              color: const Color(0xFF10B981),
              width: itemWidth,
            ),
            const SizedBox(width: 12),
            _buildMetricCard(
              title: 'Customers Served',
              value: uniqueCustomers.toString(),
              icon: Icons.apartment_rounded,
              color: const Color(0xFFF59E0B),
              width: itemWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilters(BuildContext context, DailyTaskFilter filter) {
    final filters = [
      {'key': 'today', 'label': 'Today'},
      {'key': 'specific_day', 'label': filter.dateFilter == 'specific_day' && filter.specificDate != null
          ? DateFormat('dd MMM').format(filter.specificDate!)
          : 'Specific Day ▾'},
      {'key': 'this_week', 'label': 'This Week'},
      {'key': 'this_month', 'label': 'This Month'},
      {'key': 'this_year', 'label': 'This Year'},
      {'key': 'custom', 'label': filter.dateFilter == 'custom' && filter.customStartDate != null
          ? '${DateFormat('dd MMM').format(filter.customStartDate!)} - ${DateFormat('dd MMM').format(filter.customEndDate!)}'
          : 'Custom Range ▾'},
      {'key': 'all', 'label': 'All Time'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...filters.map((f) {
            final isSelected = filter.dateFilter == f['key'];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  f['label']!,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : const Color(0xFF334155),
                  ),
                ),
                selected: isSelected,
                selectedColor: const Color(0xFF1E1B4B),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected ? const Color(0xFF1E1B4B) : const Color(0xFFCBD5E1),
                  ),
                ),
                onSelected: (selected) {
                  if (!selected) return;
                  final key = f['key']!;
                  if (key == 'specific_day') {
                    _pickSpecificDate(context);
                  } else if (key == 'custom') {
                    _pickCustomRange(context);
                  } else {
                    ref.read(dailyTaskFilterProvider.notifier).update(
                          (state) => state.copyWith(dateFilter: key, clearDate: true),
                        );
                    ref.read(dailyTasksProvider.notifier).loadTasks();
                  }
                },
              ),
            );
          }),

          // Show Deleted Toggle
          FilterChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.delete_outline,
                  size: 14,
                  color: filter.showDeleted ? Colors.white : const Color(0xFF64748B),
                ),
                const SizedBox(width: 4),
                Text(
                  'Show Deleted',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: filter.showDeleted ? FontWeight.bold : FontWeight.w500,
                    color: filter.showDeleted ? Colors.white : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
            selected: filter.showDeleted,
            selectedColor: const Color(0xFFDC2626),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: filter.showDeleted ? const Color(0xFFDC2626) : const Color(0xFFCBD5E1),
              ),
            ),
            onSelected: (selected) {
              ref.read(dailyTaskFilterProvider.notifier).update(
                    (state) => state.copyWith(showDeleted: selected),
                  );
              ref.read(dailyTasksProvider.notifier).loadTasks();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndDropdowns(
    BuildContext context,
    DailyTaskFilter filter,
    bool canFilterByUser,
  ) {
    final usersListAsync = ref.watch(taskUsersListProvider);

    return Row(
      children: [
        // Search Input
        Expanded(
          flex: 2,
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by customer, user, or task description...',
                hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          if (mounted) setState(() {});
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        // Searchable User Filter for Admins / Sales Heads
        if (canFilterByUser) ...[
          const SizedBox(width: 8),
          usersListAsync.when(
            data: (users) {
              final selectedUser = users.firstWhere(
                (u) => u['id']?.toString() == filter.selectedUserId,
                orElse: () => {},
              );
              final hasSelected = filter.selectedUserId != null && selectedUser.isNotEmpty;
              final selectedName = hasSelected
                  ? (selectedUser['full_name']?.toString() ?? 'Selected User')
                  : 'All Users';

              return InkWell(
                onTap: () {
                  _UserPickerSheet.show(
                    context,
                    users: users,
                    initialSelectedId: filter.selectedUserId,
                    onSelected: (u) {
                      ref.read(dailyTaskFilterProvider.notifier).update(
                            (state) => u == null
                                ? state.copyWith(clearUser: true)
                                : state.copyWith(selectedUserId: u['id']?.toString()),
                          );
                      ref.read(dailyTasksProvider.notifier).loadTasks();
                    },
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: hasSelected ? const Color(0xFF1E1B4B).withValues(alpha: 0.08) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasSelected ? const Color(0xFF1E1B4B) : const Color(0xFFCBD5E1),
                      width: hasSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_search_outlined,
                        size: 16,
                        color: hasSelected ? const Color(0xFF1E1B4B) : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 110),
                        child: Text(
                          selectedName,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: hasSelected ? FontWeight.bold : FontWeight.w500,
                            color: hasSelected ? const Color(0xFF1E1B4B) : const Color(0xFF334155),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (hasSelected)
                        GestureDetector(
                          onTap: () {
                            ref.read(dailyTaskFilterProvider.notifier).update(
                                  (state) => state.copyWith(clearUser: true),
                                );
                            ref.read(dailyTasksProvider.notifier).loadTasks();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF1E1B4B),
                            ),
                            child: const Icon(Icons.close, size: 10, color: Colors.white),
                          ),
                        )
                      else
                        const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF64748B)),
                    ],
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],

        // Customer Clear Chip if filtered
        if (filter.customerName != null) ...[
          const SizedBox(width: 10),
          Chip(
            label: Text('Customer: ${filter.customerName}', style: const TextStyle(fontSize: 11)),
            deleteIcon: const Icon(Icons.close, size: 14),
            onDeleted: () {
              ref.read(dailyTaskFilterProvider.notifier).update(
                    (state) => state.copyWith(clearCustomer: true),
                  );
              ref.read(dailyTasksProvider.notifier).loadTasks();
            },
            backgroundColor: const Color(0xFFEEF2FF),
            side: const BorderSide(color: Color(0xFFC7D2FE)),
          ),
        ],
      ],
    );
  }

  Widget _buildTaskCard(
    BuildContext context,
    DailyTask task,
    dynamic profile,
    bool isWide,
  ) {
    final bool isManagerOnly = profile?.roles.contains(UserRole.manager) == true &&
        profile?.roles.contains(UserRole.admin) != true;
    final bool isAdmin = profile?.roles.contains(UserRole.admin) == true;
    final bool isCreator = profile?.id == task.userId;
    final bool canEditOrDelete = !isManagerOnly && (isAdmin || isCreator);

    Color roleColor = const Color(0xFF6366F1);
    if (task.userRole.contains('admin')) {
      roleColor = const Color(0xFF0284C7);
    } else if (task.userRole.contains('sales')) {
      roleColor = const Color(0xFF059669);
    } else if (task.userRole.contains('service') || task.userRole.contains('complaint')) {
      roleColor = const Color(0xFF9333EA);
    } else if (task.userRole.contains('factory')) {
      roleColor = const Color(0xFFD97706);
    } else if (task.userRole.contains('purchase')) {
      roleColor = const Color(0xFFEA580C);
    } else if (task.userRole.contains('boq')) {
      roleColor = const Color(0xFF7C3AED);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: task.isDeleted ? const Color(0xFFFEF2F2) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: task.isDeleted ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Customer Name, Status Badges, Action Menu
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Customer Icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1B4B).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.business_rounded, color: Color(0xFF1E1B4B), size: 20),
                ),
                const SizedBox(width: 12),

                // Customer info & Timestamp
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              task.customerName,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: task.isDeleted ? const Color(0xFF991B1B) : const Color(0xFF0F172A),
                                decoration: task.isDeleted ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                          // Badges
                          if (task.isDeleted)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFFCA5A5)),
                              ),
                              child: const Text(
                                'DELETED',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            )
                          else if (task.isEdited)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFFCD34D)),
                              ),
                              child: const Text(
                                'EDITED',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFD97706),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded, size: 13, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('dd MMM yyyy, hh:mm a').format(task.completedAt),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Edit & Delete Options Menu
                if (canEditOrDelete && !task.isDeleted)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Color(0xFF64748B), size: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (val) {
                      if (val == 'edit') {
                        TaskFormDialog.show(context, taskToEdit: task);
                      } else if (val == 'delete') {
                        _confirmDelete(context, task);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 16, color: Color(0xFF1E1B4B)),
                            SizedBox(width: 8),
                            Text('Edit Task', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                            SizedBox(width: 8),
                            Text('Delete Task', style: TextStyle(fontSize: 13, color: AppColors.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Task Description Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: task.isDeleted ? const Color(0xFFFEE2E2).withValues(alpha: 0.3) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: task.isDeleted ? const Color(0xFFFECACA) : const Color(0xFFF1F5F9),
                ),
              ),
              child: Text(
                task.taskDescription,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13.5,
                  height: 1.45,
                  color: task.isDeleted ? const Color(0xFF7F1D1D) : const Color(0xFF1E293B),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Bottom Row: User Avatar, Name, Role badge, and Edit/Delete audit trail
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: roleColor.withValues(alpha: 0.15),
                  child: Text(
                    task.userName.isNotEmpty ? task.userName[0].toUpperCase() : 'U',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: roleColor),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  task.userName,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    task.userRole.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: roleColor,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const Spacer(),

                // Audit metadata
                if (task.isDeleted && task.deletedAt != null)
                  Text(
                    'Deleted: ${DateFormat('dd MMM, hh:mm a').format(task.deletedAt!)}',
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFFDC2626), fontWeight: FontWeight.w500),
                  )
                else if (task.isEdited && task.editedAt != null)
                  Text(
                    'Edited: ${DateFormat('dd MMM, hh:mm a').format(task.editedAt!)}',
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFFD97706), fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1B4B).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.assignment_turned_in_outlined, size: 54, color: Color(0xFF1E1B4B)),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Completed Tasks Found',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'No tasks match the active filters. Log a task or adjust your date/customer filters.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => TaskFormDialog.show(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Log Completed Task'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E1B4B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> users;
  final String? initialSelectedId;
  final ValueChanged<Map<String, dynamic>?> onSelected;

  const _UserPickerSheet({
    required this.users,
    required this.initialSelectedId,
    required this.onSelected,
  });

  static void show(
    BuildContext context, {
    required List<Map<String, dynamic>> users,
    required String? initialSelectedId,
    required ValueChanged<Map<String, dynamic>?> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _UserPickerSheet(
        users: users,
        initialSelectedId: initialSelectedId,
        onSelected: onSelected,
      ),
    );
  }

  @override
  State<_UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends State<_UserPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.users;
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = widget.users;
      } else {
        _filtered = widget.users.where((u) {
          final name = (u['full_name']?.toString() ?? '').toLowerCase();
          final email = (u['email']?.toString() ?? '').toLowerCase();
          final role = (u['role']?.toString() ?? '').toLowerCase();
          final roles = (u['roles'] is List)
              ? (u['roles'] as List).map((e) => e.toString().toLowerCase()).join(' ')
              : '';
          return name.contains(q) || email.contains(q) || role.contains(q) || roles.contains(q);
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 14),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1B4B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_search_outlined, color: Color(0xFF1E1B4B), size: 20),
                ),
                const SizedBox(width: 10),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filter by User / Employee',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Search and pick any team member',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Search Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by employee name, role, email...',
                hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF64748B)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // "All Users" Option tile (always on top)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                selected: widget.initialSelectedId == null,
                selectedTileColor: const Color(0xFF1E1B4B).withValues(alpha: 0.07),
                leading: CircleAvatar(
                  backgroundColor: widget.initialSelectedId == null
                      ? const Color(0xFF1E1B4B)
                      : Colors.grey.shade200,
                  foregroundColor: widget.initialSelectedId == null
                      ? Colors.white
                      : const Color(0xFF475569),
                  child: const Icon(Icons.people_alt_outlined, size: 18),
                ),
                title: const Text(
                  'All Users / Everyone',
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                subtitle: const Text(
                  "Show all team members' daily tasks",
                  style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF64748B)),
                ),
                trailing: widget.initialSelectedId == null
                    ? const Icon(Icons.check_circle, color: Color(0xFF1E1B4B), size: 20)
                    : null,
                onTap: () {
                  widget.onSelected(null);
                  Navigator.pop(context);
                },
              ),
            ),
          ),
          const Divider(height: 12, color: Color(0xFFF1F5F9)),

          // Users List
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No matching team members found',
                        style: TextStyle(fontFamily: 'Inter', color: Color(0xFF64748B)),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF8FAFC)),
                    itemBuilder: (context, index) {
                      final u = _filtered[index];
                      final id = u['id']?.toString();
                      final isSelected = id == widget.initialSelectedId;
                      final name = u['full_name']?.toString() ?? 'User';
                      final email = u['email']?.toString() ?? '';
                      final role = (u['role']?.toString() ?? '').replaceAll('_', ' ').toUpperCase();
                      final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

                      return ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        selected: isSelected,
                        selectedTileColor: const Color(0xFF1E1B4B).withValues(alpha: 0.08),
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? const Color(0xFF1E1B4B)
                              : const Color(0xFF6366F1).withValues(alpha: 0.12),
                          foregroundColor: isSelected ? Colors.white : const Color(0xFF4F46E5),
                          child: Text(
                            initial,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        title: Text(
                          name,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                        subtitle: Row(
                          children: [
                            if (role.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Text(
                                  role,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (email.isNotEmpty)
                              Expanded(
                                child: Text(
                                  email,
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: Color(0xFF1E1B4B), size: 20)
                            : null,
                        onTap: () {
                          widget.onSelected(u);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
