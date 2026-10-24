// lib/features/boq/screens/boq_form_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../core/models/boq.dart';
import '../../../core/models/customer.dart';
import '../../../core/models/product.dart';
import '../../../core/models/pipeline.dart';
import '../../../core/models/quotation.dart';
import '../../../core/widgets/inventory_autocomplete.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../pipelines/providers/pipelines_provider.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/widgets/pdf_preview_screen.dart';
import '../../../core/services/notification_backend_helper.dart';
import '../../admin/providers/manage_boq_items_provider.dart';

class BoqFormScreen extends ConsumerStatefulWidget {
  final String pipelineId;

  const BoqFormScreen({super.key, required this.pipelineId});

  @override
  ConsumerState<BoqFormScreen> createState() => _BoqFormScreenState();
}

class _BoqFormScreenState extends ConsumerState<BoqFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final List<Map<String, dynamic>> _boqItems = [];
  final TextEditingController _remarksController = TextEditingController();

  DateTime? _tentativeDispatchDate;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  Boq? _existingBoq;
  SalesPipeline? _pipeline;
  Quotation? _quotation;
  Product? _product;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _remarksController.dispose();
    for (final item in _boqItems) {
      (item['component'] as TextEditingController).dispose();
      (item['qty'] as TextEditingController).dispose();
      (item['unit'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final supabase = ref.read(supabaseClientProvider);

      // Load pipeline
      final pipelineData = await supabase
          .from('sales_pipelines')
          .select('*, products(*), customers(*)')
          .eq('id', widget.pipelineId)
          .single();
      _pipeline = SalesPipeline.fromJson(pipelineData);
      _product = _pipeline!.product;

      // Load confirmed quotation (for extra specs, references, etc.)
      final quotationData = await supabase
          .from('quotations')
          .select()
          .eq('pipeline_id', widget.pipelineId)
          .eq('status', 'confirmed')
          .maybeSingle();

      if (quotationData != null) {
        _quotation = Quotation.fromJson(quotationData);
      }

      // Load existing BOQ
      final boqData = await supabase
          .from('boqs')
          .select()
          .eq('pipeline_id', widget.pipelineId)
          .maybeSingle();

      if (boqData != null) {
        _existingBoq = Boq.fromJson(boqData);
        _isEditing = !_existingBoq!.isSubmitted;
        _tentativeDispatchDate = _existingBoq!.tentativeDispatchDate;
        _remarksController.text = _existingBoq!.remarks ?? '';

        // Prefill BOQ items if already saved
        if (_existingBoq!.items.isNotEmpty) {
          _boqItems.clear();
          for (final item in _existingBoq!.items) {
            _boqItems.add({
              'component': TextEditingController(text: item.component),
              'qty': TextEditingController(text: item.qty.toInt().toString()),
              'unit': TextEditingController(text: item.unit),
              'scope': item.scope,
            });
          }
        }
      } else {
        _isEditing = true;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addBoqItem(String scope, {String? component, String? unit, String? qty}) {
    setState(() {
      _boqItems.add({
        'component': TextEditingController(text: component ?? ''),
        'qty': TextEditingController(text: qty ?? '1'),
        'unit': TextEditingController(text: unit ?? 'NOS'),
        'scope': scope,
      });
    });
  }

  void _removeBoqItem(Map<String, dynamic> item) {
    setState(() {
      final controller1 = item['component'] as TextEditingController?;
      final controller3 = item['qty'] as TextEditingController?;
      final controller4 = item['unit'] as TextEditingController?;
      controller1?.dispose();
      controller3?.dispose();
      controller4?.dispose();
      _boqItems.remove(item);
    });
  }

  bool _validateBoqItems() {
    if (_boqItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one BOQ item before submitting.'),
          backgroundColor: AppColors.error,
        ),
      );
      return false;
    }

    bool hasAnyError = false;
    for (int i = 0; i < _boqItems.length; i++) {
      final item = _boqItems[i];
      final comp = (item['component'] as TextEditingController).text.trim();
      final qty = (item['qty'] as TextEditingController).text.trim();

      if (comp.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Component name is required for Item ${i + 1}.'),
            backgroundColor: AppColors.error,
          ),
        );
        hasAnyError = true;
      }

      final parsedQty = int.tryParse(qty);
      if (parsedQty == null || parsedQty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Quantity must be a positive integer for Item ${i + 1}.'),
            backgroundColor: AppColors.error,
          ),
        );
        hasAnyError = true;
      }
    }

    setState(() {});
    return !hasAnyError;
  }

  Future<void> _submitBoq() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_validateBoqItems()) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit BOQ'),
        content: const Text(
          'Once submitted, the Factory Order step will be unlocked. Continue?',
          style: TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit & Generate PDF'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);

    try {
      final supabase = ref.read(supabaseClientProvider);

      final items = _boqItems.map((item) {
        return {
          'component': (item['component'] as TextEditingController).text.trim(),
          'spec': '',
          'qty': (int.tryParse((item['qty'] as TextEditingController).text) ?? 1).toDouble(),
          'unit': (item['unit'] as TextEditingController).text.trim(),
          'scope': item['scope'] ?? 'company',
        };
      }).toList();

      final data = {
        'pipeline_id': widget.pipelineId,
        'items': items,
        'extra_fields': _existingBoq?.extraFields ?? {},
        'tentative_dispatch_date': _tentativeDispatchDate?.toIso8601String(),
        'remarks': _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
        'status': 'submitted',
      };

      String boqId;
      if (_existingBoq != null) {
        await supabase.from('boqs').update(data).eq('id', _existingBoq!.id);
        boqId = _existingBoq!.id;
      } else {
        final res = await supabase.from('boqs').insert(data).select('id').single();
        boqId = (res as Map)['id'] as String;
      }

      // Generate and upload BOQ PDF
      await _generateAndUploadPdf(boqId, showPrintDialog: false);

      // Advance pipeline to factory_order
      await supabase.from('sales_pipelines').update(
          {'current_step': 'factory_order'}).eq('id', widget.pipelineId);

      // Audit log
      await supabase.from('step_audit_log').insert({
        'pipeline_id': widget.pipelineId,
        'step_name': 'boq',
        'action': 'confirmed',
        'performed_by': supabase.auth.currentUser!.id,
      });

      // Notification
      final custName = _pipeline?.customer?.companyName ?? '';
      final prodName = _product?.name ?? _pipeline?.product?.name ?? 'deal';
      final custSuffix = custName.isNotEmpty ? ' for $custName ($prodName)' : '';
      await NotificationBackendHelper.notifyUser(
        supabase: supabase,
        userId: supabase.auth.currentUser!.id,
        title: 'Factory Order Unlocked',
        body: 'BOQ submitted$custSuffix. Factory order step is now available.',
        type: 'step_unlocked',
        relatedPipelineId: widget.pipelineId,
      );

      ref.invalidate(pipelineDetailProvider(widget.pipelineId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ BOQ submitted! Factory Order step unlocked.'),
            backgroundColor: AppColors.success,
          ),
        );
        context.go(AppRoutes.pipelineDetail.replaceAll(':id', widget.pipelineId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveSubmittedChanges() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_validateBoqItems()) return;

    setState(() => _isSaving = true);

    try {
      final supabase = ref.read(supabaseClientProvider);

      final items = _boqItems.map((item) {
        return {
          'component': (item['component'] as TextEditingController).text.trim(),
          'spec': (item['spec'] as TextEditingController).text.trim(),
          'qty': int.tryParse((item['qty'] as TextEditingController).text) ?? 1,
          'unit': (item['unit'] as TextEditingController).text.trim(),
          'scope': item['scope'] ?? 'company',
        };
      }).toList();

      final data = {
        'pipeline_id': widget.pipelineId,
        'items': items,
        'extra_fields': _existingBoq?.extraFields ?? {},
        'tentative_dispatch_date': _tentativeDispatchDate?.toIso8601String(),
        'remarks': _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
        'status': 'submitted',
      };

      await supabase.from('boqs').update(data).eq('id', _existingBoq!.id);

      // Generate and upload PDF
      await _generateAndUploadPdf(_existingBoq!.id);

      // Audit log
      await supabase.from('step_audit_log').insert({
        'pipeline_id': widget.pipelineId,
        'step_name': 'boq',
        'action': 'updated',
        'performed_by': supabase.auth.currentUser!.id,
      });

      ref.invalidate(pipelineDetailProvider(widget.pipelineId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ BOQ changes saved successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        setState(() => _isEditing = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving changes: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _openMasterBoqListSheet(String targetScope) {
    if (_product == null) return;
    final boqMasterItemsAsync = ref.read(productBoqItemsProvider(_product!.id));
    final masterItems = boqMasterItemsAsync.valueOrNull ?? [];

    if (masterItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No master BOQ items configured for ${_product!.name}. You can add them in Admin Panel -> Manage BOQ Items.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    // Items already in the other scope must be hidden
    final otherScope = targetScope == 'company' ? 'customer' : 'company';
    final otherScopeItemNames = _boqItems
        .where((item) => (item['scope'] ?? 'company') == otherScope)
        .map((item) => (item['component'] as TextEditingController).text.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();

    final availableMasterItems = masterItems
        .where((m) => !otherScopeItemNames.contains(m.itemName.trim().toLowerCase()))
        .toList();

    if (availableMasterItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('All available master BOQ items are already in ${otherScope == 'company' ? 'Company Scope' : 'Customer Scope'}.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    int getAddedCountInTargetScope(String itemName) {
      return _boqItems.where((item) =>
        (item['scope'] ?? 'company') == targetScope &&
        (item['component'] as TextEditingController).text.trim().toLowerCase() == itemName.trim().toLowerCase()
      ).length;
    }

    final selectedItemIds = <String>{};
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredItems = availableMasterItems.where((m) {
              return m.itemName.toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            final targetScopeLabel = targetScope == 'company' ? 'Company Scope' : 'Customer Scope';

            return Container(
              height: MediaQuery.of(context).size.height * 0.80,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'BOQ Items for $targetScopeLabel',
                          style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  Text(
                    'Select items to populate into $targetScopeLabel (${availableMasterItems.length} available)',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 10),
                  // Real-time Search Box
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search items...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) {
                      setModalState(() => searchQuery = val);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            if (selectedItemIds.length == filteredItems.length && filteredItems.isNotEmpty) {
                              selectedItemIds.clear();
                            } else {
                              selectedItemIds.addAll(filteredItems.map((m) => m.id));
                            }
                          });
                        },
                        child: Text(
                          selectedItemIds.length == filteredItems.length && filteredItems.isNotEmpty
                              ? 'Deselect All'
                              : 'Select All',
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                        icon: const Icon(Icons.add_shopping_cart, size: 16, color: Colors.white),
                        label: Text(
                          'Add Selected (${selectedItemIds.length})',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        onPressed: selectedItemIds.isEmpty
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                for (final m in availableMasterItems.where((item) => selectedItemIds.contains(item.id))) {
                                  _addBoqItem(
                                    targetScope,
                                    component: m.itemName,
                                    unit: m.defaultUnit,
                                  );
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Added ${selectedItemIds.length} items to $targetScopeLabel.'),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              },
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: filteredItems.isEmpty
                        ? Center(
                            child: Text(
                              searchQuery.isEmpty ? 'No items available' : 'No items match "$searchQuery"',
                              style: const TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filteredItems.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final m = filteredItems[idx];
                              final isSelected = selectedItemIds.contains(m.id);
                              final addedCount = getAddedCountInTargetScope(m.itemName);

                              return CheckboxListTile(
                                value: isSelected,
                                onChanged: (val) {
                                  setModalState(() {
                                    if (val == true) {
                                      selectedItemIds.add(m.id);
                                    } else {
                                      selectedItemIds.remove(m.id);
                                    }
                                  });
                                },
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        m.itemName,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                      ),
                                    ),
                                    if (addedCount > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          'Added ${addedCount}x',
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  'Unit: ${m.defaultUnit}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                activeColor: AppColors.primary,
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _generateAndUploadPdf(String boqId, {bool showPrintDialog = true}) async {
    final supabase = ref.read(supabaseClientProvider);

    // Fetch latest BOQ data
    final boqData =
        await supabase.from('boqs').select().eq('id', boqId).single();
    final boq = Boq.fromJson(boqData);

    // Fetch latest pipeline data with customer and product details
    final pipelineData = await supabase
        .from('sales_pipelines')
        .select('*, customers(*), products(*)')
        .eq('id', boq.pipelineId)
        .single();
    final pipeline = SalesPipeline.fromJson(pipelineData);

    final customer = pipeline.customer ?? Customer(
      id: pipeline.customerId,
      companyName: 'Default Customer',
      contactPerson: 'Contact Person',
      phone: '',
      email: '',
      createdBy: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final product = pipeline.product ?? Product(
      id: pipeline.productId,
      name: 'Default Product',
      category: 'HVAC',
      baseSpecs: const ProductBaseSpecs(quotationFields: [], boqRequiredFields: []),
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Fetch latest quotation data
    Quotation? quotation = _quotation;
    if (quotation == null) {
      try {
        final quotationData = await supabase
            .from('quotations')
            .select()
            .eq('pipeline_id', boq.pipelineId)
            .maybeSingle();
        if (quotationData != null) {
          quotation = Quotation.fromJson(quotationData);
        }
      } catch (_) {}
    }
    // Fallback if still null
    quotation ??= Quotation(
      id: '',
      pipelineId: boq.pipelineId,
      productId: pipeline.productId,
      lineItems: [],
      productSpecs: {},
      subtotal: 0.0,
      cgstRate: 0.0,
      sgstRate: 0.0,
      cgstAmount: 0.0,
      sgstAmount: 0.0,
      igstAmount: 0.0,
      grandTotal: 0.0,
      status: QuotationStatus.draft,
      quotationNumber: 'QT-TEMP',
      orderDate: DateTime.now(),
      billType: 'Credit',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    Map<String, dynamic> templateConfig;
    try {
      final templateData = await supabase
          .from('pdf_templates')
          .select()
          .eq('document_type', 'boq')
          .single();
      templateConfig =
          (templateData)['template_config'] as Map<String, dynamic>;
    } catch (_) {
      templateConfig = {
        'company_name': 'IZYHEAT',
        'company_address': 'IZYHEAT Office, India',
        'company_phone': '+91 99999 99999',
        'company_email': 'info@izyheat.com',
        'company_gst': '27AAAAA1111A1Z1',
        'footer_text': 'Thank you for your business.',
        'terms_default':
            '1. Payment: 50% advance, 50% before delivery.\n2. Delivery: 2-3 weeks.',
      };
    }

    // Generate PDF bytes
    final pdfBytes = await PdfService.generateBoqPdf(
      boq: boq,
      customer: customer,
      product: product,
      quotation: quotation,
      templateConfig: templateConfig,
    );

    // Write audit log
    await supabase.from('step_audit_log').insert({
      'pipeline_id': widget.pipelineId,
      'step_name': 'boq',
      'action': 'pdf_generated',
      'performed_by': supabase.auth.currentUser!.id,
    });

    if (showPrintDialog && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PdfPreviewScreen(
            pdfBytes: pdfBytes,
            fileName: '${boq.boqNumber.replaceAll('/', '_')}.pdf',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final isSubmitted = _existingBoq?.isSubmitted == true;
    final enabled = !isSubmitted || _isEditing;

    // Previews
    final quotationItemNames = _quotation?.lineItems.map((li) => li.description).where((d) => d.isNotEmpty).join(', ') ?? '';
    final displayProductName = quotationItemNames.isNotEmpty ? quotationItemNames : (_product?.name ?? 'Product');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isSubmitted && !_isEditing
            ? 'BOQ (Submitted)'
            : 'Bill of Quantities (BOQ)'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (isSubmitted && !_isEditing) ...[
            TextButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: const Icon(Icons.edit, color: Colors.white, size: 16),
              label: const Text('Edit Details',
                  style: TextStyle(color: Colors.white, fontFamily: 'Inter')),
            ),
            IconButton(
              icon: const Icon(Icons.print, color: Colors.white),
              onPressed: () => _generateAndUploadPdf(_existingBoq!.id),
            ),
          ],
          if (_isEditing && isSubmitted)
            TextButton(
              onPressed: _isSaving ? null : _saveSubmittedChanges,
              child: const Text('Save Changes',
                  style: TextStyle(color: Colors.white, fontFamily: 'Inter')),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.pagePadding,
          children: [
            // Top Preview Banner
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1B4B),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, color: Color(0xFF38BDF8), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'BOQ for product: $displayProductName',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Header Customer Details
            if (_pipeline?.customer != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pipeline!.customer!.companyName,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(_product?.name ?? '',
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: AppColors.textSecondary)),
                    if (_quotation != null)
                      Text(
                        'Ref: ${_quotation!.quotationNumber}',
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: AppColors.textSecondary),
                      ),
                    if (_existingBoq != null)
                      Text(
                        _existingBoq!.boqNumber,
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // Company Scope Section Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Company Scope',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                if (enabled && _product != null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.list_alt, size: 16, color: Colors.white),
                    label: const Text(
                      'Open list',
                      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: () => _openMasterBoqListSheet('company'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_boqItems.where((item) => (item['scope'] ?? 'company') == 'company').isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: Text(
                  'No company scope items added yet. Tap "Open list" above or "Add Item" below.',
                  style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary, fontSize: 13),
                ),
              )
            else
              ..._boqItems.where((item) => (item['scope'] ?? 'company') == 'company').map((item) {
                final globalIndex = _boqItems.indexOf(item);
                return _BoqItemRow(
                  index: globalIndex,
                  item: item,
                  onRemove: !enabled ? null : () => _removeBoqItem(item),
                  enabled: enabled,
                );
              }),
            if (enabled) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _addBoqItem('company'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Company Scope Item'),
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Customer Scope Section Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Customer Scope',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                if (enabled && _product != null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.list_alt, size: 16, color: Colors.white),
                    label: const Text(
                      'Open list',
                      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: () => _openMasterBoqListSheet('customer'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_boqItems.where((item) => (item['scope'] ?? 'company') == 'customer').isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: Text(
                  'No customer scope items added yet. Tap "Open list" above or "Add Item" below.',
                  style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary, fontSize: 13),
                ),
              )
            else
              ..._boqItems.where((item) => (item['scope'] ?? 'company') == 'customer').map((item) {
                final globalIndex = _boqItems.indexOf(item);
                return _BoqItemRow(
                  index: globalIndex,
                  item: item,
                  onRemove: !enabled ? null : () => _removeBoqItem(item),
                  enabled: enabled,
                );
              }),
            if (enabled) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _addBoqItem('customer'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Customer Scope Item'),
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Tentative Dispatch Date Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_available_outlined, color: AppColors.primary, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tentative Dispatch Date',
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _tentativeDispatchDate != null
                              ? 'Scheduled: ${DateFormat('dd MMM yyyy').format(_tentativeDispatchDate!)}'
                              : 'Not set (Notifies Factory Staff on entry)',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: _tentativeDispatchDate != null ? AppColors.primary : AppColors.textSecondary,
                            fontWeight: _tentativeDispatchDate != null ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (enabled)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _tentativeDispatchDate ?? DateTime.now().add(const Duration(days: 7)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setState(() => _tentativeDispatchDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(_tentativeDispatchDate != null ? 'Change' : 'Set Date'),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Single Remarks Input Field
            const Text(
              'Remarks / Notes',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _remarksController,
              enabled: enabled,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter general remarks, delivery notes, or site details for this BOQ...',
              ),
            ),

            const SizedBox(height: 24),

            if (!isSubmitted || _isEditing)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : (isSubmitted ? _saveSubmittedChanges : _submitBoq),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_isSaving
                      ? 'Processing...'
                      : (isSubmitted ? 'Save Changes & Print' : 'Submit BOQ')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            if (isSubmitted && !_isEditing)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.success),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'BOQ submitted. Factory Order step is unlocked.',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.success,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => _generateAndUploadPdf(_existingBoq!.id),
                      child: const Text('Print PDF'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _BoqItemRow extends StatelessWidget {
  final int index;
  final Map<String, dynamic> item;
  final VoidCallback? onRemove;
  final bool enabled;

  const _BoqItemRow({
    required this.index,
    required this.item,
    this.onRemove,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Item ${index + 1}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Spacer(),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.error, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Remove item',
                ),
            ],
          ),
          const SizedBox(height: 10),
          InventoryAutocomplete(
            controller: item['component'] as TextEditingController,
            enabled: enabled,
            labelText: 'Component Description *',
            onChanged: () {},
            onItemSelected: (selection) {
              final unitController = item['unit'] as TextEditingController;
              if (unitController.text.isEmpty) unitController.text = selection.uom ?? '';
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: item['qty'] as TextEditingController,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Qty (Integer) *',
                    hintText: 'e.g. 1, 2, 5',
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    final n = int.tryParse(v);
                    if (n == null || n <= 0) return 'Must be >= 1';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: item['unit'] as TextEditingController,
                  enabled: enabled,
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    hintText: 'NOS, MTR, SET',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
