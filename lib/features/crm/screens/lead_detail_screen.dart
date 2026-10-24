import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pdf_preview_screen.dart';
import '../data/models/lead_model.dart';
import '../data/models/prospect_model.dart';
import '../services/crm_pdf_service.dart';
import '../providers/crm_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/crm_delete_dialog.dart';
import '../widgets/product_combo_selector.dart';
import '../../quotation/screens/quotation_form_screen.dart';
import '../../../core/models/quotation.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/models/customer.dart';
import '../../../core/models/product.dart';
import '../../../core/services/record_edit_permissions.dart';
import '../../quotation_generator/ui/screens/quotation_preview_screen.dart';
import '../../quotation_generator/providers/quotation_generator_providers.dart';
import '../../quotation_generator/models/generator_company_settings.dart';
import '../../../core/providers/company_provider.dart';
import '../../quotation_generator/models/deal_quotation_item.dart';
import '../../quotation_generator/models/boom_barrier_proposal_draft.dart';
import '../../quotation_generator/models/qg_product_profile.dart';
import '../../quotation_generator/services/qg_boom_barrier_drafts_service.dart';
import '../../quotation_generator/templates/qg_template_registry.dart';
import '../../quotation_generator/templates/boom_barrier_template.dart';
import '../../quotation_generator/ui/screens/boom_barrier_preview_screen.dart';
import '../../quotation_generator/models/qg_proposal_draft.dart';
import '../../quotation_generator/services/qg_drafts_service.dart';
import '../../quotation_generator/services/qg_model_specs_resolver.dart';
import '../../../core/utils/global_click_guard.dart';
import '../../../core/widgets/pdf_loading_dialog.dart';

class LeadDetailScreen extends ConsumerStatefulWidget {
  final String id;

  const LeadDetailScreen({super.key, required this.id});

  @override
  ConsumerState<LeadDetailScreen> createState() => _LeadDetailScreenState();
}

