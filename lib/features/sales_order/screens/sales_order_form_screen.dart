import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../core/models/customer.dart';
import '../../../core/models/product.dart';
import '../../../core/models/sales_order.dart';
import '../../../core/models/pipeline.dart';
import '../../../core/widgets/inventory_autocomplete.dart';
import '../../../core/models/quotation.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../pipelines/providers/pipelines_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/services/notification_backend_helper.dart';
import '../../../core/widgets/pdf_preview_screen.dart';

class SalesOrderFormScreen extends ConsumerStatefulWidget {
  final String pipelineId;

  const SalesOrderFormScreen({super.key, required this.pipelineId});

  @override
  ConsumerState<SalesOrderFormScreen> createState() =>
      _SalesOrderFormScreenState();
}

class _SalesOrderFormScreenState extends ConsumerState<SalesOrderFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Text controllers for shipping metadata
  final _shippingCompanyController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  final _distanceController = TextEditingController();
  final _grLrNoController = TextEditingController();
  final _destinationController = TextEditingController();
  final _placeOfSupplyController = TextEditingController(text: 'Maharashtra');
  final _paymentTermsController = TextEditingController();
  final _billingAddressController = TextEditingController();
  final _shippingAddressController = TextEditingController();
  final _remarksController = TextEditingController();

  final _ewayBillNoController = TextEditingController();
  final _ewayBillDateController = TextEditingController();
  final _expectedDispatchDateController = TextEditingController();
  final _salesmanController = TextEditingController();
  final _partyContactPersonController = TextEditingController();
  String _billType = 'Credit';

  // Line items
  final List<Map<String, dynamic>> _lineItems = [];

  // GST rates
  double _cgstRate = 9.0;
  double _sgstRate = 9.0;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  SalesOrder? _existingSalesOrder;
  SalesPipeline? _pipeline;
  Product? _product;
  Quotation? _quotation;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _shippingCompanyController.dispose();
    _vehicleNumberController.dispose();
    _distanceController.dispose();
    _grLrNoController.dispose();
    _destinationController.dispose();
    _placeOfSupplyController.dispose();
    _paymentTermsController.dispose();
    _billingAddressController.dispose();
    _shippingAddressController.dispose();
    _remarksController.dispose();
    _ewayBillNoController.dispose();
    _ewayBillDateController.dispose();
    _expectedDispatchDateController.dispose();
    _salesmanController.dispose();
    _partyContactPersonController.dispose();
    for (final item in _lineItems) {
      (item['description'] as TextEditingController).dispose();
      (item['hsn_sac'] as TextEditingController).dispose();
      (item['qty'] as TextEditingController).dispose();
      (item['gst_percent'] as TextEditingController?)?.dispose();
      (item['free_qty'] as TextEditingController?)?.dispose();
      (item['uom'] as TextEditingController).dispose();
      (item['rate'] as TextEditingController).dispose();
      (item['disc_percent'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final supabase = ref.read(supabaseClientProvider);

      // Load pipeline with customer and product
      final pipelineData = await supabase
          .from('sales_pipelines')
          .select('*, products(*), customers(*)')
          .eq('id', widget.pipelineId)
          .single();

      _pipeline = SalesPipeline.fromJson(pipelineData);
      _product = _pipeline?.product;

      // Load confirmed quotation to prefill items and addresses
      final quotationData = await supabase
          .from('quotations')
          .select()
          .eq('pipeline_id', widget.pipelineId)
          .eq('status', 'confirmed')
          .maybeSingle();

      if (quotationData != null) {
        _quotation = Quotation.fromJson(quotationData);
      }

      // Load existing sales order if it exists
      final soData = await supabase
          .from('sales_orders')
          .select()
          .eq('pipeline_id', widget.pipelineId)
          .maybeSingle();

      if (soData != null) {
        _existingSalesOrder = SalesOrder.fromJson(soData);
        _isEditing = !_existingSalesOrder!.isConfirmed;

        // Prefill shipping details
        _shippingCompanyController.text =
            _existingSalesOrder!.shippingCompany ?? '';
        _vehicleNumberController.text =
            _existingSalesOrder!.vehicleNumber ?? '';
        _distanceController.text = _existingSalesOrder!.distance ?? '';
        _grLrNoController.text = _existingSalesOrder!.grLrNo ?? '';
        _destinationController.text = _existingSalesOrder!.destination ?? '';
        _placeOfSupplyController.text =
            _existingSalesOrder!.placeOfSupply ?? 'Maharashtra';
        _paymentTermsController.text = _existingSalesOrder!.paymentTerms ?? '';
        _billingAddressController.text =
            _existingSalesOrder!.billingAddress ?? '';
        _shippingAddressController.text =
            _existingSalesOrder!.shippingAddress ?? '';
        _remarksController.text = _existingSalesOrder!.remarks ?? '';
        _ewayBillNoController.text = _existingSalesOrder!.ewayBillNo ?? '';
        _ewayBillDateController.text = _existingSalesOrder!.ewayBillDate ?? '';
        _expectedDispatchDateController.text =
            _existingSalesOrder!.expectedDispatchDate != null
                ? DateFormat('dd/MM/yyyy')
                    .format(_existingSalesOrder!.expectedDispatchDate!)
                : '';
        _salesmanController.text = _existingSalesOrder!.salesman ?? '';
        _partyContactPersonController.text =
            _existingSalesOrder!.partyContactPerson ?? '';
        _billType = _existingSalesOrder!.billType ?? 'Credit';

        // Prefill line items
        for (final item in _existingSalesOrder!.lineItems) {
          _lineItems.add({
            'description': TextEditingController(text: item.description),
            'hsn_sac': TextEditingController(text: item.hsnSac ?? ''),
            'qty': TextEditingController(text: item.qty.toInt().toString()),
            'gst_percent': TextEditingController(text: item.gstPercent.toString()),
            'free_qty': TextEditingController(text: '0'),
            'uom': TextEditingController(text: item.uom),
            'rate': TextEditingController(text: InventoryAutocomplete.formatIndianPrice(item.rate)),
            'disc_percent':
                TextEditingController(text: item.discPercent.toString()),
          });
        }
        _cgstRate = _existingSalesOrder!.cgstRate;
        _sgstRate = _existingSalesOrder!.sgstRate;
      } else {
        // First-time prefill from customer and quotation
        _isEditing = true;
        if (_pipeline?.customer != null) {
          _billingAddressController.text = _pipeline!.customer!.address ?? '';
          _shippingAddressController.text = _pipeline!.customer!.address ?? '';
          _partyContactPersonController.text =
              _pipeline!.customer!.contactPerson ?? '';
        }
        final profile = ref.read(currentProfileProvider);
        if (profile != null) {
          _salesmanController.text = profile.fullName;
        }
        _billType = 'Credit';
        if (_quotation != null) {
          _paymentTermsController.text = _quotation!.termsText ?? '';
          _remarksController.text = _quotation!.termsText ?? '';
          _cgstRate = _quotation!.cgstRate;
          _sgstRate = _quotation!.sgstRate;

          // Prefill line items from quotation
          for (final item in _quotation!.lineItems) {
            _lineItems.add({
              'description': TextEditingController(text: item.description),
              'hsn_sac':
                  TextEditingController(text: item.hsnSac ?? '85308000'), // Default HSN code
              'qty': TextEditingController(text: item.qty.toInt().toString()),
              'gst_percent': TextEditingController(text: item.gstPercent.toString()),
              'free_qty': TextEditingController(text: '0'),
              'uom': TextEditingController(text: item.uom),
              'rate': TextEditingController(
                  text: InventoryAutocomplete.formatIndianPrice(item.unitPrice)),
              'disc_percent': TextEditingController(text: item.discPercent.toString()),
            });
          }
        }
      }

      if (_lineItems.isEmpty) _addLineItem();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error loading data: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addLineItem() {
    setState(() {
      _lineItems.add({
        'description': TextEditingController(),
        'hsn_sac': TextEditingController(text: '85308000'),
        'qty': TextEditingController(text: '1'),
        'gst_percent': TextEditingController(text: '18.0'),
        'free_qty': TextEditingController(text: '0'),
        'uom': TextEditingController(text: 'NOS'),
        'rate': TextEditingController(text: '0.00'),
        'disc_percent': TextEditingController(text: '0.0'),
      });
    });
  }

  void _removeLineItem(int index) {
    setState(() {
      final item = _lineItems.removeAt(index);
      (item['description'] as TextEditingController).dispose();
      (item['hsn_sac'] as TextEditingController).dispose();
      (item['qty'] as TextEditingController).dispose();
      (item['gst_percent'] as TextEditingController?)?.dispose();
      (item['free_qty'] as TextEditingController?)?.dispose();
      (item['uom'] as TextEditingController).dispose();
      (item['rate'] as TextEditingController).dispose();
      (item['disc_percent'] as TextEditingController).dispose();
    });
  }

  double _calcSubtotal() {
    double total = 0;
    for (final item in _lineItems) {
      final qty =
          num.tryParse((item['qty'] as TextEditingController).text.replaceAll(',', '').trim())?.toInt() ?? 0;
      final rate =
          double.tryParse((item['rate'] as TextEditingController).text.replaceAll(',', '').trim()) ?? 0;
      final disc = double.tryParse(
              (item['disc_percent'] as TextEditingController).text.replaceAll(',', '').trim()) ??
          0;
      total += (qty * rate) * (1 - disc / 100);
    }
    return total;
  }

  bool get _isLocalGst {
    final state = _placeOfSupplyController.text.trim().toLowerCase();
    return state == 'maharashtra' || state == '27' || state == 'mh';
  }

  double get _cgstAmount => _isLocalGst ? _calcSubtotal() * (_cgstRate / 100) : 0.0;
  double get _sgstAmount => _isLocalGst ? _calcSubtotal() * (_sgstRate / 100) : 0.0;
  double get _igstAmount => !_isLocalGst ? _calcSubtotal() * ((_cgstRate + _sgstRate) / 100) : 0.0;
  double get _unroundedTotal =>
      _calcSubtotal() + _cgstAmount + _sgstAmount + _igstAmount;
  double get _grandTotal => _unroundedTotal.roundToDouble();
  double get _roundOffAmount => _grandTotal - _unroundedTotal;

  Future<void> _saveDraft() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await _upsertSalesOrder(confirmed: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Draft saved'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveConfirmedChanges() async {
    if (!_formKey.currentState!.validate()) return;

    final lineItemsValid = _lineItems.every((item) {
      final desc = (item['description'] as TextEditingController).text.trim();
      final qty =
          num.tryParse((item['qty'] as TextEditingController).text.replaceAll(',', '').trim())?.toInt() ?? 0;
      final rate =
          double.tryParse((item['rate'] as TextEditingController).text.replaceAll(',', '').trim()) ?? -1;
      return desc.isNotEmpty && qty > 0 && rate >= 0;
    });

    if (!lineItemsValid) {
      _showError(
          'All line items must have description, quantity > 0, and rate >= 0.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final soId = await _upsertSalesOrder(confirmed: true);
      final supabase = ref.read(supabaseClientProvider);

      // Audit log
      await supabase.from('step_audit_log').insert({
        'pipeline_id': widget.pipelineId,
        'step_name': 'sales_order',
        'action': 'updated',
        'performed_by': supabase.auth.currentUser!.id,
      });

      // Prompt to choose variant for layout print
      if (mounted) {
        await _showVariantPickerDialog(soId);
      }

      ref.invalidate(pipelineDetailProvider(widget.pipelineId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Sales Order changes saved successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        setState(() => _isEditing = false);
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmSalesOrder() async {
    if (!_formKey.currentState!.validate()) return;

    final lineItemsValid = _lineItems.every((item) {
      final desc = (item['description'] as TextEditingController).text.trim();
      final qty =
          num.tryParse((item['qty'] as TextEditingController).text.replaceAll(',', '').trim())?.toInt() ?? 0;
      final rate =
          double.tryParse((item['rate'] as TextEditingController).text.replaceAll(',', '').trim()) ?? -1;
      return desc.isNotEmpty && qty > 0 && rate >= 0;
    });

    if (!lineItemsValid) {
      _showError(
          'All line items must have description, quantity > 0, and rate >= 0.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Sales Order'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Once confirmed, this will generate the Sales Order PDF and unlock the BOQ step. Continue?',
              style: TextStyle(fontFamily: 'Inter', height: 1.5),
            ),
            const SizedBox(height: 16),
            _SummaryRow('Subtotal', _calcSubtotal()),
            if (_isLocalGst) ...[
              _SummaryRow('CGST (${_cgstRate.toStringAsFixed(_cgstRate == _cgstRate.roundToDouble() ? 0 : 2)}%)', _cgstAmount),
              _SummaryRow('SGST (${_sgstRate.toStringAsFixed(_sgstRate == _sgstRate.roundToDouble() ? 0 : 2)}%)', _sgstAmount),
            ] else ...[
              _SummaryRow('IGST (${(_cgstRate + _sgstRate).toStringAsFixed((_cgstRate + _sgstRate) == (_cgstRate + _sgstRate).roundToDouble() ? 0 : 2)}%)', _igstAmount),
            ],
            if (_roundOffAmount.abs() >= 0.005) ...[
              _SummaryRow(
                'Round Off',
                _roundOffAmount,
                customValue:
                    'Rs. ${_roundOffAmount > 0 ? '+' : ''}${_roundOffAmount.toStringAsFixed(2)}',
              ),
            ],
            const Divider(),
            _SummaryRow('Grand Total', _grandTotal, bold: true),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm & Print'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      final soId = await _upsertSalesOrder(confirmed: true);
      final supabase = ref.read(supabaseClientProvider);

      // Advance pipeline to BOQ
      await supabase
          .from('sales_pipelines')
          .update({'current_step': 'boq'}).eq('id', widget.pipelineId);

      // Audit log
      await supabase.from('step_audit_log').insert({
        'pipeline_id': widget.pipelineId,
        'step_name': 'sales_order',
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
        title: 'BOQ Stage Unlocked',
        body: 'Sales Order confirmed$custSuffix. BOQ step is now available.',
        type: 'step_unlocked',
        relatedPipelineId: widget.pipelineId,
      );

      // Prompt to choose variant for layout print
      if (mounted) {
        await _showVariantPickerDialog(soId);
      }

      ref.invalidate(pipelineDetailProvider(widget.pipelineId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Sales Order confirmed! BOQ step unlocked.'),
            backgroundColor: AppColors.success,
          ),
        );
        context.go(AppRoutes.pipelineDetail.replaceAll(':id', widget.pipelineId));
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showVariantPickerDialog(String soId) async {
    final variant = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select PDF Variant'),
        content: const Text(
          'Choose the variant of Sales Order you want to print / preview:',
          style: TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'commercial'),
              child: const Text('Commercial (Main)')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'technical'),
              child: const Text('Technical (BOQ)')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'production'),
              child: const Text('Production (Factory)')),
        ],
      ),
    );

    if (variant != null && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      );
      try {
        final result = await _generatePdfBytes(soId, variant);
        if (mounted) Navigator.pop(context); // pop loading dialog
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PdfPreviewScreen(
                pdfBytes: result.bytes,
                fileName: result.fileName,
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) Navigator.pop(context);
        _showError('Failed to print PDF: $e');
      }
    }
  }

  Future<({Uint8List bytes, String fileName})> _generatePdfBytes(String soId, String variant) async {
    final supabase = ref.read(supabaseClientProvider);
    final soData =
        await supabase.from('sales_orders').select().eq('id', soId).single();
    final so = SalesOrder.fromJson(soData);

    // Fetch latest pipeline data with customer and product details
    final pipelineData = await supabase
        .from('sales_pipelines')
        .select('*, customers(*), products(*)')
        .eq('id', so.pipelineId)
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
          .eq('document_type', 'sales_order')
          .single();
      templateConfig =
          (templateData)['template_config'] as Map<String, dynamic>;
    } catch (_) {
      templateConfig = {
        'company_name': 'INSIYA TRADING CORPORATION',
        'company_address':
            'Office No 807, 8th Floor, Finswell Building, Behind Hyatt Hotel, Viman Nagar, Pune, Maharashtra 411014',
        'company_phone': '+91 92929 22992',
        'company_email': 'insiyasolarindustry@gmail.com',
        'company_gst': '27CFTPS5292A1ZY',
        'footer_text':
            'We declare that this invoice shows the actual price of the goods described.',
      };
    }

    final bytes = await PdfService.generateSalesOrderPdf(
      salesOrder: so,
      customer: customer,
      product: product,
      variant: variant,
      templateConfig: templateConfig,
    );

    final String cleanOrderNum = so.salesOrderNumber.replaceAll('/', '_');
    final String fileName = variant == 'production' ? '${cleanOrderNum}_Production.pdf' : '$cleanOrderNum.pdf';
    return (bytes: bytes, fileName: fileName);
  }

  Future<String> _upsertSalesOrder({required bool confirmed}) async {
    final supabase = ref.read(supabaseClientProvider);

    final lineItemsJson = _lineItems.map((item) {
      final qty =
          num.tryParse((item['qty'] as TextEditingController).text.replaceAll(',', '').trim())?.toInt() ?? 0;
      final rate =
          double.tryParse((item['rate'] as TextEditingController).text.replaceAll(',', '').trim()) ?? 0;
      final gstPercent = double.tryParse(
              (item['gst_percent'] as TextEditingController?)?.text.replaceAll(',', '').trim() ?? '18') ??
          18.0;
      final freeQty =
          num.tryParse((item['free_qty'] as TextEditingController?)?.text.replaceAll(',', '').trim() ?? '0')?.toInt() ??
              0;
      final disc = double.tryParse(
              (item['disc_percent'] as TextEditingController).text.replaceAll(',', '').trim()) ??
          0;
      return {
        'description':
            (item['description'] as TextEditingController).text.trim(),
        'hsn_sac': (item['hsn_sac'] as TextEditingController).text.trim(),
        'qty': qty,
        'free_qty': freeQty,
        'gst_percent': gstPercent,
        'uom': (item['uom'] as TextEditingController).text.trim().toUpperCase(),
        'rate': rate,
        'disc_percent': disc,
        'amount': (qty * rate) * (1 - disc / 100),
      };
    }).toList();

    final subtotal = _calcSubtotal();
    final data = {
      'pipeline_id': widget.pipelineId,
      'shipping_company': _shippingCompanyController.text.trim().isEmpty
          ? null
          : _shippingCompanyController.text.trim(),
      'vehicle_number': _vehicleNumberController.text.trim().isEmpty
          ? null
          : _vehicleNumberController.text.trim(),
      'distance': _distanceController.text.trim().isEmpty
          ? null
          : _distanceController.text.trim(),
      'gr_lr_no': _grLrNoController.text.trim().isEmpty
          ? null
          : _grLrNoController.text.trim(),
      'destination': _destinationController.text.trim().isEmpty
          ? null
          : _destinationController.text.trim(),
      'place_of_supply': _placeOfSupplyController.text.trim().isEmpty
          ? 'Maharashtra'
          : _placeOfSupplyController.text.trim(),
      'payment_terms': _paymentTermsController.text.trim().isEmpty
          ? null
          : _paymentTermsController.text.trim(),
      'billing_address': _billingAddressController.text.trim().isEmpty
          ? null
          : _billingAddressController.text.trim(),
      'shipping_address': _shippingAddressController.text.trim().isEmpty
          ? null
          : _shippingAddressController.text.trim(),
      'expected_dispatch_date': _expectedDispatchDateController.text.trim().isEmpty
          ? null
          : () {
              try {
                return DateFormat('dd/MM/yyyy')
                    .parseStrict(_expectedDispatchDateController.text.trim())
                    .toIso8601String();
              } catch (_) {
                return null;
              }
            }(),
      'eway_bill_no': _ewayBillNoController.text.trim().isEmpty
          ? null
          : _ewayBillNoController.text.trim(),
      'eway_bill_date': _ewayBillDateController.text.trim().isEmpty
          ? null
          : _ewayBillDateController.text.trim(),
      'bill_type': _billType,
      'salesman': _salesmanController.text.trim().isEmpty
          ? null
          : _salesmanController.text.trim(),
      'party_contact_person': _partyContactPersonController.text.trim().isEmpty
          ? null
          : _partyContactPersonController.text.trim(),
      'line_items': lineItemsJson,
      'subtotal': subtotal,
      'cgst_rate': _cgstRate,
      'sgst_rate': _sgstRate,
      'cgst_amount': _cgstAmount,
      'sgst_amount': _sgstAmount,
      'igst_amount': _igstAmount,
      'grand_total': _grandTotal,
      'remarks': _remarksController.text.trim().isEmpty
          ? null
          : _remarksController.text.trim(),
      'status': confirmed ? 'confirmed' : 'draft',
    };

    if (_existingSalesOrder != null) {
      try {
        await supabase
            .from('sales_orders')
            .update(data)
            .eq('id', _existingSalesOrder!.id);
      } catch (err) {
        final errStr = err.toString();
        if (errStr.contains('expected_dispatch_date')) {
          final fallbackData = Map<String, dynamic>.from(data)..remove('expected_dispatch_date');
          await supabase
              .from('sales_orders')
              .update(fallbackData)
              .eq('id', _existingSalesOrder!.id);
        } else {
          rethrow;
        }
      }
      return _existingSalesOrder!.id;
    } else {
      try {
        final response = await supabase
            .from('sales_orders')
            .insert(data)
            .select('id')
            .single();
        return (response as Map)['id'] as String;
      } catch (err) {
        final errStr = err.toString();
        if (errStr.contains('expected_dispatch_date')) {
          final fallbackData = Map<String, dynamic>.from(data)..remove('expected_dispatch_date');
          final response = await supabase
              .from('sales_orders')
              .insert(fallbackData)
              .select('id')
              .single();
          return (response as Map)['id'] as String;
        } else {
          rethrow;
        }
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body:
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final isConfirmed = _existingSalesOrder?.isConfirmed == true;
    final enabled = _isEditing;
    final currencyFormat = NumberFormat('#,##,##0.00', 'en_IN');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(!enabled ? 'Sales Order (Confirmed)' : 'Sales Order Form'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (isConfirmed && !enabled)
            TextButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: const Icon(Icons.edit, color: Colors.white, size: 16),
              label: const Text('Edit Details',
                  style: TextStyle(color: Colors.white, fontFamily: 'Inter')),
            ),
          if (enabled)
            TextButton(
              onPressed: _isSaving
                  ? null
                  : (isConfirmed ? _saveConfirmedChanges : _saveDraft),
              child: Text(isConfirmed ? 'Save Changes' : 'Save Draft',
                  style: const TextStyle(
                      color: Colors.white, fontFamily: 'Inter')),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.pagePadding,
          children: [
            // Details Banner
            if (isConfirmed && !enabled)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
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
                        'This Sales Order is confirmed. Tap "Edit Details" in the top bar to modify.',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: AppColors.success,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () =>
                          _showVariantPickerDialog(_existingSalesOrder!.id),
                      child: const Text('Print PDF'),
                    ),
                  ],
                ),
              ),

            // Metadata card
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
                          color: AppColors.primary),
                    ),
                    if (_pipeline!.customer!.phone != null && _pipeline!.customer!.phone!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Row(
                          children: [
                            const Icon(Icons.phone_outlined, size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 8),
                            Text(
                              _pipeline!.customer!.phone!,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(_product?.name ?? '',
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.textSecondary)),
                    if (_existingSalesOrder != null)
                      Text(
                        'Order No: ${_existingSalesOrder!.salesOrderNumber}',
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

            // Shipping Metadata Section
            _SectionHeader('Shipping Metadata'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _shippingCompanyController,
                    enabled: enabled,
                    decoration:
                        const InputDecoration(labelText: 'Shipping Company'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _vehicleNumberController,
                    enabled: enabled,
                    decoration:
                        const InputDecoration(labelText: 'Vehicle Number'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _distanceController,
                    enabled: enabled,
                    decoration: const InputDecoration(
                        labelText: 'Distance (e.g. 120km)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _grLrNoController,
                    enabled: enabled,
                    decoration:
                        const InputDecoration(labelText: 'GR/LR Number'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _destinationController,
                    enabled: enabled,
                    decoration: const InputDecoration(labelText: 'Destination'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _placeOfSupplyController,
                    enabled: enabled,
                    decoration: const InputDecoration(
                        labelText: 'Place of Supply (State)'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _ewayBillNoController,
                    enabled: enabled,
                    decoration:
                        const InputDecoration(labelText: 'Eway Bill No'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: !enabled
                        ? null
                        : () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) {
                              _ewayBillDateController.text =
                                  DateFormat('dd/MM/yyyy').format(date);
                            }
                          },
                    child: IgnorePointer(
                      child: TextFormField(
                        controller: _ewayBillDateController,
                        enabled: enabled,
                        decoration: const InputDecoration(
                          labelText: 'Eway Bill Date',
                          suffixIcon: Icon(Icons.calendar_today, size: 18),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: !enabled
                        ? null
                        : () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (date != null) {
                              _expectedDispatchDateController.text =
                                  DateFormat('dd/MM/yyyy').format(date);
                            }
                          },
                    child: IgnorePointer(
                      child: TextFormField(
                        controller: _expectedDispatchDateController,
                        enabled: enabled,
                        decoration: const InputDecoration(
                          labelText: 'Expected Dispatch Date',
                          suffixIcon: Icon(Icons.event_available, size: 18),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _billType,
                    decoration: const InputDecoration(labelText: 'Bill Type'),
                    items: const [
                      DropdownMenuItem(value: 'Credit', child: Text('Credit')),
                      DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                    ],
                    onChanged: !enabled
                        ? null
                        : (v) {
                            if (v != null) {
                              setState(() => _billType = v);
                            }
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _salesmanController,
                    enabled: enabled,
                    decoration: const InputDecoration(labelText: 'Salesman'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _partyContactPersonController,
                    enabled: enabled,
                    decoration:
                        const InputDecoration(labelText: 'Party Contact Person'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Addresses
            _SectionHeader('Addresses'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _billingAddressController,
              enabled: enabled,
              maxLines: 2,
              decoration:
                  const InputDecoration(labelText: 'Customer Billing Address'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _shippingAddressController,
              enabled: enabled,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Shipping Address'),
            ),
            const SizedBox(height: 20),

            // Payment terms
            TextFormField(
              controller: _paymentTermsController,
              enabled: enabled,
              decoration: const InputDecoration(labelText: 'Payment Terms'),
            ),
            const SizedBox(height: 20),

            // Item grid
            _SectionHeader('Line Items'),
            const SizedBox(height: 12),
            ..._lineItems.asMap().entries.map(
                  (entry) => _SalesOrderLineItemRow(
                    index: entry.key,
                    item: entry.value,
                    onRemove: !enabled || _lineItems.length <= 1
                        ? null
                        : () => _removeLineItem(entry.key),
                    onChanged: () => setState(() {}),
                    enabled: enabled,
                  ),
                ),
            if (enabled)
              TextButton.icon(
                onPressed: _addLineItem,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Line Item'),
              ),
            const SizedBox(height: 20),

            // Totals block
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  _TotalRow(
                      'Subtotal', '₹${currencyFormat.format(_calcSubtotal())}'),
                  const SizedBox(height: 10),
                  if (enabled) ...[
                    Row(
                      children: [
                        const Text(
                          'GST Rate:',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<double>(
                            initialValue: [0.0, 5.0, 12.0, 18.0, 28.0].contains(_cgstRate + _sgstRate)
                                ? (_cgstRate + _sgstRate)
                                : null,
                            isDense: true,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              hintText: 'Select GST %',
                            ),
                            items: [
                              const DropdownMenuItem(value: 18.0, child: Text('18% (Standard 9% + 9%)', overflow: TextOverflow.ellipsis)),
                              const DropdownMenuItem(value: 12.0, child: Text('12% (6% + 6%)', overflow: TextOverflow.ellipsis)),
                              const DropdownMenuItem(value: 5.0, child: Text('5% (2.5% + 2.5%)', overflow: TextOverflow.ellipsis)),
                              const DropdownMenuItem(value: 28.0, child: Text('28% (14% + 14%)', overflow: TextOverflow.ellipsis)),
                              const DropdownMenuItem(value: 0.0, child: Text('0% (Exempted)', overflow: TextOverflow.ellipsis)),
                              if (![0.0, 5.0, 12.0, 18.0, 28.0].contains(_cgstRate + _sgstRate))
                                DropdownMenuItem(
                                  value: _cgstRate + _sgstRate,
                                  child: Text('${(_cgstRate + _sgstRate).toStringAsFixed((_cgstRate + _sgstRate) == (_cgstRate + _sgstRate).roundToDouble() ? 0 : 2)}% (Custom)', overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _cgstRate = val / 2;
                                  _sgstRate = val / 2;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Custom GST %',
                          icon: const Icon(Icons.edit_note, size: 22, color: AppColors.primary),
                          onPressed: () async {
                            final totalGst = _cgstRate + _sgstRate;
                            final customVal = await showDialog<double>(
                              context: context,
                              builder: (ctx) {
                                final controller = TextEditingController(
                                  text: totalGst.toStringAsFixed(totalGst == totalGst.roundToDouble() ? 0 : 2),
                                );
                                return AlertDialog(
                                  title: const Text('Custom GST Rate (%)'),
                                  content: TextField(
                                    controller: controller,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(
                                      labelText: 'Enter Total GST %',
                                      suffixText: '%',
                                    ),
                                    autofocus: true,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        final parsed = double.tryParse(controller.text.trim());
                                        if (parsed != null && parsed >= 0) {
                                          Navigator.pop(ctx, parsed);
                                        }
                                      },
                                      child: const Text('Apply'),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (customVal != null) {
                              setState(() {
                                _cgstRate = customVal / 2;
                                _sgstRate = customVal / 2;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_isLocalGst) ...[
                    _TotalRow(
                        'CGST (${_cgstRate.toStringAsFixed(_cgstRate == _cgstRate.roundToDouble() ? 0 : 2)}%)', '₹${currencyFormat.format(_cgstAmount)}'),
                    const SizedBox(height: 4),
                    _TotalRow(
                        'SGST (${_sgstRate.toStringAsFixed(_sgstRate == _sgstRate.roundToDouble() ? 0 : 2)}%)', '₹${currencyFormat.format(_sgstAmount)}'),
                  ] else ...[
                    _TotalRow(
                        'IGST (${(_cgstRate + _sgstRate).toStringAsFixed((_cgstRate + _sgstRate) == (_cgstRate + _sgstRate).roundToDouble() ? 0 : 2)}%)', '₹${currencyFormat.format(_igstAmount)}'),
                  ],
                  if (_roundOffAmount.abs() >= 0.005) ...[
                    const SizedBox(height: 4),
                    _TotalRow(
                      'Round Off',
                      'Rs. ${_roundOffAmount > 0 ? '+' : ''}${_roundOffAmount.toStringAsFixed(2)}',
                    ),
                  ],
                  const Divider(height: 16),
                  _TotalRow(
                      'Grand Total', '₹${currencyFormat.format(_grandTotal)}',
                      bold: true),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Remarks
            _SectionHeader('Milestone Remarks'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _remarksController,
              enabled: enabled,
              maxLines: 2,
              decoration: const InputDecoration(
                  hintText: 'e.g. Advance: 80% Other: 20% after dispatch'),
            ),
            const SizedBox(height: 24),

            if (enabled)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : (isConfirmed
                          ? _saveConfirmedChanges
                          : _confirmSalesOrder),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_isSaving
                      ? 'Processing...'
                      : (isConfirmed
                          ? 'Save Changes & Print'
                          : 'Confirm Sales Order & Print')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _TotalRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: AppColors.textPrimary)),
        Text(value,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: bold ? 15 : 13,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
                color: AppColors.primary)),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double amount;
  final bool bold;
  final String? customValue;
  const _SummaryRow(this.label, this.amount, {this.bold = false, this.customValue});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: bold ? FontWeight.bold : null)),
        Text(
          customValue ?? 'Rs. ${NumberFormat('#,##,##0.00', 'en_IN').format(amount)}',
          style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : null),
        ),
      ],
    );
  }
}

class _SalesOrderLineItemRow extends StatelessWidget {
  final int index;
  final Map<String, dynamic> item;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;
  final bool enabled;

  const _SalesOrderLineItemRow({
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
              final hsnController = item['hsn_sac'] as TextEditingController;
              final uomController = item['uom'] as TextEditingController;
              final rateController = item['rate'] as TextEditingController;
              
              if (hsnController.text.isEmpty) hsnController.text = selection.hsnSac ?? '';
              if (uomController.text.isEmpty) uomController.text = selection.uom ?? '';
              if (rateController.text.isEmpty || rateController.text == '0.00' || rateController.text == '0') {
                rateController.text = InventoryAutocomplete.formatIndianPrice(selection.price);
              }
              onChanged();
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: item['hsn_sac'] as TextEditingController,
                  enabled: enabled,
                  decoration: const InputDecoration(labelText: 'HSN/SAC'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: item['uom'] as TextEditingController,
                  enabled: enabled,
                  decoration: const InputDecoration(labelText: 'UOM'),
                ),
              ),
            ],
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
                    if (val == null || val <= 0) return '> 0';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: item['gst_percent'] as TextEditingController?,
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(
                    labelText: 'GST % *',
                    suffixText: '%',
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    final n = double.tryParse(v.replaceAll(',', '').trim());
                    if (n == null || n < 0 || n > 100) return 'Invalid';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) {
                      final val = double.tryParse((item['rate'] as TextEditingController).text.replaceAll(',', '').trim());
                      if (val != null) {
                        (item['rate'] as TextEditingController).text = InventoryAutocomplete.formatIndianPrice(val);
                      }
                    }
                  },
                  child: TextFormField(
                    controller: item['rate'] as TextEditingController,
                    enabled: enabled,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(labelText: 'Rate (₹) *'),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      final clean = v.replaceAll(',', '').trim();
                      if ((double.tryParse(clean) ?? -1) < 0) return 'Invalid';
                      return null;
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: item['disc_percent'] as TextEditingController,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(labelText: 'Disc %'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
