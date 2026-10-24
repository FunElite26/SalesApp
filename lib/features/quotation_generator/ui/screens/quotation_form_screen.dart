// lib/features/quotation_generator/ui/screens/quotation_form_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_theme.dart';
import '../../config/quote_template_config.dart';
import '../../config/quote_type.dart';
import '../../models/all_in_one_model.dart';
import '../../models/generator_company_settings.dart';
import '../../models/generator_quotation.dart';
import '../../models/heat_pump_model.dart';
import '../../models/pool_heat_pump_model.dart';
import '../../models/price_row.dart';
import '../../models/sales_person.dart';
import '../../models/tank_line_item.dart';
import '../../models/tank_spec.dart';
import '../../providers/quotation_generator_providers.dart';
import '../../services/price_calculator.dart';
import '../../services/quote_number_service.dart';
import '../../services/qg_item_parser.dart';
import '../../services/qg_model_specs_resolver.dart';
import '../../../../core/models/customer.dart';
import '../../../../core/providers/supabase_provider.dart';
import '../../models/deal_quotation_option.dart';
import '../widgets/customer_picker_dialog.dart';
import '../widgets/deal_quotation_picker_sheet.dart';
import '../widgets/live_summary_card.dart';
import '../widgets/price_row_editor.dart';
import '../widgets/tank_lines_editor.dart';
import 'quotation_preview_screen.dart';

class QuotationGeneratorFormScreen extends ConsumerStatefulWidget {
  final GeneratorQuotation? existingQuotation;
  final QuoteType? initialQuoteType;

  const QuotationGeneratorFormScreen({
    super.key,
    this.existingQuotation,
    this.initialQuoteType,
  });

  @override
  ConsumerState<QuotationGeneratorFormScreen> createState() =>
      _QuotationGeneratorFormScreenState();
}

