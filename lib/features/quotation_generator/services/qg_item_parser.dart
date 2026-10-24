// lib/features/quotation_generator/services/qg_item_parser.dart


enum ParsedItemType {
  heatPump,
  tank,
  allInOne,
  wallMounted,
  pool,
  supplementary,
  parts,
  other,
}

enum ItemResolveStatus {
  resolved,
  unmapped,
}

class ParsedItemResult {
  final String rawDescription;
  final ParsedItemType type;
  final ItemResolveStatus status;
  final String? unmappedReason;

  // Heat Pump attributes (Whole number kW strictly required by Section 7a)
  final int? hpKw;
  final String? hpModel; // Derived as IZ-{kw}C
  final String? catalogModel; // e.g. IZ-90C for 88kW
  final String? warningMessage;

  // Tank attributes
  final int? tankCapacityLitres;
  final String? tankMaterial; // GI | MS | Enamel | SS
  final bool isPressurized;
  final String? insulationType; // Puff | Rockwool

  // All-in-One / Pool attributes
  final int? aioCapacityLitres;
  final String? poolModel;
  final int? poolKw;

  // Metadata from deal line
  final String? modelId;
  final int qty;
  final double rate;
  final double amount;
  final String? uom;
  final bool isExtra;
  final bool isIncluded;

  const ParsedItemResult({
    required this.rawDescription,
    required this.type,
    required this.status,
    this.unmappedReason,
    this.hpKw,
    this.hpModel,
    this.catalogModel,
    this.warningMessage,
    this.tankCapacityLitres,
    this.tankMaterial,
    this.isPressurized = true,
    this.insulationType,
    this.aioCapacityLitres,
    this.poolModel,
    this.poolKw,
    this.modelId,
    this.qty = 1,
    this.rate = 0.0,
    this.amount = 0.0,
    this.uom = 'NOS',
    this.isExtra = false,
    this.isIncluded = false,
  });

  bool get isResolved => status == ItemResolveStatus.resolved;

  ParsedItemResult copyWith({
    ParsedItemType? type,
    ItemResolveStatus? status,
    String? unmappedReason,
    int? hpKw,
    String? hpModel,
    String? catalogModel,
    String? warningMessage,
    int? tankCapacityLitres,
    String? tankMaterial,
    bool? isPressurized,
    String? insulationType,
    int? aioCapacityLitres,
    String? poolModel,
    int? poolKw,
    String? modelId,
    int? qty,
    double? rate,
    double? amount,
    String? uom,
    bool? isExtra,
    bool? isIncluded,
  }) {
    return ParsedItemResult(
      rawDescription: rawDescription,
      type: type ?? this.type,
      status: status ?? this.status,
      unmappedReason: unmappedReason ?? this.unmappedReason,
      hpKw: hpKw ?? this.hpKw,
      hpModel: hpModel ?? this.hpModel,
      catalogModel: catalogModel ?? this.catalogModel,
      warningMessage: warningMessage ?? this.warningMessage,
      tankCapacityLitres: tankCapacityLitres ?? this.tankCapacityLitres,
      tankMaterial: tankMaterial ?? this.tankMaterial,
      isPressurized: isPressurized ?? this.isPressurized,
      insulationType: insulationType ?? this.insulationType,
      aioCapacityLitres: aioCapacityLitres ?? this.aioCapacityLitres,
      poolModel: poolModel ?? this.poolModel,
      poolKw: poolKw ?? this.poolKw,
      modelId: modelId ?? this.modelId,
      qty: qty ?? this.qty,
      rate: rate ?? this.rate,
      amount: amount ?? this.amount,
      uom: uom ?? this.uom,
      isExtra: isExtra ?? this.isExtra,
      isIncluded: isIncluded ?? this.isIncluded,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rawDescription': rawDescription,
      'type': type.name,
      'status': status.name,
      'unmappedReason': unmappedReason,
      'hpKw': hpKw,
      'hpModel': hpModel,
      'catalogModel': catalogModel,
      'warningMessage': warningMessage,
      'tankCapacityLitres': tankCapacityLitres,
      'tankMaterial': tankMaterial,
      'isPressurized': isPressurized,
      'insulationType': insulationType,
      'aioCapacityLitres': aioCapacityLitres,
      'poolModel': poolModel,
      'poolKw': poolKw,
      'qty': qty,
      'rate': rate,
      'amount': amount,
      'uom': uom,
      'isExtra': isExtra,
      'isIncluded': isIncluded,
    };
  }

