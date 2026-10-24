import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/config/app_config.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/models/customer.dart';
import '../../../core/models/pipeline.dart';
import '../../auth/providers/auth_provider.dart';
import '../../pipelines/providers/pipelines_provider.dart';
import '../../crm/providers/crm_providers.dart';
import '../../complaints/providers/complaints_provider.dart';
import '../providers/product_inquiries_provider.dart';
import '../../../core/widgets/network_status_chip.dart';
import '../../../core/widgets/dashboard_skeleton.dart';
import '../../../core/models/user_role.dart';

final dashboardTimeFilterProvider = StateProvider<String>((ref) => 'month');

final dashboardStatsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final timeFilter = ref.watch(dashboardTimeFilterProvider);

  const supabaseUrl = AppConfig.supabaseUrl;
  if (supabaseUrl.contains('your-project-ref')) {
    return {
      'active_deals': 12,
      'revenue_in_pipeline': 845000.0,
      'customer_leads': 28,
      'service_complaints': 5,
      'trend': [
        {'date': 'Day 1', 'created': 2.0, 'completed': 1.0},
        {'date': 'Day 2', 'created': 4.0, 'completed': 2.0},
        {'date': 'Day 3', 'created': 3.0, 'completed': 1.0},
        {'date': 'Day 4', 'created': 7.0, 'completed': 4.0},
        {'date': 'Day 5', 'created': 5.0, 'completed': 3.0},
        {'date': 'Day 6', 'created': 8.0, 'completed': 5.0},
        {'date': 'Day 7', 'created': 6.0, 'completed': 4.0},
      ]
    };
  }

  Map<String, dynamic> stats = {
    'active_deals': 12,
    'revenue_in_pipeline': 845000.0,
    'customer_leads': 28,
    'service_complaints': 5,
    'trend': [
      {'date': 'Day 1', 'created': 2.0, 'completed': 1.0},
      {'date': 'Day 2', 'created': 4.0, 'completed': 2.0},
      {'date': 'Day 3', 'created': 3.0, 'completed': 1.0},
      {'date': 'Day 4', 'created': 7.0, 'completed': 4.0},
      {'date': 'Day 5', 'created': 5.0, 'completed': 3.0},
      {'date': 'Day 6', 'created': 8.0, 'completed': 5.0},
      {'date': 'Day 7', 'created': 6.0, 'completed': 4.0},
    ]
  };

  try {
    final result = await supabase.rpc('get_dashboard_stats', params: {
      'time_filter': timeFilter
    }).timeout(const Duration(seconds: 3));
    stats = Map<String, dynamic>.from(result as Map);
  } catch (e) {
    try {
      final result = await supabase
          .rpc('get_dashboard_stats')
          .timeout(const Duration(seconds: 2));
      stats = Map<String, dynamic>.from(result as Map);
    } catch (_) {}
  }

  try {
    final prospectsRes = await supabase
        .from('crm_prospects')
        .select('id')
        .timeout(const Duration(seconds: 2));
    stats['customer_leads'] = (prospectsRes as List).length;
  } catch (_) {}

  try {
    final complaintsRes = await supabase
        .from('complaints')
        .select('id')
        .inFilter('status', [
      'assigned',
      'in_progress',
      'pending_approval'
    ]).timeout(const Duration(seconds: 2));
    stats['service_complaints'] = (complaintsRes as List).length;
  } catch (_) {}

  return stats;
});

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final statsAsync = ref.watch(dashboardStatsProvider);
    final pipelinesAsync = ref.watch(pipelinesNotifierProvider);
    final leadsAsync = ref.watch(leadsProvider);
    final complaints = ref.watch(complaintsProvider);
    final currentFilter = ref.watch(dashboardTimeFilterProvider);

    final activeLeadsCount = leadsAsync.value
            ?.where((l) =>
                l.status.toLowerCase() != 'won' &&
                l.status.toLowerCase() != 'lost')
            .length ??
        0;
    final liveComplaintsCount = complaints
        .where((c) => c.status != 'closed' && c.status != 'resolved')
        .length;

    final rawName = profile?.fullName.trim() ?? '';
    final displayName = rawName.isNotEmpty
        ? rawName
        : (profile?.primaryRole.displayName ?? 'Admin User');
    final avatarInitial =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: const Color(0xFF1E1B4B),
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            automaticallyImplyLeading: false,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(28),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.none,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0F172A),
                      Color(0xFF2E1065),
                      Color(0xFF6B21A8),
                      Color(0xFF4F46E5),
                      Color(0xFF2563EB),
                    ],
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(28),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Stack(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF5A6B8A),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    avatarInitial,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              const Positioned(
                                bottom: 0,
                                right: 0,
                                child: NetworkAvatarDot(
                                  borderColor: Color(0xFF1E1B4B),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Good ${_getGreeting()},',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  DateFormat("'Today 'd MMM")
                                      .format(DateTime.now()),
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                profile?.primaryRole.name.toUpperCase() ??
                                    'ADMIN',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white.withValues(alpha: 0.85),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const NetworkStatusChip(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: IconButton(
                  icon:
                      const Icon(Icons.refresh, color: Colors.white, size: 22),
                  tooltip: 'Refresh Data',
                  onPressed: () {
                    ref.invalidate(dashboardStatsProvider);
                    ref.read(leadsProvider.notifier).load(refresh: true);
                    ref.read(prospectsProvider.notifier).load(refresh: true);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white, size: 22),
                  tooltip: 'Logout',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Logout'),
                        content:
                            const Text('Are you sure you want to sign out?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.error),
                            child: const Text('Logout',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await ref.read(authControllerProvider.notifier).signOut();
                    }
                  },
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Date Range Filters
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'Today',
                          selected: currentFilter == 'today',
                          onSelected: () => ref
                              .read(dashboardTimeFilterProvider.notifier)
                              .state = 'today',
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'This Week',
                          selected: currentFilter == 'week',
                          onSelected: () => ref
                              .read(dashboardTimeFilterProvider.notifier)
                              .state = 'week',
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'This Month',
                          selected: currentFilter == 'month',
                          onSelected: () => ref
                              .read(dashboardTimeFilterProvider.notifier)
                              .state = 'month',
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'This Year',
                          selected: currentFilter == 'year',
                          onSelected: () => ref
                              .read(dashboardTimeFilterProvider.notifier)
                              .state = 'year',
                        ),
                      ],
                    ),
                  ),
                ),

                // Stats Cards and Trend Chart loaded together
                statsAsync.when(
                  data: (stats) {
                    final trendList = stats['trend'] as List<dynamic>? ?? [];
                    final created = trendList
                        .map((t) => (t['created'] as num? ?? 0.0).toDouble())
                        .toList();
                    final completed = trendList
                        .map((t) => (t['completed'] as num? ?? 0.0).toDouble())
                        .toList();

                    while (created.length < 7) {
                      created.add(0.0);
                    }
                    while (completed.length < 7) {
                      completed.add(0.0);
                    }

                    final trendMap = {
                      'created': created,
                      'completed': completed,
                      'revenue': (stats['revenue_in_pipeline'] as num? ?? 0.0)
                          .toDouble(),
                    };

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StatsGrid(
                          stats: stats,
                          customerLeadsCount: activeLeadsCount,
                          serviceComplaintsCount: liveComplaintsCount > 0
                              ? liveComplaintsCount
                              : (stats['service_complaints'] ?? 0),
                        ),
                        const SizedBox(height: 12),
                        _TrendChartCard(
                          data: trendMap,
                          pipelines: pipelinesAsync.value ?? [],
                        ),
                      ],
                    );
                  },
                  loading: () => const DashboardSkeleton(),
                  error: (e, _) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Unable to load latest statistics. Check your internet connection.',
                            style:
                                TextStyle(fontSize: 12, color: AppColors.error),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(dashboardStatsProvider),
                          child: const Text('Retry',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Quick Actions
                const Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                const _QuickActionsGrid(),
                const SizedBox(height: 16),

                // Customer Product Interests (Admin View)
                const _CustomerProductInterestsSection(),

                // Recent Pipelines
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Recent Deals',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.go(AppRoutes.pipelines),
                      child: const Text('View All',
                          style: TextStyle(fontFamily: 'Inter')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                pipelinesAsync.when(
                  data: (pipelines) {
                    final recent = pipelines.take(5).toList();
                    if (recent.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No deals yet',
                            style: TextStyle(
                                fontFamily: 'Inter',
                                color: AppColors.textSecondary),
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: recent.map((p) {
                        return _RecentPipelineTile(pipeline: p);
                      }).toList(),
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child:
                          CircularProgressIndicator(color: AppColors.primary),
                    ),
                  ),
                  error: (e, _) => Center(child: Text('$e')),
                ),
                const SizedBox(height: 110),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    return 'Evening';
  }
}