class _LeadDetailScreenState extends ConsumerState<LeadDetailScreen> {
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(leadsProvider.notifier).load();
      ref.read(prospectsProvider.notifier).load();
    });
  }

  Future<void> _handleRefresh(String leadId) async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await Future.wait([
        ref.read(leadsProvider.notifier).load(refresh: false),
        ref.read(prospectsProvider.notifier).load(refresh: false),
        ref.read(leadCommunicationsProvider(leadId).notifier).load(),
      ]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('✓ Lead details refreshed'),
              ],
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final leadsAsync = ref.watch(leadsProvider);
    final lead = ref.watch(leadByIdProvider(widget.id));
    final prospect = lead?.prospectId != null ? ref.watch(prospectByIdProvider(lead!.prospectId!)) : null;
    final profile = ref.watch(currentProfileProvider);
    final isSalesOrAdmin = profile?.primaryRole.isSalesOrAdmin ?? false;
    final isAdmin = profile?.primaryRole == UserRole.admin || profile?.primaryRole == UserRole.manager || profile?.primaryRole == UserRole.salesHead || profile?.roles.contains(UserRole.admin) == true || profile?.roles.contains(UserRole.salesHead) == true || profile?.roles.contains(UserRole.manager) == true;
    final isSalesRole = profile?.primaryRole == UserRole.sales ||
        profile?.roles.contains(UserRole.sales) == true ||
        (!isAdmin && (lead?.assignedTo == profile?.id || lead?.createdBy == profile?.id));
    final isConverted = lead != null && (lead.convertedToCustomerId != null || lead.status.toLowerCase() == 'won');
    final isLost = lead != null && lead.status.toLowerCase() == 'lost';
    final isAssignedToMe = !isConverted && !isLost && lead != null && lead.assignedTo != null && lead.assignedTo == profile?.id;

    if (lead == null) {
      if (leadsAsync.isLoading) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(title: const Text('Lead Details')),
          body: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading lead details...', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
              ],
            ),
          ),
        );
      }

      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Lead Details'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/crm/leads');
              }
            },
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_outline_rounded, size: 48, color: Color(0xFFEF4444)),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Lead Not Found',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This lead may have been deleted or removed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/crm/leads');
                    }
                  },
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Back to Leads'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final displayName = (lead.prospectName != null && lead.prospectName!.isNotEmpty)
        ? lead.prospectName!
        : (prospect?.name ?? 'Lead #${lead.id.substring(0, 6)}');
    final displayPhone = (lead.contactPhone != null && lead.contactPhone!.isNotEmpty)
        ? lead.contactPhone!
        : (prospect?.phone ?? '');
    final displayEmail = prospect?.email;

    final canEdit = RecordEditPermissions.canEditRecord(
      userRole: profile?.primaryRole,
      allRoles: profile?.roles ?? [],
      currentUserId: profile?.id,
      creatorId: lead.createdBy,
      assigneeId: lead.assignedTo,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/crm/leads');
            }
          },
        ),
        title: Text(displayName),
        actions: [
          if (canEdit && !isConverted)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Lead',
              onPressed: () => _showEditLeadModal(context, ref, lead),
            ),
          if (isAdmin)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.25)),
              ),
              child: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFF87171), size: 20),
                tooltip: 'Delete Lead (Admin)',
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => _confirmDeleteLead(context, ref, lead, prospect, displayName),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Download Communication & Lead PDF',
            onPressed: () => _downloadReportPdf(context, ref, lead, prospect),
          ),
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isRefreshing ? null : () => _handleRefresh(lead.id),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isRefreshing) const LinearProgressIndicator(minHeight: 2.5),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 100.0),
              child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isAdmin && lead.reassignmentRequested && !isConverted)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade400, width: 1.5),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '⚠️ REASSIGNMENT REQUESTED',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.brown,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Reason: "${lead.reassignmentReason ?? 'Salesperson requested reassignment'}"',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _showAssignLeadSheet(context, ref, lead),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text('Reassign', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
              ),

            // 1. Lead Header Card
            Card(
              elevation: 0,
              color: isAssignedToMe ? const Color(0xFFFFFBEB) : AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isAssignedToMe ? const Color(0xFFF59E0B) : AppColors.border,
                  width: isAssignedToMe ? 2 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: isConverted
                              ? AppColors.success.withOpacity(0.1)
                              : (isAssignedToMe ? const Color(0xFFFEF3C7) : AppColors.primary.withOpacity(0.1)),
                          child: Icon(
                            isConverted
                                ? Icons.check_circle
                                : (isAssignedToMe ? Icons.assignment_ind : Icons.trending_up),
                            size: 32,
                            color: isConverted
                                ? AppColors.success
                                : (isAssignedToMe ? const Color(0xFFD97706) : AppColors.primary),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                lead.productName,
                                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              if (displayPhone.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(displayPhone, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                              ],
                              if (isAssignedToMe) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFF59E0B)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.stars, size: 12, color: Color(0xFFD97706)),
                                      SizedBox(width: 4),
                                      Text(
                                        '🎯 Assigned to You',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 11,
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
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Quick Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (displayPhone.isNotEmpty) ...[
                          _QuickActionButton(
                            icon: Icons.phone,
                            label: 'Call',
                            color: AppColors.primary,
                            onTap: () => _makePhoneCall(context, ref, lead.id, displayPhone),
                          ),
                          const SizedBox(width: 20),
                          _QuickActionButton(
                            icon: Icons.chat,
                            label: 'WhatsApp',
                            color: const Color(0xFF25D366),
                            onTap: () => _openWhatsApp(context, ref, lead.id, displayPhone),
                          ),
                        ],
                        if (displayEmail != null && displayEmail.isNotEmpty) ...[
                          const SizedBox(width: 20),
                          _QuickActionButton(
                            icon: Icons.email,
                            label: 'Email',
                            color: Colors.blue,
                            onTap: () => _sendEmail(context, ref, lead.id, displayEmail),
                          ),
                        ],
                        const SizedBox(width: 20),
                        _QuickActionButton(
                          icon: Icons.notification_add_outlined,
                          label: (lead.reminders.isNotEmpty || lead.reminderDate != null)
                              ? 'Alerts (${lead.reminders.isNotEmpty ? lead.reminders.length : 1})'
                              : 'Set Alert',
                          color: const Color(0xFFD97706),
                          onTap: () => _showSetReminderDialog(context, ref, lead),
                        ),
                      ],
                    ),
                    if (lead.reminders.isNotEmpty || lead.reminderDate != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFF59E0B)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: const [
                                    Text('🔔', style: TextStyle(fontSize: 16)),
                                    SizedBox(width: 8),
                                    Text(
                                      'Scheduled Follow-up Alerts',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF92400E),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                InkWell(
                                  onTap: () => _showSetReminderDialog(context, ref, lead),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    child: Text(
                                      '+ Add Alert',
                                      style: TextStyle(
                                        color: Color(0xFFB45309),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(color: Color(0xFFFDE68A), height: 16),
                            if (lead.reminders.isNotEmpty)
                              ...lead.reminders.map((r) {
                                final rId = r['id']?.toString() ?? '';
                                final dtStr = r['date_time']?.toString() ?? '';
                                final dt = DateTime.tryParse(dtStr)?.toLocal();
                                final note = r['note']?.toString();

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.alarm, size: 16, color: Color(0xFFD97706)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              dt != null
                                                  ? DateFormat('dd MMM yyyy, hh:mm a').format(dt)
                                                  : 'Follow-up scheduled',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF92400E),
                                                fontSize: 12,
                                              ),
                                            ),
                                            if (note != null && note.isNotEmpty)
                                              Text(
                                                note,
                                                style: const TextStyle(
                                                  color: Color(0xFF78350F),
                                                  fontSize: 12,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 16, color: Color(0xFFB45309)),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        tooltip: 'Delete alert',
                                        onPressed: () {
                                          if (rId.isNotEmpty) {
                                            ref.read(leadsProvider.notifier).deleteReminder(
                                                  leadId: lead.id,
                                                  reminderId: rId,
                                                );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              })
                            else if (lead.reminderDate != null)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.alarm, size: 16, color: Color(0xFFD97706)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          DateFormat('dd MMM yyyy, hh:mm a').format(lead.reminderDate!.toLocal()),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF92400E),
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (lead.reminderNote != null && lead.reminderNote!.isNotEmpty)
                                          Text(
                                            lead.reminderNote!,
                                            style: const TextStyle(
                                              color: Color(0xFF78350F),
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. Deal Details Card
            Card(
              elevation: 0,
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Deal Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        _DealStatusHeader(lead: lead, isConverted: isConverted),
                      ],
                    ),
                    const Divider(height: 24),
                    _buildDetailRow(Icons.solar_power_outlined, 'Product', lead.productName),
                    const SizedBox(height: 12),
                    _buildDetailRow(Icons.currency_rupee, 'Est. Value', '₹${lead.estimatedValue.toStringAsFixed(2)}'),
                    if (lead.expectedDate != null) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        Icons.event_outlined,
                        'Expected Close',
                        '${lead.expectedDate!.day.toString().padLeft(2, '0')}/${lead.expectedDate!.month.toString().padLeft(2, '0')}/${lead.expectedDate!.year}',
                      ),
                    ],
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      Icons.calendar_today_outlined,
                      'Created Date',
                      '${lead.createdAt.day.toString().padLeft(2, '0')}/${lead.createdAt.month.toString().padLeft(2, '0')}/${lead.createdAt.year}',
                    ),
                    if (lead.capacity != null && lead.capacity!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(Icons.speed_outlined, 'Capacity', lead.capacity!),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.assignment_ind_outlined, size: 20, color: AppColors.textSecondary),
                        const SizedBox(width: 12),
                        const SizedBox(width: 110, child: Text('Salesperson', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500))),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  lead.assignedByName ?? (lead.assignedTo != null ? 'Assigned' : 'Not Assigned'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: (lead.assignedByName != null || lead.assignedTo != null)
                                        ? AppColors.textPrimary
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                              if (!isConverted && !isLost) ...[
                                if (isAdmin) ...[
                                  InkWell(
                                    onTap: () => _showAssignLeadSheet(context, ref, lead),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        lead.assignedTo != null ? 'Reassign' : 'Assign',
                                        style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                  if (lead.assignedTo != null) ...[
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () => _confirmRemoveLeadAssignment(context, ref, lead),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.error.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Remove',
                                          style: TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ],
                                ]
                                else if (isSalesRole && !lead.reassignmentRequested)
                                  InkWell(
                                    onTap: () => _showRequestReassignDialog(context, ref, lead),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Request Reassign',
                                        style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (lead.convertedByName != null && lead.convertedByName!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildDetailRow(Icons.verified_user_outlined, 'Converted by', lead.convertedByName!),
                    ],
                    if (lead.notes != null && lead.notes!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('Notes / Requirements:', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(lead.notes!, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. Lead Quotations & Revision History
            _LeadQuotationsSection(
              lead: lead,
              canCreateQuotation: !isLost && (profile?.primaryRole.canCreateQuotation ?? false),
            ),
            const SizedBox(height: 16),

            // 4. Communication History (Only inside Lead)
            _LeadCommunicationSection(
              leadId: lead.id,
              isWon: lead.status == 'Won',
              isLost: isLost,
              onDownloadPdf: () => _downloadReportPdf(context, ref, lead, prospect),
            ),
            const SizedBox(height: 24),

            // 4. Bottom Action
            if (isConverted)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.success,
                  side: const BorderSide(color: AppColors.success),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: profile?.primaryRole == UserRole.crmStaff
                    ? null
                    : () {
                        if (lead.convertedToCustomerId != null) {
                          context.push('/customers/${lead.convertedToCustomerId}');
                        } else {
                          context.go('/crm/customers');
                        }
                      },
                icon: const Icon(Icons.check_circle, color: AppColors.success),
                label: Text(
                  profile?.primaryRole == UserRole.crmStaff
                      ? 'Deal Won (Converted)'
                      : 'Deal Won • View Customer',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              )
            else if (!isLost && isSalesOrAdmin) ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _showConvertToCustomerSheet(context, ref, lead, displayName, displayPhone, displayEmail, prospect?.address, prospect?.gst),
                icon: const Icon(Icons.star, color: Colors.white),
                label: const Text('Convert to Customer (Won)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              if (!isConverted && !isLost) ...[
                if (isAdmin) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFF6366F1)),
                      foregroundColor: const Color(0xFF6366F1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _showAssignLeadSheet(context, ref, lead),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Transfer / Reassign to Sales Rep', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ] else if (isSalesRole) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.orange),
                      foregroundColor: Colors.orange.shade800,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _showRequestReassignDialog(context, ref, lead),
                    icon: const Icon(Icons.outgoing_mail),
                    label: const Text('Request Admin to Reassign Lead', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    ),
  ],
),
);
  }

  bool _isGeneratingReport = false;
  Future<void> _downloadReportPdf(BuildContext context, WidgetRef ref, Lead lead, Prospect? prospect) async {
    if (_isGeneratingReport || !GlobalClickGuard.canClick()) return;
    _isGeneratingReport = true;
    final dismissLoading = PdfLoadingDialog.show(
      context,
      title: 'Generating Lead Report PDF...',
      message: 'Compiling lead communications & activity.\nPlease wait...',
    );

    try {
      final comms = ref.read(leadCommunicationsProvider(lead.id)).value ?? [];
      final pdfBytes = await CrmPdfService.generateLeadReportPdf(
        lead: lead,
        prospect: prospect,
        communications: comms,
      );
      final cleanName = (lead.prospectName ?? 'Lead').replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final fileName = '${cleanName}_Communication_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';

      dismissLoading();
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PdfPreviewScreen(
              pdfBytes: pdfBytes,
              fileName: fileName,
            ),
          ),
        );
      }
    } catch (e) {
      dismissLoading();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating PDF: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      _isGeneratingReport = false;
    }
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        SizedBox(width: 110, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500))),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
      ],
    );
  }

  void _showEditLeadModal(BuildContext context, WidgetRef ref, Lead lead) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        bottom: true,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: _EditLeadSheet(lead: lead),
        ),
      ),
    );
  }

  void _showSetReminderDialog(BuildContext context, WidgetRef ref, Lead lead) {
    DateTime selectedDate = lead.reminderDate?.toLocal() ?? DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(selectedDate);
    final noteCtrl = TextEditingController(text: lead.reminderNote ?? '');
    final timeTextCtrl = TextEditingController(
      text: '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.alarm, color: Color(0xFFD97706)),
              SizedBox(width: 8),
              Text('Set Follow-up Alert'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Schedule a reminder to call or follow up on this lead:',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today, color: AppColors.primary),
                  title: const Text('Date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(DateFormat('dd MMM yyyy').format(selectedDate)),
                  onTap: () async {
                    final today = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate.isBefore(today) ? today : selectedDate,
                      firstDate: DateTime(today.year, today.month, today.day),
                      lastDate: today.add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: timeTextCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Time (HH:mm)',
                          hintText: 'e.g. 14:30 or 02:30 PM',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.access_time, color: AppColors.primary),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        onChanged: (val) {
                          final parts = val.trim().split(':');
                          if (parts.length == 2) {
                            final h = int.tryParse(parts[0].trim());
                            final m = int.tryParse(parts[1].trim());
                            if (h != null && m != null && h >= 0 && h < 24 && m >= 0 && m < 60) {
                              selectedTime = TimeOfDay(hour: h, minute: m);
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.timer_outlined, color: AppColors.primary, size: 28),
                      tooltip: 'Pick Time',
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setDialogState(() {
                            selectedTime = picked;
                            timeTextCtrl.text =
                                '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Reminder Note',
                    hintText: 'e.g. Call to discuss pricing proposal',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                int finalHour = selectedTime.hour;
                int finalMinute = selectedTime.minute;
                final rawTime = timeTextCtrl.text.trim();
                final match = RegExp(r'^(\d{1,2}):(\d{2})(?:\s*(am|pm))?$', caseSensitive: false).firstMatch(rawTime);
                if (match != null) {
                  int h = int.parse(match.group(1)!);
                  int m = int.parse(match.group(2)!);
                  final ampm = match.group(3)?.toLowerCase();
                  if (ampm == 'pm' && h < 12) h += 12;
                  if (ampm == 'am' && h == 12) h = 0;
                  if (h >= 0 && h < 24 && m >= 0 && m < 60) {
                    finalHour = h;
                    finalMinute = m;
                  }
                }

                final combined = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  finalHour,
                  finalMinute,
                );

                Navigator.pop(ctx);
                await ref.read(leadsProvider.notifier).addReminder(
                      leadId: lead.id,
                      reminderDate: combined,
                      reminderNote: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🔔 Follow-up alert added successfully!'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              },
              child: const Text('Save Alert'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRequestReassignDialog(BuildContext context, WidgetRef ref, Lead lead) {
    final noteCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Reassignment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Request Admin to transfer "${lead.prospectName ?? "this lead"}" to another salesperson.'),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason for reassignment (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(leadsProvider.notifier).requestTransfer(
                    leadId: lead.id,
                    leadName: lead.prospectName ?? 'Lead #${lead.id.substring(0, 6)}',
                    reason: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                  );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Reassignment request sent to Admin successfully.'),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
            child: const Text('Submit Request', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveLeadAssignment(BuildContext context, WidgetRef ref, Lead lead) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Assignment'),
        content: Text('Are you sure you want to remove the salesperson assignment for "${lead.prospectName ?? "this lead"}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(leadsProvider.notifier).unassignLead(leadId: lead.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Assignment removed successfully.'),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAssignLeadSheet(BuildContext context, WidgetRef ref, Lead lead) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          bottom: true,
          child: _AssignLeadDetailSheet(lead: lead),
        );
      },
    );
  }

  void _showConvertToCustomerSheet(
    BuildContext context,
    WidgetRef ref,
    Lead lead,
    String defaultName,
    String defaultPhone,
    String? defaultEmail,
    String? defaultAddress,
    String? defaultGst,
  ) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: defaultName);
    final phoneCtrl = TextEditingController(text: defaultPhone);
    final emailCtrl = TextEditingController(text: defaultEmail ?? '');
    final addressCtrl = TextEditingController(text: defaultAddress ?? '');
    final gstCtrl = TextEditingController(text: defaultGst ?? '');
    final notesCtrl = TextEditingController(text: lead.notes ?? '');
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final availHeight = MediaQuery.of(context).size.height - MediaQuery.of(context).viewInsets.bottom;
            return Container(
              constraints: BoxConstraints(maxHeight: (availHeight * 0.9).clamp(320.0, double.infinity)),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 24,
                left: 24,
                right: 24,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Convert Lead to Customer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          IconButton(onPressed: () => ctx.pop(), icon: const Icon(Icons.close)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Marking this lead as WON and creating a formal customer account.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Customer / Company Name *', border: OutlineInputBorder()),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneCtrl,
                        decoration: const InputDecoration(labelText: 'Phone Number *', border: OutlineInputBorder()),
                        keyboardType: TextInputType.phone,
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailCtrl,
                        decoration: const InputDecoration(labelText: 'Email Address (Optional)', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressCtrl,
                        decoration: const InputDecoration(labelText: 'Address (Optional)', border: OutlineInputBorder()),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: gstCtrl,
                        decoration: const InputDecoration(labelText: 'GST Number (Optional)', border: OutlineInputBorder()),
                        textCapitalization: TextCapitalization.characters,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesCtrl,
                        decoration: const InputDecoration(labelText: 'Notes (Optional)', border: OutlineInputBorder()),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setSheetState(() => isSaving = true);
                                try {
                                  await ref.read(leadsProvider.notifier).convertToCustomer(
                                        leadId: lead.id,
                                        customerName: nameCtrl.text.trim(),
                                        phone: phoneCtrl.text.trim(),
                                        email: emailCtrl.text.trim(),
                                        address: addressCtrl.text.trim(),
                                        gstNumber: gstCtrl.text.trim(),
                                        notes: notesCtrl.text.trim(),
                                      );
                                  if (ctx.mounted) {
                                    ctx.pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Lead converted to Customer successfully!'), backgroundColor: AppColors.success),
                                    );
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
                                    );
                                  }
                                } finally {
                                  if (ctx.mounted) setSheetState(() => isSaving = false);
                                }
                              },
                        child: isSaving
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Confirm Won & Create Customer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _makePhoneCall(BuildContext context, WidgetRef ref, String leadId, String phone) async {
    try {
      final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
      final uri = Uri.parse('tel:$cleanPhone');
      await launchUrl(uri);
      _promptLogCommunication(context, ref, leadId, 'Call');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not initiate phone call: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _openWhatsApp(BuildContext context, WidgetRef ref, String leadId, String phone) async {
    try {
      var cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
      if (cleanPhone.length == 10) {
        cleanPhone = '91$cleanPhone';
      }
      final uri = Uri.parse('https://wa.me/$cleanPhone');
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      _promptLogCommunication(context, ref, leadId, 'WhatsApp');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open WhatsApp: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _sendEmail(BuildContext context, WidgetRef ref, String leadId, String email) async {
    try {
      final uri = Uri.parse('mailto:${email.trim()}');
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      _promptLogCommunication(context, ref, leadId, 'Email');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open Email app: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _promptLogCommunication(BuildContext context, WidgetRef ref, String leadId, String type) {
    final currentLead = ref.read(leadByIdProvider(leadId));
    final isWon = currentLead?.status.toLowerCase() == 'won';
    final profile = ref.read(currentProfileProvider);
    final isAdmin = (profile?.primaryRole == UserRole.admin) || (profile?.roles.contains(UserRole.admin) ?? false);
    if (isWon && !isAdmin) return;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (context.mounted) {
        _showLogDialog(context, ref, leadId, defaultType: type, isWon: isWon);
      }
    });
  }

  static Future<void> _showManageInteractionTypesModal(BuildContext context, WidgetRef ref) async {
    final addCtrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final typesAsync = ref.watch(crmInteractionTypesProvider);
          final types = typesAsync.value ?? CrmInteractionTypesNotifier.defaultTypes;
          final availHeight = MediaQuery.of(context).size.height - MediaQuery.of(context).viewInsets.bottom;

          return Container(
            constraints: BoxConstraints(maxHeight: (availHeight * 0.85).clamp(280.0, double.infinity)),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 20,
              left: 20,
              right: 20,
            ),
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
                        'Manage Interaction Types',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Add custom interaction channels or remove unused ones:',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: addCtrl,
                        decoration: const InputDecoration(
                          labelText: 'New Type Name',
                          hintText: 'e.g. Site Visit, Demo',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onPressed: () async {
                        final text = addCtrl.text.trim();
                        if (text.isNotEmpty) {
                          await ref.read(crmInteractionTypesProvider.notifier).addType(text);
                          addCtrl.clear();
                          setSheetState(() {});
                        }
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                Expanded(
                  child: ListView.separated(
                    itemCount: types.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = types[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          child: const Icon(Icons.chat_bubble_outline, size: 14, color: AppColors.primary),
                        ),
                        title: Text(item, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                          tooltip: 'Delete type',
                          onPressed: () async {
                            await ref.read(crmInteractionTypesProvider.notifier).deleteType(item);
                            setSheetState(() {});
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static void _showLogDialog(BuildContext context, WidgetRef ref, String leadId, {String defaultType = 'Call', bool isWon = false}) {
    final profile = ref.read(currentProfileProvider);
    final isAdmin = (profile?.primaryRole == UserRole.admin) || (profile?.roles.contains(UserRole.admin) ?? false);
    if (isWon && !isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer is Won. Adding communication logs is disabled.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final summaryCtrl = TextEditingController();
    String selectedType = defaultType;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        bool isSubmitting = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final typeList = ref.watch(crmInteractionTypesProvider).value ?? CrmInteractionTypesNotifier.defaultTypes;
            if (!typeList.contains(selectedType)) {
              selectedType = typeList.isNotEmpty ? typeList.first : 'Call';
            }

            final availHeight = MediaQuery.of(context).size.height - MediaQuery.of(context).viewInsets.bottom;

            return Container(
              constraints: BoxConstraints(maxHeight: (availHeight * 0.9).clamp(300.0, double.infinity)),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 24,
                left: 24,
                right: 24,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Log Communication', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      IconButton(onPressed: () => ctx.pop(), icon: const Icon(Icons.close)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Interaction Type *',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.settings, size: 14),
                        label: const Text('Manage Types', style: TextStyle(fontSize: 12)),
                        onPressed: () async {
                          await _showManageInteractionTypesModal(context, ref);
                          setSheetState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: typeList
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setSheetState(() => selectedType = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: summaryCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Summary / Outcome *',
                      hintText: 'e.g. Discussed pricing, customer requested 10% discount',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            if (summaryCtrl.text.trim().isEmpty) return;
                            if (!GlobalClickGuard.canClick()) return;

                            setSheetState(() => isSubmitting = true);
                            GlobalClickGuard.setBusy(true);

                            try {
                              await ref.read(leadCommunicationsProvider(leadId).notifier).logCommunication(
                                    type: selectedType,
                                    summary: summaryCtrl.text.trim(),
                                  );
                              if (ctx.mounted) {
                                ctx.pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Interaction logged!'), backgroundColor: AppColors.success),
                                );
                              }
                            } finally {
                              GlobalClickGuard.setBusy(false);
                              if (ctx.mounted) {
                                setSheetState(() => isSubmitting = false);
                              }
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save Interaction', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteLead(
    BuildContext context,
    WidgetRef ref,
    Lead lead,
    Prospect? prospect,
    String displayName,
  ) async {
    String? customerId = lead.convertedToCustomerId;
    if (customerId == null) {
      try {
        final client = ref.read(supabaseClientProvider);
        final custRes = await client
            .from('customers')
            .select('id')
            .or('lead_id.eq.${lead.id},phone.eq.${lead.contactPhone ?? ""}')
            .maybeSingle();
        if (custRes != null) {
          customerId = custRes['id'] as String?;
        }
      } catch (_) {}
    }

    if (!context.mounted) return;

    if (customerId != null) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => CrmDeleteConvertedDialog(
          recordName: displayName,
          recordType: 'Lead',
        ),
      );

      if (choice == null || choice == 'cancel') return;
      final isBoth = choice == 'crm_and_customer';

      if (!context.mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => CrmDeleteConfirmDialog(
          title: isBoth ? 'Confirm Permanent Delete' : 'Delete from CRM Only',
          message: isBoth
              ? 'Are you sure you want to permanently delete lead for "$displayName" from CRM AND remove their customer profile? This action cannot be undone.'
              : 'Are you sure you want to remove lead for "$displayName" from CRM? Their customer account and order history will remain safely preserved.',
          confirmLabel: isBoth ? 'Delete Both' : 'Delete from CRM',
          isDestructive: true,
        ),
      );

      if (confirm == true) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => PopScope(
            canPop: false,
            child: Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Text(
                        isBoth ? 'Deleting from CRM & Customers...' : 'Deleting lead...',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        try {
          await ref.read(leadsProvider.notifier).deleteLead(
                leadId: lead.id,
                deleteCustomer: isBoth,
                customerId: customerId,
              );
          await ref.read(prospectsProvider.notifier).load();

          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pop(); // dismiss progress dialog
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/crm/leads');
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isBoth
                            ? '✓ Lead and customer record deleted successfully'
                            : '✓ Lead deleted successfully',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pop(); // dismiss progress dialog
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Error deleting lead: $e'),
                    ),
                  ],
                ),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => CrmDeleteConfirmDialog(
          title: 'Delete Lead',
          message: 'Are you sure you want to delete lead for "$displayName"? This action cannot be undone.',
          confirmLabel: 'Delete',
          isDestructive: true,
        ),
      );

      if (confirm == true) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => PopScope(
            canPop: false,
            child: Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    SizedBox(width: 18),
                    Expanded(
                      child: Text(
                        'Deleting lead...',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        try {
          await ref.read(leadsProvider.notifier).deleteLead(leadId: lead.id);
          await ref.read(prospectsProvider.notifier).load();

          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pop(); // dismiss progress dialog
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/crm/leads');
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '✓ Lead deleted successfully',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pop(); // dismiss progress dialog
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Error deleting lead: $e'),
                    ),
                  ],
                ),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    }
  }
}

class _EditLeadSheet extends ConsumerStatefulWidget {
  final Lead lead;
  const _EditLeadSheet({required this.lead});

  @override
  ConsumerState<_EditLeadSheet> createState() => _EditLeadSheetState();
}

class _EditLeadSheetState extends ConsumerState<_EditLeadSheet> {
  final _formKey = GlobalKey<FormState>();
  Prospect? _selectedProspect;
  late final TextEditingController _contactPhoneCtrl;
  late final TextEditingController _valCtrl;
  late final TextEditingController _notesCtrl;
  DateTime? _expectedDate;
  bool _isSaving = false;

  List<ProductComboItem> _availableCombos = [];
  List<ProductComboItem> _selectedProducts = [];
  String? _productError;

  @override
  void initState() {
    super.initState();
    _contactPhoneCtrl = TextEditingController(text: widget.lead.contactPhone ?? '');
    _valCtrl = TextEditingController(
      text: _formatIndianDealValue(widget.lead.estimatedValue),
    );
    _notesCtrl = TextEditingController(text: widget.lead.notes ?? '');
    _expectedDate = widget.lead.expectedDate;

    // Initialize prospect
    if (widget.lead.prospectName != null && widget.lead.prospectName!.isNotEmpty) {
      _selectedProspect = Prospect(
        id: widget.lead.prospectId ?? '',
        name: widget.lead.prospectName!,
        phone: widget.lead.contactPhone ?? '',
        source: 'Manual',
        createdBy: widget.lead.createdBy,
        createdAt: widget.lead.createdAt,
        updatedAt: DateTime.now(),
      );
    }

    _availableCombos = List<ProductComboItem>.from(ProductComboItem.defaultCombos);

    // Initialize selected products
    if (widget.lead.components != null && widget.lead.components!.isNotEmpty) {
      _selectedProducts = widget.lead.components!
          .map((c) => ProductComboItem.fromComponentMap(c))
          .toList();
    } else if (widget.lead.productName.isNotEmpty) {
      final names = widget.lead.productName.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
      for (final n in names) {
        final match = _availableCombos.where((c) => c.displayName.toLowerCase() == n.toLowerCase()).firstOrNull;
        if (match != null) {
          _selectedProducts.add(match);
        } else {
          _selectedProducts.add(
            ProductComboItem(
              displayName: n,
              productName: n,
              capacity: widget.lead.capacity,
              price: widget.lead.estimatedValue,
            ),
          );
        }
      }
    }

    _loadCombos();
  }

  String _formatIndianDealValue(double value) {
    if (value <= 0) return '0';
    final isWhole = (value % 1 == 0);
    final pattern = isWhole ? '#,##,###' : '#,##,###.##';
    return NumberFormat(pattern, 'en_IN').format(value);
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
      _valCtrl.text = _formatIndianDealValue(total);
    });
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
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
      final cleanValStr = _valCtrl.text.replaceAll(',', '').trim();
      final totalValue = double.tryParse(cleanValStr) ??
          _selectedProducts.fold<double>(0.0, (sum, i) => sum + i.price);

      await ref.read(leadsProvider.notifier).updateLead(
            leadId: widget.lead.id,
            prospectId: _selectedProspect?.id.isNotEmpty == true ? _selectedProspect!.id : null,
            prospectName: _selectedProspect?.name ?? widget.lead.prospectName ?? '',
            contactPhone: _contactPhoneCtrl.text.trim(),
            productName: joinedProductName,
            estimatedValue: totalValue,
            expectedDate: _expectedDate,
            notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            capacity: joinedCapacity.isNotEmpty ? joinedCapacity : null,
            components: _selectedProducts.map((p) => p.toComponentMap()).toList(),
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lead updated successfully!'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update lead: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    child: Text(
                      'Edit Lead Details',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 16),

              // 1. Prospect Name (Locked / Non-editable in Edit Lead)
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Customer / Prospect Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: Color(0xFFF3F4F6),
                  suffixIcon: Tooltip(
                    message: 'Prospect cannot be changed once lead is created',
                    child: Icon(Icons.lock_outline, size: 18, color: AppColors.textSecondary),
                  ),
                ),
                child: Text(
                  _selectedProspect != null
                      ? (_selectedProspect!.company != null && _selectedProspect!.company!.isNotEmpty
                          ? '${_selectedProspect!.name} (${_selectedProspect!.company})'
                          : _selectedProspect!.name)
                      : (widget.lead.prospectName ?? 'Prospect'),
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 12),

              // 2. Contact Phone Number (Locked / Non-editable in Edit Lead)
              TextFormField(
                controller: _contactPhoneCtrl,
                enabled: false,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Contact Phone Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: Color(0xFFF3F4F6),
                  suffixIcon: Tooltip(
                    message: 'Phone number cannot be changed once lead is created',
                    child: Icon(Icons.lock_outline, size: 18, color: AppColors.textSecondary),
                  ),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),

              // 3. Multi-Product Selector
              MultiProductSelectorField(
                selectedItems: _selectedProducts,
                availableItems: _availableCombos,
                onChanged: _onProductsChanged,
                errorText: _productError,
              ),
              const SizedBox(height: 12),

              // 4. Estimated Deal Value
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
                    initialDate: _expectedDate ?? DateTime.now().add(const Duration(days: 14)),
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
                    : const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadCommunicationSection extends ConsumerWidget {
  final String leadId;
  final bool isWon;
  final bool isLost;
  final VoidCallback onDownloadPdf;

  const _LeadCommunicationSection({
    required this.leadId,
    this.isWon = false,
    this.isLost = false,
    required this.onDownloadPdf,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commsAsync = ref.watch(leadCommunicationsProvider(leadId));
    final profile = ref.watch(currentProfileProvider);
    final isAdmin = (profile?.primaryRole == UserRole.admin) || (profile?.roles.contains(UserRole.admin) ?? false);
    final canAddLog = !isLost && (!isWon || isAdmin);

    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Communication Log', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf, size: 20, color: AppColors.primary),
                      tooltip: 'Download PDF',
                      onPressed: onDownloadPdf,
                    ),
                    if (canAddLog)
                      TextButton.icon(
                        onPressed: () => _LeadDetailScreenState._showLogDialog(context, ref, leadId, isWon: isWon),
                        icon: const Icon(Icons.add_comment_outlined, size: 18),
                        label: const Text('Add Log', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ],
            ),
            const Divider(height: 16),
            commsAsync.when(
              data: (comms) {
                if (comms.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(
                      child: Text('No interactions logged yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: comms.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final comm = comms[index];
                    IconData icon = Icons.note;
                    Color color = Colors.grey;

                    if (comm.type == 'Call') {
                      icon = Icons.phone;
                      color = AppColors.primary;
                    } else if (comm.type == 'WhatsApp') {
                      icon = Icons.chat;
                      color = const Color(0xFF25D366);
                    } else if (comm.type == 'Email') {
                      icon = Icons.email;
                      color = Colors.blue;
                    } else if (comm.type == 'Meeting') {
                      icon = Icons.groups;
                      color = Colors.purple;
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                          child: Icon(icon, size: 16, color: color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(comm.type, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                                  Text(
                                    '${comm.createdAt.day}/${comm.createdAt.month} ${comm.createdAt.hour.toString().padLeft(2, '0')}:${comm.createdAt.minute.toString().padLeft(2, '0')}',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(comm.summary, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                              if (comm.loggedByName != null && comm.loggedByName!.trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.person_outline, size: 12, color: AppColors.textSecondary),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Logged by: ${comm.loggedByName}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error loading logs: $e', style: const TextStyle(color: AppColors.error))),
            ),
          ],
        ),
      ),
    );
  }
}

class _DealStatusHeader extends ConsumerWidget {
  final Lead lead;
  final bool isConverted;

  const _DealStatusHeader({required this.lead, required this.isConverted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Color statusColor = Colors.blue;
    if (lead.status == 'Won' || isConverted) {
      statusColor = AppColors.success;
    } else if (lead.status == 'Lost') {
      statusColor = AppColors.error;
    } else if (lead.status == 'Negotiating') {
      statusColor = Colors.purple;
    } else if (lead.status == 'In Progress') {
      statusColor = Colors.orange;
    }

    final isClosed = lead.status == 'Won' || lead.status == 'Lost' || isConverted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusColor.withOpacity(0.6)),
          ),
          child: Text(
            isConverted ? 'Won' : lead.status,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        if (!isClosed) ...[
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              minimumSize: const Size(60, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            icon: const Icon(Icons.cancel_outlined, size: 14),
            label: const Text('Mark as Lost', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            onPressed: () => _confirmMarkAsLost(context, ref),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmMarkAsLost(BuildContext context, WidgetRef ref) async {
    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.cancel, color: AppColors.error),
            SizedBox(width: 8),
            Text('Mark Deal as Lost'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to mark this deal as Lost? You can enter an optional reason below:',
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason for Lost Deal (Optional)',
                hintText: 'e.g. Price too high, Competitor chosen',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark as Lost'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(leadsProvider.notifier).updateStatus(lead.id, 'Lost');
        final reason = reasonCtrl.text.trim();
        if (reason.isNotEmpty) {
          try {
            await ref.read(leadCommunicationsProvider(lead.id).notifier).logCommunication(
                  type: 'Note',
                  summary: 'Deal marked as Lost. Reason: $reason',
                );
          } catch (_) {}
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lead marked as Lost.'), backgroundColor: AppColors.error),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating status: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AssignLeadDetailSheet extends ConsumerStatefulWidget {
  final Lead lead;

  const _AssignLeadDetailSheet({required this.lead});

  @override
  ConsumerState<_AssignLeadDetailSheet> createState() =>
      _AssignLeadDetailSheetState();
}

class _AssignLeadDetailSheetState extends ConsumerState<_AssignLeadDetailSheet> {
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

      if (mounted) {
        setState(() {
          _salesStaff = list;
          _selectedSalesUserId = widget.lead.assignedTo != null && list.any((s) => s['id'] == widget.lead.assignedTo)
              ? widget.lead.assignedTo
              : (_salesStaff.isNotEmpty ? _salesStaff.first['id'] as String? : null);
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
      await ref.read(leadsProvider.notifier).assignLead(
            leadId: widget.lead.id,
            salesUserId: _selectedSalesUserId!,
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Lead assigned to salesperson successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error assigning lead: $e'), backgroundColor: AppColors.error),
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
                  'Assign / Transfer Lead',
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
            'Assign "${widget.lead.prospectName ?? "this lead"}" to a sales representative.',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          if (_fetchingStaff)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          else if (_salesStaff.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text('No sales representatives found.', style: TextStyle(color: AppColors.textSecondary)),
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
                : const Text('Confirm Assignment', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (widget.lead.assignedTo != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.person_remove_outlined, size: 16, color: AppColors.error),
              label: const Text('Remove Assignment (Unassign)', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isLoading
                  ? null
                  : () async {
                      setState(() => _isLoading = true);
                      try {
                        await ref.read(leadsProvider.notifier).unassignLead(leadId: widget.lead.id);
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Lead assignment removed.'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error removing assignment: $e'), backgroundColor: AppColors.error),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    },
            ),
          ],
        ],
      ),
    );
  }
}

class _LeadQuotationsSection extends ConsumerStatefulWidget {
  final Lead lead;
  final bool canCreateQuotation;

  const _LeadQuotationsSection({
    required this.lead,
    required this.canCreateQuotation,
  });

  @override
  ConsumerState<_LeadQuotationsSection> createState() =>
      _LeadQuotationsSectionState();
}

class _LeadQuotationsSectionState
    extends ConsumerState<_LeadQuotationsSection> {
  bool _isLoading = true;
  bool _isPdfActionBusy = false;
  bool _isNavigatingToQuotationForm = false;
  List<Quotation> _quotations = [];

  @override
  void initState() {
    super.initState();
    _loadQuotations();
  }

  Future<void> _loadQuotations() async {
    setState(() => _isLoading = true);
    try {
      final supabase = ref.read(supabaseClientProvider);
      final res = await supabase
          .from('quotations')
          .select()
          .eq('lead_id', widget.lead.id)
          .order('revision', ascending: false);

      final list = (res as List)
          .map((json) => Quotation.fromJson(json as Map<String, dynamic>))
          .toList();

      if (mounted) {
        setState(() {
          _quotations = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _viewPdf(Quotation quot) async {
    if (_isPdfActionBusy || !GlobalClickGuard.canClick()) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top header with icon and close button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.picture_as_pdf_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'View Quotation PDF',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Select format to generate & preview',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.pop(ctx),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: isDark ? Colors.white54 : Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Card 1: Single Page Quotation
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    if (!GlobalClickGuard.canClick()) return;
                    Navigator.pop(ctx, 'single');
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.description_outlined,
                            color: Color(0xFF0284C7),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Single-Page Quotation',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Standard 1-page commercial offer & BOQ summary',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: isDark ? Colors.white38 : Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Card 2: Multi-Page Quotation (Highlighted)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    if (!GlobalClickGuard.canClick()) return;
                    Navigator.pop(ctx, 'multi');
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A8A).withValues(alpha: isDark ? 0.25 : 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.auto_stories_outlined,
                            color: Color(0xFF2563EB),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Multi-Page Proposal',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'FULL SPECS',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF10B981),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Complete proposal with technical specs & terms',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: Color(0xFF2563EB),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Cancel Button
                SizedBox(
                  height: 38,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark ? Colors.white60 : Colors.grey.shade700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (choice == null) return;

    _isPdfActionBusy = true;
    GlobalClickGuard.setBusy(true);

    if (choice == 'multi') {
      final dismissLoading = PdfLoadingDialog.show(
        context,
        title: 'Preparing Multi-Page Proposal...',
        message: 'Loading specifications, equipment details & terms.\nPlease wait...',
      );

      try {
        // Detect product from Lead product name, quotation line items, and product ID
        final leadProd = widget.lead.productName.trim();
        final lineDescs = quot.lineItems.map((e) => e.description).join(' ');
        final combinedProduct = '$leadProd $lineDescs ${quot.productId}'.toLowerCase();

        final template = QgTemplateRegistry.findTemplateForProduct(leadProd.isNotEmpty ? leadProd : lineDescs);
        final isBoomBarrier = template is BoomBarrierTemplate ||
            combinedProduct.contains('boom barrier') ||
            combinedProduct.contains('barrier');

        if (isBoomBarrier) {
          final prodKey = quot.productId.isNotEmpty ? quot.productId : 'Boom Barrier';
          final company = ref.read(companyForProductProvider(prodKey));
          final profile = QgProductProfile.defaultBoomBarrier().withAppCompany(company).copyWith(
            logoPath: (company.logoUrl != null && !company.logoUrl!.contains('logo.png'))
                ? company.logoUrl
                : 'assets/images/boom_barrier/sefdor_logo.png',
          );

          BoomBarrierProposalDraft? bbDraft = await QgBoomBarrierDraftsService.loadDraft(quot.id);
          if (bbDraft == null) {
            final dealItem = DealQuotationItem(
              id: quot.id,
              quotationNumber: quot.quotationNumber,
              status: quot.status.displayName,
              revision: quot.revision,
              orderDate: quot.orderDate ?? quot.createdAt,
              createdAt: quot.createdAt,
              updatedAt: quot.updatedAt,
              customerName: quot.customerName ?? widget.lead.prospectName ?? 'Valued Customer',
              customerPhone: quot.customerPhone ?? widget.lead.contactPhone ?? '',
              customerAddress: quot.billingAddress ?? '',
              customerGst: quot.customerGstin,
              salesmanName: quot.salesman ?? widget.lead.assignedByName ?? widget.lead.createdByName ?? 'Insiya Sales',
              salesmanPhone: '',
              subtotal: quot.subtotal,
              supplementarySubtotal: quot.supplementarySubtotal,
              cgstAmount: quot.cgstAmount,
              sgstAmount: quot.sgstAmount,
              igstAmount: quot.igstAmount,
              grandTotal: quot.grandTotal,
              cgstRate: quot.cgstRate,
              sgstRate: quot.sgstRate,
              igstRate: 0.0,
              lineItems: quot.lineItems.map((e) => e.toJson()).toList(),
              supplementaryTerms: quot.supplementaryTerms?.map((e) => e.toJson()).toList() ?? const [],
              paymentTerms: quot.paymentTerms ?? const [],
              termsText: quot.termsText,
              pipelineId: quot.pipelineId,
              productId: quot.productId,
              productName: widget.lead.productName.isNotEmpty ? widget.lead.productName : 'Boom Barrier',
            );
            bbDraft = BoomBarrierProposalDraft.fromDealQuotation(dealItem, profile);
          }

          if (mounted) {
            dismissLoading();
            GlobalClickGuard.setBusy(false);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => BoomBarrierPreviewScreen(
                  draft: bbDraft!,
                  profile: profile,
                ),
              ),
            );
          }
          return;
        }

        // ─── HEAT PUMP / ALL-IN-ONE / MULTI-PAGE PROPOSAL ───
        final company = ref.read(companyForProductProvider(quot.productId));
        var settings = GeneratorCompanySettings.fromAppCompany(company);
        final moduleSettings = ref.read(quotationSettingsProvider).valueOrNull;
        if (moduleSettings != null) {
          settings = settings.copyWith(
            models: moduleSettings.models.isNotEmpty ? moduleSettings.models : null,
            allInOneModels: moduleSettings.allInOneModels.isNotEmpty ? moduleSettings.allInOneModels : null,
            poolModels: moduleSettings.poolModels.isNotEmpty ? moduleSettings.poolModels : null,
            defaultCoverImagePath: moduleSettings.defaultCoverImagePath,
            defaultBannerImagePath: moduleSettings.defaultBannerImagePath,
            stampImagePath: moduleSettings.stampImagePath,
            domesticHpImagePath: moduleSettings.domesticHpImagePath,
            allInOneImagePath: moduleSettings.allInOneImagePath,
            allInOneWallImagePath: moduleSettings.allInOneWallImagePath,
            swimmingPoolImagePath: moduleSettings.swimmingPoolImagePath,
          );
        } else {
          try {
            final repoSettings = await ref.read(quotationRepositoryProvider).getSettings();
            settings = settings.copyWith(
              models: repoSettings.models.isNotEmpty ? repoSettings.models : null,
              allInOneModels: repoSettings.allInOneModels.isNotEmpty ? repoSettings.allInOneModels : null,
              poolModels: repoSettings.poolModels.isNotEmpty ? repoSettings.poolModels : null,
              defaultCoverImagePath: repoSettings.defaultCoverImagePath,
              defaultBannerImagePath: repoSettings.defaultBannerImagePath,
              stampImagePath: repoSettings.stampImagePath,
              domesticHpImagePath: repoSettings.domesticHpImagePath,
              allInOneImagePath: repoSettings.allInOneImagePath,
              allInOneWallImagePath: repoSettings.allInOneWallImagePath,
              swimmingPoolImagePath: repoSettings.swimmingPoolImagePath,
            );
          } catch (_) {}
        }

        final dealItem = DealQuotationItem(
          id: quot.id,
          quotationNumber: quot.quotationNumber,
          status: quot.status.displayName,
          revision: quot.revision,
          orderDate: quot.orderDate ?? quot.createdAt,
          createdAt: quot.createdAt,
          updatedAt: quot.updatedAt,
          customerName: quot.customerName ?? widget.lead.prospectName ?? 'Valued Customer',
          customerPhone: quot.customerPhone ?? widget.lead.contactPhone ?? '',
          customerAddress: quot.billingAddress ?? '',
          customerGst: quot.customerGstin,
          salesmanName: quot.salesman ?? widget.lead.assignedByName ?? widget.lead.createdByName ?? 'Insiya Sales',
          salesmanPhone: '',
          subtotal: quot.subtotal,
          supplementarySubtotal: quot.supplementarySubtotal,
          cgstAmount: quot.cgstAmount,
          sgstAmount: quot.sgstAmount,
          igstAmount: quot.igstAmount,
          grandTotal: quot.grandTotal,
          cgstRate: quot.cgstRate,
          sgstRate: quot.sgstRate,
          igstRate: quot.igstAmount > 0 ? (quot.cgstRate + quot.sgstRate) : 0.0,
          lineItems: quot.lineItems.map((e) => e.toJson()).toList(),
          supplementaryTerms: quot.supplementaryTerms?.map((e) => e.toJson()).toList() ?? const [],
          paymentTerms: quot.paymentTerms ?? const [],
          termsText: quot.termsText,
          pipelineId: quot.pipelineId,
          productId: quot.productId,
          productName: widget.lead.productName.isNotEmpty ? widget.lead.productName : 'Heat Pump',
        );

        final QgProposalDraft draft = (await QgDraftsService.loadDraft(quot.id)) ??
            QgProposalDraft.fromDealQuotation(dealItem, settings: settings);

        // Ensure draft specs are in sync with Module Settings according to heat pump type
        HeatPumpType hpType = HeatPumpType.domesticCommercial;
        if (draft.specCategoryId == 'all_in_one' || draft.specCategoryId == 'wall_mounted') {
          hpType = HeatPumpType.allInOne;
        } else if (draft.specCategoryId == 'pool') {
          hpType = HeatPumpType.swimmingPool;
        }

        final resSpecs = QgModelSpecsResolver.resolve(
          modelName: draft.hpModel,
          kw: draft.hpKw.toDouble(),
          isWallMounted: draft.specCategoryId == 'wall_mounted',
          heatPumpType: hpType,
          settings: settings,
        );
        if (resSpecs.specs.isNotEmpty) {
          draft.hpSpecs = Map<String, String>.from(resSpecs.specs);
          draft.hpModel = resSpecs.modelName;
          if (resSpecs.kw > 0) draft.hpKw = resSpecs.kw.round();
          draft.specsCopiedFrom = resSpecs.specsCopiedFrom;
        }
        await QgDraftsService.saveDraft(draft);

        final genQuot = draft.toGeneratorQuotation(settings: settings);

        if (mounted) {
          dismissLoading();
          GlobalClickGuard.setBusy(false);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (ctx) => QuotationPreviewScreen(
                quotation: genQuot,
                settings: settings,
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error opening multi-page quotation: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      } finally {
        dismissLoading();
        GlobalClickGuard.setBusy(false);
        if (mounted) {
          setState(() => _isPdfActionBusy = false);
        } else {
          _isPdfActionBusy = false;
        }
      }
      return;
    }

    final dismissLoading = PdfLoadingDialog.show(
      context,
      title: 'Generating Quotation PDF...',
      message: 'Preparing single-page commercial offer & BOQ summary.\nPlease wait...',
    );

    try {
      final supabase = ref.read(supabaseClientProvider);
      final lead = widget.lead;

      // Fetch prospect for address/contact details
      Prospect? prospect;
      final pId = lead.prospectId;
      if (pId != null && pId.isNotEmpty) {
        final pRes = await supabase
            .from('crm_prospects')
            .select()
            .eq('id', pId)
            .maybeSingle();
        if (pRes != null) {
          prospect = Prospect.fromJson(pRes);
        }
      }

      // Fetch active quotation PDF template config
      final templateRes = await supabase
          .from('pdf_templates')
          .select('template_config')
          .eq('document_type', 'quotation')
          .eq('is_active', true)
          .maybeSingle();

      final templateConfig = (templateRes != null && templateRes['template_config'] is Map)
          ? Map<String, dynamic>.from(templateRes['template_config'] as Map)
          : <String, dynamic>{};

      // Construct customer and product models so PdfService can render standard layout
      final customer = Customer(
        id: lead.convertedToCustomerId ?? lead.id,
        companyName: quot.customerName ?? lead.prospectName ?? prospect?.company ?? prospect?.name ?? 'Valued Customer',
        contactPerson: quot.partyContactPerson ?? prospect?.name ?? '',
        phone: quot.customerPhone ?? lead.contactPhone ?? prospect?.phone ?? '',
        email: prospect?.email ?? '',
        address: quot.billingAddress ?? prospect?.address ?? '',
        gstNumber: quot.customerGstin ?? prospect?.gst ?? '',
        createdBy: lead.createdBy,
        createdAt: lead.createdAt,
        updatedAt: DateTime.now(),
      );

      final product = Product(
        id: quot.productId.isNotEmpty ? quot.productId : 'general',
        name: lead.productName.isNotEmpty ? lead.productName : 'Solar Energy Solution',
        category: 'Solar',
        baseSpecs: const ProductBaseSpecs(
          quotationFields: [],
          boqRequiredFields: [],
        ),
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final pdfBytes = await PdfService.generateQuotationPdf(
        quotation: quot,
        customer: customer,
        product: product,
        templateConfig: templateConfig,
        docTitle: 'QUOTATION',
      );

      if (mounted) {
        final fileName = quot.revision > 0
            ? '${quot.quotationNumber.replaceAll('/', '_')}_Rev${quot.revision}.pdf'
            : '${quot.quotationNumber.replaceAll('/', '_')}.pdf';
        dismissLoading();
        GlobalClickGuard.setBusy(false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => PdfPreviewScreen(
              pdfBytes: pdfBytes,
              fileName: fileName,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rendering PDF: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      dismissLoading();
      GlobalClickGuard.setBusy(false);
      if (mounted) {
        setState(() => _isPdfActionBusy = false);
      } else {
        _isPdfActionBusy = false;
      }
    }
  }

  Future<void> _approveQuotation(Quotation quot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Quotation'),
        content: Text('Are you sure you want to approve quotation ${quot.quotationNumber.isNotEmpty ? quot.quotationNumber : quot.id}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final supabase = ref.read(supabaseClientProvider);
      await supabase.from('quotations').update({
        'status': 'confirmed',
        'confirmed_by': supabase.auth.currentUser?.id,
        'confirmed_at': DateTime.now().toIso8601String(),
      }).eq('id', quot.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Quotation approved successfully!'), backgroundColor: AppColors.success),
        );
      }
      _loadQuotations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error approving quotation: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _rejectQuotation(Quotation quot) async {
    final reasonCtrl = TextEditingController();
    String? validationError;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Reject Quotation'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Specify reason for rejecting quotation ${quot.quotationNumber.isNotEmpty ? quot.quotationNumber : quot.id}:'),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Enter rejection notes...',
                    border: const OutlineInputBorder(),
                    errorText: validationError,
                  ),
                  onChanged: (_) {
                    if (validationError != null) {
                      setDialogState(() => validationError = null);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () {
                  final reason = reasonCtrl.text.trim();
                  if (reason.isEmpty) {
                    setDialogState(() {
                      validationError = 'Rejection reason cannot be empty';
                    });
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Reject', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;

    final reason = reasonCtrl.text.trim();
    if (reason.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rejection reason cannot be empty.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    try {
      final supabase = ref.read(supabaseClientProvider);
      final existingRemarks = quot.remarks ?? '';
      final updatedRemarks = existingRemarks.isNotEmpty
          ? '$existingRemarks\n[Rejected]: $reason'
          : '[Rejected]: $reason';

      final updateData = <String, dynamic>{
        'status': 'rejected',
        'remarks': updatedRemarks,
        'updated_at': DateTime.now().toIso8601String(),
      };

      try {
        await supabase.from('quotations').update({
          ...updateData,
          'rejection_reason': reason,
        }).eq('id', quot.id);
      } catch (_) {
        // Fallback for missing rejection_reason column in schema cache
        await supabase.from('quotations').update(updateData).eq('id', quot.id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quotation rejected.'), backgroundColor: AppColors.error),
        );
      }
      _loadQuotations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error rejecting quotation: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _openCreateQuotation({Quotation? initialQuotation}) async {
    if (_isNavigatingToQuotationForm || !GlobalClickGuard.canClick()) return;
    _isNavigatingToQuotationForm = true;
    try {
      final profile = ref.read(currentProfileProvider);
      final isAdmin = (profile?.primaryRole == UserRole.admin) || (profile?.roles.contains(UserRole.admin) ?? false);
      final isWon = widget.lead.status == 'Won';
      if (isWon && !isAdmin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Customer is Won. Creating new quotations or revisions is blocked.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      if (!widget.canCreateQuotation) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => QuotationFormScreen(
            leadId: widget.lead.id,
            initialQuotation: initialQuotation,
            revisionNumber: initialQuotation != null ? initialQuotation.revision + 1 : null,
          ),
        ),
      );
      _loadQuotations();
    } finally {
      if (mounted) {
        setState(() => _isNavigatingToQuotationForm = false);
      } else {
        _isNavigatingToQuotationForm = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat('#,##,##0.00', 'en_IN');
    final profile = ref.watch(currentProfileProvider);
    final canApprove = (profile?.primaryRole.canApproveQuotations ?? false) || (profile?.roles.any((r) => r.canApproveQuotations) ?? false);
    final isSalesExecutive = !canApprove;
    final isWon = widget.lead.status == 'Won';
    final isLost = widget.lead.status.toLowerCase() == 'lost';
    final isLeadClosed = isWon || isLost;

    // Hide Add/Revise buttons while any quotation is pending approval
    final hasAnyPendingApproval = _quotations.any((q) => q.status == QuotationStatus.pendingApproval);

    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.request_quote_outlined, size: 20, color: AppColors.primary),
                      const SizedBox(width: 8),
                      const Flexible(
                        child: Text(
                          'Quotations & Revisions',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_quotations.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_quotations.length}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (widget.canCreateQuotation && !isLeadClosed && !hasAnyPendingApproval)
                  ElevatedButton.icon(
                    onPressed: () => _openCreateQuotation(),
                    icon: const Icon(Icons.add, size: 14, color: Colors.white),
                    label: const Text(
                      'Quotation',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(60, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),
            if (isLeadClosed)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isWon ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isWon ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isWon ? Icons.lock : Icons.lock_outline,
                      color: isWon ? const Color(0xFF059669) : const Color(0xFFDC2626),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Quotations locked — Lead is ${widget.lead.status}. No further revisions allowed.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isWon ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_quotations.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.description_outlined, size: 36, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      const Text(
                        'No quotation generated for this lead yet.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      if (widget.canCreateQuotation && !isLeadClosed) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _openCreateQuotation(),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Generate First Quotation (Rev 1)'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.primary),
                            foregroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else
              ..._quotations.map((quot) {
                final isLatest = _quotations.first.id == quot.id;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isLatest ? const Color(0xFFF0F7FF) : AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isLatest ? const Color(0xFF93C5FD) : AppColors.border,
                      width: isLatest ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Rev ${quot.revision}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              if (isWon && isLatest) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.verified, color: Colors.white, size: 12),
                                      SizedBox(width: 4),
                                      Text(
                                        'FINAL QUOTATION',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (isLatest) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDBEAFE),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'LATEST',
                                    style: TextStyle(
                                      color: Color(0xFF1D4ED8),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          _buildStatusBadge(quot.status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        quot.quotationNumber.isNotEmpty
                            ? quot.quotationNumber
                            : 'Quote #${quot.id.substring(0, 8)}',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            DateFormat('dd MMM yyyy, hh:mm a').format(quot.createdAt),
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                          Text(
                            '₹${currencyFormat.format(quot.grandTotal)}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (canApprove && quot.status == QuotationStatus.pendingApproval) ...[
                            ElevatedButton.icon(
                              onPressed: () => _approveQuotation(quot),
                              icon: const Icon(Icons.check_circle_outline, size: 14, color: Colors.white),
                              label: const Text('Approve', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: const Size(60, 30),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _rejectQuotation(quot),
                              icon: const Icon(Icons.cancel_outlined, size: 14, color: AppColors.error),
                              label: const Text('Reject', style: TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.error),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: const Size(60, 30),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                          ],
                          if (isSalesExecutive && quot.status != QuotationStatus.confirmed)
                            OutlinedButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Quotation PDF is locked until approved by Sales Head / Admin.'),
                                    backgroundColor: AppColors.warning,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.lock_outline, size: 14, color: AppColors.textDisabled),
                              label: const Text('PDF Locked', style: TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: const Size(60, 30),
                                side: const BorderSide(color: AppColors.border),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: () => _viewPdf(quot),
                              icon: const Icon(Icons.picture_as_pdf, size: 14),
                              label: const Text('View PDF', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: const Size(60, 30),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                          if (widget.canCreateQuotation && !isLeadClosed && !hasAnyPendingApproval) ...[
                            ElevatedButton.icon(
                              onPressed: () => _openCreateQuotation(initialQuotation: quot),
                              icon: const Icon(Icons.history_edu, size: 14, color: Colors.white),
                              label: Text(
                                'Revise (Rev ${quot.revision + 1})',
                                style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: const Size(60, 30),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(QuotationStatus status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case QuotationStatus.confirmed:
        bg = AppColors.successLight;
        fg = AppColors.success;
        label = 'Confirmed';
        break;
      case QuotationStatus.pendingApproval:
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        label = 'Pending Approval';
        break;
      case QuotationStatus.rejected:
        bg = AppColors.errorLight;
        fg = AppColors.error;
        label = 'Rejected';
        break;
      case QuotationStatus.draft:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        label = 'Draft';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }
}
