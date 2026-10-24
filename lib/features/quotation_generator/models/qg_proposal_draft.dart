import 'package:flutter/foundation.dart';
import 'deal_quotation_item.dart';
import 'generator_quotation.dart';
import 'heat_pump_model.dart';
import 'price_row.dart';
import 'price_item.dart';
import 'tank_line_item.dart';
import 'heat_pump_line_item.dart';
import 'tank_spec.dart';
import 'generator_company_settings.dart';
import 'all_in_one_model.dart';
import 'pool_heat_pump_model.dart';
import '../config/quote_type.dart';
import '../services/qg_item_parser.dart';
import '../services/price_calculator.dart';
import '../services/qg_payment_sentence_builder.dart';
import '../services/qg_model_specs_resolver.dart';

/// Represents the in-memory and locally persisted draft of a Heat Pump Proposal.
/// Encapsulates all salesperson edits, item resolutions, specifications,
/// and image overrides prior to approval and finalization.
class QgProposalDraft {
  final String quotationId;
  final String quotationNumber;
  final String status;
  final int revision;
  final DateTime quotationUpdatedAt;
  
  // Customer
  String customerSalutation;
  String customerName;
  String customerAddress;
  String customerPhone;
  String? customerGst;

  // Salesperson
  String salesmanSalutation;
  String salesmanName;
  String salesmanPhone;
  
  // Date & Reference
  String quoteDate; // dd/MM/yyyy
  String refNumberMode; // 'deal_number' or 'legacy'
  String refNumber;

  // Parsed Items
  List<ParsedItemResult> items;

  // Supplementary Items
  List<Map<String, dynamic>> supplementaryItems;

  // Payment Terms
  List<Map<String, dynamic>> paymentTerms;
  String paymentTermsText;

  // Totals
  double subtotal;
  double supplementarySubtotal;
  double cgstRate;
  double sgstRate;
  double igstRate;
  double cgstAmount;
  double sgstAmount;
  double igstAmount;
  double grandTotal;
  String? reconciliationWarning;

  // Technical Specifications
  String specCategoryId; // hp_4_8, hp_9_24, hp_38_100, all_in_one, wall_mounted, pool, other
  String hpModel; // IZ-{kW}C
  int hpKw;
  Map<String, String> hpSpecs; // 13-row specs table
  String? specsCopiedFrom; // Warning note if fallback used

  // Tank details
  bool hasTank;
  String tankMaterial; // 'GI', 'MS', 'Enamel', 'SS'
  String tankInsulation; // 'Puff', 'Rockwool', 'Custom'
  String tankInsulationCustomText;
  int tankCapacityLitres;
  int tankQty;
  bool isTankPressurized;
  double tankRate;
  Map<String, String> tankSpecs;

  // Terms & Warranties
  int warrantyHpYears;
  int warrantyTankYears;
  int validityDays;
  String tcItem4Status; // 'Included' or 'Extra'

  // Image overrides (local file paths or asset paths)
  String? coverImagePath;
  String? stampImagePath;
  String? bannerImagePath;
  String? productImagePath;

  DateTime draftUpdatedAt;

  QgProposalDraft({
    required this.quotationId,
    required this.quotationNumber,
    required this.status,
    required this.revision,
    required this.quotationUpdatedAt,
    this.customerSalutation = 'M/s.',
    required this.customerName,
    required this.customerAddress,
    required this.customerPhone,
    this.customerGst,
    this.salesmanSalutation = 'Mr.',
    required this.salesmanName,
    required this.salesmanPhone,
    required this.quoteDate,
    this.refNumberMode = 'deal_number',
    required this.refNumber,
    required this.items,
    required this.supplementaryItems,
    required this.paymentTerms,
    required this.paymentTermsText,
    required this.subtotal,
    required this.supplementarySubtotal,
    required this.cgstRate,
    required this.sgstRate,
    required this.igstRate,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.igstAmount,
    required this.grandTotal,
    this.reconciliationWarning,
    required this.specCategoryId,
    required this.hpModel,
    required this.hpKw,
    required this.hpSpecs,
    this.specsCopiedFrom,
    this.hasTank = false,
    this.tankMaterial = 'GI',
    this.tankInsulation = 'Puff',
    this.tankInsulationCustomText = '',
    this.tankCapacityLitres = 500,
    this.tankQty = 1,
    this.isTankPressurized = true,
    this.tankRate = 0.0,
    required this.tankSpecs,
    this.warrantyHpYears = 2,
    this.warrantyTankYears = 5,
    this.validityDays = 7,
    this.tcItem4Status = 'Included',
    this.coverImagePath,
    this.stampImagePath,
    this.bannerImagePath,
    this.productImagePath,
    DateTime? draftUpdatedAt,
  }) : draftUpdatedAt = draftUpdatedAt ?? DateTime.now();

