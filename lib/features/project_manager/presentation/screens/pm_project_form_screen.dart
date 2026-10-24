import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/models/customer.dart';
import '../../../admin/providers/inventory_provider.dart';
import '../theme/pm_tokens.dart';
import '../../data/models/pm_company.dart';
import '../../providers/pm_company_provider.dart';
import '../../providers/pm_providers.dart';
import '../widgets/customer_search_picker.dart';
import '../widgets/pm_button.dart';
import '../widgets/pm_card.dart';

class PmProjectFormScreen extends ConsumerStatefulWidget {
  final String? editId;
  final bool isPurchase;

  const PmProjectFormScreen({
    super.key,
    this.editId,
    this.isPurchase = false,
  });

  @override
  ConsumerState<PmProjectFormScreen> createState() => _PmProjectFormScreenState();
}

class _PmProjectFormScreenState extends ConsumerState<PmProjectFormScreen> {
  final _formKey = GlobalKey<FormState>();

  Customer? _selectedCustomer;
  int? _idNo;
  String _orderType = 'Heat Pump';
  DateTime _customerSinceDate = DateTime.now();

  final _siteNameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _firmNameCtrl = TextEditingController();
  final _partyPrintNameCtrl = TextEditingController();
  final _salesmanNameCtrl = TextEditingController();
  final _hpTypeCtrl = TextEditingController();
  final _hpQtyCtrl = TextEditingController(text: '0');
  final _tankTypeCtrl = TextEditingController();
  final _tankQtyCtrl = TextEditingController(text: '0');
  final _glCtrl = TextEditingController(text: '0');
  final _orderValueCtrl = TextEditingController(text: '0');
  final _extraWorkValueCtrl = TextEditingController(text: '0');
  final _workRemarkCtrl = TextEditingController();

  bool _isLoading = false;
  bool _isInit = true;

