// lib/features/daily_tasks/widgets/task_form_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/customer.dart';
import '../models/daily_task_model.dart';
import '../providers/daily_tasks_provider.dart';

class TaskFormDialog extends ConsumerStatefulWidget {
  final DailyTask? taskToEdit;
  final String? preselectedCustomerId;
  final String? preselectedCustomerName;

  const TaskFormDialog({
    super.key,
    this.taskToEdit,
    this.preselectedCustomerId,
    this.preselectedCustomerName,
  });

  static Future<bool?> show(
    BuildContext context, {
    DailyTask? taskToEdit,
    String? preselectedCustomerId,
    String? preselectedCustomerName,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TaskFormDialog(
        taskToEdit: taskToEdit,
        preselectedCustomerId: preselectedCustomerId,
        preselectedCustomerName: preselectedCustomerName,
      ),
    );
  }

  @override
  ConsumerState<TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends ConsumerState<TaskFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _taskController;
  late final TextEditingController _customerSearchController;

  String? _selectedCustomerId;
  String? _selectedCustomerName;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _taskController = TextEditingController(text: widget.taskToEdit?.taskDescription ?? '');
    _customerSearchController = TextEditingController();

    _selectedCustomerId = widget.taskToEdit?.customerId ?? widget.preselectedCustomerId;
    _selectedCustomerName = widget.taskToEdit?.customerName ?? widget.preselectedCustomerName;
  }

  @override
  void dispose() {
    _taskController.dispose();
    _customerSearchController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCustomerName == null || _selectedCustomerName!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a customer name (compulsory)'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (widget.taskToEdit != null) {
        // Edit existing task
        await ref.read(dailyTasksProvider.notifier).updateTask(
          widget.taskToEdit!.id,
          taskDescription: _taskController.text.trim(),
          customerId: _selectedCustomerId,
          customerName: _selectedCustomerName,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Task updated successfully (logged as edited)'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        // Create new task
        await ref.read(dailyTasksProvider.notifier).createTask(
          customerId: _selectedCustomerId ?? '',
          customerName: _selectedCustomerName!,
          taskDescription: _taskController.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Task submitted successfully'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save task: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showCustomerPicker(List<Customer> customers) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CustomerPickerSheet(
        customers: customers,
        initialSelectedId: _selectedCustomerId,
        onSelected: (customer) {
          setState(() {
            _selectedCustomerId = customer.id;
            _selectedCustomerName = customer.customerName.trim().isNotEmpty
                ? customer.customerName
                : (customer.contactPerson?.isNotEmpty == true ? customer.contactPerson! : customer.companyName);
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(taskSelectableCustomersProvider);
    final isEditing = widget.taskToEdit != null;
    final now = DateTime.now();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1B4B).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isEditing ? Icons.edit_note_rounded : Icons.add_task_rounded,
                        color: const Color(0xFF1E1B4B),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing ? 'Edit Completed Task' : 'Log Daily Task Completed',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isEditing
                                ? 'Changes will be saved and logged as edited.'
                                : 'Record work done for a customer with automatic timestamp.',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 18),

                // Customer Selection Field (COMPULSARY)
                const Row(
                  children: [
                    Text(
                      'Customer Name',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    SizedBox(width: 4),
                    Text('*', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),

                customersAsync.when(
                  data: (customers) {
                    final isPreselected = widget.preselectedCustomerId != null && widget.preselectedCustomerId!.isNotEmpty;

                    return InkWell(
                      onTap: isPreselected ? null : () => _showCustomerPicker(customers),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isPreselected ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedCustomerName != null ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.business_outlined, size: 20, color: Color(0xFF64748B)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _selectedCustomerName ?? 'Tap to select customer...',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  fontWeight: _selectedCustomerName != null ? FontWeight.w600 : FontWeight.w400,
                                  color: _selectedCustomerName != null ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                            if (!isPreselected)
                              const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
                          ],
                        ),
                      ),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Error loading customers: $e', style: const TextStyle(color: AppColors.error)),
                ),
                const SizedBox(height: 18),

                // Task Completed Field (COMPULSARY)
                const Row(
                  children: [
                    Text(
                      'Task Completed',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    SizedBox(width: 4),
                    Text('*', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _taskController,
                  maxLines: 4,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter task details (compulsory)';
                    }
                    return null;
                  },
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    hintText: 'Enter details of the task completed...\n(e.g., Conducted site survey, shared quotation, resolved inverter issue, completed client follow up)',
                    hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1E1B4B), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Timestamp info banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF16A34A)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isEditing
                              ? 'Edited at: ${DateFormat('dd MMM yyyy, hh:mm a').format(now)}'
                              : 'Auto-recorded at submit: ${DateFormat('dd MMM yyyy, hh:mm a').format(now)}',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // Dialog Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E1B4B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              isEditing ? 'Save Changes' : 'Submit Task',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerPickerSheet extends StatefulWidget {
  final List<Customer> customers;
  final String? initialSelectedId;
  final ValueChanged<Customer> onSelected;

  const _CustomerPickerSheet({
    required this.customers,
    required this.initialSelectedId,
    required this.onSelected,
  });

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Customer> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.customers;
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = widget.customers;
      } else {
        _filtered = widget.customers.where((c) {
          final name = c.customerName.toLowerCase();
          final contact = (c.contactPerson ?? '').toLowerCase();
          final comp = c.companyName.toLowerCase();
          final phone = (c.phone ?? '').toLowerCase();
          return name.contains(q) || contact.contains(q) || comp.contains(q) || phone.contains(q);
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
                const Icon(Icons.people_alt_outlined, color: Color(0xFF1E1B4B)),
                const SizedBox(width: 10),
                const Text(
                  'Select Customer',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.bold),
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

          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search customer by name, company, or phone...',
                prefixIcon: const Icon(Icons.search, size: 20),
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

          // List
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text('No customers found', style: TextStyle(color: Colors.grey)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    itemBuilder: (context, index) {
                      final c = _filtered[index];
                      final isSelected = c.id == widget.initialSelectedId;
                      final title = c.customerName.trim().isNotEmpty
                          ? c.customerName
                          : (c.contactPerson?.isNotEmpty == true ? c.contactPerson! : c.companyName);
                      final subtitle = [
                        if (c.companyName.isNotEmpty && c.companyName != title)
                          c.companyName,
                        if (c.phone != null && c.phone!.isNotEmpty) c.phone,
                      ].join(' • ');

                      return ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        selected: isSelected,
                        selectedTileColor: const Color(0xFF1E1B4B).withValues(alpha: 0.08),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF1E1B4B).withValues(alpha: 0.1),
                          child: Text(
                            title.isNotEmpty ? title[0].toUpperCase() : 'C',
                            style: const TextStyle(color: Color(0xFF1E1B4B), fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          title,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            fontSize: 14,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        subtitle: subtitle.isNotEmpty
                            ? Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))
                            : null,
                        trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF1E1B4B)) : null,
                        onTap: () => widget.onSelected(c),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
