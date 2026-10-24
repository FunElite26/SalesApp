import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/excel_service.dart';
import '../data/models/prospect_model.dart';
import '../providers/crm_providers.dart';
import '../../../core/models/user_role.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/product_combo_selector.dart';

class LeadsListScreen extends ConsumerStatefulWidget {
  const LeadsListScreen({super.key});

  @override
  ConsumerState<LeadsListScreen> createState() => _LeadsListScreenState();
}

class _LeadsListScreenState extends ConsumerState<LeadsListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatus = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leadsAsync = ref.watch(leadsProvider);
    final prospectsAsync = ref.watch(prospectsProvider);
    final profile = ref.watch(currentProfileProvider);
    final isAdmin = profile?.primaryRole == UserRole.admin || profile?.primaryRole == UserRole.manager || profile?.primaryRole == UserRole.salesHead || (profile?.roles.contains(UserRole.admin) ?? false);
    final canSeePendingApproval = (profile?.primaryRole.canApproveQuotations ?? false) ||
        (profile?.roles.any((r) => r.canApproveQuotations) ?? false) ||
        profile?.primaryRole == UserRole.manager ||
        (profile?.roles.contains(UserRole.manager) ?? false);
    final isCrmStaff = profile?.primaryRole == UserRole.crmStaff;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/crm/dashboard');
            }
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Leads & Deals'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${leadsAsync.value?.length ?? 0}',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export Leads',
            onPressed: () {
              final leads = ref.read(leadsProvider).value;
              final prospects = ref.read(prospectsProvider).value ?? [];
              if (leads != null && leads.isNotEmpty) {
                ExcelService.exportLeads(context, leads, prospects);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No leads to export')));
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.read(leadsProvider.notifier).load(refresh: true);
              ref.read(prospectsProvider.notifier).load(refresh: true);
              ref.invalidate(leadsWithPendingQuotationApprovalProvider);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(
            ref.watch(leadsWithPendingQuotationApprovalProvider).value ?? const <String>{},
            canSeePendingApproval: canSeePendingApproval,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.surface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.leaderboard_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Total Leads: ${leadsAsync.value?.length ?? 0}',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                Text(
                  'All Stages',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.read(leadsProvider.notifier).load(refresh: true);
                ref.read(prospectsProvider.notifier).load(refresh: true);
                ref.invalidate(leadsWithPendingQuotationApprovalProvider);
              },
              child: leadsAsync.when(
                data: (leads) {
                  final prospects = prospectsAsync.value ?? [];
                  final pendingApprovalLeads =
                      ref.watch(leadsWithPendingQuotationApprovalProvider).value ?? const <String>{};

                  // Apply filters
                  var filtered = leads.where((l) {
                    final prospect = prospects.where((p) => p.id == l.prospectId).firstOrNull;
                    final displayName = (l.prospectName != null && l.prospectName!.isNotEmpty)
                        ? l.prospectName!
                        : (prospect?.name ?? '');
                    final phone = (l.contactPhone != null && l.contactPhone!.isNotEmpty)
                        ? l.contactPhone!
                        : (prospect?.phone ?? '');

                    final matchesSearch = displayName.toLowerCase().contains(_searchQuery.toLowerCase()) || 
                                          phone.contains(_searchQuery) ||
                                          l.productName.toLowerCase().contains(_searchQuery.toLowerCase());
                    final matchesStatus = _selectedStatus == 'All' ||
                        (_selectedStatus == 'Pending Approval'
                            ? pendingApprovalLeads.contains(l.id)
                            : l.status == _selectedStatus);
                    return matchesSearch && matchesStatus;
                  }).toList();

                  // Sort: Uncompleted leads at top (with Pending Approval prioritized), Won & Lost at bottom; then newest first
                  filtered.sort((a, b) {
                    final aDone = a.status == 'Won' || a.status == 'Lost' || a.convertedToCustomerId != null;
                    final bDone = b.status == 'Won' || b.status == 'Lost' || b.convertedToCustomerId != null;
                    if (aDone != bDone) {
                      return aDone ? 1 : -1;
                    }
                    final aPending = pendingApprovalLeads.contains(a.id);
                    final bPending = pendingApprovalLeads.contains(b.id);
                    if (aPending != bPending) {
                      return aPending ? -1 : 1;
                    }
                    return b.createdAt.compareTo(a.createdAt);
                  });

                  if (filtered.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 100),
                        Center(
                          child: Text('No leads found.', style: TextStyle(color: AppColors.textSecondary)),
                        ),
                      ],
                    );
                  }

                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, itemIndex) {
                      final lead = filtered[itemIndex];
                      final prospect = prospects.where((p) => p.id == lead.prospectId).firstOrNull;
                      final displayName = (lead.prospectName != null && lead.prospectName!.isNotEmpty)
                          ? lead.prospectName!
                          : (prospect?.name ?? 'Lead #${lead.id.substring(0, 6)}');
                      final displayPhone = (lead.contactPhone != null && lead.contactPhone!.isNotEmpty)
                          ? lead.contactPhone!
                          : (prospect?.phone ?? '');

                      final isWon = lead.status == 'Won' || lead.convertedToCustomerId != null;
                      final isLost = lead.status == 'Lost';
                      final hasPendingApproval = pendingApprovalLeads.contains(lead.id);

                      Color statusColor = Colors.blue;
                      if (isWon) statusColor = AppColors.success;
                      if (isLost) statusColor = AppColors.error;
                      if (lead.status == 'Negotiating') statusColor = Colors.purple;
                      if (lead.status == 'In Progress') statusColor = Colors.orange;

                      final isAssignedToMe = !isWon && lead.assignedTo != null && lead.assignedTo == profile?.id;

                      final isReassignReq = !isWon && lead.reassignmentRequested;

                      return Card(
                        elevation: 0,
                        color: isReassignReq
                            ? const Color(0xFFFFFBEB)
                            : (hasPendingApproval
                                ? const Color(0xFFFFFDF5)
                                : (isAssignedToMe ? const Color(0xFFFFFDF5) : AppColors.surface)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isReassignReq
                                ? const Color(0xFFF59E0B)
                                : (hasPendingApproval
                                    ? const Color(0xFFF59E0B)
                                    : (isAssignedToMe ? const Color(0xFFF59E0B) : AppColors.border.withOpacity(0.5))),
                            width: (isReassignReq || hasPendingApproval) ? 1.6 : (isAssignedToMe ? 1.2 : 1),
                          ),
                        ),
                        child: ListTile(
                          onTap: () {
                            context.push('/crm/leads/${lead.id}');
                          },
                          leading: CircleAvatar(
                            backgroundColor: hasPendingApproval
                                ? const Color(0xFFFEF3C7)
                                : statusColor.withOpacity(0.1),
                            child: Icon(
                              hasPendingApproval
                                  ? Icons.hourglass_top_rounded
                                  : (isWon ? Icons.check_circle : (isLost ? Icons.cancel : Icons.trending_up)),
                              color: hasPendingApproval ? const Color(0xFFD97706) : statusColor,
                            ),
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                ),
                              ),
                              if (hasPendingApproval) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.6)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.hourglass_top_rounded, size: 11, color: Color(0xFFB45309)),
                                      SizedBox(width: 4),
                                      Text(
                                        'Quotation Approval Pending',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFB45309),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (isAssignedToMe) ...[
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.6)),
                                  ),
                                  child: const Text(
                                    'Assigned to You',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (displayPhone.isNotEmpty)
                                Text(displayPhone, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                              Text(
                                lead.productName,
                                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              Text('₹${lead.estimatedValue.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 12)),
                              if (!isWon && (lead.assignedByName != null || lead.assignedTo != null)) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isAssignedToMe ? Colors.green.withOpacity(0.08) : const Color(0xFF2563EB).withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.person_outline, size: 11, color: isAssignedToMe ? Colors.green : const Color(0xFF2563EB)),
                                      const SizedBox(width: 3),
                                      Text(
                                        isAssignedToMe
                                            ? 'Assigned to: You'
                                            : 'Assigned to: ${lead.assignedByName ?? 'Assigned'}',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 11,
                                          color: isAssignedToMe ? Colors.green : const Color(0xFF2563EB),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (!isWon && lead.reassignmentRequested) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFF59E0B)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.warning_amber_rounded, size: 11, color: Color(0xFFB45309)),
                                      SizedBox(width: 3),
                                      Text(
                                        'Reassign Requested',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFB45309),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: statusColor.withOpacity(0.5)),
                            ),
                            child: Text(
                              lead.status,
                              style: TextStyle(
                                fontSize: 10,
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.error))),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: isCrmStaff
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: FloatingActionButton.extended(
                heroTag: 'add_lead_fab',
                onPressed: () => _showAddLeadForm(context),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('Add Lead', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                backgroundColor: AppColors.primary,
              ),
            ),
    );
  }

  Widget _buildFilters(Set<String> pendingApprovalLeads, {required bool canSeePendingApproval}) {
    final filterOptions = [
      'All',
      if (canSeePendingApproval) 'Pending Approval',
      'New',
      'In Progress',
      'Negotiating',
      'Won',
      'Lost',
    ];

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search by prospect, product, phone...',
              hintStyle: const TextStyle(color: AppColors.textSecondary),
              prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18, color: AppColors.textSecondary),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filterOptions.map((status) {
                final isSelected = _selectedStatus == status;
                final isPendingChip = status == 'Pending Approval';
                final count = isPendingChip ? pendingApprovalLeads.length : 0;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: isPendingChip
                        ? Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF59E0B),
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
                    label: Text(
                      isPendingChip && count > 0
                          ? 'Pending Approval ($count)'
                          : status,
                      style: TextStyle(
                        color: isSelected
                            ? (isPendingChip ? const Color(0xFFB45309) : AppColors.primary)
                            : (isPendingChip ? const Color(0xFFD97706) : AppColors.textPrimary),
                        fontWeight: (isSelected || isPendingChip) ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() => _selectedStatus = status);
                    },
                    selectedColor: isPendingChip
                        ? const Color(0xFFFEF3C7)
                        : AppColors.primary.withOpacity(0.15),
                    checkmarkColor: isPendingChip ? const Color(0xFFB45309) : AppColors.primary,
                    backgroundColor: isPendingChip ? const Color(0xFFFFFBEB) : AppColors.background,
                    side: isPendingChip
                        ? BorderSide(color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFFFDE68A))
                        : null,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }



  void _showAddLeadForm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: const SafeArea(
            bottom: true,
            child: AddDirectLeadForm(),
          ),
        );
      },
    );
  }
}