  bool get isConfirmed => status.trim().toLowerCase() == 'confirmed';

  /// Reconciles printed totals with source grand total
  double get calculatedSubTotal => subtotal + supplementarySubtotal;
  double get calculatedTotalGst => cgstAmount + sgstAmount + igstAmount;
  double get calculatedGrandTotal => calculatedSubTotal + calculatedTotalGst;

  bool get hasReconciliationMismatch {
    return (calculatedGrandTotal - grandTotal).abs() > 1.0;
  }

  /// Initial factory from read-only DealQuotationItem
  factory QgProposalDraft.fromDealQuotation(
    DealQuotationItem q, {
    GeneratorCompanySettings? settings,
    Map<String, String>? initialHpSpecs,
    String? initialSpecCategory,
    String? initialSpecsCopiedFrom,
  }) {
    // 1. Parse line items
    final parsedItems = q.lineItems.map<ParsedItemResult>((raw) {
      final desc = raw['description']?.toString() ?? '';
      final qty = (raw['qty'] as num?)?.toInt() ?? 1;
      final rate = (raw['unit_price'] as num?)?.toDouble() ?? 0.0;
      final amt = (raw['total'] as num?)?.toDouble() ?? 0.0;
      final modelId = raw['model_id']?.toString() ?? raw['modelId']?.toString();
      return QgItemParser.parseLineItem(desc, qty: qty, rate: rate, amount: amt, modelId: modelId);
    }).toList();

    // 2. Classify items and identify primary Heat Pump line by type
    ParsedItemResult? primaryAioItem;
    ParsedItemResult? primaryPoolItem;
    ParsedItemResult? primaryHpItem;
    int? highestHpKw;
    String? derivedHpModel;
    String? derivedHpModelId;

    for (final it in parsedItems) {
      if (it.type == ParsedItemType.allInOne || it.type == ParsedItemType.wallMounted) {
        primaryAioItem ??= it;
      } else if (it.type == ParsedItemType.pool) {
        primaryPoolItem ??= it;
      } else if (it.type == ParsedItemType.heatPump) {
        if (it.hpKw != null && (highestHpKw == null || it.hpKw! > highestHpKw)) {
          highestHpKw = it.hpKw!;
          derivedHpModel = it.hpModel ?? 'IZ-${it.hpKw}C';
          derivedHpModelId = it.modelId;
          primaryHpItem = it;
        } else if (primaryHpItem == null) {
          primaryHpItem = it;
        }
      }
    }

    String catId;
    String effectiveHpModel;
    int effectiveHpKw;
    ResolvedModelSpecs resolvedSpecsResult;

    if (primaryAioItem != null) {
      final isWall = primaryAioItem.type == ParsedItemType.wallMounted;
      catId = isWall ? 'wall_mounted' : 'all_in_one';
      final capLitres = primaryAioItem.aioCapacityLitres ?? (isWall ? 100 : 200);
      effectiveHpModel = primaryAioItem.hpModel ?? (isWall ? 'IZ-${capLitres}WM' : 'IZ-${capLitres}A');
      effectiveHpKw = 0;

      resolvedSpecsResult = QgModelSpecsResolver.resolve(
        modelId: primaryAioItem.modelId,
        modelName: effectiveHpModel,
        litres: capLitres,
        isWallMounted: isWall,
        heatPumpType: HeatPumpType.allInOne,
        settings: settings,
        rawDescription: primaryAioItem.rawDescription,
      );
    } else if (primaryPoolItem != null) {
      catId = 'pool';
      final poolKw = primaryPoolItem.poolKw ?? 35;
      effectiveHpModel = primaryPoolItem.poolModel ?? 'IZ-${poolKw}SP';
      effectiveHpKw = poolKw;

      resolvedSpecsResult = QgModelSpecsResolver.resolve(
        modelId: primaryPoolItem.modelId,
        modelName: effectiveHpModel,
        kw: poolKw.toDouble(),
        heatPumpType: HeatPumpType.swimmingPool,
        settings: settings,
        rawDescription: primaryPoolItem.rawDescription,
      );
    } else {
      // Domestic / Commercial Air Source Heat Pump
      effectiveHpKw = highestHpKw ?? 4;
      effectiveHpModel = derivedHpModel ?? 'IZ-${effectiveHpKw}C';

      if (effectiveHpKw <= 8) {
        catId = 'hp_4_8';
      } else if (effectiveHpKw <= 24) {
        catId = 'hp_9_24';
      } else if (effectiveHpKw <= 100) {
        catId = 'hp_38_100';
      } else {
        catId = 'other';
      }

      resolvedSpecsResult = QgModelSpecsResolver.resolve(
        modelId: derivedHpModelId,
        modelName: effectiveHpModel,
        kw: effectiveHpKw.toDouble(),
        heatPumpType: HeatPumpType.domesticCommercial,
        settings: settings,
        rawDescription: primaryHpItem?.rawDescription,
      );
    }

    // 4. Identify Tank line (not applicable for All-In-One which has internal tank)
    bool hasTankLine = false;
    int tankLitres = 500;
    int tankQty = 1;
    String tankMat = 'GI';
    bool isPressurized = true;
    double tankRate = 0.0;

    if (primaryAioItem == null) {
      for (final it in parsedItems) {
        if (it.type == ParsedItemType.tank) {
          hasTankLine = true;
          tankLitres = it.tankCapacityLitres ?? 500;
          tankQty = it.qty;
          tankMat = it.tankMaterial ?? 'GI';
          isPressurized = it.isPressurized;
          tankRate = it.rate;
          break;
        }
      }
    }

    // 5. HP specs from centralized resolver
    final defaultSpecs = initialHpSpecs ?? resolvedSpecsResult.specs;
    final specsCopiedSource = initialSpecsCopiedFrom ?? resolvedSpecsResult.specsCopiedFrom;

    // 6. Tank specifications
    final defaultTankSpecs = _buildDefaultTankSpecs(
      material: tankMat,
      litres: tankLitres,
      isPressurized: isPressurized,
    );

    // 7. Payment terms text
    String pTermsText = q.termsText ?? '';
    if (pTermsText.isEmpty && q.paymentTerms.isNotEmpty) {
      pTermsText = QgPaymentSentenceBuilder.buildSentence(
        paymentTerms: q.paymentTerms,
        isAnnexureQuirk: true,
      );
    }

    // 8. Date format
    final d = q.orderDate;
    final dateStr = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    // 9. Reconciliation check
    String? reconWarn;
    final calcTotal = (q.subtotal + q.supplementarySubtotal) + (q.cgstAmount + q.sgstAmount + q.igstAmount);
    if ((calcTotal - q.grandTotal).abs() > 1.0) {
      reconWarn = 'Note: Deal grand total (₹${q.grandTotal.toStringAsFixed(2)}) differs from calculated sum (₹${calcTotal.toStringAsFixed(2)}).';
    }

    return QgProposalDraft(
      quotationId: q.id,
      quotationNumber: q.quotationNumber,
      status: q.status,
      revision: q.revision,
      quotationUpdatedAt: q.updatedAt,
      customerSalutation: 'M/s.',
      customerName: q.customerName,
      customerAddress: q.customerAddress,
      customerPhone: q.customerPhone,
      customerGst: q.customerGst,
      salesmanSalutation: 'Mr.',
      salesmanName: q.salesmanName,
      salesmanPhone: q.salesmanPhone,
      quoteDate: dateStr,
      refNumberMode: 'deal_number',
      refNumber: q.quotationNumber,
      items: parsedItems,
      supplementaryItems: q.supplementaryTerms.map((st) {
        final qVal = (st['qty'] as num?)?.toInt();
        return {
          'name': (st['name'] ?? st['term'] ?? st['item_name'] ?? '').toString(),
          'type': (st['type'] ?? st['status'] ?? 'Included').toString(),
          'qty': (qVal != null && qVal > 0) ? qVal : 1,
          'rate': (st['rate'] as num?)?.toDouble() ?? 0.0,
          'amount': (st['amount'] as num?)?.toDouble() ?? 0.0,
        };
      }).toList(),
      paymentTerms: List<Map<String, dynamic>>.from(q.paymentTerms),
      paymentTermsText: pTermsText,
      subtotal: q.subtotal,
      supplementarySubtotal: q.supplementarySubtotal,
      cgstRate: q.cgstRate,
      sgstRate: q.sgstRate,
      igstRate: q.igstRate,
      cgstAmount: q.cgstAmount,
      sgstAmount: q.sgstAmount,
      igstAmount: q.igstAmount,
      grandTotal: q.grandTotal,
      reconciliationWarning: reconWarn,
      specCategoryId: initialSpecCategory ?? catId,
      hpModel: resolvedSpecsResult.modelName.isNotEmpty ? resolvedSpecsResult.modelName : effectiveHpModel,
      hpKw: effectiveHpKw,
      hpSpecs: defaultSpecs,
      specsCopiedFrom: specsCopiedSource,
      hasTank: hasTankLine,
      tankMaterial: tankMat,
      tankInsulation: 'Puff',
      tankInsulationCustomText: '',
      tankCapacityLitres: tankLitres,
      tankQty: tankQty,
      isTankPressurized: isPressurized,
      tankRate: tankRate,
      tankSpecs: defaultTankSpecs,
      warrantyHpYears: 2,
      warrantyTankYears: tankMat == 'Enamel' ? 15 : 5,
      validityDays: 7,
      tcItem4Status: 'Included',
    );
  }