  final List<String> _orderTypes = [
    'Heat Pump',
    'SWH',
    'Solar Water Heater',
    'Solar System',
    'Commercial SWH',
    'Boom Barrier',
    'Vendor Supply',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.editId == null && _firmNameCtrl.text.isEmpty) {
        setState(() {
          _firmNameCtrl.text = ref.read(pmActiveCompanyProvider).name;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      _loadData();
      _isInit = false;
    }
  }

  @override
  void dispose() {
    _siteNameCtrl.dispose();
    _mobileCtrl.dispose();
    _addressCtrl.dispose();
    _firmNameCtrl.dispose();
    _partyPrintNameCtrl.dispose();
    _salesmanNameCtrl.dispose();
    _hpTypeCtrl.dispose();
    _hpQtyCtrl.dispose();
    _tankTypeCtrl.dispose();
    _tankQtyCtrl.dispose();
    _glCtrl.dispose();
    _orderValueCtrl.dispose();
    _extraWorkValueCtrl.dispose();
    _workRemarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final activeCompany = ref.read(pmActiveCompanyProvider);
    final companies = ref.read(pmCompaniesListProvider);

    if (widget.editId != null) {
      setState(() => _isLoading = true);
      if (widget.isPurchase) {
        final purchase = await ref.read(pmPurchasesRepositoryProvider).getPurchaseById(widget.editId!);
        if (purchase != null) {
          _idNo = purchase.idNo;
          _orderType = purchase.orderType;
          _siteNameCtrl.text = purchase.siteName;
          _mobileCtrl.text = purchase.mobileNumber ?? '';
          _addressCtrl.text = purchase.address ?? '';
          final pComp = companies.cast<PmCompany?>().firstWhere(
            (c) => c?.id == purchase.companyId,
            orElse: () => null,
          );
          _firmNameCtrl.text = (purchase.firmName != null && purchase.firmName!.trim().isNotEmpty)
              ? purchase.firmName!
              : (pComp?.name ?? activeCompany.name);
          _partyPrintNameCtrl.text = purchase.partyPrintName ?? '';
          _orderValueCtrl.text = purchase.quotationValue.toStringAsFixed(0);
          _customerSinceDate = purchase.createdAt;
        }
      } else {
        final project = await ref.read(pmProjectsRepositoryProvider).getProjectById(widget.editId!);
        if (project != null) {
          _idNo = project.idNo;
          _selectedCustomer = project.customer;
          _orderType = project.orderType;
          _siteNameCtrl.text = project.siteName;
          _mobileCtrl.text = project.mobileNumber ?? '';
          _addressCtrl.text = project.address ?? '';
          _hpTypeCtrl.text = project.hpType ?? '';
          _hpQtyCtrl.text = project.hpQty.toString();
          _tankTypeCtrl.text = project.tankType ?? '';
          _tankQtyCtrl.text = project.tankQty.toString();
          _glCtrl.text = project.gl.toString();
          _orderValueCtrl.text = project.orderValue.toStringAsFixed(0);
          _extraWorkValueCtrl.text = project.extraWorkValue.toStringAsFixed(0);
          _workRemarkCtrl.text = project.workRemark ?? '';

          // Sales Man auto-pick
          final smCandidate = (project.salesmanName != null && project.salesmanName!.trim().isNotEmpty)
              ? project.salesmanName!.trim()
              : (project.customer?.salesmanName ?? project.customer?.assignedToName ?? '');
          _salesmanNameCtrl.text = smCandidate;

          // Firm Name auto-picked from project's company or active company
          final projComp = companies.cast<PmCompany?>().firstWhere(
            (c) => c?.id == project.companyId,
            orElse: () => null,
          );
          _firmNameCtrl.text = projComp?.name ?? project.firmName;

          _customerSinceDate = project.createdAt;
        }
      }
      setState(() => _isLoading = false);
    } else {
      // Auto-assign next ID No and auto-pick active company name
      final nextId = widget.isPurchase
          ? await ref.read(pmPurchasesRepositoryProvider).getNextIdNo()
          : await ref.read(pmProjectsRepositoryProvider).getNextIdNo();
      setState(() {
        _idNo = nextId;
        _firmNameCtrl.text = activeCompany.name;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!widget.isPurchase && _selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an existing customer from SalesApp')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final activeCompany = ref.read(pmActiveCompanyProvider);
    final companies = ref.read(pmCompaniesListProvider);
    final matchedCompany = companies.cast<PmCompany?>().firstWhere(
      (c) => c?.name.trim().toLowerCase() == _firmNameCtrl.text.trim().toLowerCase(),
      orElse: () => null,
    );
    final targetCompanyId = matchedCompany?.id ?? activeCompany.id;

    try {
      if (widget.isPurchase) {
        final data = {
          'id_no': _idNo ?? 1001,
          'order_type': _orderType,
          'site_name': _siteNameCtrl.text.trim(),
          'mobile_number': _mobileCtrl.text.trim(),
          'address': _addressCtrl.text.trim(),
          'firm_name': _firmNameCtrl.text.trim(),
          'party_print_name': _partyPrintNameCtrl.text.trim(),
          'quotation_value': double.tryParse(_orderValueCtrl.text) ?? 0.0,
          'company_id': targetCompanyId,
          'created_at': _customerSinceDate.toIso8601String(),
        };

        if (widget.editId != null) {
          await ref.read(pmPurchasesRepositoryProvider).updatePurchase(widget.editId!, data);
        } else {
          await ref.read(pmPurchasesRepositoryProvider).createPurchase(data);
        }
        ref.invalidate(pmPurchasesListProvider);
      } else {
        final data = {
          'id_no': _idNo ?? 1001,
          'customer_id': _selectedCustomer!.id,
          'order_type': _orderType,
          'site_name': _siteNameCtrl.text.trim().isNotEmpty
              ? _siteNameCtrl.text.trim()
              : _selectedCustomer!.companyName,
          'address': _addressCtrl.text.trim().isNotEmpty
              ? _addressCtrl.text.trim()
              : (_selectedCustomer!.address ?? ''),
          'hp_type': _hpTypeCtrl.text.trim(),
          'hp_qty': int.tryParse(_hpQtyCtrl.text) ?? 0,
          'tank_type': _tankTypeCtrl.text.trim(),
          'tank_qty': int.tryParse(_tankQtyCtrl.text) ?? 0,
          'gl': int.tryParse(_glCtrl.text) ?? 0,
          'order_value': double.tryParse(_orderValueCtrl.text) ?? 0.0,
          'extra_work_value': double.tryParse(_extraWorkValueCtrl.text) ?? 0.0,
          'work_remark': _workRemarkCtrl.text.trim(),
          'salesman_name': _salesmanNameCtrl.text.trim(),
          'company_id': targetCompanyId,
          'created_at': _customerSinceDate.toIso8601String(),
        };

        if (widget.editId != null) {
          await ref.read(pmProjectsRepositoryProvider).updateProject(widget.editId!, data);
        } else {
          await ref.read(pmProjectsRepositoryProvider).createProject(data);
        }
        ref.invalidate(pmProjectsListProvider);
      }

      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving record: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _pickInventoryItem({
    required String title,
    required TextEditingController targetCtrl,
  }) async {
    final inventoryItems = await ref.read(inventoryProvider.future);

    if (!mounted) return;

    showDialog<String>(
      context: context,
      builder: (ctx) {
        String searchQuery = '';
        final searchController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = inventoryItems.where((item) {
              if (searchQuery.trim().isEmpty) return true;
              return item.itemName.toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x, size: 18),
                        onPressed: () => Navigator.of(ctx).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Select strictly from active inventory stock items',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search inventory items...',
                      prefixIcon: const Icon(LucideIcons.search, size: 18),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(LucideIcons.x, size: 16),
                              onPressed: () {
                                searchController.clear();
                                setModalState(() => searchQuery = '');
                              },
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    onChanged: (val) {
                      setModalState(() => searchQuery = val);
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                height: 380,
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'No matching inventory items found.',
                          style: TextStyle(color: Color(0xFF94A3B8)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final item = filtered[i];
                          final isSelected = targetCtrl.text == item.itemName;
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            title: Text(
                              item.itemName,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? const Color(0xFF005CE6) : const Color(0xFF0F172A),
                              ),
                            ),
                            subtitle: Text(
                              '₹${NumberFormat('#,##,##0', 'en_IN').format(item.price)}${item.uom != null ? ' / ${item.uom}' : ''}',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                            ),
                            trailing: isSelected
                                ? const Icon(LucideIcons.check, size: 18, color: Color(0xFF005CE6))
                                : null,
                            onTap: () => Navigator.of(ctx).pop(item.itemName),
                          );
                        },
                      ),
              ),
              actionsPadding: const EdgeInsets.all(12),
              actions: [
                if (targetCtrl.text.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(''),
                    icon: const Icon(LucideIcons.trash2, size: 14, color: Colors.red),
                    label: const Text('Clear Selection', style: TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    ).then((selected) {
      if (selected != null) {
        setState(() {
          targetCtrl.text = selected;
        });
      }
    });
  }

  void _pickSalesStaff() async {
    final staffList = await ref.read(pmSalesStaffProvider.future);

    if (!mounted) return;

    showDialog<String>(
      context: context,
      builder: (ctx) {
        String searchQuery = '';
        final searchController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = staffList.where((staff) {
              final name = (staff['full_name'] ?? '').toString();
              if (searchQuery.trim().isEmpty) return true;
              return name.toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select Sales Executive / Head',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x, size: 18),
                        onPressed: () => Navigator.of(ctx).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Search salesman & sales head names',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by employee name...',
                      prefixIcon: const Icon(LucideIcons.search, size: 18),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(LucideIcons.x, size: 16),
                              onPressed: () {
                                searchController.clear();
                                setModalState(() => searchQuery = '');
                              },
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    onChanged: (val) {
                      setModalState(() => searchQuery = val);
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                height: 360,
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'No sales staff found.',
                          style: TextStyle(color: Color(0xFF94A3B8)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final staff = filtered[i];
                          final name = (staff['full_name'] ?? '').toString();
                          final role = (staff['role'] ?? '').toString();
                          final isSelected = _salesmanNameCtrl.text == name;

                          String roleDisplay = 'Sales Executive';
                          Color roleColor = const Color(0xFF005CE6);
                          if (role == 'salesHead') {
                            roleDisplay = 'Sales Head';
                            roleColor = const Color(0xFF7C3AED);
                          } else if (role == 'admin') {
                            roleDisplay = 'Admin';
                            roleColor = const Color(0xFFDC2626);
                          } else if (role == 'manager') {
                            roleDisplay = 'Manager';
                            roleColor = const Color(0xFF059669);
                          }

                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            title: Text(
                              name,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? const Color(0xFF005CE6) : const Color(0xFF0F172A),
                              ),
                            ),
                            subtitle: Container(
                              margin: const EdgeInsets.only(top: 2),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: roleColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    roleDisplay,
                                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: roleColor),
                                  ),
                                ),
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(LucideIcons.check, size: 18, color: Color(0xFF005CE6))
                                : null,
                            onTap: () => Navigator.of(ctx).pop(name),
                          );
                        },
                      ),
              ),
              actionsPadding: const EdgeInsets.all(12),
              actions: [
                if (_salesmanNameCtrl.text.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(''),
                    icon: const Icon(LucideIcons.trash2, size: 14, color: Colors.red),
                    label: const Text('Clear Selection', style: TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    ).then((selected) {
      if (selected != null) {
        setState(() {
          _salesmanNameCtrl.text = selected;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pm = context.pm;
    final isEdit = widget.editId != null;

    return Scaffold(
      backgroundColor: pm.background,
      appBar: AppBar(
        backgroundColor: pm.card,
        foregroundColor: pm.foreground,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, size: 20, color: Color(0xFF0F172A)),
          tooltip: 'Back to Directory',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/pm');
            }
          },
        ),
        title: Text(
          isEdit
              ? (widget.isPurchase ? 'Edit Vendor #$_idNo' : 'Edit Project #$_idNo')
              : (widget.isPurchase ? 'Add New Vendor' : 'Create New Project'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: PmButton(
              size: PmButtonSize.sm,
              isLoading: _isLoading,
              onPressed: _save,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.check, size: 14),
                  SizedBox(width: 6),
                  Text('Save Record'),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading && isEdit
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Customer Picker (Sales mode)
                        if (!widget.isPurchase) ...[
                          PmCard(
                            child: CustomerSearchPicker(
                              selectedCustomer: _selectedCustomer,
                              onCustomerSelected: (cust) {
                                setState(() {
                                  _selectedCustomer = cust;
                                  if (_siteNameCtrl.text.isEmpty) {
                                    _siteNameCtrl.text = cust.companyName;
                                  }
                                  if (_addressCtrl.text.isEmpty && cust.address != null) {
                                    _addressCtrl.text = cust.address!;
                                  }
                                  if (_mobileCtrl.text.isEmpty && cust.phone != null) {
                                    _mobileCtrl.text = cust.phone!;
                                  }
                                  if (_salesmanNameCtrl.text.trim().isEmpty) {
                                    final sName = cust.salesmanName ?? cust.assignedToName ?? '';
                                    if (sName.isNotEmpty) {
                                      _salesmanNameCtrl.text = sName;
                                    }
                                  }
                                  if (_firmNameCtrl.text.trim().isEmpty) {
                                    _firmNameCtrl.text = ref.read(pmActiveCompanyProvider).name;
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Main Details Card
                        PmCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Account & Site Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: pm.foreground)),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 1,
                                    child: _buildTextField('ID Number', TextEditingController(text: _idNo?.toString() ?? 'Auto'), readOnly: true),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: _buildDropdown('Order Type', _orderType, _orderTypes, (val) {
                                      if (val != null) setState(() => _orderType = val);
                                    }),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Customer Since Date Picker
                              _buildDateField(
                                'Customer Since Date',
                                _customerSinceDate,
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _customerSinceDate,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setState(() => _customerSinceDate = picked);
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                widget.isPurchase ? 'Vendor / Company Name*' : 'Site / Project Name*',
                                _siteNameCtrl,
                                validator: (v) => v?.trim().isEmpty == true ? 'Name is required' : null,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(child: _buildTextField('Mobile Number', _mobileCtrl)),
                                  if (!widget.isPurchase) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        'Sales Man',
                                        _salesmanNameCtrl,
                                        suffixIcon: IconButton(
                                          icon: const Icon(LucideIcons.userCheck, size: 18, color: Color(0xFF005CE6)),
                                          tooltip: 'Pick from sales team',
                                          onPressed: _pickSalesStaff,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                'Firm Name',
                                _firmNameCtrl,
                                suffixIcon: PopupMenuButton<PmCompany>(
                                  icon: const Icon(LucideIcons.building, size: 18, color: Color(0xFF005CE6)),
                                  tooltip: 'Select Firm / Company',
                                  onSelected: (comp) {
                                    setState(() => _firmNameCtrl.text = comp.name);
                                  },
                                  itemBuilder: (ctx) {
                                    final comps = ref.read(pmCompaniesListProvider);
                                    return comps.map((c) => PopupMenuItem(
                                      value: c,
                                      child: Text(c.name, style: const TextStyle(fontSize: 13)),
                                    )).toList();
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildTextField('Address', _addressCtrl, maxLines: 2),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Technical Specifications Card (Strictly inventory items for HP & Tank Type)
                        if (!widget.isPurchase) ...[
                          PmCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Technical Specifications', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: pm.foreground)),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: _buildSearchablePickerField(
                                        label: 'Heat Pump Type (Inventory)*',
                                        value: _hpTypeCtrl.text,
                                        hintText: 'Select Heat Pump model...',
                                        onTap: () => _pickInventoryItem(title: 'Select Heat Pump Type', targetCtrl: _hpTypeCtrl),
                                        onClear: _hpTypeCtrl.text.isNotEmpty ? () => setState(() => _hpTypeCtrl.clear()) : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 1,
                                      child: _buildTextField('HP Qty', _hpQtyCtrl, keyboardType: TextInputType.number),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: _buildSearchablePickerField(
                                        label: 'Tank Type (Inventory)*',
                                        value: _tankTypeCtrl.text,
                                        hintText: 'Select Tank model...',
                                        onTap: () => _pickInventoryItem(title: 'Select Tank Type', targetCtrl: _tankTypeCtrl),
                                        onClear: _tankTypeCtrl.text.isNotEmpty ? () => setState(() => _tankTypeCtrl.clear()) : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 1,
                                      child: _buildTextField('Tank Qty', _tankQtyCtrl, keyboardType: TextInputType.number),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _buildTextField('GL (Glass Lining)', _glCtrl, keyboardType: TextInputType.number),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Financial Values Card
                        PmCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Commercial & Booking Values', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: pm.foreground)),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildTextField(
                                      widget.isPurchase ? 'Quotation Value (₹)' : 'Order Value (₹)',
                                      _orderValueCtrl,
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                  if (!widget.isPurchase) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        'Extra Work Value (₹)',
                                        _extraWorkValueCtrl,
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (!widget.isPurchase) ...[
                                const SizedBox(height: 12),
                                _buildTextField('Initial Work Remark', _workRemarkCtrl, maxLines: 2),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        PmButton(
                          size: PmButtonSize.lg,
                          isLoading: _isLoading,
                          onPressed: _save,
                          child: Text(isEdit ? 'Update Record' : 'Save & Create Record'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildDateField(
    String label,
    DateTime date, {
    required VoidCallback onTap,
  }) {
    final pm = context.pm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pm.mutedForeground)),
        const SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(pm.radiusMd),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: pm.card,
              borderRadius: BorderRadius.circular(pm.radiusMd),
              border: Border.all(color: pm.border),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.calendar, size: 16, color: Color(0xFF005CE6)),
                const SizedBox(width: 10),
                Text(
                  DateFormat('dd/MM/yyyy').format(date),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: pm.foreground),
                ),
                const Spacer(),
                Text('Change', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: pm.primary)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchablePickerField({
    required String label,
    required String value,
    required String hintText,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final pm = context.pm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pm.mutedForeground)),
        const SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(pm.radiusMd),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: pm.card,
              borderRadius: BorderRadius.circular(pm.radiusMd),
              border: Border.all(color: pm.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value.isNotEmpty ? value : hintText,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: value.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                      color: value.isNotEmpty ? pm.foreground : pm.mutedForeground,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (value.isNotEmpty && onClear != null)
                  GestureDetector(
                    onTap: onClear,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(LucideIcons.x, size: 14, color: pm.mutedForeground),
                    ),
                  ),
                Icon(LucideIcons.chevronDown, size: 16, color: pm.mutedForeground),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool readOnly = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    Widget? suffixIcon,
  }) {
    final pm = context.pm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pm.mutedForeground)),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: validator,
          style: TextStyle(fontSize: 14, color: pm.foreground),
          decoration: InputDecoration(
            isDense: true,
            filled: readOnly,
            fillColor: readOnly ? pm.secondary.withOpacity(0.5) : pm.card,
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(pm.radiusMd),
              borderSide: BorderSide(color: pm.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(pm.radiusMd),
              borderSide: BorderSide(color: pm.border),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(
    String label,
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    final pm = context.pm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pm.mutedForeground)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: items.contains(value) ? value : items.first,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(pm.radiusMd),
              borderSide: BorderSide(color: pm.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(pm.radiusMd),
              borderSide: BorderSide(color: pm.border),
            ),
          ),
        ),
      ],
    );
  }
}