class _QuotationGeneratorFormScreenState
    extends ConsumerState<QuotationGeneratorFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Active Quote Type
  late QuoteType _quoteType;

  // Customer
  String _salutation = 'M/s.';
  final _customerNameCtrl = TextEditingController();
  final _customerAddressCtrl = TextEditingController();
  final _customerMobileCtrl = TextEditingController();
  List<DealQuotationOption> _availableDeals = [];
  DealQuotationOption? _linkedDeal;
  bool _isFetchingDeals = false;

  // Quotation Meta
  DateTime _date = DateTime.now();
  final _quoteRefNoCtrl = TextEditingController();
  final _salesRefCtrl = TextEditingController(text: 'Insiya Sales');
  final _salesMobileCtrl = TextEditingController(text: '+91 9292922992');
  String? _selectedSalesPersonId;

  // Type-specific titles
  final _subjectOverrideCtrl = TextEditingController();
  final _proposalTitleCtrl = TextEditingController(text: 'Heat Pump Spare Parts & Accessories');
  final _purposeCtrl = TextEditingController(text: 'HOT WATER STORAGE');

  // Heat Pump selection
  HeatPumpModel? _selectedModel;
  int _hpQty = 1;

  // Pool Heat Pump selection
  PoolHeatPumpModel? _selectedPoolModel;

  // All-In-One selection
  AllInOneModel? _selectedAllInOneModel;

  // Multi-Tank lines
  List<TankLineItem> _tankLines = [];

  // Price Table Rows & Entry Mode
  List<PriceRow> _priceRows = [];
  String _priceEntryMode = 'exclusive'; // 'exclusive' | 'inclusive'
  int? _targetTotal;

  // Buyback
  bool _hasBuyback = false;
  final _buybackDescCtrl = TextEditingController(text: 'Old System Buyback');
  final _buybackRateCtrl = TextEditingController(text: '0');
  final _buybackQtyCtrl = TextEditingController(text: '1');

  // Commercial Terms
  final _advanceSplitCtrl = TextEditingController(text: '70');
  final _deliverySplitCtrl = TextEditingController(text: '20');
  final _commissioningSplitCtrl = TextEditingController(text: '10');
  final _hpWarrantyCtrl = TextEditingController(text: '2');
  final _tankWarrantyCtrl = TextEditingController(text: '5');
  final _validityDaysCtrl = TextEditingController(text: '7');
  List<String> _termsAndConditions = [];

  // Images & toggles
  String? _customCoverPath;
  String? _customBannerPath;
  List<String> _productImagePaths = [];
  bool _includeProductImagePage = true;
  bool _includeBanner = true;

  String _status = 'Draft';
  bool _initialized = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _quoteType = widget.existingQuotation?.quoteType ??
        widget.initialQuoteType ??
        QuoteType.hpWithTank;
  }

  @override
  void dispose() {
    _customerNameCtrl.dispose();
    _customerAddressCtrl.dispose();
    _customerMobileCtrl.dispose();
    _quoteRefNoCtrl.dispose();
    _salesRefCtrl.dispose();
    _salesMobileCtrl.dispose();
    _subjectOverrideCtrl.dispose();
    _proposalTitleCtrl.dispose();
    _purposeCtrl.dispose();
    _buybackDescCtrl.dispose();
    _buybackRateCtrl.dispose();
    _buybackQtyCtrl.dispose();
    _advanceSplitCtrl.dispose();
    _deliverySplitCtrl.dispose();
    _commissioningSplitCtrl.dispose();
    _hpWarrantyCtrl.dispose();
    _tankWarrantyCtrl.dispose();
    _validityDaysCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCustomerPicker() async {
    final selected = await CustomerPickerDialog.show(
      context,
      currentName: _customerNameCtrl.text,
    );

    if (selected != null) {
      setState(() {
        final name = selected.companyName.trim().isNotEmpty
            ? selected.companyName.trim()
            : (selected.contactPerson?.trim() ?? '');
        _customerNameCtrl.text = name;
        _customerAddressCtrl.text = selected.address?.trim() ?? '';
        _customerMobileCtrl.text = selected.phone?.trim() ?? '';
      });

      await _fetchDealsForCustomer(selected, showPickerIfMultiple: true);
    }
  }

  Future<void> _fetchDealsForCustomer(
    Customer customer, {
    bool showPickerIfMultiple = true,
  }) async {
    setState(() => _isFetchingDeals = true);
    final deals = <DealQuotationOption>[];

    try {
      final supabase = ref.read(supabaseClientProvider);

      // 1. Fetch from sales_pipelines where customer_id matches
      final pipelinesRes = await supabase.from('sales_pipelines').select('''
        id,
        customer_id,
        created_by,
        created_at,
        products (id, name),
        profiles!sales_pipelines_created_by_fkey (id, full_name, phone, email),
        quotations (*)
      ''').eq('customer_id', customer.id).order('created_at', ascending: false);

      for (final p in pipelinesRes) {
        final quotesRaw = p['quotations'];
        final List<Map<String, dynamic>> quotes = [];
        if (quotesRaw is List) {
          for (final item in quotesRaw) {
            if (item is Map) quotes.add(Map<String, dynamic>.from(item));
          }
        } else if (quotesRaw is Map) {
          quotes.add(Map<String, dynamic>.from(quotesRaw));
        }

        final productMap = p['products'] as Map<String, dynamic>?;
        final profileMap = p['profiles'] as Map<String, dynamic>?;
        final productName = productMap?['name']?.toString() ?? 'Heat Pump System';
        final productId = productMap?['id']?.toString();
        final pipelineId = p['id']?.toString();
        final profileName = profileMap?['full_name']?.toString();
        final profilePhone = profileMap?['phone']?.toString();

        for (final q in quotes) {
          final qNum = q['quotation_number']?.toString();
          if (qNum == null || qNum.trim().isEmpty) continue;

          deals.add(DealQuotationOption(
            quotationNumber: qNum,
            productName: productName,
            productId: productId,
            pipelineId: pipelineId,
            salesman: q['salesman']?.toString() ?? profileName ?? customer.salesmanName ?? customer.assignedToName,
            salesmanPhone: profilePhone,
            lineItems: (q['line_items'] as List?) ?? [],
            paymentTerms: (q['payment_terms'] as List?) ?? [],
            termsText: q['terms_text']?.toString(),
            grandTotal: (q['grand_total'] as num?)?.toDouble() ?? 0.0,
            createdAt: q['created_at'] != null ? DateTime.tryParse(q['created_at'].toString()) : null,
          ));
        }
      }

      // 2. Fallback check: quotations table directly by customer name or phone
      if (deals.isEmpty) {
        final cleanPhone = customer.phone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
        var query = supabase.from('quotations').select('''
          *,
          products (id, name)
        ''');
        if (customer.companyName.isNotEmpty && cleanPhone.isNotEmpty) {
          query = query.or('customer_name.eq.${customer.companyName},customer_phone.ilike.%$cleanPhone%');
        } else if (customer.companyName.isNotEmpty) {
          query = query.eq('customer_name', customer.companyName);
        } else if (cleanPhone.isNotEmpty) {
          query = query.ilike('customer_phone', '%$cleanPhone%');
        }

        final directQuotes = await query.order('created_at', ascending: false).limit(10);
        for (final q in directQuotes) {
          final qNum = q['quotation_number']?.toString();
          if (qNum == null || qNum.trim().isEmpty) continue;
          final productMap = q['products'] as Map<String, dynamic>?;
          deals.add(DealQuotationOption(
            quotationNumber: qNum,
            productName: productMap?['name']?.toString() ?? 'Heat Pump System',
            productId: productMap?['id']?.toString(),
            pipelineId: q['pipeline_id']?.toString(),
            salesman: q['salesman']?.toString() ?? customer.salesmanName ?? customer.assignedToName,
            salesmanPhone: null,
            lineItems: (q['line_items'] as List?) ?? [],
            paymentTerms: (q['payment_terms'] as List?) ?? [],
            termsText: q['terms_text']?.toString(),
            grandTotal: (q['grand_total'] as num?)?.toDouble() ?? 0.0,
            createdAt: q['created_at'] != null ? DateTime.tryParse(q['created_at'].toString()) : null,
          ));
        }
      }
    } catch (e) {
      debugPrint('Error fetching deals for customer: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingDeals = false;
          _availableDeals = deals;
        });
      }
    }

    if (!mounted) return;

    if (deals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auto-filled details for ${_customerNameCtrl.text}. (No deal quotations found in CRM)'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } else if (deals.length == 1) {
      _applyDealQuotation(deals.first);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Linked Deal [${deals.first.quotationNumber}] (${deals.first.productName})'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      if (showPickerIfMultiple) {
        final chosen = await DealQuotationPickerSheet.show(
          context,
          customerName: customer.companyName,
          deals: deals,
          currentQuotationNumber: _quoteRefNoCtrl.text,
        );
        if (chosen != null) {
          _applyDealQuotation(chosen);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✓ Linked Deal [${chosen.quotationNumber}] (${chosen.productName})'),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else if (_linkedDeal == null && deals.isNotEmpty) {
          _applyDealQuotation(deals.first);
        }
      }
    }
  }

  Future<void> _applyDealQuotation(DealQuotationOption deal) async {
    final settings = ref.read(quotationSettingsProvider).valueOrNull ?? const GeneratorCompanySettings();

    setState(() {
      _linkedDeal = deal;

      // 1. Quotation Number (Requirement 3: same as generated in deals)
      _quoteRefNoCtrl.text = deal.quotationNumber;

      // 2. Sales Representative (Requirement 2: auto fetch who created quotation in deals)
      final repName = deal.salesman?.trim() ?? '';
      if (repName.isNotEmpty) {
        _salesRefCtrl.text = repName;
        if (deal.salesmanPhone != null && deal.salesmanPhone!.isNotEmpty) {
          _salesMobileCtrl.text = deal.salesmanPhone!;
        }

        final match = settings.salesPersons.where(
          (s) => s.name.toLowerCase().trim() == repName.toLowerCase(),
        ).firstOrNull;
        if (match != null) {
          _selectedSalesPersonId = match.id;
          _salesMobileCtrl.text = match.mobile;
        } else {
          _selectedSalesPersonId = 'deal_rep_${repName.hashCode}';
        }
      }

      // 3. Price Table Items (Requirement 4: auto fetch items, qty, rate, etc.)
      if (deal.lineItems.isNotEmpty) {
        final List<PriceRow> newRows = [];
        int idx = 1;
        for (final raw in deal.lineItems) {
          if (raw is! Map) continue;
          final desc = raw['description']?.toString() ?? '';
          final qty = (raw['qty'] as num? ?? 1).toInt();
          final unitPrice = (raw['unit_price'] as num? ?? raw['item_rate'] as num? ?? 0).round();
          final hsn = raw['hsn_sac']?.toString();
          final gst = (raw['gst_percent'] as num? ?? raw['gst_rate'] as num? ?? 18).toDouble();
          final uom = raw['uom']?.toString() ?? 'NOS';

          newRows.add(PriceRow(
            id: const Uuid().v4(),
            serialNo: '$idx',
            description: desc,
            qty: qty > 0 ? qty : 1,
            rate: unitPrice,
            status: unitPrice > 0 ? PriceRowStatus.priced : PriceRowStatus.included,
            unitLabel: uom,
            metadata: {
              if (hsn != null) 'hsn_sac': hsn,
              'gst_percent': gst,
            },
          ));
          idx++;
        }
        if (newRows.isNotEmpty) {
          _priceRows = newRows;
        }

        // Match primary Heat Pump model for single model selection
        for (final row in newRows) {
          final parsed = QgItemParser.parseLineItem(row.description);
          if (parsed.type == ParsedItemType.allInOne || parsed.type == ParsedItemType.wallMounted) {
            _quoteType = parsed.type == ParsedItemType.wallMounted
                ? QuoteType.allInOneWall
                : QuoteType.allInOneFloor;
            final aioLitres = parsed.aioCapacityLitres ?? parsed.tankCapacityLitres;
            final resolved = QgModelSpecsResolver.resolve(
              modelName: parsed.modelId ?? parsed.hpModel,
              litres: aioLitres,
              settings: settings,
              heatPumpType: HeatPumpType.allInOne,
            );
            final match = settings.allInOneModels.cast<AllInOneModel?>().firstWhere(
              (m) =>
                  m != null &&
                  (m.id.toLowerCase() == resolved.modelId.toLowerCase() ||
                      m.modelName.toLowerCase() == resolved.modelName.toLowerCase()),
              orElse: () => null,
            );
            if (match != null) {
              _selectedAllInOneModel = match;
            } else {
              _selectedAllInOneModel = AllInOneModel(
                id: resolved.modelId.isNotEmpty ? resolved.modelId : resolved.modelName,
                modelName: resolved.modelName,
                mountType: parsed.type == ParsedItemType.wallMounted ? 'wall' : 'floor',
                tankVolumeLitres: resolved.litres ?? aioLitres ?? 200,
                description: 'Make: IZYHEAT All in one Heat pump\nModel: ${resolved.modelName}',
                specs: resolved.specs,
              );
            }
            _hpQty = row.qty;
            break;
          } else if (parsed.type == ParsedItemType.pool) {
            _quoteType = QuoteType.swimmingPool;
            final resolved = QgModelSpecsResolver.resolve(
              modelName: parsed.modelId ?? parsed.poolModel ?? parsed.hpModel,
              kw: (parsed.poolKw ?? parsed.hpKw)?.toDouble(),
              settings: settings,
              heatPumpType: HeatPumpType.swimmingPool,
            );
            final match = settings.poolModels.cast<PoolHeatPumpModel?>().firstWhere(
              (m) =>
                  m != null &&
                  (m.id.toLowerCase() == resolved.modelId.toLowerCase() ||
                      m.modelName.toLowerCase() == resolved.modelName.toLowerCase()),
              orElse: () => null,
            );
            if (match != null) {
              _selectedPoolModel = match;
            } else {
              _selectedPoolModel = PoolHeatPumpModel(
                id: resolved.modelId.isNotEmpty ? resolved.modelId : resolved.modelName,
                modelName: resolved.modelName,
                capacityKw: resolved.kw,
                description: 'Make: IZYHEAT Swimming Pool Heat Pump\nModel: ${resolved.modelName}',
                specs: resolved.specs,
              );
            }
            _hpQty = row.qty;
            break;
          } else if (parsed.type == ParsedItemType.heatPump) {
            final hasTank = newRows.any((r) {
              final p = QgItemParser.parseLineItem(r.description);
              return p.type == ParsedItemType.tank;
            });
            _quoteType = hasTank ? QuoteType.hpWithTank : QuoteType.hpOnly;

            final resolved = QgModelSpecsResolver.resolve(
              modelName: parsed.hpModel,
              kw: parsed.hpKw?.toDouble(),
              settings: settings,
              heatPumpType: HeatPumpType.domesticCommercial,
            );
            final match = settings.models.cast<HeatPumpModel?>().firstWhere(
              (m) =>
                  m != null &&
                  (m.id.toLowerCase() == resolved.modelId.toLowerCase() ||
                      m.modelName.toLowerCase() == resolved.modelName.toLowerCase()),
              orElse: () => null,
            );
            if (match != null) {
              _selectedModel = match;
            } else {
              _selectedModel = HeatPumpModel(
                id: resolved.modelId.isNotEmpty ? resolved.modelId : resolved.modelName,
                modelName: resolved.modelName,
                displayCapacityKw: resolved.kw,
                specs: resolved.specs,
              );
            }
            _hpQty = row.qty;
            break;
          }
        }
      }

      // 4. Payment Terms (Requirement 5: auto fetch payment terms)
      if (deal.paymentTerms.isNotEmpty) {
        num advancePct = 0;
        num dispatchPct = 0;
        num commissioningPct = 0;

        for (final t in deal.paymentTerms) {
          if (t is! Map) continue;
          final termName = (t['term']?.toString() ?? '').toLowerCase();
          final pct = (t['percent'] as num? ?? 0);
          if (termName.contains('adv')) {
            advancePct += pct;
          } else if (termName.contains('disp') || termName.contains('deliv')) {
            dispatchPct += pct;
          } else if (termName.contains('inst') || termName.contains('comp') || termName.contains('comm')) {
            commissioningPct += pct;
          }
        }

        if (advancePct > 0 || dispatchPct > 0 || commissioningPct > 0) {
          _advanceSplitCtrl.text = advancePct.round().toString();
          _deliverySplitCtrl.text = dispatchPct.round().toString();
          _commissioningSplitCtrl.text = commissioningPct.round().toString();
        }
      }

      // 5. Proposal Title override if product name is present
      if (deal.productName.isNotEmpty) {
        _proposalTitleCtrl.text = 'PROPOSAL FOR SUPPLY OF ${deal.productName.toUpperCase()}';
      }

      // 6. Additional Terms
      if (deal.termsText != null && deal.termsText!.trim().isNotEmpty) {
        final text = deal.termsText!.trim();
        if (!_termsAndConditions.contains(text)) {
          _termsAndConditions.insert(0, text);
        }
      }
    });

    // Lookup profile phone if still empty
    if (_salesMobileCtrl.text.isEmpty && deal.salesman != null && deal.salesman!.isNotEmpty) {
      try {
        final supabase = ref.read(supabaseClientProvider);
        final pRes = await supabase
            .from('profiles')
            .select('phone')
            .ilike('full_name', deal.salesman!.trim())
            .maybeSingle();
        if (pRes != null && pRes['phone'] != null && mounted) {
          setState(() {
            _salesMobileCtrl.text = pRes['phone'].toString();
          });
        }
      } catch (_) {}
    }
  }

  void _initForm(GeneratorCompanySettings settings) {
    if (_initialized) return;
    _initialized = true;

    final q = widget.existingQuotation;
    if (q != null) {
      _quoteType = q.quoteType;
      _salutation = q.salutation;
      _customerNameCtrl.text = q.customerName;
      _customerAddressCtrl.text = q.customerAddress;
      _customerMobileCtrl.text = q.customerMobile;
      _date = q.date;
      _quoteRefNoCtrl.text = q.quoteRefNo;
      _salesRefCtrl.text = q.salesRef;
      _salesMobileCtrl.text = q.salesMobile;
      _selectedSalesPersonId = q.salesPersonId;
      _subjectOverrideCtrl.text = q.subjectOverride ?? '';
      _proposalTitleCtrl.text = q.proposalTitle ?? '';
      _purposeCtrl.text = q.purpose ?? 'HOT WATER STORAGE';

      _selectedModel = settings.models.any((m) => m.id == q.model.id)
          ? settings.models.firstWhere((m) => m.id == q.model.id)
          : (settings.models.any((m) => m.modelName == q.model.modelName)
              ? settings.models.firstWhere((m) => m.modelName == q.model.modelName)
              : (settings.models.isNotEmpty ? settings.models.first : q.model));
      _hpQty = q.heatPumpQty;

      _selectedPoolModel = q.poolModel ?? (settings.poolModels.isNotEmpty ? settings.poolModels.first : null);
      _selectedAllInOneModel = q.allInOneModel ?? (settings.allInOneModels.isNotEmpty ? settings.allInOneModels.first : null);

      _tankLines = List.from(q.tankLines);
      _priceRows = List.from(q.priceRows);
      _priceEntryMode = q.priceEntryMode;
      _targetTotal = q.targetTotal;

      _hasBuyback = q.hasBuyback;
      _buybackDescCtrl.text = q.buybackDescription ?? 'Old System Buyback';
      _buybackRateCtrl.text = q.buybackRate.toString();
      _buybackQtyCtrl.text = q.buybackQty.toString();

      _advanceSplitCtrl.text = q.paymentSplitAdvance.toString();
      _deliverySplitCtrl.text = q.paymentSplitDelivery.toString();
      _commissioningSplitCtrl.text = q.paymentSplitCommissioning.toString();
      _hpWarrantyCtrl.text = q.warrantyHpYears.toString();
      _tankWarrantyCtrl.text = q.warrantyTankYears.toString();
      _validityDaysCtrl.text = q.validityDays.toString();
      _termsAndConditions = List.from(q.termsAndConditions);

      _customCoverPath = q.coverImagePath;
      _customBannerPath = q.bannerImagePath;
      _productImagePaths = List.from(q.productImagePaths);
      _includeProductImagePage = q.includeProductImagePage;
      _includeBanner = q.includeBanner;
      _status = q.status;
    } else {
      // New quotation: apply template defaults
      _applyTemplateDefaults(settings, _quoteType);
      final nextNum = settings.nextRunningNumber;
      _quoteRefNoCtrl.text = QuoteNumberService.formatQuoteRef(
        prefix: settings.quotePrefix,
        date: _date,
        runningNumber: nextNum,
      );

      // Default salesperson
      if (settings.salesPersons.isNotEmpty) {
        final sp = settings.salesPersons.first;
        _selectedSalesPersonId = sp.id;
        _salesRefCtrl.text = sp.name;
        _salesMobileCtrl.text = sp.mobile;
      }
    }
  }

  void _applyTemplateDefaults(GeneratorCompanySettings settings, QuoteType type) {
    final config = QuoteTemplateConfig.forType(type);

    if (settings.models.isNotEmpty) {
      _selectedModel = settings.models.first;
    }
    if (settings.poolModels.isNotEmpty) {
      _selectedPoolModel = settings.poolModels.first;
    }
    if (settings.allInOneModels.isNotEmpty) {
      _selectedAllInOneModel = type == QuoteType.allInOneWall
          ? settings.allInOneModels.firstWhere((m) => m.modelName.contains('100'), orElse: () => settings.allInOneModels.first)
          : settings.allInOneModels.firstWhere((m) => m.modelName.contains('200'), orElse: () => settings.allInOneModels.first);
    }

    _tankLines = [
      TankLineItem(
        id: 'tank_1',
        capacityLitres: 500,
        qty: 1,
        isPressurized: true,
        rate: 120000,
        innerTankMaterial: 'GI',
        innerTankThickness: '3mm',
        outerCladdingThickness: '3mm',
        insulationMaterial: 'PUF',
        insulationThickness: '50mm',
      )
    ];

    _priceRows = List.from(config.defaultRows);
    _advanceSplitCtrl.text = config.defaultPaymentPreset == PaymentPresetType.advance100 ? '100' : '70';
    _deliverySplitCtrl.text = config.defaultPaymentPreset == PaymentPresetType.advance100 ? '0' : '20';
    _commissioningSplitCtrl.text = config.defaultPaymentPreset == PaymentPresetType.advance100 ? '0' : '10';

    _hpWarrantyCtrl.text = '2';
    _tankWarrantyCtrl.text = '5';
    _validityDaysCtrl.text = settings.defaultValidityDays.toString();
    _termsAndConditions = List.from(config.defaultTerms);
  }

  PriceCalculationResult _calculateTotals() {
    final settings = ref.read(quotationSettingsProvider).valueOrNull ?? const GeneratorCompanySettings();
    final buybackRate = int.tryParse(_buybackRateCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final buybackQty = int.tryParse(_buybackQtyCtrl.text) ?? 1;

    return PriceCalculator.calculateFromRows(
      rows: _priceRows,
      gstPercent: settings.defaultGstPercent,
      hasBuyback: _hasBuyback,
      buybackRate: buybackRate,
      buybackQty: buybackQty,
      priceEntryMode: _priceEntryMode,
      targetTotal: _targetTotal,
    );
  }

  GeneratorQuotation _buildQuotationObject() {
    final totals = _calculateTotals();
    final settings = ref.read(quotationSettingsProvider).valueOrNull ?? const GeneratorCompanySettings();
    final id = widget.existingQuotation?.id ?? const Uuid().v4();
    final now = DateTime.now();

    final buybackRate = int.tryParse(_buybackRateCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final buybackQty = int.tryParse(_buybackQtyCtrl.text) ?? 1;

    final primaryTank = _tankLines.isNotEmpty ? _tankLines.first : null;

    return GeneratorQuotation(
      id: id,
      quoteType: _quoteType,
      salutation: _salutation,
      customerName: _customerNameCtrl.text.trim(),
      customerAddress: _customerAddressCtrl.text.trim(),
      customerMobile: _customerMobileCtrl.text.trim(),
      date: _date,
      quoteRefNo: _quoteRefNoCtrl.text.trim(),
      salesRef: _salesRefCtrl.text.trim(),
      salesMobile: _salesMobileCtrl.text.trim(),
      salesPersonId: _selectedSalesPersonId,
      subjectOverride: _subjectOverrideCtrl.text.trim().isNotEmpty ? _subjectOverrideCtrl.text.trim() : null,
      proposalTitle: _proposalTitleCtrl.text.trim().isNotEmpty ? _proposalTitleCtrl.text.trim() : null,
      purpose: _purposeCtrl.text.trim().isNotEmpty ? _purposeCtrl.text.trim() : null,
      model: _selectedModel ?? (settings.models.isNotEmpty ? settings.models.first : const HeatPumpModel(
        id: 'IZ-4C',
        modelName: 'IZ-4C',
        displayCapacityKw: 4.0,
        ratedHeatingCapacity: '3.6kw',
        descriptionLine: 'Air Source Heat pump 3.6kw',
        makeModelLine: 'Make: IZYHEAT Heat Pump Model: IZ-4C 3.6kw',
        powerInputText: 'Power Input 0.86kw, output 3.6kw, 220V - 1Phase, 50Hz With Auto Defrost.',
      )),
      heatPumpQty: _hpQty,
      poolModel: _selectedPoolModel,
      allInOneModel: _selectedAllInOneModel,
      tankCapacityLitres: primaryTank?.capacityLitres ?? 500,
      tankQty: primaryTank?.qty ?? 1,
      isTankPressurized: primaryTank?.isPressurized ?? true,
      tankRate: primaryTank?.rate ?? 0,
      tankSpec: primaryTank?.toTankSpec() ?? const TankSpec(),
      tankLines: _tankLines,
      priceRows: totals.adjustedRows.isNotEmpty ? totals.adjustedRows : _priceRows,
      extraPriceRows: const [],
      priceEntryMode: _priceEntryMode,
      targetTotal: _targetTotal,
      subtotal: totals.subtotal,
      gstPercent: totals.gstPercent,
      gstAmount: totals.gstAmount,
      grossTotal: totals.grossTotal,
      hasBuyback: _hasBuyback,
      buybackDescription: _buybackDescCtrl.text.trim(),
      buybackRate: buybackRate,
      buybackQty: buybackQty,
      buybackTotal: totals.buybackAmount,
      netPayable: totals.netPayable,
      grandTotal: totals.grandTotal,
      paymentSplitAdvance: int.tryParse(_advanceSplitCtrl.text) ?? 70,
      paymentSplitDelivery: int.tryParse(_deliverySplitCtrl.text) ?? 20,
      paymentSplitCommissioning: int.tryParse(_commissioningSplitCtrl.text) ?? 10,
      warrantyHpYears: int.tryParse(_hpWarrantyCtrl.text) ?? 2,
      warrantyTankYears: int.tryParse(_tankWarrantyCtrl.text) ?? 5,
      validityDays: int.tryParse(_validityDaysCtrl.text) ?? 7,
      termsAndConditions: _termsAndConditions,
      coverImagePath: _customCoverPath,
      bannerImagePath: _customBannerPath,
      productImagePaths: _productImagePaths,
      includeProductImagePage: _includeProductImagePage,
      includeBanner: _includeBanner,
      status: _status,
      createdAt: widget.existingQuotation?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> _saveDraft() async {
    if (_customerNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter customer name'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final quotation = _buildQuotationObject();
      await ref.read(quotationsHistoryProvider.notifier).saveQuotation(quotation);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Quotation saved over Supabase'), backgroundColor: AppColors.success),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving over Supabase: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _previewPdf() {
    if (_customerNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter customer name'), backgroundColor: AppColors.error),
      );
      return;
    }

    final quotation = _buildQuotationObject();
    final settings = ref.read(quotationSettingsProvider).valueOrNull ?? const GeneratorCompanySettings();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuotationPreviewScreen(
          quotation: quotation,
          settings: settings,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(quotationSettingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return settingsAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (settings) {
        _initForm(settings);
        final config = QuoteTemplateConfig.forType(_quoteType);
        final totals = _calculateTotals();

        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.existingQuotation != null ? 'Edit Quotation' : 'New Quotation',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.navBarColor,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: 'Preview PDF',
                onPressed: _previewPdf,
              ),
            ],
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
              children: [
                // ─── CUSTOMER INFORMATION ──────────────────────────────────
                _buildCard(
                  title: 'Customer Details',
                  icon: Icons.person_pin_outlined,
                  isDark: isDark,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 105,
                          child: DropdownButtonFormField<String>(
                            value: _salutation,
                            isDense: true,
                            decoration: InputDecoration(
                              labelText: 'Title',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'M/s.', child: Text('M/s.')),
                              DropdownMenuItem(value: 'Mr.', child: Text('Mr.')),
                              DropdownMenuItem(value: 'Ms.', child: Text('Ms.')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _salutation = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _customerNameCtrl,
                            readOnly: true,
                            onTap: _openCustomerPicker,
                            decoration: InputDecoration(
                              labelText: 'Customer Name *',
                              hintText: 'Tap to pick from customer list',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary),
                                onPressed: _openCustomerPicker,
                              ),
                            ),
                            validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _customerMobileCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Customer Mobile',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _customerAddressCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Installation Site Address',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.location_on_outlined, size: 18),
                      ),
                    ),

                    // Deal Quotation Link status / Switcher
                    if (_isFetchingDeals) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 4),
                      const Text(
                        'Searching CRM deals & quotations...',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ] else if (_linkedDeal != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.link, color: Colors.white, size: 16),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        _linkedDeal!.quotationNumber,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Linked Deal',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '${_linkedDeal!.productName} • ${_linkedDeal!.lineItemsSummary}',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (_availableDeals.length > 1)
                              TextButton(
                                onPressed: () async {
                                  final chosen = await DealQuotationPickerSheet.show(
                                    context,
                                    customerName: _customerNameCtrl.text,
                                    deals: _availableDeals,
                                    currentQuotationNumber: _quoteRefNoCtrl.text,
                                  );
                                  if (chosen != null) {
                                    _applyDealQuotation(chosen);
                                  }
                                },
                                child: const Text('Switch Deal', style: TextStyle(fontSize: 12)),
                              ),
                          ],
                        ),
                      ),
                    ] else if (_availableDeals.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.link, size: 16),
                        label: Text('Link Deal Quotation (${_availableDeals.length} available)'),
                        onPressed: () async {
                          final chosen = await DealQuotationPickerSheet.show(
                            context,
                            customerName: _customerNameCtrl.text,
                            deals: _availableDeals,
                            currentQuotationNumber: _quoteRefNoCtrl.text,
                          );
                          if (chosen != null) {
                            _applyDealQuotation(chosen);
                          }
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                // ─── 3. QUOTATION METADATA & SALESPERSON ────────────────────
                _buildCard(
                  title: 'Quotation Meta & Representative',
                  icon: Icons.badge_outlined,
                  isDark: isDark,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _quoteRefNoCtrl,
                            decoration: InputDecoration(
                              labelText: 'Quote Ref No *',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _date,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) setState(() => _date = picked);
                            },
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Date',
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                suffixIcon: const Icon(Icons.calendar_today, size: 16),
                              ),
                              child: Text(DateFormat('dd/MM/yyyy').format(_date)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Salesperson Selection
                    Builder(
                      builder: (context) {
                        final allSalesPersons = List<SalesPerson>.from(settings.salesPersons);
                        if (_salesRefCtrl.text.isNotEmpty &&
                            !allSalesPersons.any((s) => s.name.toLowerCase().trim() == _salesRefCtrl.text.toLowerCase().trim())) {
                          allSalesPersons.insert(
                            0,
                            SalesPerson(
                              id: _selectedSalesPersonId ?? 'deal_rep_${_salesRefCtrl.text.hashCode}',
                              name: _salesRefCtrl.text,
                              mobile: _salesMobileCtrl.text,
                            ),
                          );
                        }

                        if (allSalesPersons.isEmpty) return const SizedBox.shrink();

                        final currentId = allSalesPersons.any((s) => s.id == _selectedSalesPersonId)
                            ? _selectedSalesPersonId
                            : allSalesPersons.first.id;

                        return Column(
                          children: [
                            DropdownButtonFormField<String>(
                              value: currentId,
                              isDense: true,
                              decoration: InputDecoration(
                                labelText: 'Sales Representative',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                prefixIcon: const Icon(Icons.support_agent_outlined, size: 18),
                              ),
                              items: allSalesPersons.map((sp) {
                                return DropdownMenuItem(
                                  value: sp.id,
                                  child: Text('${sp.name}${sp.mobile.isNotEmpty ? " (${sp.mobile})" : ""}'),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  final sp = allSalesPersons.firstWhere((s) => s.id == val);
                                  setState(() {
                                    _selectedSalesPersonId = sp.id;
                                    _salesRefCtrl.text = sp.name;
                                    _salesMobileCtrl.text = sp.mobile;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _salesMobileCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: 'Representative Mobile',
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                prefixIcon: const Icon(Icons.phone_outlined, size: 18),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ─── 4. ADAPTIVE SYSTEM SELECTION ───────────────────────────
                if (config.requiredInputs.hasHpModel) ...[
                  _buildCard(
                    title: 'Heat Pump Model',
                    icon: Icons.ac_unit_outlined,
                    isDark: isDark,
                    children: [
                      DropdownButtonFormField<String>(
                        value: _selectedModel?.id ?? (settings.models.isNotEmpty ? settings.models.first.id : 'IZ-4C'),
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: 'Heat Pump Model',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: settings.models.map((m) {
                          return DropdownMenuItem(
                            value: m.id,
                            child: Text('${m.modelName} (${m.displayCapacityKw} kW - ${m.powerSupply})'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            final m = settings.models.firstWhere((e) => e.id == val);
                            setState(() => _selectedModel = m);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        initialValue: '$_hpQty',
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Heat Pump Machine Quantity',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (val) {
                          final q = int.tryParse(val) ?? 1;
                          setState(() => _hpQty = q);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                if (config.requiredInputs.hasPoolModel) ...[
                  _buildCard(
                    title: 'Swimming Pool Model',
                    icon: Icons.pool_outlined,
                    isDark: isDark,
                    children: [
                      DropdownButtonFormField<String>(
                        value: _selectedPoolModel?.id ?? (settings.poolModels.isNotEmpty ? settings.poolModels.first.id : 'IZ-35SP'),
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: 'Pool Heat Pump Model',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: (settings.poolModels.isNotEmpty ? settings.poolModels : [PoolHeatPumpModel.defaultModel()]).map((m) {
                          return DropdownMenuItem(value: m.id, child: Text('${m.modelName} (${m.capacityKw} kW Pool Heat Pump)'));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            final m = settings.poolModels.firstWhere((e) => e.id == val, orElse: () => PoolHeatPumpModel.defaultModel());
                            setState(() => _selectedPoolModel = m);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                if (config.requiredInputs.hasAllInOneModel) ...[
                  _buildCard(
                    title: 'All In One Unit Model',
                    icon: Icons.home_repair_service_outlined,
                    isDark: isDark,
                    children: [
                      DropdownButtonFormField<String>(
                        value: _selectedAllInOneModel?.id ?? (settings.allInOneModels.isNotEmpty ? settings.allInOneModels.first.id : 'IZ-200A'),
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: 'All In One Heat Pump Model',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: (settings.allInOneModels.isNotEmpty ? settings.allInOneModels : [AllInOneModel.defaultFloorModel(), AllInOneModel.defaultWallModel()]).map((m) {
                          return DropdownMenuItem(value: m.id, child: Text('${m.modelName} (${m.tankVolumeLtr}L ${m.isWallMounted ? "Wall" : "Floor"} Mount)'));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            final m = settings.allInOneModels.firstWhere((e) => e.id == val, orElse: () => AllInOneModel.defaultFloorModel());
                            setState(() => _selectedAllInOneModel = m);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                if (config.requiredInputs.hasProposalTitle) ...[
                  _buildCard(
                    title: 'Proposal Details',
                    icon: Icons.title_outlined,
                    isDark: isDark,
                    children: [
                      TextFormField(
                        controller: _proposalTitleCtrl,
                        decoration: InputDecoration(
                          labelText: 'Proposal Title (e.g. Return Line Pump & Spares)',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                if (config.requiredInputs.hasPurposeSelector) ...[
                  _buildCard(
                    title: 'Tank Purpose',
                    icon: Icons.water_drop_outlined,
                    isDark: isDark,
                    children: [
                      DropdownButtonFormField<String>(
                        value: ['HOT WATER STORAGE', 'SOLAR WATER HEATER TANK'].contains(_purposeCtrl.text.toUpperCase())
                            ? _purposeCtrl.text.toUpperCase()
                            : 'HOT WATER STORAGE',
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: 'Tank Purpose',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'HOT WATER STORAGE', child: Text('Hot Water Storage Tank')),
                          DropdownMenuItem(value: 'SOLAR WATER HEATER TANK', child: Text('Solar Water Heater Tank')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _purposeCtrl.text = val);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // ─── 5. TANK LINES (For hpWithTank & tankOnly) ───────────────
                if (config.requiredInputs.hasTankConfig) ...[
                  TankLinesEditor(
                    tankLines: _tankLines,
                    onLinesChanged: (lines) => setState(() => _tankLines = lines),
                  ),
                  const SizedBox(height: 16),
                ],

                // ─── 6. PRICE SCHEDULE & ENTRY MODE ─────────────────────────
                _buildCard(
                  title: 'Price Schedule & Commercials',
                  icon: Icons.table_chart_outlined,
                  isDark: isDark,
                  children: [
                    PriceRowEditor(
                      rows: _priceRows,
                      onRowsChanged: (rows) => setState(() => _priceRows = rows),
                      priceEntryMode: _priceEntryMode,
                      onPriceEntryModeChanged: (mode) => setState(() => _priceEntryMode = mode),
                      targetTotal: _targetTotal,
                      onTargetTotalChanged: (val) => setState(() => _targetTotal = val),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ─── 7. BUYBACK (Optional) ───────────────────────────────────
                if (config.requiredInputs.hasBuyback) ...[
                  _buildCard(
                    title: 'Old System Buyback Deduction',
                    icon: Icons.recycling_outlined,
                    isDark: isDark,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Include Old System Buyback', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: const Text('Deducts buyback amount from gross total to compute net payable', style: TextStyle(fontSize: 11)),
                        value: _hasBuyback,
                        onChanged: (val) => setState(() => _hasBuyback = val),
                      ),
                      if (_hasBuyback) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _buybackDescCtrl,
                          decoration: InputDecoration(
                            labelText: 'Buyback System Description',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _buybackQtyCtrl,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Qty',
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _buybackRateCtrl,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Buyback Amount (₹)',
                                  prefixText: '₹ ',
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // ─── 8. COMMERCIAL TERMS & WARRANTY ─────────────────────────
                _buildCard(
                  title: 'Terms & Warranty',
                  icon: Icons.gavel_outlined,
                  isDark: isDark,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _advanceSplitCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Advance %',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _deliverySplitCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Delivery %',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _commissioningSplitCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Comm. %',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _hpWarrantyCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'HP Warranty (Yrs)',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _tankWarrantyCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Tank Warranty (Yrs)',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _validityDaysCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Validity (Days)',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ─── 9. MEDIA ATTACHMENTS ───────────────────────────────────
                _buildCard(
                  title: 'Media & Branding Showcase',
                  icon: Icons.image_outlined,
                  isDark: isDark,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Include Product Showcase Page', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      value: _includeProductImagePage,
                      onChanged: (val) => setState(() => _includeProductImagePage = val),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Include Banner Graphic', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      value: _includeBanner,
                      onChanged: (val) => setState(() => _includeBanner = val),
                    ),
                  ],
                ),
              ],
            ),
          ),
          bottomSheet: LiveSummaryCard(
            subtotal: totals.subtotal,
            gstPercent: totals.gstPercent,
            gstAmount: totals.gstAmount,
            grandTotal: totals.grandTotal,
            hasBuyback: _hasBuyback,
            buybackAmount: totals.buybackAmount,
            netPayable: totals.netPayable,
            isSaving: _isSaving,
            onSaveDraft: _saveDraft,
            onPreview: _previewPdf,
          ),
        );
      },
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white12 : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const Divider(height: 18),
          ...children,
        ],
      ),
    );
  }
}