  static Map<String, String> _buildDefaultTankSpecs({
    required String material,
    required int litres,
    required bool isPressurized,
  }) {
    String shellThick = '3mm';
    String dishThick = '3mm';
    if (material == 'Enamel') {
      shellThick = '2mm';
      dishThick = '2mm';
    } else if (material == 'MS') {
      shellThick = '5mm';
      dishThick = '6mm';
    }

    return {
      'Capacity and Thickness': '$litres ltr, $shellThick Shell, $dishThick Dish.',
      'Operating pressure': isPressurized ? 'Up to 5 Bar' : 'Atmospheric',
      'Testing Pressure': isPressurized ? '7 bar pressure' : 'Atmospheric',
      'Hot Water Inlet/ outlet': '2 Inch,',
      'Heat Pump Circulation': '1 Inch,',
      'Outer Tank Insulation': 'PUF',
      'Temperature drop': '3° C / 8 hour',
      'Inner and outer Tank': material,
      'Tank direction': 'Horizontal / Vertical',
      'Other': 'Solar Provision Additional Heat Pump Provision',
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'quotationId': quotationId,
      'quotationNumber': quotationNumber,
      'status': status,
      'revision': revision,
      'quotationUpdatedAt': quotationUpdatedAt.toIso8601String(),
      'customerSalutation': customerSalutation,
      'customerName': customerName,
      'customerAddress': customerAddress,
      'customerPhone': customerPhone,
      'customerGst': customerGst,
      'salesmanSalutation': salesmanSalutation,
      'salesmanName': salesmanName,
      'salesmanPhone': salesmanPhone,
      'quoteDate': quoteDate,
      'refNumberMode': refNumberMode,
      'refNumber': refNumber,
      'items': items.map((e) => e.toJson()).toList(),
      'supplementaryItems': supplementaryItems,
      'paymentTerms': paymentTerms,
      'paymentTermsText': paymentTermsText,
      'subtotal': subtotal,
      'supplementarySubtotal': supplementarySubtotal,
      'cgstRate': cgstRate,
      'sgstRate': sgstRate,
      'igstRate': igstRate,
      'cgstAmount': cgstAmount,
      'sgstAmount': sgstAmount,
      'igstAmount': igstAmount,
      'grandTotal': grandTotal,
      'reconciliationWarning': reconciliationWarning,
      'specCategoryId': specCategoryId,
      'hpModel': hpModel,
      'hpKw': hpKw,
      'hpSpecs': hpSpecs,
      'specsCopiedFrom': specsCopiedFrom,
      'hasTank': hasTank,
      'tankMaterial': tankMaterial,
      'tankInsulation': tankInsulation,
      'tankInsulationCustomText': tankInsulationCustomText,
      'tankCapacityLitres': tankCapacityLitres,
      'tankQty': tankQty,
      'isTankPressurized': isTankPressurized,
      'tankRate': tankRate,
      'tankSpecs': tankSpecs,
      'warrantyHpYears': warrantyHpYears,
      'warrantyTankYears': warrantyTankYears,
      'validityDays': validityDays,
      'tcItem4Status': tcItem4Status,
      'coverImagePath': coverImagePath,
      'stampImagePath': stampImagePath,
      'bannerImagePath': bannerImagePath,
      'productImagePath': productImagePath,
      'draftUpdatedAt': draftUpdatedAt.toIso8601String(),
    };
  }