String _formatCompactRevenue(double value) {
  if (value >= 10000000) {
    final cr = value / 10000000;
    return '₹${cr.toStringAsFixed(cr.truncateToDouble() == cr ? 0 : 1)}Cr';
  } else if (value >= 100000) {
    final l = value / 100000;
    return '₹${l.toStringAsFixed(l.truncateToDouble() == l ? 0 : 1)}L';
  } else if (value >= 1000) {
    final k = value / 1000;
    return '₹${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}k';
  } else {
    return '₹${NumberFormat('#,##,##0').format(value.toInt())}';
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF0F172A)
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected
                ? const Color(0xFF0F172A)
                : (isDark ? const Color(0xFF334155) : Colors.grey.shade300),
            width: 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? Colors.white
                : (isDark ? Colors.grey.shade300 : const Color(0xFF334155)),
          ),
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final Map<String, dynamic> stats;
  final int customerLeadsCount;
  final int serviceComplaintsCount;

  const _StatsGrid({
    required this.stats,
    required this.customerLeadsCount,
    required this.serviceComplaintsCount,
  });

  @override
  Widget build(BuildContext context) {
    final revenue = (stats['revenue_in_pipeline'] as num? ?? 0).toDouble();
    final activeDeals = stats['active_deals'] ?? stats['active_pipelines'] ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 800 ? 4 : 2;
        final childAspectRatio = constraints.maxWidth >= 800 ? 1.6 : 1.34;

        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: childAspectRatio,
          children: [
            _StatCard(
              title: 'Active\nDeals',
              value: '$activeDeals',
              icon: Icons.alt_route,
              color: const Color(0xFF2563EB),
              onTap: () => context.go(AppRoutes.pipelines),
            ),
            _StatCard(
              title: 'Pipeline\nRevenue',
              value: _formatCompactRevenue(revenue),
              icon: Icons.currency_rupee,
              color: const Color(0xFF10B981),
              onTap: () => context.go(AppRoutes.pipelines),
            ),
            _StatCard(
              title: 'Customer\nLeads',
              value: '$customerLeadsCount',
              icon: Icons.person,
              color: const Color(0xFF06B6D4),
              onTap: () => context.push('/crm/prospects'),
            ),
            _StatCard(
              title: 'Service\nComplaints',
              value: '$serviceComplaintsCount',
              icon: Icons.support_agent_outlined,
              color: const Color(0xFF8B5CF6),
              onTap: () => context.go('/complaints/dashboard'),
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.grey.shade300
                            : const Color(0xFF1E293B),
                        height: 1.2,
                      ),
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionBtn {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _QuickActionCategory {
  final String title;
  final IconData icon;
  final Color color;
  final List<_QuickActionBtn> actions;

  const _QuickActionCategory({
    required this.title,
    required this.icon,
    required this.color,
    required this.actions,
  });
}

class _QuickActionsGrid extends ConsumerWidget {
  const _QuickActionsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userProfile = ref.watch(currentProfileProvider);
    final roles = userProfile?.roles ?? [];
    final isAccountsOnly = roles.contains(UserRole.accounts) &&
        !roles.contains(UserRole.admin);

    final categories = <_QuickActionCategory>[
      if (!isAccountsOnly)
        _QuickActionCategory(
          title: 'CRM',
          icon: Icons.people_alt_outlined,
          color: const Color(0xFF3B82F6),
          actions: [
            _QuickActionBtn(
              label: 'CRM',
              icon: Icons.people_alt_outlined,
              color: const Color(0xFF3B82F6),
              onTap: () => context.push('/crm/dashboard'),
            ),
          ],
        ),
      if (!isAccountsOnly)
        _QuickActionCategory(
          title: 'Sales',
          icon: Icons.trending_up,
          color: const Color(0xFF6366F1),
          actions: [
            _QuickActionBtn(
              label: 'Deals',
              icon: Icons.currency_rupee,
              color: const Color(0xFF6366F1),
              onTap: () => context.go(AppRoutes.pipelines),
            ),
            _QuickActionBtn(
              label: 'Quotation Generator',
              icon: Icons.request_quote_outlined,
              color: const Color(0xFF0284C7),
              onTap: () => context.push(AppRoutes.heatPumpQuotationHub),
            ),
            _QuickActionBtn(
              label: 'Product Interests',
              icon: Icons.shopping_cart_outlined,
              color: const Color(0xFF0EA5E9),
              onTap: () => context.go(AppRoutes.productInterests),
            ),
          ],
        ),
      _QuickActionCategory(
        title: 'Work & Tasks',
        icon: Icons.calendar_month_outlined,
        color: const Color(0xFF4F46E5),
        actions: [
          _QuickActionBtn(
            label: 'Assigned Work',
            icon: Icons.calendar_month_outlined,
            color: const Color(0xFF4F46E5),
            onTap: () => context.push(AppRoutes.assignedWork),
          ),
          _QuickActionBtn(
            label: 'Daily Tasks',
            icon: Icons.fact_check_outlined,
            color: const Color(0xFF8B5CF6),
            onTap: () => context.push(AppRoutes.dailyTasks),
          ),
        ],
      ),
      _QuickActionCategory(
        title: 'Finance',
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF005CE6),
        actions: [
          _QuickActionBtn(
            label: 'Project Manager',
            icon: Icons.solar_power_outlined,
            color: const Color(0xFF005CE6),
            onTap: () => context.go(AppRoutes.projectManager),
          ),
        ],
      ),
      if (!isAccountsOnly)
        _QuickActionCategory(
          title: 'Field Operations & Service',
          icon: Icons.engineering_outlined,
          color: const Color(0xFF0284C7),
          actions: [
            _QuickActionBtn(
              label: 'Installations',
              icon: Icons.build_circle_outlined,
              color: const Color(0xFF0284C7),
              onTap: () => context.go('/installations/dashboard'),
            ),
            _QuickActionBtn(
              label: 'Complaints',
              icon: Icons.build_outlined,
              color: const Color(0xFF8B5CF6),
              onTap: () => context.go('/complaints/dashboard'),
            ),
            _QuickActionBtn(
              label: 'AMC',
              icon: Icons.shield_outlined,
              color: const Color(0xFF2563EB),
              onTap: () => context.push('/amc'),
            ),
          ],
        ),
      if (!isAccountsOnly)
        _QuickActionCategory(
          title: 'Reports & Analytics',
          icon: Icons.analytics_outlined,
          color: const Color(0xFF10B981),
          actions: [
            _QuickActionBtn(
              label: "Today's Report",
              icon: Icons.bar_chart_outlined,
              color: const Color(0xFF10B981),
              onTap: () => context.push('/reports/activity'),
            ),
            _QuickActionBtn(
              label: 'Customer 360',
              icon: Icons.contact_page_outlined,
              color: const Color(0xFFF59E0B),
              onTap: () => context.push('/reports/customer'),
            ),
            _QuickActionBtn(
              label: 'List of PDFs',
              icon: Icons.folder_copy_outlined,
              color: const Color(0xFFE11D48),
              onTap: () => context.push(AppRoutes.pdfList),
            ),
            _QuickActionBtn(
              label: 'Search PDF',
              icon: Icons.picture_as_pdf_outlined,
              color: const Color(0xFFF97316),
              onTap: () => context.push(AppRoutes.searchPdf),
            ),
          ],
        ),
      if (!isAccountsOnly)
        _QuickActionCategory(
          title: 'Catalog & Inventory',
          icon: Icons.inventory_2_outlined,
          color: const Color(0xFFEC4899),
          actions: [
            _QuickActionBtn(
              label: 'View Products',
              icon: Icons.grid_view_outlined,
              color: const Color(0xFF0D9488),
              onTap: () => context.push('/products'),
            ),
            _QuickActionBtn(
              label: 'Inventory',
              icon: Icons.inventory_2_outlined,
              color: const Color(0xFFEC4899),
              onTap: () => context.push(AppRoutes.inventory),
            ),
          ],
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: categories.map((cat) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 2),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: cat.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(cat.icon, size: 13, color: cat.color),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          cat.title.toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: isDark
                                ? Colors.grey.shade400
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildActionGrid(cat.actions, constraints, isDark),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildActionGrid(
      List<_QuickActionBtn> actions, BoxConstraints constraints, bool isDark) {
    final crossAxisCount = constraints.maxWidth >= 700 ? 4 : 2;
    final rows = <Widget>[];

    for (int i = 0; i < actions.length; i += crossAxisCount) {
      final rowChildren = <Widget>[];
      for (int j = 0; j < crossAxisCount; j++) {
        if (i + j < actions.length) {
          final a = actions[i + j];
          rowChildren.add(
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: a.onTap,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color:
                          isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : Colors.grey.shade200,
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: isDark ? 0.2 : 0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: a.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(a.icon, color: a.color, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            a.label,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        } else {
          rowChildren.add(const Expanded(child: SizedBox.shrink()));
        }

        if (j < crossAxisCount - 1) {
          rowChildren.add(const SizedBox(width: 10));
        }
      }

      rows.add(Row(children: rowChildren));
      if (i + crossAxisCount < actions.length) {
        rows.add(const SizedBox(height: 10));
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }
}

class _RecentPipelineTile extends StatelessWidget {
  final dynamic pipeline;

  const _RecentPipelineTile({required this.pipeline});

  Color _getBadgeColor(String step, String status) {
    if (status == 'completed') return Colors.green;
    if (status == 'suspended' || status == 'cancelled') return Colors.red;

    switch (step) {
      case 'quotation':
        return Colors.amber;
      case 'sales_order':
      case 'salesOrder':
        return Colors.blue;
      case 'boq':
        return Colors.purple;
      case 'factory_order':
      case 'factoryOrder':
        return Colors.orange;
      case 'purchase_order':
      case 'purchaseOrder':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (pipeline == null) return const SizedBox.shrink();

    String stepValue = 'quotation';
    String statusValue = 'in_progress';
    String stepName = 'Quotation';
    String companyName = '';
    String productName = '';
    String pipelineId = '';

    if (pipeline is Map) {
      pipelineId = pipeline['id'] as String? ?? '';
      stepValue = pipeline['current_step'] as String? ?? 'quotation';
      statusValue = pipeline['status'] as String? ?? 'in_progress';
      stepName = PipelineStep.fromString(stepValue).displayName;

      final cust = pipeline['customers'];
      if (cust is Map) {
        companyName = cust['customer_name'] as String? ??
            cust['company_name'] as String? ??
            cust['contact_person'] as String? ??
            '';
      }
      final prod = pipeline['products'];
      if (prod is Map) {
        productName = prod['name'] as String? ?? '';
      }
    } else {
      // SalesPipeline object
      try {
        pipelineId = pipeline.id;
        stepValue = pipeline.currentStep.dbValue;
        statusValue = pipeline.status.dbValue;
        stepName = pipeline.currentStep.displayName;
        companyName = pipeline.customer?.customerName ??
            pipeline.customer?.companyName ??
            pipeline.customer?.contactPerson ??
            '';
        productName = pipeline.product?.name ?? '';
      } catch (_) {}
    }

    final badgeColor = _getBadgeColor(stepValue, statusValue);

    return GestureDetector(
      onTap: () {
        if (pipelineId.isNotEmpty) {
          context.push(
            AppRoutes.pipelineDetail.replaceAll(':id', pipelineId),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.alt_route_outlined,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (companyName.isNotEmpty) ...[
                    Text(
                      companyName,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    productName,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: companyName.isNotEmpty ? 12 : 14,
                      fontWeight: companyName.isNotEmpty
                          ? FontWeight.normal
                          : FontWeight.w600,
                      color: companyName.isNotEmpty
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: badgeColor.withOpacity(0.3)),
              ),
              child: Text(
                stepName,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: badgeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendChartCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final List<SalesPipeline> pipelines;

  const _TrendChartCard({
    required this.data,
    this.pipelines = const [],
  });

  @override
  State<_TrendChartCard> createState() => _TrendChartCardState();
}

class _TrendChartCardState extends State<_TrendChartCard> {
  String _viewMode = 'stages'; // 'stages' or 'trend'
  int? _selectedStageIndex;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Real Stage Counts from live pipelines
    final quotationCount = widget.pipelines
        .where((p) => p.currentStep == PipelineStep.quotation)
        .length;
    final salesOrderCount = widget.pipelines
        .where((p) => p.currentStep == PipelineStep.salesOrder)
        .length;
    final boqCount =
        widget.pipelines.where((p) => p.currentStep == PipelineStep.boq).length;
    final factoryCount = widget.pipelines
        .where((p) => p.currentStep == PipelineStep.factoryOrder)
        .length;
    final purchaseCount = widget.pipelines
        .where((p) => p.currentStep == PipelineStep.purchaseOrder)
        .length;
    final completedCount = widget.pipelines
        .where((p) => p.currentStep == PipelineStep.completed)
        .length;

    final stages = [
      {
        'name': 'Quotation',
        'short': 'Quote',
        'count': quotationCount,
        'color': const Color(0xFFF59E0B),
        'step': 'quotation'
      },
      {
        'name': 'Sales Order',
        'short': 'Order',
        'count': salesOrderCount,
        'color': const Color(0xFF3B82F6),
        'step': 'sales_order'
      },
      {
        'name': 'BOQ',
        'short': 'BOQ',
        'count': boqCount,
        'color': const Color(0xFF06B6D4),
        'step': 'boq'
      },
      {
        'name': 'Factory Order',
        'short': 'Factory',
        'count': factoryCount,
        'color': const Color(0xFF8B5CF6),
        'step': 'factory_order'
      },
      {
        'name': 'Purchase Order',
        'short': 'PO',
        'count': purchaseCount,
        'color': const Color(0xFF6366F1),
        'step': 'purchase_order'
      },
      {
        'name': 'Completed',
        'short': 'Done',
        'count': completedCount,
        'color': const Color(0xFF10B981),
        'step': 'completed'
      },
    ];

    final totalDeals = widget.pipelines.length;
    final activeDeals = totalDeals - completedCount;
    final maxStageCount =
        stages.fold<int>(0, (prev, s) => max(prev, s['count'] as int));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Title & View Switcher
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _viewMode == 'stages'
                          ? 'Deal Stages Distribution'
                          : 'Deals Activity Trend',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _viewMode == 'stages'
                          ? (_selectedStageIndex != null
                              ? '${stages[_selectedStageIndex!]['name']}: ${stages[_selectedStageIndex!]['count']} deals (${totalDeals > 0 ? ((stages[_selectedStageIndex!]['count'] as int) / totalDeals * 100).toStringAsFixed(0) : 0}%)'
                              : '$totalDeals total deals • $activeDeals in progress')
                          : 'Created vs. completed deal trajectory',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11.5,
                        fontWeight: _selectedStageIndex != null
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: _selectedStageIndex != null
                            ? (stages[_selectedStageIndex!]['color'] as Color)
                            : (isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
              ),
              // Toggle pills: Stages vs Trend
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildToggleBtn('Stages', _viewMode == 'stages', isDark),
                    _buildToggleBtn('Trend', _viewMode == 'trend', isDark),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Main Interactive Chart
          if (_viewMode == 'stages') ...[
            _buildInteractiveStagesBarChart(stages, maxStageCount, isDark),
          ] else ...[
            _buildInteractiveTrendLineChart(isDark),
          ],

          const SizedBox(height: 16),

          // Bottom Interactive Badges / Filters
          if (_viewMode == 'stages') ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(stages.length, (i) {
                  final s = stages[i];
                  final isSelected = _selectedStageIndex == i;
                  final color = s['color'] as Color;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedStageIndex = isSelected ? null : i;
                        });
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color
                              : color.withValues(alpha: isDark ? 0.2 : 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? color
                                : color.withValues(alpha: 0.3),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.white : color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${s['name']}: ${s['count']}',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark
                                        ? Colors.grey.shade300
                                        : const Color(0xFF1E293B)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2563EB),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Deals Created',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color:
                        isDark ? Colors.grey.shade400 : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 20),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Deals Completed',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color:
                        isDark ? Colors.grey.shade400 : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToggleBtn(String label, bool isSelected, bool isDark) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _viewMode = label.toLowerCase();
          _selectedStageIndex = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF1E293B) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? (isDark ? Colors.white : const Color(0xFF0F172A))
                : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
          ),
        ),
      ),
    );
  }

  Widget _buildInteractiveStagesBarChart(
      List<Map<String, dynamic>> stages, int maxCount, bool isDark) {
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(stages.length, (index) {
          final s = stages[index];
          final count = s['count'] as int;
          final color = s['color'] as Color;
          final isSelected = _selectedStageIndex == index;
          final isAnySelected = _selectedStageIndex != null;

          final ratio = maxCount > 0 ? (count / maxCount) : 0.0;
          final barHeight = 8.0 + (ratio * 64.0);
          final opacity = isAnySelected && !isSelected ? 0.35 : 1.0;

          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _selectedStageIndex = isSelected ? null : index;
                });
              },
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: opacity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected
                            ? color
                            : (isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade700),
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: barHeight,
                      width: isSelected ? 22 : 18,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            color,
                            color.withValues(alpha: 0.65),
                          ],
                        ),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6)),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s['short'] as String,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? color
                            : (isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildInteractiveTrendLineChart(bool isDark) {
    final List<double> created =
        List<double>.from(widget.data['created'] ?? [0, 0, 0, 0, 0, 0, 0]);
    final List<double> completed =
        List<double>.from(widget.data['completed'] ?? [0, 0, 0, 0, 0, 0, 0]);

    while (created.length < 7) {
      created.add(0.0);
    }
    while (completed.length < 7) {
      completed.add(0.0);
    }

    double maxY = 5.0;
    for (final v in created) {
      if (v > maxY) maxY = v + 2;
    }
    for (final v in completed) {
      if (v > maxY) maxY = v + 2;
    }

    return SizedBox(
      height: 110,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: 6,
          minY: 0,
          maxY: maxY,
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final isCreated = spot.barIndex == 0;
                  return LineTooltipItem(
                    '${isCreated ? "Created" : "Done"}: ${spot.y.toInt()}',
                    TextStyle(
                      color: isCreated
                          ? const Color(0xFF60A5FA)
                          : const Color(0xFF34D399),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(7, (i) => FlSpot(i.toDouble(), created[i])),
              isCurved: true,
              color: const Color(0xFF2563EB),
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF2563EB).withValues(alpha: 0.08),
              ),
            ),
            LineChartBarData(
              spots:
                  List.generate(7, (i) => FlSpot(i.toDouble(), completed[i])),
              isCurved: true,
              color: const Color(0xFF10B981),
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF10B981).withValues(alpha: 0.08),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerProductInterestsSection extends ConsumerWidget {
  const _CustomerProductInterestsSection();

  void _launchCall(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (clean.isEmpty) return;
    final uri = Uri.parse('tel:$clean');
    try {
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    } catch (_) {}
  }

  void _launchWhatsApp(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.isEmpty) return;
    final uri = Uri.parse('https://wa.me/$clean');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Future<void> _cancelRequest(
      BuildContext context, WidgetRef ref, ProductInterestItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Request?'),
        content: Text(
            'Are you sure you want to reject the interest request for "${item.productName}" from ${item.customerName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Reject'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(productInquiriesServiceProvider).cancelInquiry(item);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request cancelled successfully'),
            backgroundColor: Colors.black87,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error cancelling request: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _acceptRequest(
      BuildContext context, WidgetRef ref, ProductInterestItem item) async {
    try {
      final res = await ref.read(productInquiriesServiceProvider).acceptAndCreateDeal(item);
      if (context.mounted) {
        if (res.isUnavailable) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.message),
              backgroundColor: AppColors.warning,
            ),
          );
        } else if (res.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.message),
              backgroundColor: const Color(0xFF16A34A),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${res.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error accepting request: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showInterestMenu(
      BuildContext context, WidgetRef ref, ProductInterestItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final sheetBg = isDark ? const Color(0xFF1E293B) : Colors.white;

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_outline,
                        color: Color(0xFF2563EB), size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.customerName,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          item.customerPhone,
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Product of Interest',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(item.productName,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    if (item.modelNumber.isNotEmpty)
                      Text('Model: ${item.modelNumber}',
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        foregroundColor: const Color(0xFF16A34A),
                        side: const BorderSide(color: Color(0xFF16A34A)),
                      ),
                      onPressed: () => _launchWhatsApp(item.customerPhone),
                      icon: const Icon(Icons.chat_outlined),
                      label: const Text('WhatsApp',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        foregroundColor: const Color(0xFF2563EB),
                        side: const BorderSide(color: Color(0xFF2563EB)),
                      ),
                      onPressed: () => _launchCall(item.customerPhone),
                      icon: const Icon(Icons.phone_outlined),
                      label: const Text('Call',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (item.status != 'accepted') ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _acceptRequest(context, ref, item);
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Accept Request',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _cancelRequest(context, ref, item);
                  },
                  icon: Icon(Icons.cancel_outlined,
                      color: Colors.red.shade600, size: 18),
                  label: Text('Reject Request',
                      style: TextStyle(
                          color: Colors.red.shade600,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 10),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inquiriesAsync = ref.watch(productInquiriesProvider);

    return inquiriesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (interests) {
        final pendingInterests = interests.where((e) {
          final s = e.status.toLowerCase().trim();
          return s == 'requested' || s == 'pending' || s == 'new';
        }).toList();

        if (pendingInterests.isEmpty) return const SizedBox.shrink();

        final item = pendingInterests.first;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Customer Product Interests',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${pendingInterests.length}',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => context.go(AppRoutes.productInterests),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View All',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                          SizedBox(width: 2),
                          Icon(Icons.chevron_right, size: 16, color: Color(0xFF2563EB)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.refresh,
                          size: 18, color: AppColors.textSecondary),
                      tooltip: 'Refresh inquiries',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => ref.invalidate(productInquiriesProvider),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Latest interest card
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showInterestMenu(context, ref, item),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color:
                            const Color(0xFF2563EB).withValues(alpha: 0.2)),
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(0xFF2563EB).withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB)
                                  .withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.shopping_cart_outlined,
                              color: Color(0xFF2563EB),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                RichText(
                                  text: TextSpan(
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      color: Color(0xFF1E293B),
                                      height: 1.35,
                                    ),
                                    children: [
                                      const TextSpan(
                                          text: 'Respected customer '),
                                      TextSpan(
                                        text: item.customerName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      if (item.customerPhone.isNotEmpty)
                                        TextSpan(
                                          text: ' (${item.customerPhone})',
                                          style: const TextStyle(
                                              color: Color(0xFF64748B)),
                                        ),
                                      const TextSpan(
                                          text:
                                              ' has shown interest in following product: '),
                                      TextSpan(
                                        text: item.productName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF2563EB),
                                        ),
                                      ),
                                      if (item.modelNumber.isNotEmpty)
                                        TextSpan(
                                          text: ' (${item.modelNumber})',
                                          style: const TextStyle(
                                              color: Color(0xFF64748B)),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.schedule,
                                        size: 13,
                                        color: Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Text(
                                      DateFormat('dd MMM yyyy, hh:mm a')
                                          .format(item.createdAt),
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: item.status == 'accepted'
                                            ? Colors.green.shade50
                                            : Colors.amber.shade50,
                                        borderRadius:
                                            BorderRadius.circular(4),
                                        border: Border.all(
                                          color: item.status == 'accepted'
                                              ? Colors.green.shade300
                                              : Colors.amber.shade200,
                                        ),
                                      ),
                                      child: Text(
                                        item.status.toUpperCase(),
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: item.status == 'accepted'
                                              ? Colors.green.shade800
                                              : Colors.amber.shade800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 10),

                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.touch_app_outlined,
                                  size: 15, color: Colors.blue.shade600),
                              const SizedBox(width: 4),
                              Text(
                                'Tap for actions',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF16A34A),
                                  side: const BorderSide(
                                      color: Color(0xFF16A34A), width: 1.2),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.chat_outlined,
                                    size: 14),
                                label: const Text('WhatsApp',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                                onPressed: () =>
                                    _launchWhatsApp(item.customerPhone),
                              ),
                              const SizedBox(width: 6),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  visualDensity: VisualDensity.compact,
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.phone, size: 14),
                                label: const Text('Call',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                                onPressed: () =>
                                    _launchCall(item.customerPhone),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
        );
      },
    );
  }
}