  factory ParsedItemResult.fromJson(Map<String, dynamic> json) {
    return ParsedItemResult(
      rawDescription: json['rawDescription'] as String? ?? '',
      type: ParsedItemType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ParsedItemType.other,
      ),
      status: ItemResolveStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ItemResolveStatus.unmapped,
      ),
      unmappedReason: json['unmappedReason'] as String?,
      hpKw: (json['hpKw'] as num?)?.toInt(),
      hpModel: json['hpModel'] as String?,
      catalogModel: json['catalogModel'] as String?,
      warningMessage: json['warningMessage'] as String?,
      tankCapacityLitres: (json['tankCapacityLitres'] as num?)?.toInt(),
      tankMaterial: json['tankMaterial'] as String?,
      isPressurized: json['isPressurized'] as bool? ?? true,
      insulationType: json['insulationType'] as String?,
      aioCapacityLitres: (json['aioCapacityLitres'] as num?)?.toInt(),
      poolModel: json['poolModel'] as String?,
      poolKw: (json['poolKw'] as num?)?.toInt(),
      qty: (json['qty'] as num?)?.toInt() ?? 1,
      rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      uom: json['uom'] as String?,
      isExtra: json['isExtra'] as bool? ?? false,
      isIncluded: json['isIncluded'] as bool? ?? false,
    );
  }
}

/// Core item parser service implementing rules from Section 7 & 7a.
class QgItemParser {
  /// Auto-derives the Heat Pump model number deterministically from whole-number kW.
  /// Rule: IZ-{kW}C
  static String deriveHpModelFromKw(int kw) {
    return 'IZ-${kw}C';
  }

  /// Parses an item description string from a deal line item.
  static ParsedItemResult parseLineItem(
    String description, {
    int qty = 1,
    double rate = 0.0,
    double amount = 0.0,
    String? uom,
    bool isExtra = false,
    bool isIncluded = false,
    String? modelId,
  }) {
    final text = description.trim();
    final lower = text.toLowerCase();

    // ------------------------------------------------------------------------
    // 1. All-in-One / Wall Mounted Detection
    // ------------------------------------------------------------------------
    if (lower.contains('all in one') || lower.contains('all-in-one') || lower.contains('aio')) {
      final isWall = lower.contains('wall') || lower.contains('v');
      final litreMatch = RegExp(r'(\d+)\s*(?:ltr|l|liter|litre)', caseSensitive: false).firstMatch(lower);
      final int? litres = litreMatch != null ? int.tryParse(litreMatch.group(1)!) : null;

      return ParsedItemResult(
        rawDescription: text,
        type: isWall ? ParsedItemType.wallMounted : ParsedItemType.allInOne,
        status: ItemResolveStatus.resolved,
        aioCapacityLitres: litres ?? 200,
        qty: qty,
        rate: rate,
        amount: amount,
        uom: uom ?? 'SET',
        isExtra: isExtra,
        isIncluded: isIncluded,
        modelId: modelId,
      );
    }

    if (lower.contains('swimming pool') ||
        lower.contains('pool heat pump') ||
        RegExp(r'\b\d+\s*sp\b|\biz-\d+sp\b|\bpool\b', caseSensitive: false).hasMatch(lower)) {
      final kwMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:kw)', caseSensitive: false).firstMatch(lower);
      int? poolKw;
      if (kwMatch != null) {
        final val = double.tryParse(kwMatch.group(1)!);
        if (val != null) poolKw = val.round();
      }

      return ParsedItemResult(
        rawDescription: text,
        type: ParsedItemType.pool,
        status: ItemResolveStatus.resolved,
        poolKw: poolKw,
        poolModel: poolKw != null ? 'IZ-${poolKw}SP' : null,
        qty: qty,
        rate: rate,
        amount: amount,
        uom: uom ?? 'SET',
        isExtra: isExtra,
        isIncluded: isIncluded,
        modelId: modelId,
      );
    }