  factory QgProposalDraft.fromJson(Map<String, dynamic> map) {
    final rawItems = map['items'] as List<dynamic>? ?? [];
    return QgProposalDraft(
      quotationId: map['quotationId'] as String? ?? '',
      quotationNumber: map['quotationNumber'] as String? ?? '',
      status: map['status'] as String? ?? 'draft',
      revision: (map['revision'] as num?)?.toInt() ?? 1,
      quotationUpdatedAt: DateTime.tryParse(map['quotationUpdatedAt']?.toString() ?? '') ?? DateTime.now(),
      customerSalutation: map['customerSalutation'] as String? ?? 'M/s.',
      customerName: map['customerName'] as String? ?? '',
      customerAddress: map['customerAddress'] as String? ?? '',
      customerPhone: map['customerPhone'] as String? ?? '',
      customerGst: map['customerGst'] as String?,
      salesmanSalutation: map['salesmanSalutation'] as String? ?? 'Mr.',
      salesmanName: map['salesmanName'] as String? ?? '',
      salesmanPhone: map['salesmanPhone'] as String? ?? '',
      quoteDate: map['quoteDate'] as String? ?? '',
      refNumberMode: map['refNumberMode'] as String? ?? 'deal_number',
      refNumber: map['refNumber'] as String? ?? '',
      items: rawItems.map((e) => ParsedItemResult.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      supplementaryItems: (map['supplementaryItems'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      paymentTerms: (map['paymentTerms'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      paymentTermsText: map['paymentTermsText'] as String? ?? '',
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
      supplementarySubtotal: (map['supplementarySubtotal'] as num?)?.toDouble() ?? 0.0,
      cgstRate: (map['cgstRate'] as num?)?.toDouble() ?? 9.0,
      sgstRate: (map['sgstRate'] as num?)?.toDouble() ?? 9.0,
      igstRate: (map['igstRate'] as num?)?.toDouble() ?? 0.0,
      cgstAmount: (map['cgstAmount'] as num?)?.toDouble() ?? 0.0,
      sgstAmount: (map['sgstAmount'] as num?)?.toDouble() ?? 0.0,
      igstAmount: (map['igstAmount'] as num?)?.toDouble() ?? 0.0,
      grandTotal: (map['grandTotal'] as num?)?.toDouble() ?? 0.0,
      reconciliationWarning: map['reconciliationWarning'] as String?,
      specCategoryId: map['specCategoryId'] as String? ?? 'hp_4_8',
      hpModel: map['hpModel'] as String? ?? 'IZ-8C',
      hpKw: (map['hpKw'] as num?)?.toInt() ?? 8,
      hpSpecs: (map['hpSpecs'] as Map? ?? {}).map((k, v) => MapEntry(k.toString(), v.toString())),
      specsCopiedFrom: map['specsCopiedFrom'] as String?,
      hasTank: map['hasTank'] as bool? ?? false,
      tankMaterial: map['tankMaterial'] as String? ?? 'GI',
      tankInsulation: map['tankInsulation'] as String? ?? 'Puff',
      tankInsulationCustomText: map['tankInsulationCustomText'] as String? ?? '',
      tankCapacityLitres: (map['tankCapacityLitres'] as num?)?.toInt() ?? 500,
      tankQty: (map['tankQty'] as num?)?.toInt() ?? 1,
      isTankPressurized: map['isTankPressurized'] as bool? ?? true,
      tankRate: (map['tankRate'] as num?)?.toDouble() ?? 0.0,
      tankSpecs: (map['tankSpecs'] as Map? ?? {}).map((k, v) => MapEntry(k.toString(), v.toString())),
      warrantyHpYears: (map['warrantyHpYears'] as num?)?.toInt() ?? 2,
      warrantyTankYears: (map['warrantyTankYears'] as num?)?.toInt() ?? 5,
      validityDays: (map['validityDays'] as num?)?.toInt() ?? 7,
      tcItem4Status: map['tcItem4Status'] as String? ?? 'Included',
      coverImagePath: map['coverImagePath'] as String?,
      stampImagePath: map['stampImagePath'] as String?,
      bannerImagePath: map['bannerImagePath'] as String?,
      productImagePath: map['productImagePath'] as String?,
      draftUpdatedAt: DateTime.tryParse(map['draftUpdatedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  /// Converts this draft to a GeneratorQuotation instance for rendering with PdfQuotationBuilder
  GeneratorQuotation toGeneratorQuotation({GeneratorCompanySettings? settings}) {
    final bool isAllInOne = specCategoryId == 'all_in_one' ||
        items.any((it) => it.type == ParsedItemType.allInOne);
    final bool isWallMounted = specCategoryId == 'wall_mounted' ||
        items.any((it) => it.type == ParsedItemType.wallMounted);
    final bool isPool = specCategoryId == 'pool' ||
        items.any((it) => it.type == ParsedItemType.pool);

    QuoteType resolvedQuoteType;
    if (isAllInOne) {
      resolvedQuoteType = QuoteType.allInOneFloor;
    } else if (isWallMounted) {
      resolvedQuoteType = QuoteType.allInOneWall;
    } else if (isPool) {
      resolvedQuoteType = QuoteType.swimmingPool;
    } else if (hasTank) {
      resolvedQuoteType = QuoteType.hpWithTank;
    } else {
      resolvedQuoteType = QuoteType.hpOnly;
    }

    AllInOneModel? resolvedAioModel;
    PoolHeatPumpModel? resolvedPoolModel;
    HeatPumpModel heatPumpModel;
    final hpLineItems = <HeatPumpLineItem>[];

    int hpRateVal = 0;
    int hpQtyVal = 1;
    for (final it in items) {
      if (it.type == ParsedItemType.heatPump || it.type == ParsedItemType.allInOne || it.type == ParsedItemType.pool) {
        hpRateVal = it.rate.round();
        hpQtyVal = it.qty;
        break;
      }
    }
    if (hpRateVal == 0 && !hasTank) {
      hpRateVal = subtotal.round();
    }

    if (isAllInOne || isWallMounted) {
      final aioItem = items.firstWhere(
        (it) => it.type == ParsedItemType.allInOne || it.type == ParsedItemType.wallMounted,
        orElse: () => items.isNotEmpty ? items.first : ParsedItemResult(rawDescription: 'All in one 200Ltr', type: ParsedItemType.allInOne, status: ItemResolveStatus.resolved, aioCapacityLitres: 200),
      );
      final cap = aioItem.aioCapacityLitres ?? 200;

      final aioRes = QgModelSpecsResolver.resolve(
        modelId: aioItem.modelId,
        modelName: aioItem.hpModel ?? hpModel,
        litres: cap,
        isWallMounted: isWallMounted,
        heatPumpType: HeatPumpType.allInOne,
        settings: settings,
        rawDescription: aioItem.rawDescription,
      );

      final effectiveAioSpecs = (hpSpecs.isNotEmpty && (specCategoryId == 'all_in_one' || specCategoryId == 'wall_mounted'))
          ? Map<String, String>.from(hpSpecs)
          : aioRes.specs;

      resolvedAioModel = aioRes.matchedAioModel?.copyWith(specs: effectiveAioSpecs) ?? AllInOneModel(
        id: aioRes.modelId,
        modelName: aioRes.modelName,
        mountType: isWallMounted ? 'wall' : 'floor',
        tankVolumeLitres: aioRes.litres ?? cap,
        description: 'Make: IZYHEAT All in one Heat pump\nModel: ${aioRes.modelName}\nCapacity: ${aioRes.litres ?? cap} Ltr',
        specs: effectiveAioSpecs,
      );

      heatPumpModel = HeatPumpModel(
        id: resolvedAioModel.id,
        modelName: resolvedAioModel.modelName,
        displayCapacityKw: 0,
        specs: effectiveAioSpecs,
      );
    } else if (isPool) {
      final poolRes = QgModelSpecsResolver.resolve(
        modelName: hpModel,
        kw: hpKw.toDouble(),
        heatPumpType: HeatPumpType.swimmingPool,
        settings: settings,
      );

      final effectivePoolSpecs = hpSpecs.isNotEmpty ? Map<String, String>.from(hpSpecs) : poolRes.specs;
      resolvedPoolModel = poolRes.matchedPoolModel?.copyWith(specs: effectivePoolSpecs) ?? PoolHeatPumpModel.defaultModel().copyWith(
        modelName: poolRes.modelName,
        capacityKw: poolRes.kw,
        specs: effectivePoolSpecs,
      );

      heatPumpModel = HeatPumpModel(
        id: resolvedPoolModel.id,
        modelName: resolvedPoolModel.modelName,
        displayCapacityKw: resolvedPoolModel.capacityKw,
        specs: effectivePoolSpecs,
      );
    } else {
      // Domestic / Commercial Air Source Heat Pump
      final singleResolved = QgModelSpecsResolver.resolve(
        modelName: hpModel,
        kw: hpKw.toDouble(),
        heatPumpType: HeatPumpType.domesticCommercial,
        settings: settings,
      );

      final effectiveSpecs = hpSpecs.isNotEmpty ? Map<String, String>.from(hpSpecs) : singleResolved.specs;

      heatPumpModel = HeatPumpModel(
        id: singleResolved.matchedModel?.id ?? singleResolved.modelName,
        modelName: singleResolved.modelName,
        displayCapacityKw: singleResolved.kw,
        ratedHeatingCapacity: '${singleResolved.kw.toInt() == singleResolved.kw ? singleResolved.kw.toInt() : singleResolved.kw}kw',
        descriptionLine: 'Air Source Heat pump ${singleResolved.kw.toInt() == singleResolved.kw ? singleResolved.kw.toInt() : singleResolved.kw}kw',
        makeModelLine: 'Make: IZYHEAT Heat Pump Model: ${singleResolved.modelName} ${singleResolved.kw.toInt() == singleResolved.kw ? singleResolved.kw.toInt() : singleResolved.kw}kw',
        powerInputText: effectiveSpecs['Power Supply'] ?? '',
        defaultImagePath: singleResolved.matchedModel?.defaultImagePath ?? 'assets/images/model_iz_4c.png',
        specs: effectiveSpecs,
      );

      int hpItemIdx = 1;
      for (int i = 0; i < items.length; i++) {
        final it = items[i];
        if (it.type == ParsedItemType.heatPump) {
          final kwVal = it.hpKw?.toDouble() ?? hpKw.toDouble();
          final model = it.hpModel ?? hpModel;

          final itemResolved = QgModelSpecsResolver.resolve(
            modelId: it.modelId,
            modelName: model,
            kw: kwVal,
            heatPumpType: HeatPumpType.domesticCommercial,
            settings: settings,
            rawDescription: it.rawDescription,
          );

          hpLineItems.add(HeatPumpLineItem(
            id: it.modelId ?? 'hp_${hpItemIdx++}',
            modelName: itemResolved.modelName,
            kw: itemResolved.kw,
            qty: it.qty,
            rate: it.rate.round(),
            amount: it.amount.round(),
            description: it.rawDescription,
            specs: itemResolved.specs,
            model: itemResolved.matchedModel,
          ));
        }
      }

      if (hpLineItems.isEmpty) {
        hpLineItems.add(HeatPumpLineItem(
          id: 'hp_1',
          modelName: hpModel,
          kw: hpKw.toDouble(),
          qty: hpQtyVal,
          rate: hpRateVal,
          amount: hpRateVal * hpQtyVal,
          specs: effectiveSpecs,
        ));
      }
    }

    // Multi Tank Lines
    final tankLinesList = <TankLineItem>[];
    int tankIdx = 1;
    if (!isAllInOne && !isWallMounted) {
      for (final it in items) {
        if (it.type == ParsedItemType.tank) {
          final cap = it.tankCapacityLitres ?? tankCapacityLitres;
          final mat = it.tankMaterial ?? tankMaterial;
          final isPress = it.isPressurized;
          final thick = (mat == 'Enamel') ? '2mm' : (mat == 'MS' ? '5mm' : '3mm');
          tankLinesList.add(TankLineItem(
            id: 'tank_${tankIdx++}',
            capacityLitres: cap,
            qty: it.qty,
            isPressurized: isPress,
            rate: it.rate.round(),
            innerTankMaterial: mat,
            innerTankThickness: thick,
            outerCladdingMaterial: 'Galvanized Painted',
            insulationMaterial: it.insulationType ?? tankInsulation,
          ));
        }
      }
      if (tankLinesList.isEmpty && hasTank) {
        tankLinesList.add(TankLineItem(
          id: 'tank_1',
          capacityLitres: tankCapacityLitres,
          qty: tankQty,
          isPressurized: isTankPressurized,
          rate: tankRate.round(),
          innerTankMaterial: tankMaterial,
          innerTankThickness: '3mm',
          outerCladdingMaterial: 'Galvanized Painted',
          insulationMaterial: (tankInsulation.toLowerCase().contains('puff') || tankInsulation.toLowerCase().contains('puf')) ? 'PUF' : tankInsulation,
        ));
      }
    }

    final mappedPriceRows = <PriceRow>[];
    for (int i = 0; i < items.length; i++) {
      final it = items[i];
      mappedPriceRows.add(PriceRow(
        id: 'item_$i',
        serialNo: (i + 1).toString().padLeft(2, '0'),
        description: it.rawDescription,
        qty: it.qty,
        status: it.rate > 0 ? PriceRowStatus.priced : PriceRowStatus.included,
        rate: it.rate.round(),
        amount: it.amount.round(),
        hpKw: it.hpKw?.toDouble(),
        systemLph: it.tankCapacityLitres,
        metadata: {
          'type': it.type.name,
          'hpModel': it.hpModel,
          'tankMaterial': it.tankMaterial,
          'isPressurized': it.isPressurized,
          'insulationType': it.insulationType,
        },
      ));
    }

    final mappedExtraRows = <PriceItem>[];
    for (int i = 0; i < supplementaryItems.length; i++) {
      final supp = supplementaryItems[i];
      final term = (supp['name'] ?? supp['term'] ?? '').toString().trim();
      if (term.isEmpty) continue;
      final typeStr = (supp['type'] ?? supp['status'] ?? 'Included').toString().trim();
      final isExtra = typeStr.toLowerCase() == 'extra';
      final isNa = typeStr.toLowerCase() == 'na' || typeStr.toLowerCase() == 'n/a';
      final rateNum = (supp['rate'] as num?)?.toInt() ?? 0;
      final qtyNum = (supp['qty'] as num?)?.toInt() ?? 1;
      final totalNum = isExtra ? (rateNum * qtyNum) : 0;

      PriceRowType rowType;
      if (isExtra) {
        rowType = totalNum > 0 ? PriceRowType.amount : PriceRowType.extra;
      } else if (isNa) {
        rowType = PriceRowType.customText;
      } else {
        rowType = PriceRowType.included;
      }

      final desc = term;

      mappedExtraRows.add(PriceItem(
        serialNo: (items.length + i + 1).toString().padLeft(2, '0'),
        description: desc,
        qty: '$qtyNum',
        systemRate: (isExtra && rateNum > 0) ? PriceCalculator.formatIndianCurrency(rateNum) : '',
        amountType: rowType,
        customText: isNa ? 'NA' : '',
        numericAmount: totalNum,
      ));
    }

    DateTime parsedDate;
    try {
      final parts = quoteDate.split('/');
      if (parts.length == 3) {
        parsedDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
      } else {
        parsedDate = quotationUpdatedAt;
      }
    } catch (_) {
      parsedDate = quotationUpdatedAt;
    }

    int advSplit = 70;
    int delSplit = 20;
    int commSplit = 10;
    if (paymentTerms.isNotEmpty) {
      for (final pt in paymentTerms) {
        final t = (pt['term'] ?? '').toString().toLowerCase();
        final p = (pt['percent'] as num?)?.toInt() ?? (pt['percentage'] as num?)?.toInt() ?? 0;
        if (t.contains('advance') || t.contains('po')) {
          advSplit = p;
        } else if (t.contains('delivery') || t.contains('dispatch')) {
          delSplit = p;
        } else if (t.contains('install') || t.contains('commission') || t.contains('completion')) {
          commSplit = p;
        }
      }
    }

    return GeneratorQuotation(
      id: quotationId,
      quoteType: resolvedQuoteType,
      status: isConfirmed ? 'confirmed' : 'draft',
      salutation: customerSalutation,
      customerName: customerName,
      customerAddress: customerAddress,
      customerMobile: customerPhone,
      date: parsedDate,
      quoteRefNo: refNumber,
      salesRef: salesmanName,
      salesMobile: salesmanPhone,
      model: heatPumpModel,
      allInOneModel: resolvedAioModel,
      poolModel: resolvedPoolModel,
      heatPumpQty: hpQtyVal,
      heatPumpNumericPrice: hpRateVal,
      heatPumpAmountType: PriceRowType.amount,
      heatPumpLines: hpLineItems,
      tankLines: (isAllInOne || isWallMounted) ? const [] : tankLinesList,
      tankSpec: (isAllInOne || isWallMounted)
          ? const TankSpec(capacityLitres: 0, isPressurized: false)
          : TankSpec(
              capacityLitres: hasTank ? tankCapacityLitres : 0,
              isPressurized: hasTank ? isTankPressurized : false,
              innerAndOuterTank: hasTank ? tankMaterial : 'GI',
            ),
      extraPriceRows: mappedExtraRows,
      tankCapacityLitres: (isAllInOne || isWallMounted) ? 0 : (hasTank ? tankCapacityLitres : 0),
      tankQty: (isAllInOne || isWallMounted) ? 0 : (hasTank ? tankQty : 0),
      tankRate: (isAllInOne || isWallMounted) ? 0 : (hasTank ? tankRate.round() : 0),
      priceRows: mappedPriceRows,
      subtotal: subtotal.round(),
      gstPercent: cgstRate + sgstRate,
      gstAmount: (cgstAmount + sgstAmount).round(),
      grossTotal: (subtotal + cgstAmount + sgstAmount).round(),
      grandTotal: grandTotal.round(),
      netPayable: grandTotal.round(),
      paymentSplitAdvance: advSplit,
      paymentSplitDelivery: delSplit,
      paymentSplitCommissioning: commSplit,
      paymentTerms: paymentTerms,
      warrantyHpYears: warrantyHpYears,
      warrantyTankYears: hasTank ? warrantyTankYears : 0,
      validityDays: validityDays,
      termsAndConditions: settings?.defaultTerms ?? const [
        'Proper 1 / 3 Phase power should be arranged where you install the heat pump.',
        'Electrical/civil/plumbing work materials – Customer Scope.',
        'Safe storage place need to be provided by you to keep our material & tools.',
        'All Interconnected pipe lines between system and Tank Your Scope but our team will do the installation. (If applicable): Extra',
      ],
      coverImagePath: coverImagePath,
      bannerImagePath: bannerImagePath,
      productImagePaths: [
        if (productImagePath != null && productImagePath!.isNotEmpty)
          productImagePath!
        else if (resolvedAioModel?.defaultImagePath.isNotEmpty == true)
          resolvedAioModel!.defaultImagePath
        else if (heatPumpModel.defaultImagePath.isNotEmpty &&
            heatPumpModel.defaultImagePath != 'assets/images/model_iz_4c.png')
          heatPumpModel.defaultImagePath
      ],
      createdAt: quotationUpdatedAt,
      updatedAt: draftUpdatedAt,
    );
  }
}
