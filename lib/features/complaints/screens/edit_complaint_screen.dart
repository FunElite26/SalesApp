// lib/features/complaints/screens/edit_complaint_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/complaints_provider.dart';
import '../data/models/complaint_model.dart';

class EditComplaintScreen extends ConsumerStatefulWidget {
  final String complaintId;

  const EditComplaintScreen({super.key, required this.complaintId});

  @override
  ConsumerState<EditComplaintScreen> createState() => _EditComplaintScreenState();
}

class _EditComplaintScreenState extends ConsumerState<EditComplaintScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _custNameController;
  late TextEditingController _custPhoneController;
  late TextEditingController _custAddressController;
  late TextEditingController _sealBeforeController;
  late TextEditingController _sealAfterController;

  String _priority = 'Medium Priority';
  String _status = 'pending';
  String? _productName;
  String? _errorCode;
  String? _errorDesc;
  String? _technicianId;
  String? _technicianName;

  bool _initialized = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descController = TextEditingController();
    _custNameController = TextEditingController();
    _custPhoneController = TextEditingController();
    _custAddressController = TextEditingController();
    _sealBeforeController = TextEditingController();
    _sealAfterController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _custNameController.dispose();
    _custPhoneController.dispose();
    _custAddressController.dispose();
    _sealBeforeController.dispose();
    _sealAfterController.dispose();
    super.dispose();
  }

  void _initFromComplaint(Complaint complaint) {
    if (_initialized) return;
    _titleController.text = complaint.title;
    _descController.text = complaint.description;
    _custNameController.text = complaint.customerName;
    _custPhoneController.text = complaint.customerPhone;
    _custAddressController.text = complaint.customerAddress;
    _sealBeforeController.text = complaint.sealNumberBefore ?? '';
    _sealAfterController.text = complaint.sealNumberAfter ?? '';

    _priority = complaint.priority;
    _status = complaint.status;
    _productName = complaint.productName;
    _errorCode = complaint.errorCode;
    _errorDesc = complaint.errorDescription;
    _technicianId = complaint.technicianId;
    _technicianName = complaint.technicianName;
    _initialized = true;
  }

  Future<void> _saveChanges(Complaint complaint) async {
    if (complaint.status == 'closed' || complaint.status == 'resolved') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Closed complaints cannot be modified.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final updated = complaint.copyWith(
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        priority: _priority,
        status: _status,
        productName: _productName,
        errorCode: _errorCode,
        errorDescription: _errorDesc,
        technicianId: _technicianId,
        technicianName: _technicianName,
        // Customer name and mobile are not allowed to be edited from complaints
        customerName: complaint.customerName,
        customerPhone: complaint.customerPhone,
        customerAddress: _custAddressController.text.trim().isNotEmpty
            ? _custAddressController.text.trim()
            : complaint.customerAddress,
        sealNumberBefore: _sealBeforeController.text.trim().isNotEmpty
            ? _sealBeforeController.text.trim()
            : null,
        sealNumberAfter: _sealAfterController.text.trim().isNotEmpty
            ? _sealAfterController.text.trim()
            : null,
      );

      await ref.read(complaintsProvider.notifier).updateComplaint(updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complaint updated successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update complaint: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Searchable Product Picker Modal
  void _openSearchableProductPicker(List<String> products) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String filter = '';
        final searchCtrl = TextEditingController();
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = products.where((p) {
              if (filter.isEmpty) return true;
              return p.toLowerCase().contains(filter.toLowerCase());
            }).toList();

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 16,
                left: 16,
                right: 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.65,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Select Product',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: searchCtrl,
                      autofocus: false,
                      onChanged: (val) => setModalState(() => filter = val.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search products by name...',
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF6D28D9)),
                        suffixIcon: searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setModalState(() => filter = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text('No products found matching search.'),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (ctx, i) => const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final pName = filtered[i];
                                final isSelected = _productName == pName;
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFFEDE9FE) : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.solar_power_outlined,
                                      color: isSelected ? const Color(0xFF6D28D9) : Colors.grey.shade700,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    pName,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                      color: isSelected ? const Color(0xFF6D28D9) : Colors.black87,
                                    ),
                                  ),
                                  trailing: isSelected
                                      ? const Icon(Icons.check_circle, color: Color(0xFF6D28D9))
                                      : null,
                                  onTap: () {
                                    setState(() {
                                      _productName = pName;
                                    });
                                    Navigator.pop(ctx);
                                  },
                                );
                              },
                            ),
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

  // Searchable Error Code Picker Modal
  void _openSearchableErrorCodePicker(List<ErrorCodeItem> errorCodes) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String filter = '';
        final searchCtrl = TextEditingController();
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = errorCodes.where((ec) {
              if (filter.isEmpty) return true;
              final q = filter.toLowerCase();
              return ec.code.toLowerCase().contains(q) ||
                  ec.description.toLowerCase().contains(q);
            }).toList();

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 16,
                left: 16,
                right: 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.65,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Select Error / Fault Code',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: searchCtrl,
                      autofocus: false,
                      onChanged: (val) => setModalState(() => filter = val.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search by code (e.g. E01) or description...',
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF6D28D9)),
                        suffixIcon: searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setModalState(() => filter = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('None', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      title: const Text('No Error Code / General Issue'),
                      trailing: _errorCode == null ? const Icon(Icons.check_circle, color: Color(0xFF6D28D9)) : null,
                      onTap: () {
                        setState(() {
                          _errorCode = null;
                          _errorDesc = null;
                        });
                        Navigator.pop(ctx);
                      },
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text('No error codes matching search.'),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (ctx, i) => const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final ec = filtered[i];
                                final isSelected = _errorCode == ec.code;
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  leading: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFFEDE9FE) : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected ? const Color(0xFF6D28D9) : Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Text(
                                      ec.code,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? const Color(0xFF6D28D9) : const Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    ec.description,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 13,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                      color: isSelected ? const Color(0xFF6D28D9) : Colors.black87,
                                    ),
                                  ),
                                  trailing: isSelected
                                      ? const Icon(Icons.check_circle, color: Color(0xFF6D28D9))
                                      : null,
                                  onTap: () {
                                    setState(() {
                                      _errorCode = ec.code;
                                      _errorDesc = ec.description;
                                    });
                                    Navigator.pop(ctx);
                                  },
                                );
                              },
                            ),
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

  // Searchable Technician Picker Modal
  void _openSearchableTechnicianPicker(List<TechnicianInfo> technicians) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String filter = '';
        final searchCtrl = TextEditingController();
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = technicians.where((t) {
              if (filter.isEmpty) return true;
              final q = filter.toLowerCase();
              return t.name.toLowerCase().contains(q) ||
                  (t.phone != null && t.phone!.contains(q));
            }).toList();

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 16,
                left: 16,
                right: 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.65,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Assign Technician',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: searchCtrl,
                      autofocus: false,
                      onChanged: (val) => setModalState(() => filter = val.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search technician by name or phone...',
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF6D28D9)),
                        suffixIcon: searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setModalState(() => filter = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.grey,
                        radius: 16,
                        child: Icon(Icons.person_off_outlined, color: Colors.white, size: 18),
                      ),
                      title: const Text('Unassigned / Clear Assignment'),
                      trailing: _technicianId == null
                          ? const Icon(Icons.check_circle, color: Color(0xFF6D28D9))
                          : null,
                      onTap: () {
                        setState(() {
                          _technicianId = null;
                          _technicianName = null;
                        });
                        Navigator.pop(ctx);
                      },
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text('No technicians found.'),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (ctx, i) => const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final t = filtered[i];
                                final isSelected = _technicianId == t.id;
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFFEDE9FE),
                                    radius: 18,
                                    child: Text(
                                      t.name.isNotEmpty ? t.name[0].toUpperCase() : 'T',
                                      style: const TextStyle(
                                        color: Color(0xFF6D28D9),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    t.name,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                      color: isSelected ? const Color(0xFF6D28D9) : Colors.black87,
                                    ),
                                  ),
                                  subtitle: Text(t.phone ?? 'No phone', style: const TextStyle(fontSize: 12)),
                                  trailing: isSelected
                                      ? const Icon(Icons.check_circle, color: Color(0xFF6D28D9))
                                      : null,
                                  onTap: () {
                                    setState(() {
                                      _technicianId = t.id;
                                      _technicianName = t.name;
                                      if (_status == 'pending') {
                                        _status = 'assigned';
                                      }
                                    });
                                    Navigator.pop(ctx);
                                  },
                                );
                              },
                            ),
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

  @override
  Widget build(BuildContext context) {
    final complaints = ref.watch(complaintsProvider);
    final complaint = complaints.where((c) => c.id == widget.complaintId).firstOrNull;

    if (complaint == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Complaint Not Found'),
          backgroundColor: const Color(0xFF1E1B4B),
        ),
        body: const Center(child: Text('Complaint ticket could not be found.')),
      );
    }

    _initFromComplaint(complaint);
    final isClosed = complaint.status == 'closed' || complaint.status == 'resolved';

    final errorCodes = ref.watch(errorCodesProvider);
    final productsAsync = ref.watch(productsListProvider);
    final techniciansAsync = ref.watch(availableTechniciansProvider);

    final productsList = productsAsync.value ?? [];
    final techniciansList = techniciansAsync.value ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Edit Complaint ${complaint.ticketNumber}',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF1E1B4B),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Closed Complaint Warning Banner
              if (isClosed) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline_rounded, color: Color(0xFFDC2626), size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Closed Complaint (Read Only)',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Color(0xFF991B1B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'This ticket has been marked as ${complaint.status.toUpperCase()} and cannot be edited.',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFB91C1C),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // SECTION 1: Ticket Details
              _buildSectionCard(
                title: 'Ticket Information',
                icon: Icons.confirmation_number_outlined,
                children: [
                  const Text('Complaint Title *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _titleController,
                    readOnly: isClosed,
                    validator: (val) => val == null || val.trim().isEmpty ? 'Title is required' : null,
                    decoration: _inputDecoration('Enter complaint issue title'),
                  ),
                  const SizedBox(height: 14),
                  const Text('Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _descController,
                    readOnly: isClosed,
                    minLines: 2,
                    maxLines: 4,
                    decoration: _inputDecoration('Provide full details of the customer complaint...'),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // SECTION 2: Priority & Status
              _buildSectionCard(
                title: 'Status & Priority',
                icon: Icons.flag_outlined,
                children: [
                  Row(
                    children: [
                      // Priority
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Priority', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: isClosed ? Colors.grey.shade100 : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _priority,
                                  isExpanded: true,
                                  items: ['Low Priority', 'Medium Priority', 'High Priority', 'Urgent'].map((p) {
                                    Color color = Colors.blue;
                                    if (p == 'Medium Priority') color = Colors.orange;
                                    if (p == 'High Priority') color = Colors.deepOrange;
                                    if (p == 'Urgent') color = Colors.red;
                                    return DropdownMenuItem(
                                      value: p,
                                      child: Row(
                                        children: [
                                          Icon(Icons.circle, size: 8, color: color),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              p,
                                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  selectedItemBuilder: (BuildContext context) {
                                    return ['Low Priority', 'Medium Priority', 'High Priority', 'Urgent'].map<Widget>((p) {
                                      Color color = Colors.blue;
                                      if (p == 'Medium Priority') color = Colors.orange;
                                      if (p == 'High Priority') color = Colors.deepOrange;
                                      if (p == 'Urgent') color = Colors.red;
                                      return Row(
                                        children: [
                                          Icon(Icons.circle, size: 8, color: color),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              p,
                                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      );
                                    }).toList();
                                  },
                                  onChanged: isClosed
                                      ? null
                                      : (val) {
                                          if (val != null) setState(() => _priority = val);
                                        },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Status
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: isClosed ? Colors.grey.shade100 : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _status,
                                  isExpanded: true,
                                  items: [
                                    {'val': 'pending', 'label': 'Pending', 'color': Colors.orange},
                                    {'val': 'assigned', 'label': 'Assigned', 'color': Colors.blue},
                                    {'val': 'in_progress', 'label': 'In Progress', 'color': Colors.indigo},
                                    {'val': 'closed', 'label': 'Closed', 'color': Colors.green},
                                    {'val': 'cancelled', 'label': 'Cancelled', 'color': Colors.grey},
                                  ].map((s) {
                                    return DropdownMenuItem(
                                      value: s['val'] as String,
                                      child: Row(
                                        children: [
                                          Icon(Icons.circle, size: 8, color: s['color'] as Color),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              s['label'] as String,
                                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  selectedItemBuilder: (BuildContext context) {
                                    return [
                                      {'val': 'pending', 'label': 'Pending', 'color': Colors.orange},
                                      {'val': 'assigned', 'label': 'Assigned', 'color': Colors.blue},
                                      {'val': 'in_progress', 'label': 'In Progress', 'color': Colors.indigo},
                                      {'val': 'closed', 'label': 'Closed', 'color': Colors.green},
                                      {'val': 'cancelled', 'label': 'Cancelled', 'color': Colors.grey},
                                    ].map<Widget>((s) {
                                      return Row(
                                        children: [
                                          Icon(Icons.circle, size: 8, color: s['color'] as Color),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              s['label'] as String,
                                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      );
                                    }).toList();
                                  },
                                  onChanged: isClosed
                                      ? null
                                      : (val) {
                                          if (val != null) setState(() => _status = val);
                                        },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // SECTION 3: Searchable Diagnostics & Hardware (Product, Error Code, Technician)
              _buildSectionCard(
                title: 'Diagnostics & Assignment (Searchable)',
                icon: Icons.settings_suggest_outlined,
                children: [
                  // Product Picker
                  const Text('Product Line', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: isClosed ? null : () => _openSearchableProductPicker(productsList),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isClosed ? Colors.grey.shade100 : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.solar_power_outlined, size: 20, color: Color(0xFF6D28D9)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _productName ?? 'Select Product (Tap to Search)',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: _productName != null ? FontWeight.w600 : FontWeight.normal,
                                color: _productName != null ? const Color(0xFF1E293B) : Colors.grey.shade600,
                              ),
                            ),
                          ),
                          if (!isClosed) const Icon(Icons.arrow_drop_down, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Error Code Picker
                  const Text('Error Code', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: isClosed ? null : () => _openSearchableErrorCodePicker(errorCodes),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isClosed ? Colors.grey.shade100 : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, size: 20, color: Color(0xFF6D28D9)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _errorCode != null
                                ? Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEDE9FE),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          _errorCode!,
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF6D28D9),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _errorDesc ?? '',
                                          style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    'None / Select Error Code (Tap to Search)',
                                    style: TextStyle(fontFamily: 'Inter', color: Colors.grey.shade600, fontSize: 13),
                                  ),
                          ),
                          if (!isClosed) const Icon(Icons.arrow_drop_down, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Assigned Technician Picker
                  const Text('Assigned Technician', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: isClosed ? null : () => _openSearchableTechnicianPicker(techniciansList),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isClosed ? Colors.grey.shade100 : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.engineering_outlined, size: 20, color: Color(0xFF6D28D9)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _technicianName != null
                                  ? '$_technicianName (Assigned)'
                                  : 'Not Assigned (Tap to Search Technician)',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: _technicianName != null ? FontWeight.w600 : FontWeight.normal,
                                color: _technicianName != null ? const Color(0xFF1E293B) : Colors.grey.shade600,
                              ),
                            ),
                          ),
                          if (!isClosed) const Icon(Icons.arrow_drop_down, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // SECTION 4: Customer Details (Read-only / Non-editable)
              _buildSectionCard(
                title: 'Customer Details',
                icon: Icons.person_outline_rounded,
                headerBadge: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 12, color: Colors.grey),
                      SizedBox(width: 4),
                      Text('Non-editable', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                    ],
                  ),
                ),
                children: [
                  const Text('Customer Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _custNameController,
                    readOnly: true,
                    enabled: false,
                    decoration: _readOnlyInputDecoration(
                      hint: 'Customer Name',
                      prefixIcon: Icons.person_outline,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4, left: 2),
                    child: Text(
                      'Customer name is linked to customer profile and cannot be modified from complaint.',
                      style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Customer Phone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _custPhoneController,
                    readOnly: true,
                    enabled: false,
                    decoration: _readOnlyInputDecoration(
                      hint: 'Customer Phone',
                      prefixIcon: Icons.phone_outlined,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4, left: 2),
                    child: Text(
                      'Mobile number cannot be edited from complaint.',
                      style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Customer Address', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _custAddressController,
                    readOnly: isClosed,
                    maxLines: 2,
                    decoration: _inputDecoration('Enter customer service address'),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // SECTION 5: Meter / Seal Numbers
              _buildSectionCard(
                title: 'Seal / Meter Verification',
                icon: Icons.verified_outlined,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Seal No. Before', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _sealBeforeController,
                              readOnly: isClosed,
                              decoration: _inputDecoration('e.g. SL-1024'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Seal No. After', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _sealAfterController,
                              readOnly: isClosed,
                              decoration: _inputDecoration('e.g. SL-1025'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // ACTION BUTTONS: Cancel & Save Changes
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => context.pop(),
                      child: Text(isClosed ? 'Back' : 'Cancel', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: isClosed
                        ? ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade300,
                              foregroundColor: Colors.grey.shade600,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                            onPressed: null,
                            icon: const Icon(Icons.lock_outline, size: 18),
                            label: const Text(
                              'Complaint is Closed',
                              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          )
                        : ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6D28D9),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 1,
                            ),
                            onPressed: _isSaving ? null : () => _saveChanges(complaint),
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.check, size: 18),
                            label: const Text(
                              'Save Changes',
                              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                  ),
                ],
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    Widget? headerBadge,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(icon, color: const Color(0xFF6D28D9), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF1E1B4B),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (headerBadge != null) ...[
                const SizedBox(width: 8),
                headerBadge,
              ],
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF6D28D9), width: 1.5),
      ),
    );
  }

  InputDecoration _readOnlyInputDecoration({required String hint, required IconData prefixIcon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(prefixIcon, color: Colors.grey.shade500, size: 18),
      suffixIcon: const Icon(Icons.lock_outline, color: Colors.grey, size: 16),
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
    );
  }
}
