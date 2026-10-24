// lib/features/installations/screens/book_installation_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../providers/installations_provider.dart';
import '../data/models/installation_model.dart';
import '../../complaints/providers/complaints_provider.dart'
    show availableTechniciansProvider;
import '../../complaints/data/models/complaint_model.dart' show TechnicianInfo;
import '../../../features/customers/providers/customers_provider.dart';
import '../../../core/models/customer.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../core/models/user_role.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/widgets/searchable_dropdown.dart';

import '../../../core/models/pipeline.dart';

class BookInstallationScreen extends ConsumerStatefulWidget {
  const BookInstallationScreen({super.key});

  @override
  ConsumerState<BookInstallationScreen> createState() =>
      _BookInstallationScreenState();
}

class _BookInstallationScreenState
    extends ConsumerState<BookInstallationScreen> {
  final _searchController = TextEditingController();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _addressController = TextEditingController();
  final _sealNumberBeforeController = TextEditingController();
  final _mobileController = TextEditingController();
  String _selectedPriority = 'High Priority';
  bool _isSubmitting = false;

  Customer? _selectedCustomer;
  TechnicianInfo? _selectedTechnician;
  String? _selectedProduct;
  List<Map<String, dynamic>> _customerCompletedDeals = [];
  Map<String, dynamic>? _selectedDeal;
  List<TechnicianInfo> _selectedSupporters = [];
  final List<String> _sitePhotosBase64 = [];
  final ImagePicker _picker = ImagePicker();

  final Map<String, TextEditingController> _itemQtyControllers = {};
  Map<String, Map<String, int>> _previousInstalledCounts = {};

  @override
  void dispose() {
    _searchController.dispose();
    _titleController.dispose();
    _descController.dispose();
    _addressController.dispose();
    _sealNumberBeforeController.dispose();
    _mobileController.dispose();
    _clearItemQtyControllers();
    super.dispose();
  }

  void _clearItemQtyControllers() {
    for (final c in _itemQtyControllers.values) {
      c.dispose();
    }
    _itemQtyControllers.clear();
  }

  void _initItemQuantities() {
    _clearItemQtyControllers();
    if (_selectedDeal == null) return;

    final dealId = _selectedDeal!['id']?.toString() ?? '';
    final dealPrev = _previousInstalledCounts[dealId] ?? _previousInstalledCounts['all'] ?? {};

    final items = (_selectedDeal?['quotations'] as List?)?.isNotEmpty == true &&
            (_selectedDeal?['quotations'][0]['items'] != null)
        ? (_selectedDeal!['quotations'][0]['items'] as List)
        : [];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final desc = (item['description'] ?? item['name'] ?? 'Item $i').toString().trim();
      final totalQty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
      final prevInstalled = dealPrev[desc] ?? 0;
      final available = (totalQty - prevInstalled).clamp(0, totalQty);
      final defaultQty = available > 0 ? available : 0;
      _itemQtyControllers[desc] = TextEditingController(text: defaultQty.toString());
    }
  }

  Map<String, Map<String, int>> _parsePreviousInstalledItems(List<dynamic> installations) {
    final Map<String, Map<String, int>> result = {};
    for (final inst in installations) {
      final notes = (inst['notes'] ?? '').toString();
      if (notes.isEmpty) continue;

      String? dealId;
      final dealMatch = RegExp(r'Deal ID:\s*([a-zA-Z0-9\-]+)').firstMatch(notes);
      if (dealMatch != null) {
        dealId = dealMatch.group(1)?.trim();
      }

      final itemsMatch = RegExp(r'\[INSTALLED_ITEMS:\s*(\[.*?\])\s*\]').firstMatch(notes);
      if (itemsMatch != null) {
        try {
          final jsonStr = itemsMatch.group(1)!;
          final list = jsonDecode(jsonStr) as List<dynamic>;
          for (final item in list) {
            final desc = (item['description'] ?? item['name'] ?? '').toString().trim();
            final qty = int.tryParse(item['qty']?.toString() ?? '0') ?? 0;
            if (desc.isNotEmpty && qty > 0) {
              final key = (dealId != null && dealId.isNotEmpty) ? dealId : 'all';
              result.putIfAbsent(key, () => {});
              result[key]![desc] = (result[key]![desc] ?? 0) + qty;
            }
          }
        } catch (e) {
          debugPrint('Error parsing installed items from notes: $e');
        }
      }
    }
    return result;
  }

  void _onCustomerSelected(Customer customer) async {
    setState(() {
      _selectedCustomer = customer;
      _addressController.text = customer.address ?? '';
      _mobileController.text = customer.phone ?? '';
      _customerCompletedDeals = [];
      _selectedDeal = null;
      _selectedProduct = null;
      _previousInstalledCounts = {};
      _clearItemQtyControllers();
    });

    final supabase = ref.read(supabaseClientProvider);
    try {
      final res = await supabase.from('sales_pipelines').select('''
        *,
        customers(*),
        products(id, name, category),
        profiles!sales_pipelines_created_by_fkey(id, full_name),
        quotations(id, status, line_items),
        sales_orders(id, status),
        boqs(id, status),
        factory_orders(id, status),
        purchase_orders(id, status)
      ''').eq('customer_id', customer.id);

      final prevInstRes = await supabase
          .from('installations')
          .select('id, notes, created_at')
          .eq('customer_id', customer.id);

      final prevMap = _parsePreviousInstalledItems((prevInstRes as List<dynamic>?) ?? []);
      
      if (mounted) {
        final pipelines = (res as List).map((p) => SalesPipeline.fromJson(p as Map<String, dynamic>)).toList();
        final completedDeals = pipelines
            .where((p) => p.currentStep == PipelineStep.completed || p.status == PipelineStatus.completed)
            .map((p) {
              return {
                'id': p.id,
                'products': p.product != null ? {'name': p.product!.name, 'id': p.product!.id} : null,
                'quotations': p.quotation != null ? [{'items': p.quotation!.lineItems.map((i) => i.toJson()).toList()}] : [],
              };
            })
            .toList();

        setState(() {
          _customerCompletedDeals = completedDeals;
          _previousInstalledCounts = prevMap;
        });
      }
    } catch (e) {
      debugPrint('Error fetching completed deals: $e');
    }
  }

  void _showPhotoSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Add Site Photo',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            ListTile(
              leading:
                  const Icon(Icons.camera_alt, color: Color(0xFF0284C7)),
              title: const Text('Take Photo with Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickSitePhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: Color(0xFF0284C7)),
              title: const Text('Choose Photos from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickSitePhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSitePhoto(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final List<XFile> photos =
            await _picker.pickMultiImage(imageQuality: 70);
        if (photos.isNotEmpty) {
          for (final photo in photos) {
            final bytes = await photo.readAsBytes();
            final base64Str = base64Encode(bytes);
            _sitePhotosBase64.add('data:image/jpeg;base64,$base64Str');
          }
          setState(() {});
        }
      } else {
        final XFile? photo =
            await _picker.pickImage(source: source, imageQuality: 70);
        if (photo != null) {
          final bytes = await photo.readAsBytes();
          final base64Str = base64Encode(bytes);
          setState(() {
            _sitePhotosBase64.add('data:image/jpeg;base64,$base64Str');
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  void _submitInstallation() async {
    final profile = ref.read(currentProfileProvider);
    final isTech = profile?.primaryRole == UserRole.technician;

    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer first')),
      );
      return;
    }

    if (_selectedDeal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a completed deal/product first')),
      );
      return;
    }

    if (isTech && profile != null) {
      _selectedTechnician = TechnicianInfo(
        id: profile.id,
        name: profile.fullName,
        avatarUrl: '',
        status: 'Available',
        distance: '0km',
        activeTasksCount: 0,
        rating: 4.9,
      );
    }

    if (_selectedTechnician == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please assign a technician before scheduling the installation.')),
      );
      return;
    }

    final List<Map<String, dynamic>> installedItemsList = [];
    final items = (_selectedDeal?['quotations'] as List?)?.isNotEmpty == true &&
            (_selectedDeal?['quotations'][0]['items'] != null)
        ? (_selectedDeal!['quotations'][0]['items'] as List)
        : [];

    final dealId = _selectedDeal!['id']?.toString() ?? '';
    final dealPrev = _previousInstalledCounts[dealId] ?? _previousInstalledCounts['all'] ?? {};

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final desc = (item['description'] ?? item['name'] ?? 'Item $i').toString().trim();
      final totalQty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
      final prevInstalled = dealPrev[desc] ?? 0;
      final available = (totalQty - prevInstalled).clamp(0, totalQty);

      final ctrl = _itemQtyControllers[desc];
      final entered = int.tryParse(ctrl?.text.trim() ?? '0') ?? 0;
      final validQty = entered.clamp(0, available);
      if (validQty > 0) {
        installedItemsList.add({
          'description': desc,
          'qty': validQty,
        });
      }
    }

    if (items.isNotEmpty && installedItemsList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please specify quantity to install for at least one item.')),
      );
      return;
    }

    String title = 'Installation for ${_selectedCustomer!.companyName}';
    if (_selectedDeal != null) {
      final prodName = _selectedDeal!['products']?['name'] ?? 'System';
      title = 'Installation: $prodName';
      _selectedProduct = prodName;
    }

    String supportersStr = _selectedSupporters.isNotEmpty 
        ? 'Supporters: ${_selectedSupporters.map((s) => s.name).join(", ")}'
        : '';
    String finalNotes = supportersStr;
    if (_selectedDeal != null) {
      if (finalNotes.isNotEmpty) finalNotes += '\n';
      finalNotes += 'Deal ID: ${_selectedDeal!['id']}';
    }
    if (installedItemsList.isNotEmpty) {
      if (finalNotes.isNotEmpty) finalNotes += '\n';
      final humanItems = installedItemsList.map((e) => '${e['description']} (Qty: ${e['qty']})').join(', ');
      finalNotes += 'Installed Items: $humanItems\n';
      finalNotes += '[INSTALLED_ITEMS:${jsonEncode(installedItemsList)}]';
    }

    setState(() => _isSubmitting = true);

    List<String> finalUrls = [];
    try {
      final supabase = ref.read(supabaseClientProvider);
      finalUrls = await StorageService.uploadMultipleImages(
        supabase: supabase,
        base64OrPaths: _sitePhotosBase64,
        folder: 'installation_photos',
      );
    } catch (_) {}

    final ticketNum = await generateNextInstallationTicketNumber(ref);
    final updatedAddress = _addressController.text.trim().isEmpty
        ? (_selectedCustomer!.address ?? '')
        : _addressController.text.trim();

    final newInstallation = Installation(
      id: const Uuid().v4(),
      ticketNumber: ticketNum,
      customerId: _selectedCustomer!.id,
      customerName: _selectedCustomer!.companyName,
      customerPhone: _selectedCustomer!.phone ?? '',
      customerAddress: updatedAddress,
      productName: _selectedProduct,
      priority: _selectedPriority,
      title: title,
      description: _descController.text.trim(),
      status: 'assigned',
      technicianId: _selectedTechnician!.id,
      technicianName: _selectedTechnician!.name,
      technicianAvatarUrl: _selectedTechnician!.avatarUrl,
      tatRemaining: '48h',
      beforeImageUrl: finalUrls.isNotEmpty ? finalUrls.join('|||') : null,
      sealNumberBefore: _sealNumberBeforeController.text.trim().isNotEmpty
          ? _sealNumberBeforeController.text.trim()
          : null,
      source: 'staff',
      notes: finalNotes.isNotEmpty ? finalNotes : null,
      createdAt: DateTime.now(),
    );

    try {
      await ref
          .read(installationsProvider.notifier)
          .addInstallation(newInstallation);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Installation $ticketNum created successfully!'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error booking installation: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(serviceCustomersNotifierProvider);
    final techniciansAsync = ref.watch(availableTechniciansProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Schedule Installation',
          style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.bold,
              color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Customer Selector Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Customer Information',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    customersAsync.when(
                      data: (customers) {
                        return SearchableDropdown<Customer>(
                          label: 'Customer',
                          hint: 'Select Customer',
                          value: _selectedCustomer,
                          items: customers,
                          itemLabel: (c) => c.companyName,
                          onChanged: (c) {
                            if (c != null) _onCustomerSelected(c);
                          },
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Error loading customers: $e'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _mobileController,
                      decoration: const InputDecoration(
                        labelText: 'Mobile Number',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'Site Address',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            if (_selectedCustomer != null) ...[
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Installation Product',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_customerCompletedDeals.isEmpty)
                        const Text('No completed deals found for this customer.', style: TextStyle(color: Colors.grey))
                      else
                        DropdownButtonFormField<Map<String, dynamic>>(
                          decoration: const InputDecoration(
                            labelText: 'Select Deal / Product',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          value: _selectedDeal,
                          items: _customerCompletedDeals.map((deal) {
                            final productName = deal['products']?['name'] ?? 'Unknown Product';
                            return DropdownMenuItem(
                              value: deal,
                              child: Text(productName),
                            );
                          }).toList(),
                          onChanged: (deal) {
                            setState(() {
                              _selectedDeal = deal;
                              _initItemQuantities();
                            });
                          },
                        ),
                      _buildQuotationItemsSection(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Installation Details Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Installation Details',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descController,
                      decoration: const InputDecoration(
                        labelText: 'Scope / Technical Notes',
                        hintText: 'e.g. Structure erection, panel wiring, inverter setup',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedPriority,
                            decoration: const InputDecoration(
                              labelText: 'Priority',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: ['High Priority', 'Medium Priority', 'Low Priority']
                                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _selectedPriority = v);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _sealNumberBeforeController,
                            decoration: const InputDecoration(
                              labelText: 'Initial Seal # (Optional)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Technician Assignment Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Assign Technician *',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    techniciansAsync.when(
                      data: (technicians) {
                        return DropdownButtonFormField<TechnicianInfo>(
                          value: _selectedTechnician,
                          hint: const Text('Select Installer / Technician'),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: technicians
                              .map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t.name),
                                  ))
                              .toList(),
                          onChanged: (t) => setState(() => _selectedTechnician = t),
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Error loading technicians: $e'),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Supporter(s) (Optional)',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    techniciansAsync.when(
                      data: (technicians) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _selectedSupporters.map((t) {
                                  return Chip(
                                    label: Text(t.name),
                                    deleteIcon: const Icon(Icons.close, size: 16),
                                    onDeleted: () {
                                      setState(() {
                                        _selectedSupporters.remove(t);
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            ),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF14B8A6),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) {
                                    return StatefulBuilder(
                                      builder: (context, setStateDialog) {
                                        return AlertDialog(
                                          title: const Text('Add Supporters'),
                                          content: SizedBox(
                                            width: double.maxFinite,
                                            child: ListView(
                                              shrinkWrap: true,
                                              children: technicians
                                                  .where((t) => t != _selectedTechnician)
                                                  .map((t) {
                                                final isSelected = _selectedSupporters.contains(t);
                                                return CheckboxListTile(
                                                  title: Text(t.name),
                                                  value: isSelected,
                                                  activeColor: const Color(0xFF14B8A6),
                                                  onChanged: (val) {
                                                    setStateDialog(() {
                                                      if (val == true) {
                                                        _selectedSupporters.add(t);
                                                      } else {
                                                        _selectedSupporters.remove(t);
                                                      }
                                                    });
                                                    setState(() {});
                                                  },
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context),
                                              child: const Text('Done', style: TextStyle(color: Color(0xFF14B8A6))),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (e, _) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Site Photos
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Pre-installation Site Photos',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _showPhotoSourceSheet,
                          icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                          label: const Text('Add Photo'),
                        ),
                      ],
                    ),
                    if (_sitePhotosBase64.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 90,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _sitePhotosBase64.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, idx) {
                            final str = _sitePhotosBase64[idx];
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    base64Decode(str.substring(str.indexOf(',') + 1)),
                                    width: 90,
                                    height: 90,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() => _sitePhotosBase64.removeAt(idx));
                                    },
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(2),
                                      child: const Icon(Icons.close, size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isSubmitting ? null : _submitInstallation,
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Submit Installation',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotationItemsSection() {
    if (_selectedDeal == null) return const SizedBox.shrink();

    final items = (_selectedDeal?['quotations'] as List?)?.isNotEmpty == true &&
            (_selectedDeal?['quotations'][0]['items'] != null)
        ? (_selectedDeal!['quotations'][0]['items'] as List)
        : [];

    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No items found in quotation.', style: TextStyle(color: Colors.grey, fontSize: 13)),
      );
    }

    final dealId = _selectedDeal!['id']?.toString() ?? '';
    final dealPrev = _previousInstalledCounts[dealId] ?? _previousInstalledCounts['all'] ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Quotation Items (from Deal)',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Color(0xFF1E293B),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${items.length} items',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...List.generate(items.length, (idx) {
          final item = items[idx];
          final desc = (item['description'] ?? item['name'] ?? 'Item $idx').toString().trim();
          final totalQty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
          final prevInstalled = dealPrev[desc] ?? 0;
          final isSubsequentSchedule = prevInstalled > 0;
          final availableQty = (totalQty - prevInstalled).clamp(0, totalQty);

          final ctrl = _itemQtyControllers.putIfAbsent(desc, () {
            final def = availableQty > 0 ? availableQty : 0;
            return TextEditingController(text: def.toString());
          });

          final enteredQty = int.tryParse(ctrl.text.trim()) ?? 0;
          final currentInstalling = enteredQty.clamp(0, availableQty);
          final remainingQty = (availableQty - currentInstalling).clamp(0, availableQty);
          final isFullyInstalled = availableQty == 0;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isFullyInstalled ? const Color(0xFFF8FAFC) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isFullyInstalled ? const Color(0xFFE2E8F0) : const Color(0xFFCBD5E1),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Item header: Title + Status
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isFullyInstalled
                            ? const Color(0xFFE2E8F0)
                            : const Color(0xFF0284C7).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.inventory_2_outlined,
                        size: 18,
                        color: isFullyInstalled ? const Color(0xFF64748B) : const Color(0xFF0284C7),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            desc,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: isFullyInstalled ? const Color(0xFF64748B) : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Quantities stats badges
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              _buildQtyBadge(
                                label: 'Total Qty: $totalQty',
                                bgColor: const Color(0xFFF1F5F9),
                                textColor: const Color(0xFF475569),
                              ),
                              if (isSubsequentSchedule) ...[
                                _buildQtyBadge(
                                  label: 'Installed: $prevInstalled',
                                  bgColor: const Color(0xFFEEF2FF),
                                  textColor: const Color(0xFF4F46E5),
                                ),
                                _buildQtyBadge(
                                  label: 'Available: $availableQty',
                                  bgColor: isFullyInstalled ? const Color(0xFFF1F5F9) : const Color(0xFFECFDF5),
                                  textColor: isFullyInstalled ? const Color(0xFF94A3B8) : const Color(0xFF059669),
                                ),
                              ],
                              if (isFullyInstalled)
                                _buildQtyBadge(
                                  label: '✓ Fully Installed',
                                  bgColor: const Color(0xFFECFDF5),
                                  textColor: const Color(0xFF047857),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 12),

                // Interactive Installing Now & Auto-Calculated Remaining
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Installing Quantity Selector
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Installing Now',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isFullyInstalled ? Colors.grey : const Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (isFullyInstalled)
                          const Text('0', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey))
                        else
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                              color: const Color(0xFFF8FAFC),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 16),
                                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                                  padding: EdgeInsets.zero,
                                  onPressed: currentInstalling > 0
                                      ? () {
                                          setState(() {
                                            ctrl.text = (currentInstalling - 1).toString();
                                          });
                                        }
                                      : null,
                                ),
                                SizedBox(
                                  width: 44,
                                  child: TextField(
                                    controller: ctrl,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                                    ),
                                    onChanged: (val) {
                                      setState(() {});
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 16),
                                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                                  padding: EdgeInsets.zero,
                                  onPressed: currentInstalling < availableQty
                                      ? () {
                                          setState(() {
                                            ctrl.text = (currentInstalling + 1).toString();
                                          });
                                        }
                                      : null,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),

                    // Remaining Quantity display (Auto Calculate)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: remainingQty == 0
                            ? const Color(0xFFECFDF5)
                            : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: remainingQty == 0
                              ? const Color(0xFFA7F3D0)
                              : const Color(0xFFFDE68A),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Remaining Qty',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: remainingQty == 0 ? const Color(0xFF047857) : const Color(0xFFB45309),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$remainingQty',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: remainingQty == 0 ? const Color(0xFF047857) : const Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildQtyBadge({required String label, required Color bgColor, required Color textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
