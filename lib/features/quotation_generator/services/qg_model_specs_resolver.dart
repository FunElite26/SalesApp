// lib/features/quotation_generator/services/qg_model_specs_resolver.dart

import 'package:flutter/foundation.dart';
import '../models/generator_company_settings.dart';
import '../models/heat_pump_model.dart';
import '../models/all_in_one_model.dart';
import '../models/pool_heat_pump_model.dart';
import 'qg_item_parser.dart';

/// Distinct categories of Heat Pump units supported in the quotation system.
enum HeatPumpType {
  domesticCommercial, // Standard Air Source Heat Pump (4kW - 100kW), stored in settings.models
  allInOne,           // All In One Heat Pump (100L - 300L), stored in settings.allInOneModels
  swimmingPool,       // Swimming Pool Heat Pump (35kW - 60kW SP), stored in settings.poolModels
}

/// Result of specification resolution for a quotation line item.
class ResolvedModelSpecs {
  final String modelId;
  final String modelName;
  final double kw;
  final int? litres;
  final Map<String, String> specs;
  final String specsCopiedFrom;
  final HeatPumpType heatPumpType;
  final HeatPumpModel? matchedModel;
  final AllInOneModel? matchedAioModel;
  final PoolHeatPumpModel? matchedPoolModel;
  final bool isHigherModelFallback;
  final bool isDefaultFallback;

  const ResolvedModelSpecs({
    this.modelId = '',
    required this.modelName,
    required this.kw,
    this.litres,
    required this.specs,
    required this.specsCopiedFrom,
    this.heatPumpType = HeatPumpType.domesticCommercial,
    this.matchedModel,
    this.matchedAioModel,
    this.matchedPoolModel,
    this.isHigherModelFallback = false,
    this.isDefaultFallback = false,
  });
}

/// Centralized specification resolver for quotation line items.
///
/// STRICTURES:
/// - Categorizes heat pump type (Domestic/Commercial, All-In-One, Swimming Pool).
/// - NEVER crosses categories: All-In-One resolves ONLY against allInOneModels,
///   Swimming Pool resolves ONLY against poolModels, and Domestic/Commercial
///   resolves ONLY against models.
/// - Exact match on unique product/model id (case-insensitive).
/// - Exact match on full model name (case-insensitive, trimmed).
/// - Exact match on numeric capacity (kW or Litres).
/// - Higher Model Fallback: If exact model is missing, borrow specs of the next
///   higher available model in that category, but preserve the item's own
///   model number, capacity, and volume.
/// - Explicit Fallback: If no higher model exists, generate deterministic standard
///   specs for that category without borrowing arbitrary siblings.
class QgModelSpecsResolver {
  QgModelSpecsResolver._();

  static ResolvedModelSpecs resolve({
    String? modelId,
    String? modelName,
    double? kw,
    int? litres,
    bool isWallMounted = false,
    HeatPumpType? heatPumpType,
    GeneratorCompanySettings? settings,
    String? rawDescription,
  }) {
    // 1. Detect heat pump type if not explicitly supplied
    final resolvedType = heatPumpType ?? _detectType(
      modelId: modelId,
      modelName: modelName,
      rawDescription: rawDescription,
    );

    switch (resolvedType) {
      case HeatPumpType.allInOne:
        return _resolveAllInOne(
          modelId: modelId,
          modelName: modelName,
          litres: litres,
          isWallMounted: isWallMounted,
          settings: settings,
          rawDescription: rawDescription,
        );
      case HeatPumpType.swimmingPool:
        return _resolvePool(
          modelId: modelId,
          modelName: modelName,
          kw: kw,
          settings: settings,
          rawDescription: rawDescription,
        );
      case HeatPumpType.domesticCommercial:
        return _resolveDomesticCommercial(
          modelId: modelId,
          modelName: modelName,
          kw: kw,
          settings: settings,
          rawDescription: rawDescription,
        );
    }
  }

