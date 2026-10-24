import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/user_role.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/excel_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/models/prospect_model.dart';
import '../providers/crm_providers.dart';

class ProspectsListScreen extends ConsumerStatefulWidget {
  const ProspectsListScreen({super.key});

  @override
  ConsumerState<ProspectsListScreen> createState() => _ProspectsListScreenState();
}

class _ProspectsListScreenState extends ConsumerState<ProspectsListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedSource = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prospectsAsync = ref.watch(prospectsProvider);
    final leads = ref.watch(leadsProvider).value ?? [];
    final profile = ref.watch(currentProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              final role = profile?.primaryRole;
              if (role == UserRole.factory || role == UserRole.purchase || role == UserRole.boq) {
                context.go(getRoleHome(role!));
              } else if (role == UserRole.admin || role == UserRole.manager) {
                context.go(AppRoutes.adminDashboard);
              } else {
                context.go('/crm/dashboard');
              }
            }
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Prospects'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${prospectsAsync.value?.length ?? 0}',
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
            tooltip: 'Export Prospects',
            onPressed: () {
              final prospects = ref.read(prospectsProvider).value;
              if (prospects != null && prospects.isNotEmpty) {
                ExcelService.exportProspects(context, prospects);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No prospects to export')));
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.read(prospectsProvider.notifier).load(refresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.surface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.people_alt_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Total Prospects: ${prospectsAsync.value?.length ?? 0}',
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
                  'Active Pipeline',
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
              onRefresh: () => ref.read(prospectsProvider.notifier).load(refresh: true),
              child: prospectsAsync.when(
              data: (prospects) {
                // Apply filters
                var filtered = prospects.where((p) {
                  final matchesSearch = p.name.toLowerCase().contains(_searchQuery.toLowerCase()) || 
                                        p.phone.contains(_searchQuery) ||
                                        (p.company?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
                  final matchesSource = _selectedSource == 'All' || p.source == _selectedSource;
                  return matchesSearch && matchesSource;
                }).toList();

                bool checkConverted(Prospect p) {
                  if (p.convertedToLeadId != null) return true;
                  return leads.any((l) =>
                      (l.prospectId != null && l.prospectId == p.id) ||
                      (p.phone.isNotEmpty && l.contactPhone != null && l.contactPhone!.trim() == p.phone.trim()));
                }

                // Sort: Unconverted at top, converted at bottom; then newest first
                filtered.sort((a, b) {
                  final aConverted = checkConverted(a);
                  final bConverted = checkConverted(b);
                  if (aConverted != bConverted) {
                    return aConverted ? 1 : -1;
                  }
                  return b.createdAt.compareTo(a.createdAt);
                });

                if (filtered.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 100),
                      Center(
                        child: Text('No prospects found.', style: TextStyle(color: AppColors.textSecondary)),
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
                    final prospect = filtered[itemIndex];
                      final isConverted = checkConverted(prospect);
                      final isAssignedToMe = prospect.assignedTo != null && prospect.assignedTo == profile?.id;
                      final isCreatedByMe = prospect.createdBy == profile?.id;
                      final isTransferredAway = isCreatedByMe && prospect.assignedTo != null && prospect.assignedTo != profile?.id;
                      final isAdmin = profile?.primaryRole == UserRole.admin || profile?.primaryRole == UserRole.manager || profile?.primaryRole == UserRole.salesHead || profile?.roles.contains(UserRole.admin) == true;

                      final isReassignReq = prospect.reassignmentRequested;

                      return Card(
                        elevation: 0,
                        color: isReassignReq
                            ? const Color(0xFFFFFBEB)
                            : (isAssignedToMe ? const Color(0xFFFFFDF5) : AppColors.surface),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isReassignReq
                                ? const Color(0xFFF59E0B)
                                : (isAssignedToMe ? const Color(0xFFF59E0B) : AppColors.border.withOpacity(0.5)),
                            width: isReassignReq ? 1.6 : (isAssignedToMe ? 1.4 : 1),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          onTap: () {
                            context.push('/crm/prospects/${prospect.id}');
                          },
                          leading: CircleAvatar(
                            backgroundColor: isConverted
                                ? AppColors.success.withOpacity(0.1)
                                : (isAssignedToMe ? const Color(0xFFFEF3C7) : AppColors.primary.withOpacity(0.1)),
                            child: Icon(
                              isConverted
                                  ? Icons.check_circle
                                  : (isAssignedToMe ? Icons.assignment_ind : Icons.person),
                              color: isConverted
                                  ? AppColors.success
                                  : (isAssignedToMe ? const Color(0xFFD97706) : AppColors.primary),
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  prospect.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                              ),
                              if (isAssignedToMe)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFF59E0B)),
                                  ),
                                  child: const Text(
                                    'Assigned by Admin',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (prospect.company != null && prospect.company!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(prospect.company!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                              ],
                              const SizedBox(height: 4),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 4,
                                runSpacing: 2,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.person_outline, size: 12, color: Colors.grey.shade600),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Added by: ${prospect.createdByName ?? "Staff"}',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: _getRoleTagColor(prospect.createdByRole).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: _getRoleTagColor(prospect.createdByRole).withOpacity(0.4)),
                                    ),
                                    child: Text(
                                      _formatRoleDisplayName(prospect.createdByRole),
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: _getRoleTagColor(prospect.createdByRole),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (prospect.assignedByName != null || prospect.assignedTo != null) ...[
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
                                            : 'Assigned to: ${prospect.assignedByName ?? 'Assigned'}',
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
                              if (prospect.reassignmentRequested) ...[
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
                              ] else if (isAdmin && (prospect.reassignmentReason?.contains('Cancelled') == true || (prospect.notes?.contains('[REASSIGNMENT_CANCELLED]') ?? false))) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blueGrey.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.blueGrey.shade200),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.cancel_outlined, size: 11, color: Colors.blueGrey.shade700),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Reassign Request Cancelled',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blueGrey.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: ((isAdmin || profile?.primaryRole == UserRole.salesHead || profile?.primaryRole == UserRole.manager) && prospect.assignedTo == null && !isConverted)
                              ? ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6366F1),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                    minimumSize: const Size(60, 28),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  onPressed: () => _showTransferModal(context, ref, prospect),
                                  child: const Text('Assign', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isConverted
                                        ? AppColors.success.withOpacity(0.1)
                                        : (isTransferredAway ? Colors.grey.shade200 : AppColors.background),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isConverted
                                          ? AppColors.success
                                          : (isTransferredAway ? Colors.grey.shade400 : AppColors.border.withOpacity(0.5)),
                                    ),
                                  ),
                                  child: Text(
                                    isConverted
                                        ? 'Converted'
                                        : (isTransferredAway ? 'Transferred' : prospect.source),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: isConverted ? FontWeight.bold : FontWeight.normal,
                                      color: isConverted
                                          ? AppColors.success
                                          : (isTransferredAway ? Colors.grey.shade700 : AppColors.textSecondary),
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
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: FloatingActionButton.extended(
          heroTag: 'add_prospect_fab',
          onPressed: () {
            _showAddProspectForm(context);
          },
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('Add Prospect', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.primary,
        ),
      ),
    );
  }

  void _showTransferModal(BuildContext context, WidgetRef ref, Prospect prospect) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          bottom: true,
          child: _AssignProspectSheet(prospect: prospect),
        );
      },
    );
  }



  Widget _buildFilters() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search by name, phone, company...',
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
              children: ['All', ...(ref.watch(crmSourcesProvider).value ?? CrmSourcesNotifier.defaultSources)].map((source) {
                final isSelected = _selectedSource == source;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(
                      source,
                      style: TextStyle(
                        color: isSelected ? AppColors.primary : AppColors.textPrimary,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() => _selectedSource = source);
                    },
                    selectedColor: AppColors.primary.withOpacity(0.15),
                    checkmarkColor: AppColors.primary,
                    backgroundColor: AppColors.background,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleTagColor(String? role) {
    if (role == null) return Colors.grey;
    final r = role.toLowerCase();
    if (r.contains('admin')) return const Color(0xFF6366F1);
    if (r.contains('manager')) return Colors.purple;
    if (r.contains('sales_head')) return Colors.teal;
    if (r.contains('sales')) return const Color(0xFF0284C7);
    if (r.contains('boq')) return const Color(0xFFEC4899);
    if (r.contains('factory')) return const Color(0xFFF59E0B);
    if (r.contains('purchase')) return const Color(0xFF10B981);
    return Colors.blueGrey;
  }

  String _formatRoleDisplayName(String? role) {
    if (role == null || role.isEmpty) return 'Staff';
    final r = role.toLowerCase();
    if (r == 'boq') return 'BOQ Staff';
    if (r == 'factory') return 'Factory Staff';
    if (r == 'purchase') return 'Material Requisition Staff';
    if (r == 'sales') return 'Sales Executive';
    if (r == 'sales_head') return 'Sales Head';
    if (r == 'admin') return 'Admin';
    if (r == 'manager') return 'Manager';
    return role.toUpperCase();
  }

  void _showAddProspectForm(BuildContext context) {
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
            child: AddProspectForm(),
          ),
        );
      },
    );
  }
}