    // ------------------------------------------------------------------------
    // 3. Tank Detection
    // ------------------------------------------------------------------------
    if (lower.contains('tank') || lower.contains('storage tank') || lower.contains('lpd') || lower.contains('ltr')) {
      // Exclude Heat Pump lines that mention tank in long descriptions
      if (!lower.contains('heat pump') || lower.contains('pressurised tank') || lower.contains('pressurized tank')) {
        // Material detection
        String material = 'GI';
        if (lower.contains('enamel')) {
          material = 'Enamel';
        } else if (lower.contains('ms ') || lower.contains('ms-') || lower.startsWith('ms')) {
          material = 'MS';
        } else if (lower.contains('ss ') || lower.contains('ss-') || lower.contains('ss 304') || lower.contains('stainless')) {
          material = 'SS';
        } else if (lower.contains('gi')) {
          material = 'GI';
        }

        // Pressurization
        final isPressurized = lower.contains('pressuri') || lower.contains('pressurised') || lower.contains('pressurized');

        // Capacity in Litres
        final litreMatch = RegExp(r'(\d+)\s*(?:ltr|lpd|l\b|liter|litre)', caseSensitive: false).firstMatch(lower);
        int? litres;
        if (litreMatch != null) {
          litres = int.tryParse(litreMatch.group(1)!);
        } else {
          // Try bare number before tank
          final bareMatch = RegExp(r'(\d+)\s*(?:tank)', caseSensitive: false).firstMatch(lower);
          if (bareMatch != null) {
            litres = int.tryParse(bareMatch.group(1)!);
          }
        }

        // Insulation
        String? insulation;
        if (lower.contains('rockwool')) {
          insulation = 'Rockwool';
        } else if (lower.contains('puff')) {
          insulation = 'Puff';
        }

        if (litres != null) {
          return ParsedItemResult(
            rawDescription: text,
            type: ParsedItemType.tank,
            status: ItemResolveStatus.resolved,
            tankCapacityLitres: litres,
            tankMaterial: material,
            isPressurized: isPressurized,
            insulationType: insulation ?? 'Puff',
            qty: qty,
            rate: rate,
            amount: amount,
            uom: uom ?? 'NOS',
            isExtra: isExtra,
            isIncluded: isIncluded,
            modelId: modelId,
          );
        }
      }
    }

