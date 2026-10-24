import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../core/models/purchase_order.dart';
import '../../../core/models/customer.dart';
import '../../../core/models/product.dart';
import '../../../core/models/pipeline.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../pipelines/providers/pipelines_provider.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/services/notification_backend_helper.dart';
import '../../../core/widgets/pdf_preview_screen.dart';
import '../../../core/widgets/inventory_autocomplete.dart';

class PurchaseOrderScreen extends ConsumerStatefulWidget {
  final String pipelineId;

  const PurchaseOrderScreen({super.key, required this.pipelineId});

  @override
  ConsumerState<PurchaseOrderScreen> createState() =>
      _PurchaseOrderScreenState();
}

class _PurchaseOrderScreenState extends ConsumerState<PurchaseOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  // PO items
  final List<Map<String, dynamic>> _poItems = [];

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  PurchaseOrder? _existingPO;
  SalesPipeline? _pipeline;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (final item in _poItems) {
      (item['description'] as TextEditingController).dispose();
      (item['qty'] as TextEditingController).dispose();
      (item['unit'] as TextEditingController).dispose();
      (item['unit_price'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final supabase = ref.read(supabaseClientProvider);

      final pipelineData = await supabase
          .from('sales_pipelines')
          .select('*, products(*), customers(*)')
          .eq('id', widget.pipelineId)
          .single();

      _pipeline = SalesPipeline.fromJson(pipelineData);

      final poData = await supabase
          .from('purchase_orders')
          .select()
          .eq('pipeline_id', widget.pipelineId)
          .maybeSingle();

      if (poData != null) {
        _existingPO = PurchaseOrder.fromJson(poData);
        _isEditing = _existingPO!.status != PurchaseOrderStatus.ordered;

        // Prefill items
        for (final item in _existingPO!.items) {
          _poItems.add({
            'description': TextEditingController(text: item.description),
            'qty': TextEditingController(text: item.qty.toInt().toString()),
            'unit': TextEditingController(text: item.unit),
          });
        }

        _notesController.text = _existingPO!.purchaseNotes ?? '';
      } else {
        _isEditing = true;
      }

      // Pre-fill from factory order items if no PO yet
      if (_poItems.isEmpty) {
        final boqData = await supabase
            .from('boqs')
            .select()
            .eq('pipeline_id', widget.pipelineId)
            .maybeSingle();

        if (boqData != null) {
          final items = ((boqData as Map)['items'] as List<dynamic>?) ?? [];
          for (final item in items) {
            final i = item as Map<String, dynamic>;
            _poItems.add({
              'description':
                  TextEditingController(text: i['component'] as String? ?? ''),
              'qty': TextEditingController(text: (num.tryParse(i['qty']?.toString() ?? '1')?.toInt() ?? 1).toString()),
              'unit':
                  TextEditingController(text: i['unit'] as String? ?? 'nos'),
            });
          }
        }
      }

      if (_poItems.isEmpty) _addPoItem();
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

  void _addPoItem() {
    setState(() {
      _poItems.add({
        'description': TextEditingController(),
        'qty': TextEditingController(text: '1'),
        'unit': TextEditingController(text: 'nos'),
      });
    });
  }

  void _removePoItem(int index) {
    setState(() {
      final item = _poItems.removeAt(index);
      (item['description'] as TextEditingController).dispose();
      (item['qty'] as TextEditingController).dispose();
      (item['unit'] as TextEditingController).dispose();
    });
  }

  double _calcTotalQty() {
    double total = 0;
    for (final item in _poItems) {
      final qty =
          double.tryParse((item['qty'] as TextEditingController).text) ?? 0;
      total += qty;
    }
    return total;
  }

  Future<void> _submitPO() async {
    if (!_formKey.currentState!.validate()) return;

    final isPlaced = _existingPO?.status == PurchaseOrderStatus.ordered;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isPlaced ? 'Save Changes' : 'Place Material Requisition'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isPlaced
                  ? 'Are you sure you want to save changes to this Material Requisition?'
                  : 'This will complete the pipeline and generate the Material Requisition PDF. Continue?',
              style: const TextStyle(fontFamily: 'Inter'),
            ),
            const SizedBox(height: 12),
            Text(
              'Total Quantity: ${_calcTotalQty().toInt()}',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isPlaced ? 'Save' : 'Place Order'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);

    try {
      final supabase = ref.read(supabaseClientProvider);

      final items = _poItems.map((item) {
        final qty =
            int.tryParse((item['qty'] as TextEditingController).text) ?? 0;
        return {
          'description':
              (item['description'] as TextEditingController).text.trim(),
          'qty': qty,
          'unit': (item['unit'] as TextEditingController).text.trim(),
          'unit_price': 0,
          'total': 0,
        };
      }).toList();

      final vendorDetails = {
        'vendor_name': '',
      };

      final data = {
        'pipeline_id': widget.pipelineId,
        'items': items,
        'vendor_details': vendorDetails,
        'total_amount': 0,
        'purchase_notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'status': 'ordered',
        'bill_number': null,
        'bill_date': null,
        'bill_amount': null,
      };

      final wasOrdered = _existingPO?.status == PurchaseOrderStatus.ordered;

      String poId;
      if (_existingPO != null) {
        await supabase
            .from('purchase_orders')
            .update(data)
            .eq('id', _existingPO!.id);
        poId = _existingPO!.id;
      } else {
        final res = await supabase
            .from('purchase_orders')
            .insert(data)
            .select('id')
            .single();
        poId = (res as Map)['id'] as String;
      }

      // Generate and upload PDF
      await _generateAndUploadPdf(poId, showPrintDialog: false);

      if (!wasOrdered) {
        // Mark pipeline as completed
        await supabase.from('sales_pipelines').update({
          'current_step': 'completed',
          'status': 'completed',
        }).eq('id', widget.pipelineId);

        // Audit log
        await supabase.from('step_audit_log').insert({
          'pipeline_id': widget.pipelineId,
          'step_name': 'purchase_order',
          'action': 'confirmed',
          'performed_by': supabase.auth.currentUser!.id,
        });

        // Notify sales team
        final salesPipeline = await supabase
            .from('sales_pipelines')
            .select('created_by')
            .eq('id', widget.pipelineId)
            .single();

        final customerName = _pipeline?.customer?.companyName ?? '';
        final productName = _pipeline?.product?.name ?? 'product';
        final custSuffix = customerName.isNotEmpty ? ' ($customerName)' : '';

        await NotificationBackendHelper.notifyUser(
          supabase: supabase,
          userId: (salesPipeline as Map)['created_by'],
          title: 'Deal Completed!',
          body:
              'Material Requisition has been completed. Deal for $productName$custSuffix is now complete.',
          type: 'step_unlocked',
          relatedPipelineId: widget.pipelineId,
        );
      } else {
        // Audit log for update
        await supabase.from('step_audit_log').insert({
          'pipeline_id': widget.pipelineId,
          'step_name': 'purchase_order',
          'action': 'updated',
          'performed_by': supabase.auth.currentUser!.id,
        });
      }

      ref.invalidate(pipelineDetailProvider(widget.pipelineId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Material Requisition completed! Deal completed.'),
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

  Future<void> _generateAndUploadPdf(String poId, {bool showPrintDialog = true}) async {
    final supabase = ref.read(supabaseClientProvider);

    // Fetch latest PO data
    final poData =
        await supabase.from('purchase_orders').select().eq('id', poId).single();
    final purchaseOrder = PurchaseOrder.fromJson(poData);

    // Fetch latest pipeline data with customer and product details
    final pipelineData = await supabase
        .from('sales_pipelines')
        .select('*, customers(*), products(*)')
        .eq('id', purchaseOrder.pipelineId)
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

    Map<String, dynamic> templateConfig;
    try {
      final templateData = await supabase
          .from('pdf_templates')
          .select()
          .eq('document_type', 'purchase_order')
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
    final pdfBytes = await PdfService.generatePurchaseOrderPdf(
      purchaseOrder: purchaseOrder,
      customer: customer,
      product: product,
      templateConfig: templateConfig,
    );

    // Write audit log
    await supabase.from('step_audit_log').insert({
      'pipeline_id': widget.pipelineId,
      'step_name': 'purchase_order',
      'action': 'pdf_generated',
      'performed_by': supabase.auth.currentUser!.id,
    });

    if (showPrintDialog && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PdfPreviewScreen(
            pdfBytes: pdfBytes,
            fileName: '${purchaseOrder.poNumber.replaceAll('/', '_')}.pdf',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body:
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final isPlaced = _existingPO?.status == PurchaseOrderStatus.ordered;
    final enabled = _isEditing;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isPlaced && !_isEditing
            ? 'Material Requisition (Completed)'
            : 'Material Requisition'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (isPlaced && !_isEditing) ...[
            TextButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: const Icon(Icons.edit, color: Colors.white, size: 16),
              label: const Text('Edit Details',
                  style: TextStyle(color: Colors.white, fontFamily: 'Inter')),
            ),
            IconButton(
              icon: const Icon(Icons.print, color: Colors.white),
              onPressed: () => _generateAndUploadPdf(_existingPO!.id),
            ),
          ],
          if (_isEditing && isPlaced)
            TextButton(
              onPressed: _isSaving ? null : _submitPO,
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
            // Header
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
                    _pipeline?.customer?.companyName ?? '',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(_pipeline?.product?.name ?? '',
                      style: const TextStyle(
                          fontFamily: 'Inter', color: AppColors.textSecondary)),
                  if (_existingPO != null)
                    Text(
                      _existingPO!.poNumber,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // PO Items
            const Text(
              'PO Items',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ..._poItems.asMap().entries.map(
                  (entry) => _PoItemRow(
                    index: entry.key,
                    item: entry.value,
                    onRemove: !enabled || _poItems.length <= 1
                        ? null
                        : () => _removePoItem(entry.key),
                    onChanged: () => setState(() {}),
                    enabled: enabled,
                  ),
                ),
            if (enabled)
              TextButton.icon(
                onPressed: _addPoItem,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Item'),
              ),
            const SizedBox(height: 12),

            // Total
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Quantity',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    '${_calcTotalQty().toInt()} NOS',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Notes
            const Text(
              'Material Requisition Notes',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _notesController,
              maxLines: 4,
              enabled: enabled,
              decoration: const InputDecoration(
                hintText:
                    'Delivery terms, payment terms, special instructions...',
              ),
            ),
            const SizedBox(height: 24),

            if (!isPlaced || _isEditing)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _submitPO,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.shopping_cart_checkout),
                  label: Text(_isSaving
                      ? 'Processing...'
                      : (isPlaced
                          ? 'Save Changes & Print'
                          : 'Complete Material Requisition & Complete Deal')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            if (isPlaced && !_isEditing)
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
                        '🎉 Material Requisition completed. This pipeline is complete!',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.success,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => _generateAndUploadPdf(_existingPO!.id),
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

class _PoItemRow extends StatelessWidget {
  final int index;
  final Map<String, dynamic> item;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;
  final bool enabled;

  const _PoItemRow({
    required this.index,
    required this.item,
    this.onRemove,
    required this.onChanged,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withOpacity(0.8)),
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
                  tooltip: 'Remove Item',
                ),
            ],
          ),
          const SizedBox(height: 8),
          InventoryAutocomplete(
            controller: item['description'] as TextEditingController,
            enabled: enabled,
            onChanged: onChanged,
            onItemSelected: (selection) {
              final unitController = item['unit'] as TextEditingController;
              if (unitController.text.isEmpty) unitController.text = selection.uom ?? '';
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: item['qty'] as TextEditingController,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(labelText: 'Qty *'),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    final val = int.tryParse(v);
                    if (val == null || val <= 0) {
                      return 'Must be > 0';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: item['unit'] as TextEditingController,
                  enabled: enabled,
                  decoration: const InputDecoration(labelText: 'Unit *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