class AddProspectForm extends ConsumerStatefulWidget {
  const AddProspectForm({super.key});

  @override
  ConsumerState<AddProspectForm> createState() => _AddProspectFormState();
}

class _AddProspectFormState extends ConsumerState<AddProspectForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _gstCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _source = 'Manual';
  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _gstCtrl.dispose();
    _companyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(prospectsProvider.notifier).addProspect(
            name: _nameCtrl.text,
            phone: _phoneCtrl.text,
            email: _emailCtrl.text,
            address: _addressCtrl.text,
            gst: _gstCtrl.text,
            company: _companyCtrl.text,
            source: _source,
            notes: _notesCtrl.text,
          );
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prospect added successfully!'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding prospect: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
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
                    child: Text('New Prospect', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Customer/Business name *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Please enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Phone Number *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
                validator: (v) => v == null || v.trim().isEmpty ? 'Please enter a phone number' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email Address (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _companyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Contact Person Name (Optional)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _gstCtrl,
                      decoration: const InputDecoration(
                        labelText: 'GST Number (Optional)',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: (ref.watch(crmSourcesProvider).value ?? CrmSourcesNotifier.defaultSources).contains(_source)
                          ? _source
                          : ((ref.watch(crmSourcesProvider).value ?? CrmSourcesNotifier.defaultSources).isNotEmpty
                              ? (ref.watch(crmSourcesProvider).value ?? CrmSourcesNotifier.defaultSources).first
                              : 'Manual'),
                      decoration: const InputDecoration(
                        labelText: 'Lead Source',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.source_outlined),
                      ),
                      items: (ref.watch(crmSourcesProvider).value ?? CrmSourcesNotifier.defaultSources)
                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _source = v);
                      },
                    ),
                  ),
                  if (ref.watch(currentProfileProvider)?.primaryRole == UserRole.admin) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.tune, color: AppColors.primary),
                      tooltip: 'Manage Lead Sources (Admin)',
                      onPressed: () => _showManageLeadSourcesDialog(context, ref),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note_alt_outlined),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
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
                    : const Text('Save Prospect', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssignProspectSheet extends ConsumerStatefulWidget {
  final Prospect prospect;

  const _AssignProspectSheet({required this.prospect});

  @override
  ConsumerState<_AssignProspectSheet> createState() => _AssignProspectSheetState();
}

class _AssignProspectSheetState extends ConsumerState<_AssignProspectSheet> {
  String? _selectedSalesUserId;
  bool _isLoading = false;
  bool _fetchingStaff = true;
  List<Map<String, dynamic>> _salesStaff = [];

  @override
  void initState() {
    super.initState();
    _fetchSalesStaff();
  }

  Future<void> _fetchSalesStaff() async {
    setState(() => _fetchingStaff = true);
    try {
      final db = ref.read(supabaseClientProvider);
      dynamic res;
      try {
        res = await db.from('profiles').select('id, full_name, role, roles, email').order('full_name');
      } catch (_) {
        res = await db.from('profiles').select().order('created_at', ascending: false);
      }

      final list = <Map<String, dynamic>>[];
      for (final r in (res as List? ?? [])) {
        final role = (r['role'] as String? ?? '').toLowerCase();
        final rolesList = (r['roles'] is List)
            ? (r['roles'] as List).map((e) => e.toString().toLowerCase()).toList()
            : [];
        final name = (r['full_name'] as String? ?? '').toLowerCase();
        final email = (r['email'] as String? ?? '').toLowerCase();

        // 1. Exclude Admin and General Managers (supervisors who have company-wide access)
        // Keep Sales Heads and Sales Executives
        final isAdminOrManager = role == 'admin' ||
            role == 'administrator' ||
            role == 'manager' ||
            rolesList.contains('admin') ||
            rolesList.contains('administrator') ||
            rolesList.contains('manager') ||
            name.contains('admin') ||
            email.contains('admin');
        if (isAdminOrManager) continue;

        // 2. MUST be Sales Executive or Sales Head
        final isSalesHead = role == 'sales_head' ||
            role == 'saleshead' ||
            rolesList.contains('sales_head') ||
            rolesList.contains('saleshead');
        final isSalesExecutive = role == 'sales' ||
            role == 'sales_executive' ||
            rolesList.contains('sales') ||
            rolesList.contains('sales_executive');

        if (!isSalesExecutive && !isSalesHead) continue;

        final userCopy = Map<String, dynamic>.from(r as Map<String, dynamic>);
        userCopy['is_sales_head'] = isSalesHead;
        list.add(userCopy);
      }

      final finalList = list;

      if (mounted) {
        setState(() {
          _salesStaff = finalList;
          if (_salesStaff.isNotEmpty && _selectedSalesUserId == null) {
            _selectedSalesUserId = _salesStaff.first['id'] as String?;
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching sales staff: $e');
    } finally {
      if (mounted) setState(() => _fetchingStaff = false);
    }
  }

  Future<void> _assign() async {
    if (_selectedSalesUserId == null) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(prospectsProvider.notifier).assignProspect(
            prospectId: widget.prospect.id,
            salesUserId: _selectedSalesUserId!,
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Prospect transferred to salesperson successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error assigning prospect: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Transfer Prospect to Sales Rep',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Assign "${widget.prospect.name}" to a salesperson for follow-ups.',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          if (_fetchingStaff)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          else if (_salesStaff.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text('No sales representatives found in system.', style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: _selectedSalesUserId,
              decoration: const InputDecoration(
                labelText: 'Select Sales Representative',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_pin_outlined),
              ),
              items: _salesStaff.map((s) {
                final name = s['full_name'] as String? ?? s['email'] as String? ?? 'Sales Staff';
                final isHead = s['is_sales_head'] == true;
                return DropdownMenuItem<String>(
                  value: s['id'] as String,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isHead ? Colors.teal.withOpacity(0.12) : AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isHead ? 'SALES HEAD' : 'SALES EXECUTIVE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isHead ? Colors.teal.shade800 : AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedSalesUserId = val),
            ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _isLoading || _selectedSalesUserId == null ? null : _assign,
            child: _isLoading
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Confirm Transfer', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

void _showManageLeadSourcesDialog(BuildContext context, WidgetRef ref) {
  final newSourceCtrl = TextEditingController();
  showDialog(
    context: context,
    builder: (dialogCtx) {
      return Consumer(
        builder: (context, ref, _) {
          final sourcesAsync = ref.watch(crmSourcesProvider);
          final sources = sourcesAsync.value ?? CrmSourcesNotifier.defaultSources;

          return AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.tune, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Manage Lead Sources', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add or remove lead source references available across the app.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: newSourceCtrl,
                          decoration: const InputDecoration(
                            hintText: 'New Source Name',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: () async {
                          final name = newSourceCtrl.text.trim();
                          if (name.isNotEmpty) {
                            await ref.read(crmSourcesProvider.notifier).addSource(name);
                            newSourceCtrl.clear();
                          }
                        },
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: sources.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final s = sources[index];
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                          title: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                            tooltip: 'Delete source',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Delete Source?'),
                                  content: Text('Are you sure you want to delete source "$s"?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await ref.read(crmSourcesProvider.notifier).deleteSource(s);
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    },
  );
}

