// lib/core/widgets/app_shell.dart
// Main navigation shell for authenticated users

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/user_role.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/notifications/providers/notifications_provider.dart';
import '../router/app_router.dart';
import '../providers/realtime_provider.dart';
import '../providers/sidebar_provider.dart';
import '../../features/customers/providers/customers_provider.dart';
import '../../features/daily_tasks/providers/daily_tasks_provider.dart';
import '../../features/project_manager/providers/pm_providers.dart';
import '../../features/assigned_work/presentation/widgets/today_tasks_dialog.dart';
import '../../features/assigned_work/providers/assigned_work_providers.dart';
import '../../features/assigned_work/models/assigned_work_item.dart';
import '../models/profile.dart';

class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  final String currentRoute;

  const AppShell({super.key, required this.child, required this.currentRoute});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static bool _hasCheckedTodayTasks = false;
  String? _expandedGroup; // 'crm', 'sales', 'finance', 'fieldOps', 'reports', 'catalog'
  String? _fieldOpsSubGroup; // 'installations', 'complaints'
  bool _pdfLibraryExpanded = false;

  void _openGroup(String group, String route) {
    final willExpand = _expandedGroup != group;
    setState(() {
      _expandedGroup = willExpand ? group : null;
    });
    if (willExpand && widget.currentRoute != route) {
      context.go(route);
    }
  }

  void _openFieldOpsSubGroup(String subGroup, String route) {
    final willExpand = _fieldOpsSubGroup != subGroup;
    setState(() {
      _expandedGroup = 'fieldOps';
      _fieldOpsSubGroup = willExpand ? subGroup : null;
    });
    if (willExpand && widget.currentRoute != route) {
      context.go(route);
    }
  }

  void _openPdfLibrary(String route) {
    final willExpand = !_pdfLibraryExpanded;
    setState(() {
      _expandedGroup = 'reports';
      _pdfLibraryExpanded = willExpand;
    });
    if (willExpand && widget.currentRoute != route) {
      context.go(route);
    }
  }

  String? _detectGroup(String route) {
    if (route.startsWith('/crm')) return 'crm';
    if (route.startsWith('/customers') ||
        route.startsWith('/pipelines') ||
        route.startsWith('/quotation') ||
        route.startsWith('/heat-pump-quotations') ||
        route == AppRoutes.productInterests ||
        route == '/product-interests') {
      return 'sales';
    }
    if (route.startsWith('/pm')) return 'finance';
    if (route.startsWith('/installations') ||
        route.startsWith('/complaints') ||
        route.startsWith('/amc') ||
        route.startsWith('/technician') ||
        route == AppRoutes.complaintsDashboard ||
        route == AppRoutes.assignTechnician ||
        route == AppRoutes.serviceHistory ||
        route == AppRoutes.installationsDashboard ||
        route == AppRoutes.installationsList ||
        route == AppRoutes.bookInstallation ||
        route == AppRoutes.assignInstallation ||
        route == AppRoutes.installationHistory) {
      return 'fieldOps';
    }
    if (route == AppRoutes.dailyTasks ||
        route == AppRoutes.assignedWork ||
        route.startsWith('/assigned-work') ||
        route.startsWith('/reports') ||
        route.startsWith('/search-pdf') ||
        route == AppRoutes.searchPdf ||
        route == AppRoutes.pdfList) {
      return 'reports';
    }
    if (route.startsWith('/inventory') ||
        route == AppRoutes.inventory ||
        route.startsWith('/products') ||
        route == AppRoutes.productCatalog) {
      return 'catalog';
    }
    return null;
  }

  String? _detectFieldOpsSubGroup(String route) {
    if (route.startsWith('/installations') ||
        route == AppRoutes.installationsDashboard ||
        route == AppRoutes.installationsList ||
        route == AppRoutes.bookInstallation ||
        route == AppRoutes.assignInstallation ||
        route == AppRoutes.installationHistory) {
      return 'installations';
    }
    if (route.startsWith('/complaints') ||
        route.startsWith('/technician') ||
        route == AppRoutes.complaintsDashboard ||
        route == AppRoutes.assignTechnician ||
        route == AppRoutes.serviceHistory) {
      return 'complaints';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _expandedGroup = _detectGroup(widget.currentRoute);
    _fieldOpsSubGroup = _detectFieldOpsSubGroup(widget.currentRoute);
    _pdfLibraryExpanded = widget.currentRoute == AppRoutes.pdfList ||
        widget.currentRoute == AppRoutes.searchPdf ||
        widget.currentRoute.startsWith('/search-pdf');

    _triggerStartupTodayTasksPopup();
  }

  void _triggerStartupTodayTasksPopup() {
    if (_hasCheckedTodayTasks) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;

      final profile = ref.read(currentProfileProvider);
      if (profile == null) return;
      if (profile.primaryRole == UserRole.customer) {
        _hasCheckedTodayTasks = true;
        return;
      }

      _hasCheckedTodayTasks = true;

      try {
        final tasks = await ref.read(todayTasksForCurrentUserProvider.future);
        if (!mounted) return;
        // Show pop up of assigned work only if there is any pending task assigned TO this user
        final hasPending = tasks.any((t) =>
            t.assignedToUserId == profile.id &&
            t.status != WorkStatus.completed &&
            t.status != WorkStatus.cancelled);
        if (hasPending) {
          TodayTasksDialog.show(context);
        }
      } catch (_) {}
    });
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasCheckedTodayTasks) {
      _triggerStartupTodayTasksPopup();
    }
    if (oldWidget.currentRoute != widget.currentRoute) {
      final activeGroup = _detectGroup(widget.currentRoute);
      _expandedGroup = activeGroup;
      final activeSub = _detectFieldOpsSubGroup(widget.currentRoute);
      _fieldOpsSubGroup = activeSub;
      _pdfLibraryExpanded = widget.currentRoute == AppRoutes.pdfList ||
          widget.currentRoute == AppRoutes.searchPdf ||
          widget.currentRoute.startsWith('/search-pdf');

      // Auto-clear lingering search queries from background providers when switching routes/tabs
      try {
        final custNotifier = ref.read(customersNotifierProvider.notifier);
        if (custNotifier.searchQuery.isNotEmpty) {
          custNotifier.search('');
        }
      } catch (_) {}
      try {
        final taskFilter = ref.read(dailyTaskFilterProvider);
        if (taskFilter.searchQuery.isNotEmpty) {
          ref.read(dailyTaskFilterProvider.notifier).update((s) => s.copyWith(searchQuery: ''));
        }
      } catch (_) {}
      try {
        final txFilter = ref.read(dailyTransactionsFilterProvider);
        if (txFilter.searchQuery.isNotEmpty) {
          ref.read(dailyTransactionsFilterProvider.notifier).update((s) => s.copyWith(searchQuery: ''));
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<Profile?>(currentProfileProvider, (prev, next) {
      if (next != null && !_hasCheckedTodayTasks) {
        _triggerStartupTodayTasksPopup();
      }
    });

    ref.watch(realtimeSubscriptionProvider);
    final profile = ref.watch(currentProfileProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider).value ?? 0;

    if (profile == null) return widget.child;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          return;
        }

        if (context.canPop()) {
          context.pop();
          return;
        }

        final home = getRoleHome(profile.primaryRole);
        if (widget.currentRoute != home) {
          context.go(home);
          return;
        }
        
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Exit IZYHEAT?'),
            content: const Text("You'll be signed out of nothing — just closing the app."),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Exit'),
              ),
            ],
          ),
        );
        
        if (shouldExit == true) {
          SystemNavigator.pop();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: widget.currentRoute.startsWith('/pm')
            ? const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
                systemNavigationBarColor: Colors.white,
                systemNavigationBarIconBrightness: Brightness.dark,
              )
            : SystemUiOverlayStyle.light,
        child: Scaffold(
          extendBody: true,
          body: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 800;
            final isQuotationRoute = widget.currentRoute.startsWith('/heat-pump-quotations') ||
                widget.currentRoute.startsWith('/quotation');
            final showsNavBar = !isWide &&
                !isQuotationRoute &&
                profile.primaryRole != UserRole.customer &&
                !widget.currentRoute.startsWith('/inventory') &&
                widget.currentRoute != AppRoutes.inventory &&
                (!widget.currentRoute.startsWith('/crm') ||
                    profile.primaryRole == UserRole.boq ||
                    profile.primaryRole == UserRole.factory ||
                    profile.primaryRole == UserRole.purchase);

            if (isWide && profile.primaryRole != UserRole.customer) {
              return Row(
                children: [
                  _buildNavRail(context, profile.roles, unreadCount, isWide),
                  Expanded(child: widget.child),
                ],
              );
            }

            // On mobile with the floating nav bar, inject extra bottom padding
            // into MediaQuery so inner Scaffold FABs and scrollable content
            // automatically clear the ~90px floating glass nav bar.
            if (showsNavBar) {
              final mq = MediaQuery.of(context);
              final bottomInset = mq.viewPadding.bottom;
              final topOfNavBar = 69.0 + (bottomInset > 0 ? bottomInset + 4 : 12);
              return MediaQuery(
                data: mq.copyWith(
                  padding: mq.padding.copyWith(
                    bottom: topOfNavBar + 8,
                  ),
                  viewPadding: mq.viewPadding.copyWith(
                    bottom: topOfNavBar + 8,
                  ),
                ),
                child: widget.child,
              );
            }

            return widget.child;
          },
        ),
        bottomNavigationBar: MediaQuery.of(context).size.width < 800 &&
                !widget.currentRoute.startsWith('/heat-pump-quotations') &&
                !widget.currentRoute.startsWith('/quotation') &&
                profile.primaryRole != UserRole.customer &&
                !widget.currentRoute.startsWith('/inventory') &&
                widget.currentRoute != AppRoutes.inventory &&
                (!widget.currentRoute.startsWith('/crm') ||
                    profile.primaryRole == UserRole.boq ||
                    profile.primaryRole == UserRole.factory ||
                    profile.primaryRole == UserRole.purchase)
            ? _buildNavBar(context, profile.roles, unreadCount, false)
            : null,
        ),
      ),
    );
  }

  Widget _buildNavRail(BuildContext context, List<UserRole> roles, int unreadCount, bool isWide) {
    // Unified nav rail colors matching brand aesthetic across all pages
    final Color navBgColor = AppColors.navBarColor;
    const Color selectedTextColor = Colors.white;
    const Color unselectedTextColor = Color(0xFF94A3B8); // Slate 400
    final Color selectedBgColor = Colors.white.withValues(alpha: 0.18);
    const Color logoColor = Colors.white;
    final Color logoIconBg = Colors.white.withValues(alpha: 0.12);
    const Color logoIcon = Colors.white;

    final hasAdmin = roles.any((r) => r == UserRole.admin);
    final isManager = roles.any((r) => r == UserRole.manager);
    final hasAdminOrManager = roles.any((r) => r == UserRole.admin || r == UserRole.manager);
    final hasSales = roles.any((r) => r == UserRole.sales || r == UserRole.salesHead);
    final hasSalesHead = roles.any((r) => r == UserRole.salesHead);
    final hasCrm = roles.any((r) => r == UserRole.crmStaff || r == UserRole.admin || r == UserRole.manager || r == UserRole.sales || r == UserRole.salesHead);
    final hasComplaints = roles.any((r) => r == UserRole.admin || r == UserRole.manager || r == UserRole.serviceHead);
    final hasInstallations = roles.any((r) => r == UserRole.admin || r == UserRole.manager || r == UserRole.serviceHead || r == UserRole.salesHead);
    final isTechnician = roles.any((r) => r == UserRole.technician);
    final isBoq = roles.any((r) => r == UserRole.boq);
    final isFactory = roles.any((r) => r == UserRole.factory);
    final isPurchase = roles.any((r) => r == UserRole.purchase);
    final hasAccounts = roles.any((r) => r == UserRole.accounts);

    final canAccessProductInterests = hasAdminOrManager || hasSalesHead;
    final canAccessPdfList = hasAdminOrManager;
    final canAccessSearchPdf = hasAdminOrManager || hasSalesHead;
    final canAccessPdfLibrary = canAccessPdfList || canAccessSearchPdf;

    // Expansion status & active flags
    final isCrmActive = widget.currentRoute.startsWith('/crm');

    final isSalesActive = widget.currentRoute.startsWith('/customers') ||
        widget.currentRoute.startsWith('/pipelines') ||
        widget.currentRoute.startsWith('/quotation') ||
        widget.currentRoute.startsWith('/heat-pump-quotations') ||
        widget.currentRoute == AppRoutes.productInterests ||
        widget.currentRoute == '/product-interests';

    final isFinanceActive = widget.currentRoute.startsWith('/pm');

    final isInstallationsActive = widget.currentRoute.startsWith('/installations') ||
        widget.currentRoute == AppRoutes.installationsDashboard ||
        widget.currentRoute == AppRoutes.installationsList ||
        widget.currentRoute == AppRoutes.bookInstallation ||
        widget.currentRoute == AppRoutes.assignInstallation ||
        widget.currentRoute == AppRoutes.installationHistory;

    final isComplaintsActive = widget.currentRoute.startsWith('/complaints') ||
        widget.currentRoute.startsWith('/technician') ||
        widget.currentRoute == AppRoutes.complaintsDashboard ||
        widget.currentRoute == AppRoutes.assignTechnician ||
        widget.currentRoute == AppRoutes.serviceHistory;

    final isFieldOpsActive = isInstallationsActive ||
        isComplaintsActive ||
        widget.currentRoute.startsWith('/amc') ||
        widget.currentRoute == AppRoutes.amcList;

    final isPdfLibraryActive = widget.currentRoute == AppRoutes.pdfList ||
        widget.currentRoute == AppRoutes.searchPdf ||
        widget.currentRoute.startsWith('/search-pdf');

    final isReportsActive = widget.currentRoute == AppRoutes.dailyTasks ||
        widget.currentRoute.startsWith('/reports') ||
        isPdfLibraryActive;

    final isCatalogActive = widget.currentRoute.startsWith('/inventory') ||
        widget.currentRoute == AppRoutes.inventory ||
        widget.currentRoute.startsWith('/products') ||
        widget.currentRoute == AppRoutes.productCatalog;

    final isCrmExpanded = _expandedGroup == 'crm';
    final isSalesExpanded = _expandedGroup == 'sales';
    final isFinanceExpanded = _expandedGroup == 'finance';
    final isFieldOpsExpanded = _expandedGroup == 'fieldOps';
    final isReportsExpanded = _expandedGroup == 'reports';
    final isCatalogExpanded = _expandedGroup == 'catalog';
    final isSidebarCollapsed = ref.watch(sidebarCollapsedProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark || navBgColor != Colors.white;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: isSidebarCollapsed ? 70 : 250,
      decoration: BoxDecoration(
        color: navBgColor,
        border: Border(
          right: BorderSide(
            color: AppColors.border.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 32),
          // Logo area
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: isSidebarCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: logoIconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.whatshot_rounded, color: logoIcon, size: 28),
                ),
                if (!isSidebarCollapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: TextStyle(
                        color: logoColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                      child: const Text('IZYHEAT', overflow: TextOverflow.clip),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // 1. Dashboard
                _buildNavItemTile(
                  route: hasAdmin
                      ? AppRoutes.adminDashboard
                      : (hasAccounts
                          ? AppRoutes.accountsDashboard
                          : (hasSales || isManager
                              ? AppRoutes.salesDashboard
                              : (isBoq
                                  ? AppRoutes.boqDashboard
                                  : (isFactory
                                      ? AppRoutes.factoryQueue
                                      : (isPurchase
                                          ? AppRoutes.purchaseQueue
                                          : (isTechnician
                                              ? AppRoutes.technicianDashboard
                                              : '/crm/dashboard')))))),
                  label: 'Dashboard',
                  icon: const Icon(Icons.dashboard_outlined),
                  selectedIcon: const Icon(Icons.dashboard),
                  selectedTextColor: selectedTextColor,
                  unselectedTextColor: unselectedTextColor,
                  selectedBgColor: selectedBgColor,
                ),

                // 2. CRM Group (Expandable)
                if (hasCrm && !hasAccounts) ...[
                  _buildGroupHeader(
                    label: 'CRM',
                    icon: isCrmActive ? Icons.people_alt : Icons.people_alt_outlined,
                    isExpanded: isCrmExpanded,
                    isActive: isCrmActive,
                    selectedTextColor: selectedTextColor,
                    unselectedTextColor: unselectedTextColor,
                    selectedBgColor: selectedBgColor,
                    onTap: () => _openGroup('crm', '/crm/dashboard'),
                  ),
                  _AnimatedExpandableSection(
                    isExpanded: isCrmExpanded,
                    child: _buildChildContainer(
                      isDark: isDark,
                      children: [
                        _buildChildTile(
                          label: 'Dashboard',
                          route: '/crm/dashboard',
                          icon: const Icon(Icons.dashboard_outlined),
                          selectedTextColor: selectedTextColor,
                          unselectedTextColor: unselectedTextColor,
                          selectedBgColor: selectedBgColor,
                        ),
                        _buildChildTile(
                          label: 'Prospects',
                          route: '/crm/prospects',
                          icon: const Icon(Icons.person_search_outlined),
                          selectedTextColor: selectedTextColor,
                          unselectedTextColor: unselectedTextColor,
                          selectedBgColor: selectedBgColor,
                        ),
                        _buildChildTile(
                          label: 'Leads',
                          route: '/crm/leads',
                          icon: const Icon(Icons.trending_up_outlined),
                          selectedTextColor: selectedTextColor,
                          unselectedTextColor: unselectedTextColor,
                          selectedBgColor: selectedBgColor,
                        ),
                        if (hasAdminOrManager || hasSales)
                          _buildChildTile(
                            label: 'Customers',
                            route: '/crm/customers',
                            icon: const Icon(Icons.people_outline),
                            selectedTextColor: selectedTextColor,
                            unselectedTextColor: unselectedTextColor,
                            selectedBgColor: selectedBgColor,
                          ),
                      ],
                    ),
                  ),
                ],

                // 3. Sales Group (Expandable) - Not shown to BOQ per Item 9
                if ((hasAdminOrManager || hasSales) && !hasAccounts) ...[
                  _buildGroupHeader(
                    label: 'Sales',
                    icon: isSalesActive ? Icons.point_of_sale : Icons.point_of_sale_outlined,
                    isExpanded: isSalesExpanded,
                    isActive: isSalesActive,
                    selectedTextColor: selectedTextColor,
                    unselectedTextColor: unselectedTextColor,
                    selectedBgColor: selectedBgColor,
                    onTap: () => _openGroup('sales', AppRoutes.customers),
                  ),
                  _AnimatedExpandableSection(
                    isExpanded: isSalesExpanded,
                    child: _buildChildContainer(
                      isDark: isDark,
                      children: [
                        _buildChildTile(
                          label: 'Customers',
                          route: AppRoutes.customers,
                          icon: const Icon(Icons.business_outlined),
                          selectedTextColor: selectedTextColor,
                          unselectedTextColor: unselectedTextColor,
                          selectedBgColor: selectedBgColor,
                        ),
                        _buildChildTile(
                          label: 'Deals',
                          route: AppRoutes.pipelines,
                          icon: const Icon(Icons.handshake_outlined),
                          selectedTextColor: selectedTextColor,
                          unselectedTextColor: unselectedTextColor,
                          selectedBgColor: selectedBgColor,
                        ),
                        _buildChildTile(
                          label: 'Quotations',
                          route: AppRoutes.heatPumpQuotationHub,
                          icon: const Icon(Icons.request_quote_outlined),
                          selectedTextColor: selectedTextColor,
                          unselectedTextColor: unselectedTextColor,
                          selectedBgColor: selectedBgColor,
                        ),
                        if (canAccessProductInterests)
                          _buildChildTile(
                            label: 'Product Interests',
                            route: AppRoutes.productInterests,
                            icon: const Icon(Icons.shopping_cart_outlined),
                            selectedTextColor: selectedTextColor,
                            unselectedTextColor: unselectedTextColor,
                            selectedBgColor: selectedBgColor,
                          ),
                      ],
                    ),
                  ),
                ],

                // 4. Finance Group (Expandable)
                if (hasAdminOrManager || hasAccounts) ...[
                  _buildGroupHeader(
                    label: 'Finance',
                    icon: isFinanceActive ? Icons.account_balance : Icons.account_balance_outlined,
                    isExpanded: isFinanceExpanded,
                    isActive: isFinanceActive,
                    selectedTextColor: selectedTextColor,
                    unselectedTextColor: unselectedTextColor,
                    selectedBgColor: selectedBgColor,
                    onTap: () => _openGroup('finance', AppRoutes.projectManager),
                  ),
                  _AnimatedExpandableSection(
                    isExpanded: isFinanceExpanded,
                    child: _buildChildContainer(
                      isDark: isDark,
                      children: [
                        _buildChildTile(
                          label: 'Projects',
                          route: AppRoutes.projectManager,
                          icon: const Icon(Icons.solar_power_outlined),
                          selectedTextColor: selectedTextColor,
                          unselectedTextColor: unselectedTextColor,
                          selectedBgColor: selectedBgColor,
                        ),
                        _buildChildTile(
                          label: 'Daily Transaction Entry',
                          route: AppRoutes.pmDailyTransactions,
                          icon: const Icon(Icons.receipt_long_outlined),
                          selectedTextColor: selectedTextColor,
                          unselectedTextColor: unselectedTextColor,
                          selectedBgColor: selectedBgColor,
                        ),
                      ],
                    ),
                  ),
                ],

                // 5. Field Operations & Service Group (Expandable)
                if ((hasAdminOrManager || hasComplaints || hasInstallations) && !hasAccounts) ...[
                  _buildGroupHeader(
                    label: 'Field Operations & Service',
                    icon: isFieldOpsActive ? Icons.build_circle : Icons.build_circle_outlined,
                    isExpanded: isFieldOpsExpanded,
                    isActive: isFieldOpsActive,
                    selectedTextColor: selectedTextColor,
                    unselectedTextColor: unselectedTextColor,
                    selectedBgColor: selectedBgColor,
                    onTap: () => _openGroup('fieldOps', hasInstallations ? AppRoutes.installationsDashboard : (hasComplaints ? AppRoutes.complaintsDashboard : AppRoutes.amcList)),
                  ),
                  _AnimatedExpandableSection(
                    isExpanded: isFieldOpsExpanded,
                    child: _buildChildContainer(
                      isDark: isDark,
                      children: [
                        // Sub-Group 1: Installations (Extending buttons)
                        if (hasInstallations) ...[
                          _buildSubGroupHeader(
                            label: 'Installations',
                            icon: isInstallationsActive ? Icons.build_circle : Icons.build_circle_outlined,
                            isExpanded: _fieldOpsSubGroup == 'installations',
                            isActive: isInstallationsActive,
                            selectedTextColor: selectedTextColor,
                            unselectedTextColor: unselectedTextColor,
                            selectedBgColor: selectedBgColor,
                            onTap: () => _openFieldOpsSubGroup('installations', AppRoutes.installationsDashboard),
                          ),
                          _AnimatedExpandableSection(
                            isExpanded: _fieldOpsSubGroup == 'installations',
                            child: _buildSubChildContainer(
                              isDark: isDark,
                              children: [
                                _buildSubChildTile(
                                  label: 'Dashboard',
                                  route: AppRoutes.installationsDashboard,
                                  icon: const Icon(Icons.dashboard_outlined),
                                  selectedTextColor: selectedTextColor,
                                  unselectedTextColor: unselectedTextColor,
                                  selectedBgColor: selectedBgColor,
                                ),
                                _buildSubChildTile(
                                  label: 'All Installations',
                                  route: AppRoutes.installationsList,
                                  icon: const Icon(Icons.assignment_outlined),
                                  selectedTextColor: selectedTextColor,
                                  unselectedTextColor: unselectedTextColor,
                                  selectedBgColor: selectedBgColor,
                                ),
                                _buildSubChildTile(
                                  label: 'Assign Techs',
                                  route: AppRoutes.assignInstallation,
                                  icon: const Icon(Icons.assignment_ind_outlined),
                                  selectedTextColor: selectedTextColor,
                                  unselectedTextColor: unselectedTextColor,
                                  selectedBgColor: selectedBgColor,
                                ),
                                _buildSubChildTile(
                                  label: 'History',
                                  route: AppRoutes.installationHistory,
                                  icon: const Icon(Icons.history_outlined),
                                  selectedTextColor: selectedTextColor,
                                  unselectedTextColor: unselectedTextColor,
                                  selectedBgColor: selectedBgColor,
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Sub-Group 2: Complaints (Extending buttons)
                        if (hasComplaints) ...[
                          _buildSubGroupHeader(
                            label: 'Complaints',
                            icon: isComplaintsActive ? Icons.support_agent : Icons.support_agent_outlined,
                            isExpanded: _fieldOpsSubGroup == 'complaints',
                            isActive: isComplaintsActive,
                            selectedTextColor: selectedTextColor,
                            unselectedTextColor: unselectedTextColor,
                            selectedBgColor: selectedBgColor,
                            onTap: () => _openFieldOpsSubGroup('complaints', AppRoutes.complaintsDashboard),
                          ),
                          _AnimatedExpandableSection(
                            isExpanded: _fieldOpsSubGroup == 'complaints',
                            child: _buildSubChildContainer(
                              isDark: isDark,
                              children: [
                                _buildSubChildTile(
                                  label: 'Dashboard',
                                  route: AppRoutes.complaintsDashboard,
                                  icon: const Icon(Icons.dashboard_outlined),
                                  selectedTextColor: selectedTextColor,
                                  unselectedTextColor: unselectedTextColor,
                                  selectedBgColor: selectedBgColor,
                                ),
                                _buildSubChildTile(
                                  label: 'All Complaints',
                                  route: AppRoutes.complaintsList,
                                  icon: const Icon(Icons.assignment_outlined),
                                  selectedTextColor: selectedTextColor,
                                  unselectedTextColor: unselectedTextColor,
                                  selectedBgColor: selectedBgColor,
                                ),
                                _buildSubChildTile(
                                  label: 'Assign Techs',
                                  route: AppRoutes.assignTechnician,
                                  icon: const Icon(Icons.assignment_ind_outlined),
                                  selectedTextColor: selectedTextColor,
                                  unselectedTextColor: unselectedTextColor,
                                  selectedBgColor: selectedBgColor,
                                ),
                                _buildSubChildTile(
                                  label: 'Technicians',
                                  route: '/complaints/technicians',
                                  icon: const Icon(Icons.engineering_outlined),
                                  selectedTextColor: selectedTextColor,
                                  unselectedTextColor: unselectedTextColor,
                                  selectedBgColor: selectedBgColor,
                                ),
                                _buildSubChildTile(
                                  label: 'History',
                                  route: AppRoutes.serviceHistory,
                                  icon: const Icon(Icons.history_outlined),
                                  selectedTextColor: selectedTextColor,
                                  unselectedTextColor: unselectedTextColor,
                                  selectedBgColor: selectedBgColor,
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Sub-item 3: AMC (Annual Maintenance)
                        _buildChildTile(
                          label: 'AMC (Annual Maintenance)',
                          route: AppRoutes.amcList,
                          icon: const Icon(Icons.shield_outlined),
                          selectedTextColor: selectedTextColor,
                          unselectedTextColor: unselectedTextColor,
                          selectedBgColor: selectedBgColor,
                        ),
                      ],
                    ),
                  ),
                ],

                // 6. Reports & Analytics Group (Expandable)
                if ((hasAdminOrManager || hasSales) && !hasAccounts) ...[
                  _buildGroupHeader(
                    label: 'Reports & Analytics',
                    icon: isReportsActive ? Icons.analytics : Icons.analytics_outlined,
                    isExpanded: isReportsExpanded,
                    isActive: isReportsActive,
                    selectedTextColor: selectedTextColor,
                    unselectedTextColor: unselectedTextColor,
                    selectedBgColor: selectedBgColor,
                    onTap: () => _openGroup('reports', AppRoutes.dailyTasks),
                  ),
                  _AnimatedExpandableSection(
                    isExpanded: isReportsExpanded,
                    child: _buildChildContainer(
                      isDark: isDark,
                      children: [
                        _buildChildTile(
                          label: 'Daily Tasks',
                          route: AppRoutes.dailyTasks,
                          icon: const Icon(Icons.fact_check_outlined),
                          selectedTextColor: selectedTextColor,
                          unselectedTextColor: unselectedTextColor,
                          selectedBgColor: selectedBgColor,
                        ),
                        _buildChildTile(
                          label: "Today's Report",
                          route: AppRoutes.userActivityReport,
                          icon: const Icon(Icons.bar_chart_outlined),
                          selectedTextColor: selectedTextColor,
                          unselectedTextColor: unselectedTextColor,
                          selectedBgColor: selectedBgColor,
                        ),
                        _buildChildTile(
                          label: 'Customer 360 Report',
                          route: AppRoutes.customerReport,
                          icon: const Icon(Icons.contact_page_outlined),
                          selectedTextColor: selectedTextColor,
                          unselectedTextColor: unselectedTextColor,
                          selectedBgColor: selectedBgColor,
                        ),
                        _buildChildTile(
                          label: 'Assigned Work',
                          route: AppRoutes.assignedWork,
                          icon: const Icon(Icons.calendar_month_outlined),
                          selectedTextColor: selectedTextColor,
                          unselectedTextColor: unselectedTextColor,
                          selectedBgColor: selectedBgColor,
                        ),
                        if (canAccessPdfLibrary) ...[
                          _buildSubGroupHeader(
                            label: 'PDF Library',
                            icon: isPdfLibraryActive ? Icons.picture_as_pdf : Icons.picture_as_pdf_outlined,
                            isExpanded: _pdfLibraryExpanded,
                            isActive: isPdfLibraryActive,
                            selectedTextColor: selectedTextColor,
                            unselectedTextColor: unselectedTextColor,
                            selectedBgColor: selectedBgColor,
                            onTap: () => _openPdfLibrary(canAccessPdfList ? AppRoutes.pdfList : AppRoutes.searchPdf),
                          ),
                          _AnimatedExpandableSection(
                            isExpanded: _pdfLibraryExpanded,
                            child: _buildSubChildContainer(
                              isDark: isDark,
                              children: [
                                if (canAccessPdfList)
                                  _buildSubChildTile(
                                    label: 'List PDFs',
                                    route: AppRoutes.pdfList,
                                    icon: const Icon(Icons.folder_copy_outlined),
                                    selectedTextColor: selectedTextColor,
                                    unselectedTextColor: unselectedTextColor,
                                    selectedBgColor: selectedBgColor,
                                  ),
                                if (canAccessSearchPdf)
                                  _buildSubChildTile(
                                    label: 'Search PDF',
                                    route: AppRoutes.searchPdf,
                                    icon: const Icon(Icons.search_outlined),
                                    selectedTextColor: selectedTextColor,
                                    unselectedTextColor: unselectedTextColor,
                                    selectedBgColor: selectedBgColor,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // 7. Catalog & Inventory Group (Expandable)
                if (hasAdminOrManager && !hasAccounts) ...[
                  _buildGroupHeader(
                    label: 'Catalog & Inventory',
                    icon: isCatalogActive ? Icons.inventory_2 : Icons.inventory_2_outlined,
                    isExpanded: isCatalogExpanded,
                    isActive: isCatalogActive,
                    selectedTextColor: selectedTextColor,
                    unselectedTextColor: unselectedTextColor,
                    selectedBgColor: selectedBgColor,
                    onTap: () => _openGroup('catalog', AppRoutes.products),
                  ),
                  _AnimatedExpandableSection(
                    isExpanded: isCatalogExpanded,
                    child: _buildChildContainer(
                      isDark: isDark,
                      children: [
                        _buildChildTile(
                          label: 'View Products',
                          route: AppRoutes.products,
                          icon: const Icon(Icons.grid_view_outlined),
                          selectedTextColor: selectedTextColor,
                          unselectedTextColor: unselectedTextColor,
                          selectedBgColor: selectedBgColor,
                        ),
                        _buildChildTile(
                          label: 'Inventory',
                          route: AppRoutes.inventory,
                          icon: const Icon(Icons.warehouse_outlined),
                          selectedTextColor: selectedTextColor,
                          unselectedTextColor: unselectedTextColor,
                          selectedBgColor: selectedBgColor,
                        ),
                      ],
                    ),
                  ),
                ],

                // 8. Alerts & Notifications
                if (!hasAccounts || hasAdminOrManager)
                  _buildNavItemTile(
                    route: AppRoutes.notifications,
                    label: isSidebarCollapsed ? 'Alerts' : 'Alerts & Notifications',
                    icon: const Icon(Icons.notifications_outlined),
                    selectedIcon: const Icon(Icons.notifications),
                    selectedTextColor: selectedTextColor,
                    unselectedTextColor: unselectedTextColor,
                    selectedBgColor: selectedBgColor,
                    badgeCount: unreadCount,
                  ),

                // Specific role tasks for technicians, factory, purchase, boq
                if (isTechnician && !hasComplaints) ...[
                  _buildNavItemTile(
                    route: AppRoutes.technicianTasks,
                    label: 'My Tasks',
                    icon: const Icon(Icons.assignment_outlined),
                    selectedIcon: const Icon(Icons.assignment),
                    selectedTextColor: selectedTextColor,
                    unselectedTextColor: unselectedTextColor,
                    selectedBgColor: selectedBgColor,
                  ),
                  _buildNavItemTile(
                    route: AppRoutes.serviceHistory,
                    label: 'History',
                    icon: const Icon(Icons.history_outlined),
                    selectedIcon: const Icon(Icons.history),
                    selectedTextColor: selectedTextColor,
                    unselectedTextColor: unselectedTextColor,
                    selectedBgColor: selectedBgColor,
                  ),
                ],
                if (isFactory && !hasAdminOrManager)
                  _buildNavItemTile(
                    route: AppRoutes.factoryQueue,
                    label: 'Factory Queue',
                    icon: const Icon(Icons.precision_manufacturing_outlined),
                    selectedIcon: const Icon(Icons.precision_manufacturing),
                    selectedTextColor: selectedTextColor,
                    unselectedTextColor: unselectedTextColor,
                    selectedBgColor: selectedBgColor,
                  ),
                if (isPurchase && !hasAdminOrManager)
                  _buildNavItemTile(
                    route: AppRoutes.purchaseQueue,
                    label: 'Purchase Queue',
                    icon: const Icon(Icons.shopping_cart_outlined),
                    selectedIcon: const Icon(Icons.shopping_cart),
                    selectedTextColor: selectedTextColor,
                    unselectedTextColor: unselectedTextColor,
                    selectedBgColor: selectedBgColor,
                  ),
                if (isBoq && !hasAdminOrManager) ...[
                  _buildNavItemTile(
                    route: AppRoutes.boqDashboard,
                    label: 'BOQ',
                    icon: const Icon(Icons.calculate_outlined),
                    selectedIcon: const Icon(Icons.calculate),
                    selectedTextColor: selectedTextColor,
                    unselectedTextColor: unselectedTextColor,
                    selectedBgColor: selectedBgColor,
                  ),
                  _buildNavItemTile(
                    route: AppRoutes.pipelines,
                    label: 'Deals',
                    icon: const Icon(Icons.handshake_outlined),
                    selectedIcon: const Icon(Icons.handshake),
                    selectedTextColor: selectedTextColor,
                    unselectedTextColor: unselectedTextColor,
                    selectedBgColor: selectedBgColor,
                  ),
                ],
              ],
            ),
          ),

          // 9. Admin Settings pinned at bottom
          if (hasAdmin)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildNavItemTile(
                route: AppRoutes.userManagement,
                label: 'Admin Settings',
                icon: const Icon(Icons.admin_panel_settings_outlined),
                selectedIcon: const Icon(Icons.admin_panel_settings),
                selectedTextColor: selectedTextColor,
                unselectedTextColor: unselectedTextColor,
                selectedBgColor: selectedBgColor,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNavItemTile({
    required String route,
    required String label,
    required Widget icon,
    required Widget selectedIcon,
    required Color selectedTextColor,
    required Color unselectedTextColor,
    required Color selectedBgColor,
    int badgeCount = 0,
  }) {
    final isCollapsed = ref.watch(sidebarCollapsedProvider);
    final isSelected = widget.currentRoute == route || (route != '/' && widget.currentRoute.startsWith(route));

    if (isCollapsed) {
      return Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 200),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: isSelected ? selectedBgColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() {
                _expandedGroup = null;
                _fieldOpsSubGroup = null;
                _pdfLibraryExpanded = false;
              });
              context.go(route);
            },
            child: SizedBox(
              height: 42,
              child: Center(
                child: IconTheme(
                  data: IconThemeData(
                    color: isSelected ? selectedTextColor : unselectedTextColor,
                    size: 20,
                  ),
                  child: badgeCount > 0
                      ? Badge(
                          label: Text(
                            badgeCount > 99 ? '99+' : '$badgeCount',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          backgroundColor: AppColors.error,
                          child: isSelected ? selectedIcon : icon,
                        )
                      : (isSelected ? selectedIcon : icon),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isSelected ? selectedBgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          onTap: () {
            setState(() {
              _expandedGroup = null;
              _fieldOpsSubGroup = null;
              _pdfLibraryExpanded = false;
            });
            context.go(route);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                IconTheme(
                  data: IconThemeData(
                    color: isSelected ? selectedTextColor : unselectedTextColor,
                    size: 20,
                  ),
                  child: isSelected ? selectedIcon : icon,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: isSelected ? selectedTextColor : unselectedTextColor,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (badgeCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupHeader({
    required String label,
    required IconData icon,
    required bool isExpanded,
    required bool isActive,
    required Color selectedTextColor,
    required Color unselectedTextColor,
    required Color selectedBgColor,
    required VoidCallback onTap,
  }) {
    final isCollapsed = ref.watch(sidebarCollapsedProvider);
    final isHighlighted = isActive || isExpanded;

    if (isCollapsed) {
      return Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 200),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: isHighlighted ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: SizedBox(
              height: 42,
              child: Center(
                child: Icon(
                  icon,
                  size: 20,
                  color: isHighlighted ? selectedTextColor : unselectedTextColor,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isHighlighted ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isHighlighted ? selectedTextColor : unselectedTextColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: isHighlighted ? selectedTextColor : unselectedTextColor,
                      fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: isHighlighted ? selectedTextColor : unselectedTextColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChildTile({
    required String label,
    required String route,
    required Widget icon,
    required Color selectedTextColor,
    required Color unselectedTextColor,
    required Color selectedBgColor,
  }) {
    final isCollapsed = ref.watch(sidebarCollapsedProvider);
    final isSelected = widget.currentRoute == route;

    if (isCollapsed) {
      return Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 200),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? selectedBgColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.go(route),
            child: SizedBox(
              height: 36,
              child: Center(
                child: IconTheme(
                  data: IconThemeData(
                    color: isSelected ? selectedTextColor : unselectedTextColor,
                    size: 16,
                  ),
                  child: icon,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isSelected ? selectedBgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          onTap: () => context.go(route),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                IconTheme(
                  data: IconThemeData(
                    color: isSelected ? selectedTextColor : unselectedTextColor,
                    size: 17,
                  ),
                  child: icon,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: isSelected ? selectedTextColor : unselectedTextColor,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13.5,
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
    );
  }

  Widget _buildChildContainer({
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildSubChildContainer({
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(left: 12, right: 4, top: 2, bottom: 4),
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildSubGroupHeader({
    required String label,
    required IconData icon,
    required bool isExpanded,
    required bool isActive,
    required Color selectedTextColor,
    required Color unselectedTextColor,
    required Color selectedBgColor,
    required VoidCallback onTap,
  }) {
    final isCollapsed = ref.watch(sidebarCollapsedProvider);
    final isHighlighted = isActive || isExpanded;

    if (isCollapsed) {
      return Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 200),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: isHighlighted ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: SizedBox(
              height: 38,
              child: Center(
                child: Icon(
                  icon,
                  size: 18,
                  color: isHighlighted ? selectedTextColor : unselectedTextColor,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isHighlighted ? Colors.white.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: isHighlighted ? selectedTextColor : unselectedTextColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: isHighlighted ? selectedTextColor : unselectedTextColor,
                      fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: isHighlighted ? selectedTextColor : unselectedTextColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubChildTile({
    required String label,
    required String route,
    required Widget icon,
    required Color selectedTextColor,
    required Color unselectedTextColor,
    required Color selectedBgColor,
  }) {
    final isCollapsed = ref.watch(sidebarCollapsedProvider);
    final isSelected = widget.currentRoute == route;

    if (isCollapsed) {
      return Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 200),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
          decoration: BoxDecoration(
            color: isSelected ? selectedBgColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.go(route),
            child: SizedBox(
              height: 34,
              child: Center(
                child: IconTheme(
                  data: IconThemeData(
                    color: isSelected ? selectedTextColor : unselectedTextColor,
                    size: 14,
                  ),
                  child: icon,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isSelected ? selectedBgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          onTap: () => context.go(route),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                IconTheme(
                  data: IconThemeData(
                    color: isSelected ? selectedTextColor : unselectedTextColor,
                    size: 15,
                  ),
                  child: icon,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: isSelected ? selectedTextColor : unselectedTextColor,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
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
    );
  }

  Widget _buildNavBar(BuildContext context, List<UserRole> roles, int unreadCount, bool isWide) {
    final items = _getNavItems(roles, isWide);
    final currentIndex = _getCurrentIndex(items);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      color: Colors.transparent,
      padding: EdgeInsets.fromLTRB(
        screenWidth > 500 ? (screenWidth - 480) / 2 : 16,
        6,
        screenWidth > 500 ? (screenWidth - 480) / 2 : 16,
        bottomInset > 0 ? bottomInset + 4 : 12,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 69,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF0F172A).withValues(alpha: 0.78)
                  : Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.6),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.45)
                      : const Color(0xFF1E3A5F).withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(items.length, (index) {
                final item = items[index];
                final isSelected = index == currentIndex;

                return Expanded(
                  child: InkWell(
                    onTap: () => context.go(item.route),
                    borderRadius: BorderRadius.circular(22),
                    splashColor: AppColors.primary.withValues(alpha: 0.1),
                    highlightColor: Colors.transparent,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.symmetric(
                          horizontal: isSelected ? 12 : 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark
                                  ? const Color(0xFF1E3A5F).withValues(alpha: 0.35)
                                  : const Color(0xFF1E3A5F).withValues(alpha: 0.1))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: isSelected
                              ? Border.all(
                                  color: (isDark ? const Color(0xFF60A5FA) : AppColors.primary)
                                      .withValues(alpha: 0.25),
                                  width: 1,
                                )
                              : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedScale(
                              scale: isSelected ? 1.15 : 1.0,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutBack,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                transitionBuilder: (child, anim) => FadeTransition(
                                  opacity: anim,
                                  child: ScaleTransition(scale: anim, child: child),
                                ),
                                child: KeyedSubtree(
                                  key: ValueKey<bool>(isSelected),
                                  child: IconTheme(
                                    data: IconThemeData(
                                      size: 21,
                                      color: isSelected
                                          ? (isDark ? const Color(0xFF60A5FA) : AppColors.primary)
                                          : (isDark ? Colors.white60 : AppColors.textSecondary),
                                    ),
                                    child: (item.route == AppRoutes.notifications && unreadCount > 0)
                                        ? Badge(
                                            label: Text(
                                              unreadCount > 99 ? '99+' : '$unreadCount',
                                              style: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                            backgroundColor: AppColors.error,
                                            child: isSelected ? item.selectedIcon : item.icon,
                                          )
                                        : (isSelected ? item.selectedIcon : item.icon),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: isSelected ? 10.5 : 9.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                letterSpacing: -0.2,
                                color: isSelected
                                    ? (isDark ? const Color(0xFF93C5FD) : AppColors.primary)
                                    : (isDark ? Colors.white60 : AppColors.textSecondary),
                              ),
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  int _getCurrentIndex(List<_NavItem> items) {
    int bestIndex = 0;
    int maxMatchLength = -1;
    for (int i = 0; i < items.length; i++) {
      if (widget.currentRoute == items[i].route) {
        return i;
      }
      if (widget.currentRoute.startsWith(items[i].route) && items[i].route.length > maxMatchLength) {
        maxMatchLength = items[i].route.length;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  List<_NavItem> _getNavItems(List<UserRole> roles, bool isWide) {
    final bool isComplaintsRoute = widget.currentRoute.startsWith('/complaints') ||
        widget.currentRoute.startsWith('/technician') ||
        widget.currentRoute == AppRoutes.complaintsDashboard ||
        widget.currentRoute == AppRoutes.assignTechnician ||
        widget.currentRoute == AppRoutes.serviceHistory;

    final bool isInstallationsRoute = widget.currentRoute.startsWith('/installations') ||
        widget.currentRoute == AppRoutes.installationsDashboard ||
        widget.currentRoute == AppRoutes.installationsList ||
        widget.currentRoute == AppRoutes.bookInstallation ||
        widget.currentRoute == AppRoutes.assignInstallation ||
        widget.currentRoute == AppRoutes.installationHistory;

    final Map<String, _NavItem> uniqueItems = {};

    void addItem(_NavItem item) {
      if (!uniqueItems.containsKey(item.route)) {
        uniqueItems[item.route] = item;
      }
    }

    final bool hasAdmin = roles.any((r) => r == UserRole.admin);
    final bool isManager = roles.any((r) => r == UserRole.manager);
    final bool hasAdminOrManager = hasAdmin || isManager;
    final bool hasSales = roles.any((r) => r == UserRole.sales || r == UserRole.salesHead);
    final bool hasCrm = roles.any((r) => r == UserRole.crmStaff || r == UserRole.admin || r == UserRole.manager || r == UserRole.salesHead);
    final bool hasComplaints = roles.any((r) => r == UserRole.serviceHead);
    final bool hasInstallations = roles.any((r) => r == UserRole.admin || r == UserRole.manager || r == UserRole.serviceHead || r == UserRole.salesHead);
    final bool isBoq = roles.any((r) => r == UserRole.boq);
    final bool isFactory = roles.any((r) => r == UserRole.factory);
    final bool isPurchase = roles.any((r) => r == UserRole.purchase);
    final bool isTechnician = roles.any((r) => r == UserRole.technician);
    final bool hasAccounts = roles.any((r) => r == UserRole.accounts);
    final bool isAssignedWorkRoute = widget.currentRoute == AppRoutes.assignedWork ||
        widget.currentRoute.startsWith('/assigned-work');

    // 0.4 Assigned Work contextual route
    if (!isWide && isAssignedWorkRoute) {
      addItem(const _NavItem(
        route: AppRoutes.assignedWork,
        label: 'Work',
        icon: Icon(Icons.calendar_month_outlined),
        selectedIcon: Icon(Icons.calendar_month),
      ));
      addItem(_NavItem(
        route: hasAdmin ? AppRoutes.adminDashboard : (hasAccounts ? AppRoutes.accountsDashboard : AppRoutes.salesDashboard),
        label: 'Home',
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home),
      ));
      addItem(const _NavItem(
        route: AppRoutes.notifications,
        label: 'Alerts',
        icon: Icon(Icons.notifications_outlined),
        selectedIcon: Icon(Icons.notifications),
      ));
      return uniqueItems.values.toList();
    }

    final bool isPmRoute = widget.currentRoute.startsWith('/pm');

    // 0.5 Project Manager contextual route
    if (!isWide && (hasAdminOrManager || hasAccounts) && isPmRoute) {
      addItem(const _NavItem(route: AppRoutes.projectManager, label: 'Projects', icon: Icon(Icons.solar_power_outlined), selectedIcon: Icon(Icons.solar_power)));
      addItem(const _NavItem(route: AppRoutes.pmDailyTransactions, label: 'Day-Book', icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long)));
      addItem(const _NavItem(route: AppRoutes.pmFilter, label: 'Reports', icon: Icon(Icons.filter_list_outlined), selectedIcon: Icon(Icons.filter_list)));
      addItem(_NavItem(
        route: hasAdmin ? AppRoutes.adminDashboard : (hasAccounts ? AppRoutes.accountsDashboard : AppRoutes.salesDashboard),
        label: 'Home',
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home),
      ));
      return uniqueItems.values.toList();
    }

    // 1. Complaints routes
    if (!isWide && (hasAdminOrManager || hasComplaints) && isComplaintsRoute) {
      addItem(const _NavItem(route: AppRoutes.complaintsDashboard, label: 'Dashboard', icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard)));
      addItem(const _NavItem(route: AppRoutes.complaintsList, label: 'Complaints', icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment)));
      addItem(const _NavItem(route: AppRoutes.assignTechnician, label: 'Assign', icon: Icon(Icons.assignment_ind_outlined), selectedIcon: Icon(Icons.assignment_ind)));
      
      if (hasCrm) {
        addItem(const _NavItem(route: '/crm/dashboard', label: 'CRM', icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people_alt)));
      } else if (hasSales) {
        addItem(const _NavItem(route: AppRoutes.salesDashboard, label: 'Sales', icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart)));
      } else if (isBoq || isFactory || isPurchase) {
        addItem(const _NavItem(route: AppRoutes.boqDashboard, label: 'Operations', icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard)));
      } else {
        addItem(const _NavItem(route: '/complaints/technicians', label: 'Technicians', icon: Icon(Icons.engineering_outlined), selectedIcon: Icon(Icons.engineering)));
      }
      addItem(const _NavItem(route: AppRoutes.serviceHistory, label: 'History', icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history)));
      return uniqueItems.values.toList();
    }

    // 1.5 Installations routes
    if (!isWide && hasInstallations && isInstallationsRoute) {
      addItem(const _NavItem(route: AppRoutes.installationsDashboard, label: 'Dashboard', icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard)));
      addItem(const _NavItem(route: AppRoutes.installationsList, label: 'Installations', icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment)));
      addItem(const _NavItem(route: AppRoutes.assignInstallation, label: 'Assign', icon: Icon(Icons.assignment_ind_outlined), selectedIcon: Icon(Icons.assignment_ind)));
      addItem(const _NavItem(route: AppRoutes.installationHistory, label: 'History', icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history)));
      return uniqueItems.values.toList();
    }

    // 2. Admin
    if (hasAdmin) {
      addItem(const _NavItem(route: AppRoutes.adminDashboard, label: 'Dashboard', icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard)));
      addItem(const _NavItem(route: AppRoutes.customers, label: 'Customers', icon: Icon(Icons.business_outlined), selectedIcon: Icon(Icons.business)));
      addItem(const _NavItem(route: AppRoutes.pipelines, label: 'Deals', icon: Icon(Icons.handshake_outlined), selectedIcon: Icon(Icons.handshake)));
      addItem(const _NavItem(route: AppRoutes.notifications, label: 'Alerts', icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications)));
      addItem(const _NavItem(route: AppRoutes.userManagement, label: 'Admin', icon: Icon(Icons.admin_panel_settings_outlined), selectedIcon: Icon(Icons.admin_panel_settings)));
      return uniqueItems.values.toList();
    }

    // 2.5 Manager (no Admin Panel settings button)
    if (isManager) {
      addItem(const _NavItem(route: AppRoutes.salesDashboard, label: 'Dashboard', icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart)));
      addItem(const _NavItem(route: AppRoutes.customers, label: 'Customers', icon: Icon(Icons.business_outlined), selectedIcon: Icon(Icons.business)));
      addItem(const _NavItem(route: AppRoutes.pipelines, label: 'Deals', icon: Icon(Icons.handshake_outlined), selectedIcon: Icon(Icons.handshake)));
      addItem(const _NavItem(route: AppRoutes.notifications, label: 'Alerts', icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications)));
      if (hasComplaints) {
        addItem(const _NavItem(route: AppRoutes.complaintsDashboard, label: 'Complaints', icon: Icon(Icons.support_agent_outlined), selectedIcon: Icon(Icons.support_agent)));
      } else {
        addItem(const _NavItem(route: '/crm/dashboard', label: 'CRM', icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people_alt)));
      }
      return uniqueItems.values.toList();
    }

    // 3. Sales / SalesHead
    if (hasSales) {
      addItem(const _NavItem(route: AppRoutes.salesDashboard, label: 'Dashboard', icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart)));
      addItem(const _NavItem(route: AppRoutes.customers, label: 'Customers', icon: Icon(Icons.business_outlined), selectedIcon: Icon(Icons.business)));
      addItem(const _NavItem(route: AppRoutes.pipelines, label: 'Deals', icon: Icon(Icons.handshake_outlined), selectedIcon: Icon(Icons.handshake)));
      addItem(const _NavItem(route: AppRoutes.notifications, label: 'Alerts', icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications)));
      if (hasComplaints) {
        addItem(const _NavItem(route: AppRoutes.complaintsDashboard, label: 'Complaints', icon: Icon(Icons.support_agent_outlined), selectedIcon: Icon(Icons.support_agent)));
      } else {
        addItem(const _NavItem(route: '/crm/dashboard', label: 'CRM', icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people_alt)));
      }
      return uniqueItems.values.toList();
    }

    // 4. CRM Staff
    if (hasCrm) {
      addItem(const _NavItem(route: '/crm/dashboard', label: 'CRM Dashboard', icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard)));
      addItem(const _NavItem(route: '/crm/prospects', label: 'Prospects', icon: Icon(Icons.person_search_outlined), selectedIcon: Icon(Icons.person_search)));
      addItem(const _NavItem(route: '/crm/leads', label: 'Leads', icon: Icon(Icons.trending_up_outlined), selectedIcon: Icon(Icons.trending_up)));
      if (hasComplaints) {
        addItem(const _NavItem(route: AppRoutes.complaintsDashboard, label: 'Complaints', icon: Icon(Icons.support_agent_outlined), selectedIcon: Icon(Icons.support_agent)));
      } else if (isBoq || isFactory || isPurchase) {
        addItem(const _NavItem(route: AppRoutes.boqDashboard, label: 'Operations', icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard)));
      } else {
        addItem(const _NavItem(route: '/reports/activity', label: "Today's Report", icon: Icon(Icons.assessment_outlined), selectedIcon: Icon(Icons.assessment)));
      }
      addItem(const _NavItem(route: AppRoutes.notifications, label: 'Alerts', icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications)));
      return uniqueItems.values.toList();
    }

    // 5. Service Head (when not on complaints route)
    if (hasComplaints) {
      addItem(const _NavItem(route: AppRoutes.complaintsDashboard, label: 'Dashboard', icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard)));
      addItem(const _NavItem(route: AppRoutes.complaintsList, label: 'Complaints', icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment)));
      addItem(const _NavItem(route: AppRoutes.assignTechnician, label: 'Assign', icon: Icon(Icons.assignment_ind_outlined), selectedIcon: Icon(Icons.assignment_ind)));
      if (isBoq || isFactory || isPurchase) {
        addItem(const _NavItem(route: AppRoutes.boqDashboard, label: 'Operations', icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard)));
      } else {
        addItem(const _NavItem(route: '/complaints/technicians', label: 'Technicians', icon: Icon(Icons.engineering_outlined), selectedIcon: Icon(Icons.engineering)));
      }
      addItem(const _NavItem(route: AppRoutes.serviceHistory, label: 'History', icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history)));
      return uniqueItems.values.toList();
    }

    // 6. Technician
    if (isTechnician) {
      addItem(const _NavItem(route: AppRoutes.technicianDashboard, label: 'Home', icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home)));
      addItem(const _NavItem(route: AppRoutes.technicianTasks, label: 'My Tasks', icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment)));
      addItem(const _NavItem(route: AppRoutes.serviceHistory, label: 'History', icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history)));
      return uniqueItems.values.toList();
    }

    // 7. Operations (BOQ/Factory/Purchase)
    if (isBoq || isFactory || isPurchase) {
      addItem(const _NavItem(route: AppRoutes.boqDashboard, label: 'Dashboard', icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard)));
      addItem(const _NavItem(route: AppRoutes.pipelines, label: 'Deals', icon: Icon(Icons.work_outline), selectedIcon: Icon(Icons.work)));
      addItem(const _NavItem(route: '/crm/prospects', label: 'Prospects', icon: Icon(Icons.person_search_outlined), selectedIcon: Icon(Icons.person_search)));
      addItem(const _NavItem(route: AppRoutes.notifications, label: 'Alerts', icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications)));
      return uniqueItems.values.take(5).toList();
    }

    return uniqueItems.values.take(5).toList();
  }
}

class _NavItem {
  final String route;
  final String label;
  final Widget icon;
  final Widget selectedIcon;

  const _NavItem({
    required this.route,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

class _AnimatedExpandableSection extends StatelessWidget {
  final bool isExpanded;
  final Widget child;

  const _AnimatedExpandableSection({
    required this.isExpanded,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      child: isExpanded
          ? child
          : const SizedBox(
              width: double.infinity,
              height: 0,
            ),
    );
  }
}