  /// Detects whether an item belongs to All-In-One, Swimming Pool, or Standard Air Source.
  static HeatPumpType _detectType({
    String? modelId,
    String? modelName,
    String? rawDescription,
  }) {
    final combined = '${modelId ?? ""} ${modelName ?? ""} ${rawDescription ?? ""}'.toLowerCase();
    if (combined.contains('all in one') ||
        combined.contains('all-in-one') ||
        combined.contains('aio') ||
        combined.contains('wall mounted') ||
        RegExp(r'\biz-\d+a\b|\biz-\d+wm\b', caseSensitive: false).hasMatch(combined)) {
      return HeatPumpType.allInOne;
    }
    if (combined.contains('pool') ||
        combined.contains('swimming') ||
        RegExp(r'\b\d+\s*sp\b|\biz-\d+sp\b', caseSensitive: false).hasMatch(combined)) {
      return HeatPumpType.swimmingPool;
    }
    return HeatPumpType.domesticCommercial;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // ALL IN ONE RESOLVER
  // ───────────────────────────────────────────────────────────────────────────
  static ResolvedModelSpecs _resolveAllInOne({
    String? modelId,
    String? modelName,
    int? litres,
    bool isWallMounted = false,
    GeneratorCompanySettings? settings,
    String? rawDescription,
  }) {
    final cleanId = modelId?.trim().toLowerCase() ?? '';
    String derivedName = modelName?.trim() ?? '';
    int? vol = litres;
    bool wall = isWallMounted;

    if (rawDescription != null && rawDescription.isNotEmpty) {
      final parsed = QgItemParser.parseLineItem(rawDescription);
      if (parsed.aioCapacityLitres != null && vol == null) {
        vol = parsed.aioCapacityLitres;
      }
      if (parsed.type == ParsedItemType.wallMounted) {
        wall = true;
      }
    }

    if (vol == null) {
      final match = RegExp(r'(\d+)\s*(?:ltr|l\b|liter|litre|a\b|wm\b)', caseSensitive: false).firstMatch(derivedName);
      if (match != null) {
        vol = int.tryParse(match.group(1)!);
      }
      vol ??= wall ? 100 : 200;
    }

    if (derivedName.isEmpty) {
      derivedName = wall ? 'IZ-${vol}WM' : 'IZ-${vol}A';
    }

    final cleanName = derivedName.toLowerCase();
    final aioList = settings?.allInOneModels ?? const <AllInOneModel>[];

    // 1. Exact match by modelId
    if (cleanId.isNotEmpty) {
      final match = aioList.where((m) => m.id.trim().toLowerCase() == cleanId).firstOrNull;
      if (match != null && match.specs.isNotEmpty) {
        return ResolvedModelSpecs(
          modelId: match.id,
          modelName: match.modelName,
          kw: 0,
          litres: match.tankVolumeLitres,
          specs: Map<String, String>.from(match.specs),
          specsCopiedFrom: 'Module Settings: ${match.modelName}',
          heatPumpType: HeatPumpType.allInOne,
          matchedAioModel: match,
        );
      }
    }

    // 2. Exact match by modelName
    final matchByName = aioList.where(
      (m) => m.modelName.trim().toLowerCase() == cleanName || m.id.trim().toLowerCase() == cleanName,
    ).firstOrNull;
    if (matchByName != null && matchByName.specs.isNotEmpty) {
      return ResolvedModelSpecs(
        modelId: matchByName.id,
        modelName: matchByName.modelName,
        kw: 0,
        litres: matchByName.tankVolumeLitres,
        specs: Map<String, String>.from(matchByName.specs),
        specsCopiedFrom: 'Module Settings: ${matchByName.modelName}',
        heatPumpType: HeatPumpType.allInOne,
        matchedAioModel: matchByName,
      );
    }

    // 3. Exact match by volume & mount type
    final matchByVol = aioList.where(
      (m) => m.tankVolumeLitres == vol && m.isWallMounted == wall,
    ).firstOrNull ?? aioList.where((m) => m.tankVolumeLitres == vol).firstOrNull;
    if (matchByVol != null && matchByVol.specs.isNotEmpty) {
      return ResolvedModelSpecs(
        modelId: matchByVol.id,
        modelName: matchByVol.modelName,
        kw: 0,
        litres: matchByVol.tankVolumeLitres,
        specs: Map<String, String>.from(matchByVol.specs),
        specsCopiedFrom: 'Module Settings: ${matchByVol.modelName}',
        heatPumpType: HeatPumpType.allInOne,
        matchedAioModel: matchByVol,
      );
    }

    // 4. Higher Model Fallback in All-In-One models
    final higherAio = aioList.where(
      (m) => m.tankVolumeLitres > vol! && m.isWallMounted == wall && m.specs.isNotEmpty,
    ).toList()..sort((a, b) => a.tankVolumeLitres.compareTo(b.tankVolumeLitres));

    if (higherAio.isNotEmpty) {
      final higher = higherAio.first;
      final borrowed = Map<String, String>.from(higher.specs);
      borrowed['Tank Volume'] = '$vol Ltr';
      return ResolvedModelSpecs(
        modelId: higher.id,
        modelName: derivedName,
        kw: 0,
        litres: vol,
        specs: borrowed,
        specsCopiedFrom: 'Higher Model Fallback (${higher.modelName})',
        heatPumpType: HeatPumpType.allInOne,
        matchedAioModel: higher,
        isHigherModelFallback: true,
      );
    }

    // 5. Fallback Default AllInOneModel
    final fallbackModel = wall ? AllInOneModel.defaultWall() : AllInOneModel.defaultFloor();
    final fallbackSpecs = Map<String, String>.from(fallbackModel.specs);
    fallbackSpecs['Tank Volume'] = '$vol Ltr';
    if (vol <= 200) {
      fallbackSpecs['Product Dimension'] = '570x1810mm';
      fallbackSpecs['Heating Rate'] = '42 L/h';
      fallbackSpecs['Net Weight'] = '93 KG';
    } else {
      fallbackSpecs['Product Dimension'] = '640x1920mm';
      fallbackSpecs['Heating Rate'] = '65 L/h';
      fallbackSpecs['Net Weight'] = '110 KG';
    }

    return ResolvedModelSpecs(
      modelId: cleanId.isNotEmpty ? cleanId : (wall ? 'IZ-${vol}WM' : 'IZ-${vol}A'),
      modelName: derivedName,
      kw: 0,
      litres: vol,
      specs: fallbackSpecs,
      specsCopiedFrom: 'Default generated All-in-One specs (${vol}L)',
      heatPumpType: HeatPumpType.allInOne,
      isDefaultFallback: true,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // SWIMMING POOL RESOLVER
  // ───────────────────────────────────────────────────────────────────────────
  static ResolvedModelSpecs _resolvePool({
    String? modelId,
    String? modelName,
    double? kw,
    GeneratorCompanySettings? settings,
    String? rawDescription,
  }) {
    final cleanId = modelId?.trim().toLowerCase() ?? '';
    String derivedName = modelName?.trim() ?? '';
    double? resolvedKw = (kw != null && kw > 0) ? kw : null;

    if (rawDescription != null && rawDescription.isNotEmpty) {
      final parsed = QgItemParser.parseLineItem(rawDescription);
      if (parsed.poolKw != null && resolvedKw == null) {
        resolvedKw = parsed.poolKw!.toDouble();
      }
      if (parsed.poolModel != null && derivedName.isEmpty) {
        derivedName = parsed.poolModel!;
      }
    }

    resolvedKw ??= 35.0;
    if (derivedName.isEmpty) {
      derivedName = 'IZ-${resolvedKw.toInt()}SP';
    }

    final cleanName = derivedName.toLowerCase();
    final poolList = settings?.poolModels ?? const <PoolHeatPumpModel>[];

    // 1. Exact match by id
    if (cleanId.isNotEmpty) {
      final match = poolList.where((m) => m.id.trim().toLowerCase() == cleanId).firstOrNull;
      if (match != null && match.specs.isNotEmpty) {
        return ResolvedModelSpecs(
          modelId: match.id,
          modelName: match.modelName,
          kw: match.capacityKw > 0 ? match.capacityKw : resolvedKw,
          specs: Map<String, String>.from(match.specs),
          specsCopiedFrom: 'Module Settings: ${match.modelName}',
          heatPumpType: HeatPumpType.swimmingPool,
          matchedPoolModel: match,
        );
      }
    }

    // 2. Exact match by modelName
    final matchByName = poolList.where(
      (m) => m.modelName.trim().toLowerCase() == cleanName || m.id.trim().toLowerCase() == cleanName,
    ).firstOrNull;
    if (matchByName != null && matchByName.specs.isNotEmpty) {
      return ResolvedModelSpecs(
        modelId: matchByName.id,
        modelName: matchByName.modelName,
        kw: matchByName.capacityKw > 0 ? matchByName.capacityKw : resolvedKw,
        specs: Map<String, String>.from(matchByName.specs),
        specsCopiedFrom: 'Module Settings: ${matchByName.modelName}',
        heatPumpType: HeatPumpType.swimmingPool,
        matchedPoolModel: matchByName,
      );
    }

    // 3. Exact match by kW
    final matchByKw = poolList.where((m) => (m.capacityKw - resolvedKw!).abs() < 0.1).firstOrNull;
    if (matchByKw != null && matchByKw.specs.isNotEmpty) {
      return ResolvedModelSpecs(
        modelId: matchByKw.id,
        modelName: matchByKw.modelName,
        kw: matchByKw.capacityKw > 0 ? matchByKw.capacityKw : resolvedKw,
        specs: Map<String, String>.from(matchByKw.specs),
        specsCopiedFrom: 'Module Settings: ${matchByKw.modelName}',
        heatPumpType: HeatPumpType.swimmingPool,
        matchedPoolModel: matchByKw,
      );
    }

    // 4. Higher Model Fallback in Pool models
    final higherPool = poolList.where(
      (m) => m.capacityKw > resolvedKw! && m.specs.isNotEmpty,
    ).toList()..sort((a, b) => a.capacityKw.compareTo(b.capacityKw));

    if (higherPool.isNotEmpty) {
      final higher = higherPool.first;
      final borrowed = Map<String, String>.from(higher.specs);
      borrowed['Model'] = derivedName;
      borrowed['Heating Capacity'] = '${resolvedKw.toInt()}kW';
      return ResolvedModelSpecs(
        modelId: higher.id,
        modelName: derivedName,
        kw: resolvedKw,
        specs: borrowed,
        specsCopiedFrom: 'Higher Model Fallback (${higher.modelName})',
        heatPumpType: HeatPumpType.swimmingPool,
        matchedPoolModel: higher,
        isHigherModelFallback: true,
      );
    }

    // 5. Fallback default pool model
    final defPool = PoolHeatPumpModel.defaultModel();
    final fallbackSpecs = Map<String, String>.from(defPool.specs);
    fallbackSpecs['Model'] = derivedName;
    fallbackSpecs['Heating Capacity'] = '${resolvedKw.toInt()}kW';
    return ResolvedModelSpecs(
      modelId: cleanId.isNotEmpty ? cleanId : 'IZ-${resolvedKw.toInt()}SP',
      modelName: derivedName,
      kw: resolvedKw,
      specs: fallbackSpecs,
      specsCopiedFrom: 'Default generated Pool specs (${resolvedKw.toInt()}kW)',
      heatPumpType: HeatPumpType.swimmingPool,
      isDefaultFallback: true,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // DOMESTIC & COMMERCIAL AIR SOURCE RESOLVER
  // ───────────────────────────────────────────────────────────────────────────
  static ResolvedModelSpecs _resolveDomesticCommercial({
    String? modelId,
    String? modelName,
    double? kw,
    GeneratorCompanySettings? settings,
    String? rawDescription,
  }) {
    final cleanId = modelId?.trim().toLowerCase() ?? '';
    String derivedModelName = modelName?.trim() ?? '';
    double? resolvedKw = (kw != null && kw > 0) ? kw : null;

    if (rawDescription != null && rawDescription.trim().isNotEmpty) {
      final parsed = QgItemParser.parseLineItem(rawDescription);
      if (parsed.hpKw != null && resolvedKw == null) {
        resolvedKw = parsed.hpKw!.toDouble();
      }
      if (parsed.hpModel != null && derivedModelName.isEmpty) {
        derivedModelName = parsed.hpModel!;
      }
    }

    if (derivedModelName.isEmpty && resolvedKw != null) {
      derivedModelName = 'IZ-${resolvedKw.toInt()}C';
    } else if (derivedModelName.isEmpty) {
      derivedModelName = cleanId.isNotEmpty ? cleanId.toUpperCase() : 'IZ-4C';
    }

    if (resolvedKw == null) {
      final match = RegExp(r'(\d+)\s*kw|\biz-(\d+)', caseSensitive: false).firstMatch(derivedModelName);
      if (match != null) {
        final valStr = match.group(1) ?? match.group(2);
        if (valStr != null) {
          resolvedKw = double.tryParse(valStr);
        }
      }
      resolvedKw ??= 4.0;
    }

    final cleanModelName = derivedModelName.toLowerCase();
    final models = settings?.models ?? const <HeatPumpModel>[];

    // 1. Exact match on modelId
    if (cleanId.isNotEmpty) {
      final matchesById = models.where(
        (m) => m.id.trim().toLowerCase() == cleanId,
      ).toList();

      if (matchesById.isNotEmpty) {
        final matched = matchesById.first;
        return _buildResolved(
          matched: matched,
          targetModelName: derivedModelName,
          targetKw: resolvedKw,
          source: 'Module Settings: ${matched.modelName}',
        );
      }
    }

    // 2. Exact match on full modelName
    final matchesByName = models.where(
      (m) => m.modelName.trim().toLowerCase() == cleanModelName ||
             m.id.trim().toLowerCase() == cleanModelName,
    ).toList();

    if (matchesByName.isNotEmpty) {
      final matched = matchesByName.first;
      return _buildResolved(
        matched: matched,
        targetModelName: derivedModelName,
        targetKw: resolvedKw,
        source: 'Module Settings: ${matched.modelName}',
      );
    }

    // 3. Exact match on numeric kW capacity (within 0.05 kW tolerance)
    final matchesByKw = models.where(
      (m) => (m.displayCapacityKw - resolvedKw!).abs() < 0.05,
    ).toList();

    if (matchesByKw.isNotEmpty) {
      final matched = matchesByKw.first;
      return _buildResolved(
        matched: matched,
        targetModelName: derivedModelName,
        targetKw: resolvedKw,
        source: 'Module Settings: ${matched.modelName}',
      );
    }

    // 4. Higher Model Fallback Rule in standard models
    if (models.isNotEmpty) {
      final higherModels = models.where(
        (m) => m.displayCapacityKw > resolvedKw! && m.specs.isNotEmpty,
      ).toList()
        ..sort((a, b) => a.displayCapacityKw.compareTo(b.displayCapacityKw));

      if (higherModels.isNotEmpty) {
        final higherModel = higherModels.first;
        final borrowedSpecs = Map<String, String>.from(higherModel.specs);

        // Crucial: overwrite model number & capacity with item's exact values
        borrowedSpecs['Heat Pump Model'] = derivedModelName;
        final kwStr = (resolvedKw.toInt() == resolvedKw) ? '${resolvedKw.toInt()}kw' : '${resolvedKw}kw';
        borrowedSpecs['Rated Heating Capacity'] = kwStr;

        debugPrint('[QgModelSpecsResolver] Exact model "$derivedModelName" (${resolvedKw}kW) not found in Module Settings. Borrowing specs from higher model ${higherModel.modelName} (${higherModel.displayCapacityKw}kW) with model number & kW preserved.');

        return ResolvedModelSpecs(
          modelId: higherModel.id,
          modelName: derivedModelName,
          kw: resolvedKw,
          specs: borrowedSpecs,
          specsCopiedFrom: 'Higher Model Fallback (${higherModel.modelName})',
          heatPumpType: HeatPumpType.domesticCommercial,
          matchedModel: higherModel,
          isHigherModelFallback: true,
        );
      }
    }

    // 5. Explicit Default Fallback: No higher model found
    debugPrint('[QgModelSpecsResolver] Using explicit default specs for $derivedModelName (${resolvedKw}kW) - no Module Settings found');
    final defaultSpecs = buildDefaultHpSpecs(resolvedKw.toInt(), derivedModelName);
    return ResolvedModelSpecs(
      modelId: cleanId,
      modelName: derivedModelName,
      kw: resolvedKw,
      specs: defaultSpecs,
      specsCopiedFrom: 'Explicit Fallback Defaults',
      heatPumpType: HeatPumpType.domesticCommercial,
      isDefaultFallback: true,
    );
  }

  static ResolvedModelSpecs _buildResolved({
    required HeatPumpModel matched,
    required String targetModelName,
    required double targetKw,
    required String source,
  }) {
    final specs = Map<String, String>.from(matched.specs);
    if (!specs.containsKey('Heat Pump Model') || specs['Heat Pump Model']!.isEmpty) {
      specs['Heat Pump Model'] = matched.modelName;
    }
    if (!specs.containsKey('Rated Heating Capacity') || specs['Rated Heating Capacity']!.isEmpty) {
      final kwStr = (targetKw.toInt() == targetKw) ? '${targetKw.toInt()}kw' : '${targetKw}kw';
      specs['Rated Heating Capacity'] = kwStr;
    }

    return ResolvedModelSpecs(
      modelId: matched.id,
      modelName: matched.modelName,
      kw: targetKw,
      specs: specs,
      specsCopiedFrom: source,
      heatPumpType: HeatPumpType.domesticCommercial,
      matchedModel: matched,
    );
  }

  /// Builds standard deterministic 13-row specs table for Domestic/Commercial Heat Pumps
  static Map<String, String> buildDefaultHpSpecs(int kw, String model) {
    final powerSupply = kw <= 8 ? '220V - 1Phase' : '415V - 3Phase';
    final compressor = kw <= 24 ? 'Single' : 'Double';
    return {
      'Heat Pump Model': model,
      'Size (W x D x H) mm': '1410x748x1000mm',
      'Rated Heating Capacity': '${kw}kw',
      'Power Supply': powerSupply,
      'Rated Input Power': '${(kw * 0.23).toStringAsFixed(2)}kw',
      'Rated COP': '4.29',
      'Rated Water Yield': '${(kw * 21.5).round()} L/h',
      'Max Outlet Water Temperature': '60°C',
      'Water Flow Noise': '<=57dB(A)',
      'Condenser': 'Shell and tube heat exchanger',
      'Refrigerant': 'R134A/410A',
      'Operating ambient Temp': '-15~43°C',
      'Compressor': compressor,
    };
  }
}