    // ------------------------------------------------------------------------
    // 4. Heat Pump Detection (Strict Whole-Number kW enforcement per Section 7a)
    // ------------------------------------------------------------------------
    if (lower.contains('heat pump') || lower.contains('air source') || RegExp(r'\b\d+\s*kw\b', caseSensitive: false).hasMatch(lower)) {
      // Check for decimal kW: resolve to closest available whole-number kW model
      final decimalKwMatch = RegExp(r'(\d+\.\d+)\s*kw', caseSensitive: false).firstMatch(lower);
      if (decimalKwMatch != null) {
        final rawDecimal = decimalKwMatch.group(1)!;
        final dVal = double.tryParse(rawDecimal) ?? 0.0;
        final closestKw = dVal.round();
        final derivedModel = deriveHpModelFromKw(closestKw);

        return ParsedItemResult(
          rawDescription: text,
          type: ParsedItemType.heatPump,
          status: ItemResolveStatus.resolved,
          hpKw: closestKw,
          hpModel: derivedModel,
          warningMessage: 'Closest available catalog capacity: $closestKw kW (from $rawDecimal kW)',
          qty: qty,
          rate: rate,
          amount: amount,
          uom: uom ?? 'SET',
          isExtra: isExtra,
          isIncluded: isIncluded,
          modelId: modelId,
        );
      }

      // Match integer kW: e.g. "38kw", "8 KW", "8kW", "Heat Pump - 38KW"
      final integerKwMatch = RegExp(r'(?:^|[^\d.])(\d+)\s*kw', caseSensitive: false).firstMatch(lower);
      if (integerKwMatch != null) {
        final kw = int.tryParse(integerKwMatch.group(1)!)!;
        final derivedModel = deriveHpModelFromKw(kw);

        String? warning;
        String? catalogModel;
        if (kw == 88) {
          catalogModel = 'IZ-90C';
          warning = 'Catalog lists this unit as IZ-90C';
        }

        return ParsedItemResult(
          rawDescription: text,
          type: ParsedItemType.heatPump,
          status: ItemResolveStatus.resolved,
          hpKw: kw,
          hpModel: derivedModel,
          catalogModel: catalogModel,
          warningMessage: warning,
          qty: qty,
          rate: rate,
          amount: amount,
          uom: uom ?? 'SET',
          isExtra: isExtra,
          isIncluded: isIncluded,
          modelId: modelId,
        );
      }

      // Heat pump mentioned but without a clean kW specification
      return ParsedItemResult(
        rawDescription: text,
        type: ParsedItemType.heatPump,
        status: ItemResolveStatus.unmapped,
        unmappedReason: 'Heat Pump kW could not be determined. Enter whole-number kW.',
        qty: qty,
        rate: rate,
        amount: amount,
        uom: uom ?? 'SET',
        isExtra: isExtra,
        isIncluded: isIncluded,
        modelId: modelId,
      );
    }

    // ------------------------------------------------------------------------
    // 5. Supplementary Terms Detection
    // ------------------------------------------------------------------------
    if (lower.contains('transport') ||
        lower.contains('lifting') ||
        lower.contains('installation') ||
        lower.contains('circulation pump') ||
        lower.contains('plumbing')) {
      return ParsedItemResult(
        rawDescription: text,
        type: ParsedItemType.supplementary,
        status: ItemResolveStatus.resolved,
        qty: qty,
        rate: rate,
        amount: amount,
        uom: uom ?? 'LOT',
        isExtra: isExtra,
        isIncluded: isIncluded,
      );
    }

    // ------------------------------------------------------------------------
    // 6. Accessories & Parts Detection
    // ------------------------------------------------------------------------
    if (lower.contains('contractor') ||
        lower.contains('sensor') ||
        lower.contains('cpvc') ||
        lower.contains('valve') ||
        lower.contains('nipple') ||
        lower.contains('elbow') ||
        lower.contains('cable') ||
        lower.contains('switch') ||
        lower.contains('mcb') ||
        lower.contains('tape') ||
        lower.contains('boom')) {
      return ParsedItemResult(
        rawDescription: text,
        type: ParsedItemType.parts,
        status: ItemResolveStatus.resolved,
        qty: qty,
        rate: rate,
        amount: amount,
        uom: uom ?? 'NOS',
        isExtra: isExtra,
        isIncluded: isIncluded,
      );
    }

    // ------------------------------------------------------------------------
    // 7. Unmapped Fallback
    // ------------------------------------------------------------------------
    return ParsedItemResult(
      rawDescription: text,
      type: ParsedItemType.other,
      status: ItemResolveStatus.unmapped,
      unmappedReason: 'Unrecognized line item. Please map item type.',
      qty: qty,
      rate: rate,
      amount: amount,
      uom: uom ?? 'NOS',
      isExtra: isExtra,
      isIncluded: isIncluded,
    );
  }
}