class AddDirectLeadForm extends ConsumerStatefulWidget {
  const AddDirectLeadForm({super.key});

  @override
  ConsumerState<AddDirectLeadForm> createState() => _AddDirectLeadFormState();
}

class _AddDirectLeadFormState extends ConsumerState<AddDirectLeadForm> {
  final _formKey = GlobalKey<FormState>();
  Prospect? _selectedProspect;
  final _contactPhoneCtrl = TextEditingController();
  List<ProductComboItem> _selectedProducts = [];
  List<ProductComboItem> _availableCombos = [];
  String? _productError;
  final _valCtrl = TextEditingController(text: '0.00');
  final _notesCtrl = TextEditingController();
  DateTime? _expectedDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _availableCombos = List<ProductComboItem>.from(ProductComboItem.defaultCombos);
    _loadCombos();
  }

  Future<void> _loadCombos() async {
    try {
      final combos = await ProductComboItem.loadCombos(ref.read(supabaseClientProvider));
      if (mounted && combos.isNotEmpty) {
        setState(() => _availableCombos = combos);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _contactPhoneCtrl.dispose();
    _valCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _onProductsChanged(List<ProductComboItem> items) {
    setState(() {
      _selectedProducts = items;
      _productError = items.isEmpty ? 'Please select at least one product' : null;
      final total = items.fold<double>(0.0, (sum, i) => sum + i.price);
      _valCtrl.text = total > 0 ? total.toStringAsFixed(2) : '0.00';
    });
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProspect == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a prospect'), backgroundColor: AppColors.error),
      );
      return;
    }
    if (_selectedProducts.isEmpty) {
      setState(() => _productError = 'Please select at least one product');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one product'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final joinedProductName = _selectedProducts.map((p) => p.displayName).join(', ');
      final joinedCapacity = _selectedProducts
          .map((p) => p.capacity)
          .whereType<String>()
          .where((c) => c.isNotEmpty)
          .join(', ');
      final totalValue = double.tryParse(_valCtrl.text.trim()) ??
          _selectedProducts.fold<double>(0.0, (sum, i) => sum + i.price);

      final newLead = await ref.read(leadsProvider.notifier).addDirectLead(
            prospectId: _selectedProspect!.id,
            prospectName: _selectedProspect!.name,
            contactPhone: _contactPhoneCtrl.text.trim(),
            productName: joinedProductName,
            estimatedValue: totalValue,
            expectedDate: _expectedDate,
            notes: _notesCtrl.text.trim(),
            capacity: joinedCapacity.isNotEmpty ? joinedCapacity : null,
            components: _selectedProducts.map((p) => p.toComponentMap()).toList(),
          );

      if (mounted) {
        context.pop();
        ref.read(prospectsProvider.notifier).load();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lead created successfully!'), backgroundColor: AppColors.success),
        );
        if (newLead != null) {
          context.push('/crm/leads/${newLead.id}');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating lead: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prospectsList = ref.watch(prospectsProvider).value ?? [];

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('New Sales Lead', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 16),

              // 1. Searchable Prospect Selector
              if (prospectsList.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No prospects found. Please add a prospect first before creating a lead.',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                )
              else
                InkWell(
                  onTap: () async {
                    final picked = await showModalBottomSheet<Prospect>(
                      context: context,
                      useRootNavigator: true,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => SafeArea(
                        bottom: true,
                        child: SearchableProspectSheet(prospects: prospectsList),
                      ),
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedProspect = picked;
                        _contactPhoneCtrl.text = picked.phone; // Auto fill phone number!
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Select Prospect *',
                      hintText: 'Search and choose prospect',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person_search, color: AppColors.primary),
                      suffixIcon: _selectedProspect != null
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                setState(() {
                                  _selectedProspect = null;
                                  _contactPhoneCtrl.clear();
                                });
                              },
                            )
                          : const Icon(Icons.arrow_drop_down),
                    ),
                    child: _selectedProspect == null
                        ? const Text('Choose from created prospects', style: TextStyle(color: AppColors.textSecondary))
                        : Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _selectedProspect!.company != null && _selectedProspect!.company!.isNotEmpty
                                      ? '${_selectedProspect!.name} (${_selectedProspect!.company})'
                                      : _selectedProspect!.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              const SizedBox(height: 12),

              // 2. Auto-filled Phone Number
              TextFormField(
                controller: _contactPhoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Contact Phone Number (Auto-filled)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),

              // 3. Multi-Product Selector (Combines all inventory items & capacities)
              MultiProductSelectorField(
                selectedItems: _selectedProducts,
                availableItems: _availableCombos,
                onChanged: _onProductsChanged,
                errorText: _productError,
              ),
              const SizedBox(height: 12),

              // 4. Estimated Deal Value (Read-only on lead creation)
              TextFormField(
                controller: _valCtrl,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Estimated Deal Value (₹)',
                  helperText: 'Auto-calculated from selected items price',
                  filled: true,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),

              // 5. Expected Closing Date
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 14)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => _expectedDate = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Expected Closing Date (Optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.event_outlined),
                  ),
                  child: Text(
                    _expectedDate != null
                        ? '${_expectedDate!.day}/${_expectedDate!.month}/${_expectedDate!.year}'
                        : 'Select closing date',
                    style: TextStyle(
                      color: _expectedDate != null ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 6. Notes
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Initial Notes / Requirements',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),

              // Submit Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isSaving ? null : _handleSave,
                child: _isSaving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Create Lead', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SearchableProspectSheet extends StatefulWidget {
  final List<Prospect> prospects;
  const SearchableProspectSheet({super.key, required this.prospects});

  @override
  State<SearchableProspectSheet> createState() => _SearchableProspectSheetState();
}

class _SearchableProspectSheetState extends State<SearchableProspectSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.prospects.where((p) {
      final q = _query.toLowerCase().trim();
      if (q.isEmpty) return true;
      final name = p.name.toLowerCase();
      final phone = p.phone.toLowerCase();
      final company = (p.company ?? '').toLowerCase();
      return name.contains(q) || phone.contains(q) || company.contains(q);
    }).toList();

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.80),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.person_search, color: AppColors.primary, size: 24),
                const SizedBox(width: 10),
                const Text(
                  'Select Prospect',
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 17, color: AppColors.textPrimary),
                ),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by name, phone, company...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
              onChanged: (val) => setState(() => _query = val),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      _query.isEmpty ? 'No prospects available' : 'No prospects match "$_query"',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, idx) {
                      final p = filtered[idx];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          child: Text(
                            p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          p.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                        subtitle: Text(
                          [
                            if (p.company != null && p.company!.isNotEmpty) p.company!,
                            p.phone,
                          ].join(' • '),
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        trailing: p.source.isNotEmpty
                            ? Chip(
                                label: Text(p.source, style: const TextStyle(fontSize: 10)),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              )
                            : null,
                        onTap: () => Navigator.pop(context, p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
