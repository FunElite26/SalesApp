import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/pdf_service.dart';
import '../config/dynamic_annexure_resolver.dart';
import '../config/quote_template_config.dart';
import '../config/quote_type.dart';
import '../models/generator_quotation.dart';
import '../models/generator_company_settings.dart';
import '../models/price_row.dart';
import '../models/price_item.dart';
import '../models/tank_line_item.dart';
import '../models/heat_pump_line_item.dart';
import '../models/pool_heat_pump_model.dart';
import '../models/all_in_one_model.dart';
import '../models/heat_pump_model.dart';
import '../data/quotation_supabase_repository.dart';
import 'price_calculator.dart';
import 'qg_payment_sentence_builder.dart';
import 'qg_model_specs_resolver.dart';

class PdfQuotationBuilder {
  static Future<Uint8List> buildQuotationPdf(
    GeneratorQuotation quotation,
    GeneratorCompanySettings settings,
  ) async {
    final pdf = pw.Document();
    final config = QuoteTemplateConfig.forType(quotation.quoteType);
    final hasTank = quotation.hasTank;
    final dateStr = DateFormat('dd/MM/yyyy').format(quotation.date);

    // 0. Merge effectiveSettings with full module settings from Supabase
    GeneratorCompanySettings effectiveSettings = settings;
    try {
      final repoSettings = await QuotationSupabaseRepository(Supabase.instance.client).getSettings();
      effectiveSettings = effectiveSettings.copyWith(
        models: repoSettings.models.isNotEmpty ? repoSettings.models : effectiveSettings.models,
        allInOneModels: repoSettings.allInOneModels.isNotEmpty ? repoSettings.allInOneModels : effectiveSettings.allInOneModels,
        poolModels: repoSettings.poolModels.isNotEmpty ? repoSettings.poolModels : effectiveSettings.poolModels,
        defaultCoverImagePath: (repoSettings.defaultCoverImagePath?.isNotEmpty == true) ? repoSettings.defaultCoverImagePath : effectiveSettings.defaultCoverImagePath,
        defaultBannerImagePath: (repoSettings.defaultBannerImagePath?.isNotEmpty == true) ? repoSettings.defaultBannerImagePath : effectiveSettings.defaultBannerImagePath,
        stampImagePath: (repoSettings.stampImagePath?.isNotEmpty == true) ? repoSettings.stampImagePath : effectiveSettings.stampImagePath,
        domesticHpImagePath: (repoSettings.domesticHpImagePath?.isNotEmpty == true) ? repoSettings.domesticHpImagePath : effectiveSettings.domesticHpImagePath,
        allInOneImagePath: (repoSettings.allInOneImagePath?.isNotEmpty == true) ? repoSettings.allInOneImagePath : effectiveSettings.allInOneImagePath,
        allInOneWallImagePath: (repoSettings.allInOneWallImagePath?.isNotEmpty == true) ? repoSettings.allInOneWallImagePath : effectiveSettings.allInOneWallImagePath,
        swimmingPoolImagePath: (repoSettings.swimmingPoolImagePath?.isNotEmpty == true) ? repoSettings.swimmingPoolImagePath : effectiveSettings.swimmingPoolImagePath,
      );
    } catch (e) {
      debugPrint('PdfQuotationBuilder settings merge error: $e');
    }

    // Resolve models from Module Settings
    final isAioQuote = quotation.quoteType == QuoteType.allInOneFloor ||
        quotation.quoteType == QuoteType.allInOneWall ||
        quotation.priceRows.any((r) => r.description.toLowerCase().contains('all in one') || r.description.toLowerCase().contains('aio'));

    AllInOneModel? resolvedAio = quotation.allInOneModel;
    if (isAioQuote || resolvedAio != null) {
      final isWall = quotation.quoteType == QuoteType.allInOneWall || (resolvedAio?.isWallMounted ?? false);
      final targetVol = resolvedAio?.tankVolumeLitres ?? 200;
      final matchedAio = effectiveSettings.allInOneModels.cast<AllInOneModel?>().firstWhere(
        (m) => m != null && m.isWallMounted == isWall &&
               (m.tankVolumeLitres == targetVol || (resolvedAio != null && m.modelName.toLowerCase() == resolvedAio.modelName.toLowerCase())),
        orElse: () => effectiveSettings.allInOneModels.cast<AllInOneModel?>().firstWhere(
          (m) => m != null && (m.tankVolumeLitres == targetVol || m.modelName.toLowerCase().contains('$targetVol')),
          orElse: () => null,
        ),
      );
      if (matchedAio != null) {
        resolvedAio = matchedAio;
      }
    }

    PoolHeatPumpModel? resolvedPool = quotation.poolModel;
    if (quotation.quoteType == QuoteType.swimmingPool || resolvedPool != null) {
      final matchedPool = effectiveSettings.poolModels.cast<PoolHeatPumpModel?>().firstWhere(
        (m) => m != null && (m.id == resolvedPool?.id || m.modelName.toLowerCase() == resolvedPool?.modelName.toLowerCase()),
        orElse: () => effectiveSettings.poolModels.isNotEmpty ? effectiveSettings.poolModels.first : null,
      );
      if (matchedPool != null) {
        resolvedPool = matchedPool;
      }
    }

    HeatPumpModel resolvedHp = quotation.model;
    final resHpSpecs = QgModelSpecsResolver.resolve(
      modelId: resolvedHp.id,
      modelName: resolvedHp.modelName,
      kw: resolvedHp.displayCapacityKw,
      settings: effectiveSettings,
    );
    if (resHpSpecs.specs.isNotEmpty) {
      resolvedHp = resolvedHp.copyWith(
        id: resHpSpecs.modelId.isNotEmpty ? resHpSpecs.modelId : resolvedHp.id,
        modelName: resHpSpecs.modelName.isNotEmpty ? resHpSpecs.modelName : resolvedHp.modelName,
        displayCapacityKw: resHpSpecs.kw > 0 ? resHpSpecs.kw : resolvedHp.displayCapacityKw,
        specs: Map<String, String>.from(resHpSpecs.specs),
      );
    }

    final annexureResolver = DynamicAnnexureResolver(
      quoteType: quotation.quoteType,
      hasSpecs: config.hasTechnicalSpecs,
    );
    final annexureEntries = annexureResolver.resolveEntries();

    // Dynamic Page Numbering
    int nextFooterPage = 1;
    final offerLetterPage = nextFooterPage++; // 1
    final priceSchedulePage = nextFooterPage++; // 2
    final int? tankSpecPage =
        (quotation.quoteType == QuoteType.hpWithTank && hasTank)
            ? nextFooterPage++
            : null; // 3 or null
    final termsPage = nextFooterPage++; // 4 if hasTank, else 3
    final acceptPage = nextFooterPage++; // 5 if hasTank, else 4
    final int? showcasePage = quotation.includeProductImagePage
        ? nextFooterPage++
        : null; // 6 if hasTank, else 5

    // 1. Load Fonts
    pw.Font fontRegular;
    pw.Font fontBold;
    try {
      final regData =
          await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
      fontRegular = pw.Font.ttf(regData);
      fontBold = pw.Font.ttf(boldData);
    } catch (_) {
      fontRegular = pw.Font.helvetica();
      fontBold = pw.Font.helveticaBold();
    }

    final theme = pw.ThemeData.withFont(base: fontRegular, bold: fontBold);

    // 1b. Resolve Company & Bank details from active PDF template (app_companies)
    final resolvedConfig = await PdfService.resolveTemplateConfig(null);
    final companyName = (resolvedConfig['company_name'] as String?)?.trim().isNotEmpty == true
        ? (resolvedConfig['company_name'] as String).trim()
        : settings.companyName;
    final companyAddress = (resolvedConfig['company_address'] as String?)?.trim().isNotEmpty == true
        ? (resolvedConfig['company_address'] as String).trim()
        : settings.shortAddress;
    final companyEmail = (resolvedConfig['company_email'] as String?)?.trim().isNotEmpty == true
        ? (resolvedConfig['company_email'] as String).trim()
        : settings.companyEmail;
    final companyPhone = (resolvedConfig['company_phone'] as String?)?.trim().isNotEmpty == true
        ? (resolvedConfig['company_phone'] as String).trim()
        : settings.companyPhone;
    final companyPhone2 = settings.companyPhone2;
    final companyWebsite = (resolvedConfig['company_website'] as String?)?.trim().isNotEmpty == true
        ? (resolvedConfig['company_website'] as String).trim()
        : settings.companyWebsite;

    final bankAccountName = (resolvedConfig['bank_account_name'] as String?)?.trim().isNotEmpty == true
        ? (resolvedConfig['bank_account_name'] as String).trim()
        : settings.bankAccountName;
    final bankName = (resolvedConfig['bank_name'] as String?)?.trim().isNotEmpty == true
        ? (resolvedConfig['bank_name'] as String).trim()
        : settings.bankName;
    final bankAccountNumber = (resolvedConfig['bank_account_no'] as String?)?.trim().isNotEmpty == true
        ? (resolvedConfig['bank_account_no'] as String).trim()
        : settings.bankAccountNumber;
    final bankBranch = (resolvedConfig['bank_branch'] as String?)?.trim().isNotEmpty == true
        ? (resolvedConfig['bank_branch'] as String).trim()
        : settings.bankBranch;
    final bankIfsc = (resolvedConfig['bank_ifsc'] as String?)?.trim().isNotEmpty == true
        ? (resolvedConfig['bank_ifsc'] as String).trim()
        : settings.bankIfsc;

    final generatedByName = await PdfService.resolveCurrentUserName();

    // 2. Load Core Images (Template Logo & Stamp with fallbacks)
    final logoUrl = resolvedConfig['logo_url'] as String?;
    final logoBytes = (logoUrl != null && logoUrl.isNotEmpty)
        ? await _loadImageBytes(logoUrl)
        : await _loadImageBytes('assets/images/izyheat_logo.png');

    final coverImage = await _loadImageBytes(quotation.coverImagePath ??
        effectiveSettings.defaultCoverImagePath ??
        'assets/images/cover_proposal.png');
    final bannerImage = quotation.includeBanner
        ? await _loadImageBytes(quotation.bannerImagePath ??
            effectiveSettings.defaultBannerImagePath ??
            'assets/images/insiya_banner.png')
        : null;
    final stampUrl = resolvedConfig['stamp_url'] as String? ?? effectiveSettings.stampImagePath;
    final stampImage = (stampUrl != null && stampUrl.isNotEmpty)
        ? await _loadImageBytes(stampUrl)
        : await _loadImageBytes('assets/images/company_stamp.png');
    final fbIcon = await _loadImageBytes('assets/images/facebook_icon.png');
    final igIcon = await _loadImageBytes('assets/images/instagram_icon.png');
    final product38c =
        await _loadImageBytes('assets/images/product_iz_38c.png');

    // Product Images for the final page (Resolves by Heat Pump Type)
    final List<Uint8List> productImages = [];
    if (quotation.includeProductImagePage) {
      if (quotation.productImagePaths.isNotEmpty) {
        for (final p in quotation.productImagePaths) {
          final b = await _loadImageBytes(p);
          if (b != null) productImages.add(b);
        }
      }
      if (productImages.isEmpty) {
        Uint8List? resolvedImageBytes;
        final qType = quotation.quoteType;
        final modelLower = quotation.model.modelName.toLowerCase();

        // 1. SWIMMING POOL
        if (qType == QuoteType.swimmingPool ||
            modelLower.contains('pool') ||
            modelLower.contains('sp')) {
          String? imgPath = (resolvedPool?.defaultImagePath.isNotEmpty == true)
              ? resolvedPool!.defaultImagePath
              : null;
          if (imgPath == null || imgPath.isEmpty) {
            final match = effectiveSettings.poolModels.cast<PoolHeatPumpModel?>().firstWhere(
              (m) => (m?.defaultImagePath ?? '').isNotEmpty,
              orElse: () => null,
            );
            imgPath = match?.defaultImagePath;
            if (imgPath == null || imgPath.isEmpty) {
              imgPath = effectiveSettings.swimmingPoolImagePath;
            }
          }
          if (imgPath != null && imgPath.isNotEmpty) {
            resolvedImageBytes = await _loadImageBytes(imgPath);
          }
        }
        // 2. ALL IN ONE WALL MOUNTED
        else if (qType == QuoteType.allInOneWall ||
            modelLower.contains('wall') ||
            modelLower.contains('wm')) {
          String? imgPath = (resolvedAio?.defaultImagePath.isNotEmpty == true)
              ? resolvedAio!.defaultImagePath
              : null;
          if (imgPath == null || imgPath.isEmpty) {
            final match = effectiveSettings.allInOneModels.cast<AllInOneModel?>().firstWhere(
              (m) => (m?.isWallMounted ?? false) && (m?.defaultImagePath ?? '').isNotEmpty,
              orElse: () => null,
            );
            imgPath = match?.defaultImagePath;
            if (imgPath == null || imgPath.isEmpty) {
              imgPath = effectiveSettings.allInOneWallImagePath;
            }
          }
          if (imgPath != null && imgPath.isNotEmpty) {
            resolvedImageBytes = await _loadImageBytes(imgPath);
          }
        }
        // 3. ALL IN ONE FLOOR
        else if (isAioQuote ||
            qType == QuoteType.allInOneFloor ||
            modelLower.contains('all in one') ||
            modelLower.contains('aio')) {
          String? imgPath = (resolvedAio?.defaultImagePath.isNotEmpty == true)
              ? resolvedAio!.defaultImagePath
              : null;
          if (imgPath == null || imgPath.isEmpty) {
            final exactMatch = effectiveSettings.allInOneModels.cast<AllInOneModel?>().firstWhere(
              (m) => !(m?.isWallMounted ?? true) &&
                     m?.tankVolumeLitres == (resolvedAio?.tankVolumeLitres ?? 200) &&
                     (m?.defaultImagePath ?? '').isNotEmpty,
              orElse: () => null,
            );
            final anyMatch = exactMatch ?? effectiveSettings.allInOneModels.cast<AllInOneModel?>().firstWhere(
              (m) => !(m?.isWallMounted ?? true) && (m?.defaultImagePath ?? '').isNotEmpty,
              orElse: () => null,
            );
            imgPath = anyMatch?.defaultImagePath;
            if (imgPath == null || imgPath.isEmpty) {
              imgPath = effectiveSettings.allInOneImagePath;
            }
          }
          if (imgPath != null && imgPath.isNotEmpty) {
            resolvedImageBytes = await _loadImageBytes(imgPath);
          }
        }
        // 4. DOMESTIC HEAT PUMP (IZ-#C)
        else {
          String? imgPath = resolvedHp.defaultImagePath;
          if (imgPath.isEmpty || imgPath == 'assets/images/model_iz_4c.png') {
            final kw = resolvedHp.displayCapacityKw;
            if (kw <= 8.0) {
              final rangeMatch = effectiveSettings.models.cast<HeatPumpModel?>().firstWhere(
                (m) => (m?.displayCapacityKw ?? 0) <= 8.0 && (m?.defaultImagePath ?? '').isNotEmpty && m?.defaultImagePath != 'assets/images/model_iz_4c.png',
                orElse: () => null,
              );
              imgPath = rangeMatch?.defaultImagePath ?? effectiveSettings.domesticHpImagePath ?? 'assets/images/model_iz_4c.png';
            } else {
              final rangeMatch = effectiveSettings.models.cast<HeatPumpModel?>().firstWhere(
                (m) => (m?.displayCapacityKw ?? 0) > 8.0 && (m?.defaultImagePath ?? '').isNotEmpty,
                orElse: () => null,
              );
              imgPath = rangeMatch?.defaultImagePath ?? effectiveSettings.domesticHpImagePath ?? 'assets/images/product_iz_38c.png';
            }
          }
          if (imgPath.isNotEmpty) {
            resolvedImageBytes = await _loadImageBytes(imgPath);
          }
        }

        if (resolvedImageBytes != null) {
          productImages.add(resolvedImageBytes);
        }
      }
    }

    // Colors
    final navyColor = PdfColor.fromHex('#1E3A5F');
    final blueLink = PdfColor.fromHex('#1E88E5');
    final paleGreen = PdfColor.fromHex('#9CCC65');
    final greyText = PdfColor.fromHex('#555555');

    // ─── REUSABLE HEADER / FOOTER BUILDERS ─────────────────────────────────

    pw.Widget buildHeader({bool showSubHeader = false}) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 14,
                      height: 48,
                      color: paleGreen,
                      margin: const pw.EdgeInsets.only(right: 8),
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          companyName,
                          style: pw.TextStyle(
                            color: navyColor,
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'ADDRESS: - $companyAddress',
                          style: pw.TextStyle(
                              fontSize: 7.5,
                              color: greyText,
                              fontStyle: pw.FontStyle.italic),
                        ),
                        pw.Text(
                          'EMAIL ID: - $companyEmail',
                          style: pw.TextStyle(
                              fontSize: 7.5,
                              color: greyText,
                              fontStyle: pw.FontStyle.italic),
                        ),
                        pw.Text(
                          'CONTACT: $companyPhone${companyPhone2.isNotEmpty ? ' / $companyPhone2' : ''}',
                          style: pw.TextStyle(
                              fontSize: 7.5,
                              color: greyText,
                              fontStyle: pw.FontStyle.italic),
                        ),
                        pw.Row(
                          children: [
                            pw.Text(
                              'WEBSITE: - ',
                              style: pw.TextStyle(
                                  fontSize: 7.5,
                                  color: greyText,
                                  fontStyle: pw.FontStyle.italic),
                            ),
                            pw.Text(
                              companyWebsite,
                              style: pw.TextStyle(
                                fontSize: 7.5,
                                color: blueLink,
                                fontStyle: pw.FontStyle.italic,
                                decoration: pw.TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                if (logoBytes != null)
                  pw.Container(
                    width: 115,
                    height: 42,
                    child: pw.Image(pw.MemoryImage(logoBytes),
                        fit: pw.BoxFit.contain),
                  ),
              ],
            ),
            // Note: Quotation number and date appear exclusively at the bottom footer per requirement
          ],
        ),
      );
    }

    pw.Widget buildFooter(int pageNumber) {
      final double totalWidth = PdfPageFormat.a4.width - 36 - 36;
      const double barHeight = 11.0;
      const double slantWidth = 7.0;
      const double gap = 6.0;
      final blueColor = PdfColor.fromHex('#1C5D97');
      final goldColor = PdfColor.fromHex('#D1AA4B');

      return pw.Column(
        children: [
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 6),
            width: totalWidth,
            height: barHeight,
            child: pw.Stack(
              children: [
                pw.CustomPaint(
                  size: PdfPoint(totalWidth, barHeight),
                  painter: (canvas, size) {
                    final w = size.x;
                    final h = size.y;
                    final blueWidth = w * 0.44;

                    // Deep Blue polygon on left
                    canvas.setFillColor(blueColor);
                    canvas.moveTo(0, 0);
                    canvas.lineTo(0, h);
                    canvas.lineTo(blueWidth + slantWidth, h);
                    canvas.lineTo(blueWidth, 0);
                    canvas.closePath();
                    canvas.fillPath();

                    // Gold polygon on right
                    canvas.setFillColor(goldColor);
                    canvas.moveTo(blueWidth + gap, 0);
                    canvas.lineTo(blueWidth + slantWidth + gap, h);
                    canvas.lineTo(w, h);
                    canvas.lineTo(w, 0);
                    canvas.closePath();
                    canvas.fillPath();
                  },
                ),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(right: 28),
                    child: pw.Text(
                      '$pageNumber',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  quotation.quoteRefNo.isNotEmpty
                      ? quotation.quoteRefNo
                      : '«Quotation_Number»',
                  style:
                      const pw.TextStyle(fontSize: 7.5, color: PdfColors.black),
                ),
                if (generatedByName.isNotEmpty)
                  pw.Text(
                    'Generated by: $generatedByName',
                    style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                  ),
                pw.Text(
                  'DATE-  $dateStr',
                  style:
                      const pw.TextStyle(fontSize: 7.5, color: PdfColors.black),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final isConfirmed = quotation.status.toLowerCase() == 'confirmed';
    pw.Widget withWatermark(pw.Widget content) {
      if (isConfirmed) return content;
      return pw.Stack(
        fit: pw.StackFit.expand,
        children: [
          content,
          pw.Positioned.fill(
            child: pw.Center(
              child: pw.Transform.rotate(
                angle: -0.5,
                child: pw.Opacity(
                  opacity: 0.28,
                  child: pw.Text(
                    'DRAFT - NOT APPROVED',
                    maxLines: 1,
                    style: pw.TextStyle(
                      fontSize: 38,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.red800,
                      letterSpacing: 3.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PAGE 1: COVER (FULL BLEED)
    // ─────────────────────────────────────────────────────────────────────────
    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) {
          final custSalutation =
              quotation.salutation.isNotEmpty ? '${quotation.salutation} ' : '';
          return withWatermark(
            pw.Stack(
              children: [
                if (coverImage != null)
                  pw.Positioned.fill(
                    child: pw.Image(pw.MemoryImage(coverImage),
                        fit: pw.BoxFit.cover),
                  )
                else
                  pw.Positioned.fill(
                    child: pw.Container(color: navyColor),
                  ),
                // 1. Proposal title placed upside in the sky area, exactly as in reference image
                pw.Positioned(
                  top: 140,
                  left: 20,
                  right: 20,
                  child: pw.Center(
                    child: pw.Text(
                      'Proposal',
                      style: pw.TextStyle(
                        font: pw.Font.timesBold(),
                        color: PdfColors.white,
                        fontSize: 52,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // 2. Customer Name & Address overlay at the bottom dark banner
                pw.Positioned(
                  bottom: 125,
                  left: 36,
                  right: 36,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        'TO.',
                        style: pw.TextStyle(
                          font: pw.Font.timesBold(),
                          color: PdfColors.white,
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        '$custSalutation${quotation.customerName}',
                        style: pw.TextStyle(
                          font: pw.Font.timesBold(),
                          color: PdfColors.white,
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'Add-${quotation.customerAddress}',
                        style: pw.TextStyle(
                          font: pw.Font.timesBold(),
                          color: PdfColors.white,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    // ─────────────────────────────────────────────────────────────────────────
    // PAGE 2: OFFER LETTER (EXACT REFERENCE DESIGN)
    // ─────────────────────────────────────────────────────────────────────────
    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 24, 36, 20),
        build: (context) {
          final custSalutation = quotation.salutation.isNotEmpty
              ? '${quotation.salutation.toUpperCase()} '
              : '';
          final customerNameUpper = quotation.customerName.toUpperCase();

          return withWatermark(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                buildHeader(),
                pw.SizedBox(height: 6),

                // Centered QUOTATION Header at top in big font size
                pw.Center(
                  child: pw.Text(
                    'QUOTATION',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                pw.SizedBox(height: 10),

                // TO on left, Date & Ref block on right
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    // Left side: TO, Customer Name, Address
                    pw.Expanded(
                      flex: 5,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('TO,',
                              style: pw.TextStyle(
                                  fontSize: 9, fontWeight: pw.FontWeight.bold)),
                          pw.Text(
                            '$custSalutation$customerNameUpper',
                            style: pw.TextStyle(
                                fontSize: 9, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text(
                            'Add- ${quotation.customerAddress}',
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 16),
                    // Right side: DATE, Quote Ref No, Sales/Ref, Mob. No
                    pw.Expanded(
                      flex: 5,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'DATE-  $dateStr',
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.end,
                            children: [
                              pw.Text('Quote Ref No   : ',
                                  style: const pw.TextStyle(fontSize: 8.5)),
                              pw.Text(quotation.quoteRefNo,
                                  style: const pw.TextStyle(fontSize: 8.5)),
                            ],
                          ),
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.end,
                            children: [
                              pw.Text('Sales/Ref      : ',
                                  style: const pw.TextStyle(fontSize: 8.5)),
                              pw.Text(quotation.salesRef,
                                  style: const pw.TextStyle(fontSize: 8.5)),
                            ],
                          ),
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.end,
                            children: [
                              pw.Text('Mob. No        : ',
                                  style: const pw.TextStyle(fontSize: 8.5)),
                              pw.Text(quotation.salesMobile,
                                  style: const pw.TextStyle(fontSize: 8.5)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                pw.SizedBox(height: 12),

                // Subject line
                pw.RichText(
                  text: pw.TextSpan(
                    text: 'Subject: ',
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold),
                    children: [
                      pw.TextSpan(
                        text: quotation.subjectLine,
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 10),

                // Salutation & Intro
                pw.Text('Dear Sir', style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 5),
                pw.Text(
                  '    We thank you for the discussion regarding the supply of Energy Efficient "IZYHEAT" Heat Pump Water Heating Solutions for your Project. We would like to briefly present a summary of the technology that we propose as well as related cost benefits that you would derive from our solutions in response to detailed study Discussion; we are submitting our Quotation along with specifications suitable to your requirement.',
                  style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.35),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  '    Please find attached the brief presentation with summary of the technology that we propose as well as related cost benefits that you would derive from our solutions. Further we are pleased to attach herewith a quotation for your reference & speedy decision.',
                  style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.35),
                ),

                pw.SizedBox(height: 12),

                // COMPANY PROFILE
                pw.Text(
                  'COMPANY PROFILE:',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    decoration: pw.TextDecoration.underline,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  '    "$companyName", under the brand Name "${settings.brandName}" Heat Pump the manufacturers of Heat Pump System is a 15 year old company that has been a market leader and a pioneer in the Heat Pump water heater system industry. It is one of the leading brands of water heaters in India and stands for Quality, Reliability and Performance. It is in house product since 2008.',
                  style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.35),
                ),

                pw.SizedBox(height: 14),

                // Annexures list
                ...annexureEntries.map((e) {
                  String roman = e.romanNumeral;
                  if (!roman.contains('–') && !roman.contains('-')) {
                    roman = roman.replaceFirst('Annexure ', 'Annexure – ');
                  }
                  String desc;
                  if (e.romanNumeral == 'Annexure I' ||
                      e.romanNumeral.endsWith(' I')) {
                    desc = 'PRICE AND EXCLUSIONS ( OFFER 1 )';
                  } else if (e.title.contains('Technical') ||
                      e.title.contains('Specifications')) {
                    if (quotation.quoteType == QuoteType.hpWithTank) {
                      desc = hasTank
                          ? 'Technical Specifications. ( Heat Pump & Tank)'
                          : 'Technical Specifications (Heat Pump)';
                    } else if (quotation.quoteType == QuoteType.hpOnly) {
                      desc = 'Technical Specifications (Heat Pump)';
                    } else if (quotation.quoteType == QuoteType.tankOnly) {
                      desc = 'Technical Specifications (Storage Tank)';
                    } else if (quotation.quoteType == QuoteType.swimmingPool) {
                      desc =
                          'Technical Specifications (Swimming Pool Heat Pump)';
                    } else {
                      desc =
                          'Technical Specifications. (${quotation.model.modelName})';
                    }
                  } else {
                    desc = 'Commercial terms and conditions & Warranty.';
                  }
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 16, bottom: 3),
                    child: pw.Text(
                      '$roman: $desc',
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold),
                    ),
                  );
                }),

                pw.SizedBox(height: 14),

                // Signoff & Contact Details
                pw.Text(
                  companyName,
                  style: pw.TextStyle(
                    color: navyColor,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Mob: $companyPhone${companyPhone2.isNotEmpty ? ' / $companyPhone2' : ''}',
                  style: const pw.TextStyle(fontSize: 8.5),
                ),
                pw.Row(
                  children: [
                    pw.Text('Web: ', style: const pw.TextStyle(fontSize: 8.5)),
                    pw.Text(
                      companyWebsite,
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        color: blueLink,
                        decoration: pw.TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
                pw.Text('Email: $companyEmail',
                    style: const pw.TextStyle(fontSize: 8.5)),
                pw.SizedBox(height: 6),
                pw.Row(
                  children: [
                    pw.Text('Follow us on:   ',
                        style: const pw.TextStyle(fontSize: 8.5)),
                    if (fbIcon != null)
                      pw.Container(
                        width: 14,
                        height: 14,
                        margin: const pw.EdgeInsets.only(right: 6),
                        child: pw.Image(pw.MemoryImage(fbIcon)),
                      ),
                    if (igIcon != null)
                      pw.Container(
                        width: 14,
                        height: 14,
                        child: pw.Image(pw.MemoryImage(igIcon)),
                      ),
                  ],
                ),

                pw.Spacer(),
                buildFooter(offerLetterPage),
              ],
            ),
          );
        },
      ),
    );

    // ─────────────────────────────────────────────────────────────────────────
    // PAGE 3: ANNEXURE I (PRICE SCHEDULE) + ANNEXURE II (HP SPECS)
    // ─────────────────────────────────────────────────────────────────────────
    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 24, 36, 20),
        build: (context) {
          if (quotation.quoteType == QuoteType.hpWithTank ||
              quotation.quoteType == QuoteType.hpOnly) {
            return withWatermark(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  buildHeader(showSubHeader: true),
                  pw.Text(
                    'Annexure – I: Price and exclusions Offer 1',
                    style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        decoration: pw.TextDecoration.underline),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.black, width: 0.6),
                    ),
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1.5),
                    child: pw.Text('OFFER',
                        style: pw.TextStyle(
                            fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(height: 4),

                  // 8-Column Price Schedule Table
                  _build8ColumnPriceSchedule(quotation),

                  pw.SizedBox(height: 8),

                  // Annexure II HP Technical Specifications immediately beneath
                  pw.Text(
                    'Annexure – II',
                    style: pw.TextStyle(
                        fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 1.5),
                  _buildHpSpecTable(quotation.copyWith(model: resolvedHp), effectiveSettings),

                  // For HP Only, show Banner immediately beneath to fill empty space
                  if (quotation.quoteType == QuoteType.hpOnly && bannerImage != null) ...[
                    pw.SizedBox(height: 10),
                    pw.Container(
                      height: 150,
                      width: double.infinity,
                      child: pw.Image(pw.MemoryImage(bannerImage),
                          fit: pw.BoxFit.fill),
                    ),
                  ],

                  pw.Spacer(),
                  buildFooter(priceSchedulePage),
                ],
              ),
            );
          } else {
            // Flexible layout for other types (allInOne, swimmingPool, tankOnly, etc.)
            return withWatermark(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  buildHeader(showSubHeader: true),
                  pw.Text(
                    'Annexure – I: Price and exclusions Offer 1',
                    style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        decoration: pw.TextDecoration.underline),
                  ),
                  pw.SizedBox(height: 4),
                  _buildGenericPriceTable(quotation, config, effectiveSettings),

                  // Annexure II immediately beneath price table on the same page (No big empty space)
                  if (config.hasTechnicalSpecs) ...[
                    pw.SizedBox(height: 8),
                    if (config.specMode == SpecMode.allInOne) ...[
                      pw.Text(
                        'Annexure – II: TECHNICAL SPECIFICATION FOR : ALL IN ONE HEAT PUMP – ${resolvedAio?.modelName ?? "All in one 200Ltr"}',
                        style: pw.TextStyle(
                            fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 2),
                      _buildAllInOneSpecTable(resolvedAio ??
                          AllInOneModel.defaultFloorModel()),
                    ] else if (config.specMode == SpecMode.swimmingPool) ...[
                      pw.Text(
                        'Annexure – II: TECHNICAL SPECIFICATION FOR : SWIMMING POOL HEAT PUMP – ${resolvedPool?.modelName ?? "IZ-35SP"}',
                        style: pw.TextStyle(
                            fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 2),
                      _buildPoolSpecTable(resolvedPool ??
                          PoolHeatPumpModel.defaultModel()),
                    ] else if (config.specMode == SpecMode.tankOnly) ...[
                      pw.Text(
                        'Annexure – II: TECHNICAL SPECIFICATION FOR : HOT WATER STORAGE TANK',
                        style: pw.TextStyle(
                            fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 2),
                      _buildMergedTankSpecTable(quotation),
                    ],
                  ],

                  // Insiya Showcase Banner on same page to eliminate empty space
                  if (bannerImage != null) ...[
                    pw.SizedBox(height: 10),
                    pw.Container(
                      height: 150,
                      width: double.infinity,
                      child: pw.Image(pw.MemoryImage(bannerImage),
                          fit: pw.BoxFit.fill),
                    ),
                  ],

                  pw.Spacer(),
                  buildFooter(priceSchedulePage),
                ],
              ),
            );
          }
        },
      ),
    );

    // ─────────────────────────────────────────────────────────────────────────
    // PAGE 4: TANK TECHNICAL SPECIFICATIONS + BANNER (ONLY IF TANK ADDED)
    // ─────────────────────────────────────────────────────────────────────────
    if (quotation.quoteType == QuoteType.hpWithTank && hasTank) {
      pdf.addPage(
        pw.Page(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(36, 24, 36, 20),
          build: (context) {
            final tanks = quotation.effectiveTanks;
            final isMultiTank = tanks.length > 1;
            final titleMat = tanks.isNotEmpty
                ? tanks.first.innerTankMaterial
                : (quotation.tankSpec.innerTankMaterial.isNotEmpty
                    ? quotation.tankSpec.innerTankMaterial
                    : 'GI');

            return withWatermark(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  buildHeader(showSubHeader: true),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'TECHNICAL SPECIFICATION FOR : ${isMultiTank ? 'HOT WATER STORAGE TANK.' : '$titleMat HOT WATER STORAGE TANK.'}',
                    style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        decoration: pw.TextDecoration.underline),
                  ),
                  pw.SizedBox(height: 6),

                  // Merged Tank Specification Table (10 rows, multi-column support)
                  _buildMergedTankSpecTable(quotation),

                  pw.SizedBox(height: 18),

                  // Insiya Banner
                  if (bannerImage != null)
                    pw.Container(
                      height: 190,
                      width: double.infinity,
                      child: pw.Image(pw.MemoryImage(bannerImage),
                          fit: pw.BoxFit.fill),
                    ),

                  pw.Spacer(),
                  buildFooter(tankSpecPage!),
                ],
              ),
            );
          },
        ),
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TERMS & CONDITIONS & WARRANTY PAGE
    // ─────────────────────────────────────────────────────────────────────────
    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 24, 36, 20),
        build: (context) {
          final termsTitle = (quotation.quoteType == QuoteType.partsOnly)
              ? 'ANNEXURE – II: COMMERCIAL TERMS AND CONDITIONS & WARRANTY.'
              : 'Annexure – III: Commercial terms and conditions & Warranty.';

          // Payment sentence with quirk 'satisfactoryinstallation and commissioning'
          final paymentSentence = quotation.paymentTerms.isNotEmpty
              ? QgPaymentSentenceBuilder.buildSentence(
                  paymentTerms: quotation.paymentTerms,
                  isAnnexureQuirk: true,
                )
              : QgPaymentSentenceBuilder.buildFromSplits(
                  advance: quotation.paymentSplitAdvance,
                  delivery: quotation.paymentSplitDelivery,
                  commissioning: quotation.paymentSplitCommissioning,
                  isAnnexureQuirk: true,
                );

          String warrantyText;
          if (quotation.quoteType == QuoteType.allInOneFloor ||
              quotation.quoteType == QuoteType.allInOneWall) {
            warrantyText =
                '${quotation.warrantyHpYears} YEAR FOR HEAT PUMP AND 5 YEARS OF COMPRESSOR.';
          } else if (quotation.quoteType == QuoteType.partsOnly) {
            warrantyText = '1 YEAR FOR REPLACED PARTS.';
          } else if (quotation.quoteType == QuoteType.tankOnly) {
            warrantyText = '${quotation.warrantyTankYears} YEARS FOR TANK.';
          } else if (quotation.quoteType == QuoteType.hpOnly ||
              quotation.quoteType == QuoteType.swimmingPool ||
              !hasTank) {
            warrantyText = '${quotation.warrantyHpYears} YEAR FOR HEAT PUMP.';
          } else {
            warrantyText =
                '${quotation.warrantyHpYears} YEAR FOR HEAT PUMP, ${quotation.warrantyTankYears} YEARS FOR TANK .';
          }

          final termsList = quotation.termsAndConditions.isNotEmpty
              ? quotation.termsAndConditions
              : [
                  'Proper 1 / 3 Phase power should be arranged where you install the heat pump.',
                  'Electrical/civil/plumbing work materials – Customer Scope.',
                  'Safe storage place need to be provided by you to keep our material & tools.',
                  'All Interconnected pipe lines between system and Tank Your Scope but our team will do the installation. (If applicable): Included',
                ];

          return withWatermark(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                buildHeader(showSubHeader: true),
                pw.SizedBox(height: 6),
                pw.Text(
                  termsTitle,
                  style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                      decoration: pw.TextDecoration.underline),
                ),
                pw.SizedBox(height: 12),

                // Payment Terms
                pw.Text('Payment Terms :',
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 6),
                  child: pw.Text(paymentSentence,
                      style:
                          const pw.TextStyle(fontSize: 8.5, lineSpacing: 1.35)),
                ),

                pw.SizedBox(height: 12),

                // Warranty
                pw.Text('WARRANTY:- $warrantyText',
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold)),

                pw.SizedBox(height: 12),

                // Other Terms & Conditions
                pw.Text('Other Terms & Conditions:',
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 5),
                ...termsList.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final text = entry.value;
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 3.5, left: 6),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('$idx.  ',
                            style: const pw.TextStyle(fontSize: 8.5)),
                        pw.Expanded(
                            child: pw.Text(text,
                                style: const pw.TextStyle(
                                    fontSize: 8.5, lineSpacing: 1.25))),
                      ],
                    ),
                  );
                }),

                pw.SizedBox(height: 12),

                // Validity Of Offer
                pw.Text('Validity Of Offer :',
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 6),
                  child: pw.Text(
                    'Prices quoted are firm and generally valid for ${quotation.validityDays} days from date of offer. After this prices are subject to your confirmation.',
                    style: const pw.TextStyle(fontSize: 8.5, lineSpacing: 1.3),
                  ),
                ),

                pw.SizedBox(height: 12),

                // Bank Details
                pw.Text(
                  'OUR BANK ACCOUNT DETAILS:',
                  style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      decoration: pw.TextDecoration.underline),
                ),
                pw.SizedBox(height: 5),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 6),
                  child: pw.Table(
                    columnWidths: {
                      0: const pw.FixedColumnWidth(110),
                      1: const pw.FixedColumnWidth(16),
                      2: const pw.FlexColumnWidth(),
                    },
                    children: [
                      _bankRow('Account Name', bankAccountName),
                      _bankRow('Bank Name', '$bankName,'),
                      _bankRow('Account Number', bankAccountNumber),
                      _bankRow('Branch', '$bankBranch,'),
                      _bankRow('IFSC Code', bankIfsc),
                    ],
                  ),
                ),

                pw.SizedBox(height: 12),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 6),
                  child: pw.Text(
                    'We hope you will find our quotation very competitive and favor us with your valued order at early date andindulge.',
                    style: const pw.TextStyle(fontSize: 8.5),
                  ),
                ),

                pw.SizedBox(height: 12),
                pw.Text('Thanks & Regard',
                    style: const pw.TextStyle(fontSize: 9)),
                pw.Text('For', style: const pw.TextStyle(fontSize: 9)),
                pw.Text(companyName,
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),

                if (stampImage != null)
                  pw.Container(
                    width: 65,
                    height: 65,
                    child: pw.Image(pw.MemoryImage(stampImage)),
                  ),

                pw.Spacer(),
                buildFooter(termsPage),
              ],
            ),
          );
        },
      ),
    );

    // ─────────────────────────────────────────────────────────────────────────
    // QUOTATION ACCEPTANCE LETTER
    // ─────────────────────────────────────────────────────────────────────────
    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 24, 36, 20),
        build: (context) {
          final totalFormatted =
              PriceCalculator.formatIndianCurrency(quotation.netPayable);

          // Payment sentence with standard space 'satisfactory installation and commissioning'
          final acceptancePaymentSentence = quotation.paymentTerms.isNotEmpty
              ? QgPaymentSentenceBuilder.buildSentence(
                  paymentTerms: quotation.paymentTerms,
                  isAnnexureQuirk: false,
                )
              : QgPaymentSentenceBuilder.buildFromSplits(
                  advance: quotation.paymentSplitAdvance,
                  delivery: quotation.paymentSplitDelivery,
                  commissioning: quotation.paymentSplitCommissioning,
                  isAnnexureQuirk: false,
                );

          return withWatermark(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                buildHeader(showSubHeader: false),
                pw.SizedBox(height: 16),
                pw.Center(
                  child: pw.Text(
                    'QUOTATION ACCEPTANCE LETTER',
                    style: pw.TextStyle(
                        fontSize: 12.5,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.8),
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Row(
                  children: [
                    pw.Text('Customer Name: ',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.Text(quotation.customerName,
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Row(
                  children: [
                    pw.Text('Customer Address: ',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.Text(quotation.customerAddress,
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 14),
                pw.Text('Date: $dateStr',
                    style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 14),
                pw.Text('Subject: ${quotation.acceptanceSubjectLine}',
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 3),
                pw.Text('Model No ${quotation.model.modelName}',
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 14),
                pw.Text('Dear Sir,', style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 6),
                pw.Text(
                  'With reference to quotation number ${quotation.quoteRefNo} dated $dateStr, with Quotation Value $totalFormatted, I’m glad to inform you that your quote has been Approved for the corresponding project,',
                  style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.35),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'With Term conditions of Payment: $acceptancePaymentSentence',
                  style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.35),
                ),
                pw.SizedBox(height: 16),
                pw.Text('Looking forward to doing business with you.',
                    style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 28),
                pw.Text('Yours sincerely,',
                    style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 3),
                pw.Text(quotation.customerName,
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text('Mob. No:- ${quotation.customerMobile}',
                    style: const pw.TextStyle(fontSize: 9)),
                pw.Spacer(),
                buildFooter(acceptPage),
              ],
            ),
          );
        },
      ),
    );

    // ─────────────────────────────────────────────────────────────────────────
    // PRODUCT IMAGE PAGE
    // ─────────────────────────────────────────────────────────────────────────
    if (quotation.includeProductImagePage) {
      pdf.addPage(
        pw.Page(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(36, 24, 36, 20),
          build: (context) {
            final mainImg =
                productImages.isNotEmpty ? productImages.first : product38c;

            return withWatermark(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  buildHeader(showSubHeader: true),
                  pw.SizedBox(height: 8),
                  pw.Center(
                    child: pw.Text(
                      'Product Image',
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.SizedBox(height: 16),
                  if (mainImg != null)
                    pw.Center(
                      child: pw.Container(
                        height: 440,
                        width: double.infinity,
                        child: pw.Image(pw.MemoryImage(mainImg),
                            fit: pw.BoxFit.contain),
                      ),
                    ),
                  pw.Spacer(),
                  buildFooter(showcasePage!),
                ],
              ),
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  // ─── 8-COLUMN PRICE SCHEDULE TABLE (hpWithTank / hpOnly) ──────────────────

  static pw.Widget _build8ColumnPriceSchedule(GeneratorQuotation q) {
    int rowIdx = 1;
    final tableRows = <pw.TableRow>[];

    // Header Row
    tableRows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E8E8E8')),
        children: [
          _th('S.\nno.'),
          _th('DESCRIPTION'),
          _th('System\nLPH'),
          _th('HP KW'),
          _th('Qty'),
          _th('Rate/\nLiter'),
          _th('System Rate'),
          _th('AMOUNT'),
        ],
      ),
    );

    pw.TableRow buildExtraRow(String sr, String desc,
        {String qty = '',
        String rateStr = '',
        String amtStr = '',
        bool isExtra = false}) {
      return pw.TableRow(
        children: [
          _tc(sr, center: true),
          _tc(desc),
          _tc('', center: true),
          _tc('', center: true),
          _tc(qty, center: true),
          _tc('', center: true),
          _tc(rateStr, center: true),
          _tc(amtStr.isNotEmpty ? amtStr : (isExtra ? 'Extra' : 'Included'),
              center: true),
        ],
      );
    }

    if (q.priceRows.isNotEmpty) {
      // Render EVERY item from priceRows
      for (final r in q.priceRows) {
        final dLower = r.description.toLowerCase();
        final isHp = r.hpKw != null ||
            r.metadata?['type'] == 'heatPump' ||
            (dLower.contains('heat pump') && !dLower.contains('tank')) ||
            dLower.contains('air source') ||
            dLower.startsWith('iz-');
        final isTank = !isHp &&
            (r.systemLph != null ||
                r.metadata?['type'] == 'tank' ||
                dLower.contains('tank') ||
                dLower.contains('storage'));

        pw.Widget descWidget;
        String lphStr = '';
        String kwStr = '';
        String qtyStr = r.qty > 0 ? '${r.qty}' : '1';
        String rateStr = '';
        String amtStr = '';

        if (isHp) {
          final kwVal = r.hpKw ??
              (r.metadata?['kw'] as num?)?.toDouble() ??
              q.model.displayCapacityKw;
          final kwFormatted =
              (kwVal == kwVal.toInt()) ? '${kwVal.toInt()}' : '$kwVal';
          final modelName =
              r.metadata?['hpModel']?.toString() ?? q.model.modelName;
          final powerSupply = q.model.powerSupply;
          final powerInput = q.model.specs['Rated Input Power'] ?? '8.75kw';

          descWidget = pw.Padding(
            padding:
                const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Air Source Heat pump ${kwFormatted}kw',
                    style: pw.TextStyle(
                        fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                    'Make: IZYHEAT Heat Pump Model: $modelName ${kwFormatted}kw',
                    style: const pw.TextStyle(fontSize: 7.5)),
                pw.Text(
                    'Power Input $powerInput, output ${kwFormatted}kw, $powerSupply, 50Hz With Auto Defrost.',
                    style: const pw.TextStyle(fontSize: 7.5)),
              ],
            ),
          );
          kwStr = kwVal.toStringAsFixed(2);
        } else if (isTank) {
          final tankCap = r.systemLph ??
              (r.metadata?['capacityLitres'] as num?)?.toInt() ??
              q.tankCapacityLitres;
          final mat = r.metadata?['tankMaterial']?.toString() ??
              (q.tankSpec.innerTankMaterial.isNotEmpty
                  ? q.tankSpec.innerTankMaterial
                  : 'GI');
          final isPress =
              r.metadata?['isPressurized'] as bool? ?? q.isTankPressurized;
          final pressStr = isPress ? 'Pressurized' : 'Non-Pressurized';
          final shellThick =
              (mat == 'Enamel') ? '2mm' : (mat == 'MS' ? '5mm' : '3mm');

          descWidget = pw.Padding(
            padding:
                const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 4),
            child: pw.Text(
              '$tankCap  LTR Capacity, $mat $pressStr Tank, $shellThick Shell, and $shellThick Dish, , Thickness,19mm IC CLAD insulation.',
              style: const pw.TextStyle(fontSize: 7.5),
            ),
          );
          lphStr = '$tankCap';
        } else {
          descWidget = pw.Padding(
            padding:
                const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 4),
            child: pw.Text(r.description,
                style: const pw.TextStyle(fontSize: 7.5)),
          );
          qtyStr = r.qty > 0 ? '${r.qty}' : '';
        }

        if (r.rate > 0) {
          rateStr = PriceCalculator.formatIndianCurrency(r.rate);
        } else if (r.amount > 0 && r.qty > 0) {
          rateStr =
              PriceCalculator.formatIndianCurrency((r.amount / r.qty).round());
        }

        if (r.amount > 0) {
          amtStr = PriceCalculator.formatIndianCurrency(r.amount);
        } else if (r.rate > 0) {
          amtStr = PriceCalculator.formatIndianCurrency(
              r.rate * (r.qty > 0 ? r.qty : 1));
        }

        tableRows.add(
          pw.TableRow(
            children: [
              _tc((rowIdx++).toString().padLeft(2, '0'), center: true),
              descWidget,
              _tc(lphStr, center: true),
              _tc(kwStr, center: true),
              _tc(qtyStr, center: true),
              _tc('', center: true),
              _tc(rateStr, center: true),
              _tc(amtStr.isEmpty ? 'Included' : amtStr, center: true),
            ],
          ),
        );
      }
    } else {
      // Fallback for legacy quotation
      final hpKwInt = q.model.displayCapacityKw.toInt();
      final hpRatedPower = q.model.specs['Rated Input Power'] ?? '8.75kw';
      final hasTank = q.hasTank;
      final tankCap = q.tankCapacityLitres > 0 ? q.tankCapacityLitres : 3000;
      final tankQty = q.tankQty > 0 ? q.tankQty : 2;
      final innerMat = q.tankSpec.innerTankMaterial.isNotEmpty
          ? q.tankSpec.innerTankMaterial
          : 'GI';
      final pressStr = q.isTankPressurized ? 'Pressurized' : 'Non-Pressurized';

      int hpRate = q.heatPumpNumericPrice > 0
          ? q.heatPumpNumericPrice
          : (hasTank ? 0 : q.subtotal);
      final hpQty = q.heatPumpQty > 0 ? q.heatPumpQty : 1;
      final hpAmount = hpRate * hpQty;

      String hpRateStr =
          hpRate > 0 ? PriceCalculator.formatIndianCurrency(hpRate) : '';
      String hpAmountStr =
          hpAmount > 0 ? PriceCalculator.formatIndianCurrency(hpAmount) : '';

      tableRows.add(
        pw.TableRow(
          children: [
            _tc((rowIdx++).toString().padLeft(2, '0'), center: true),
            pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 4),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Air Source Heat pump ${hpKwInt}kw',
                      style: pw.TextStyle(
                          fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                      'Make: IZYHEAT Heat Pump Model: ${q.model.modelName} ${hpKwInt}kw',
                      style: const pw.TextStyle(fontSize: 7.5)),
                  pw.Text(
                      'Power Input $hpRatedPower, output ${hpKwInt}kw, ${q.model.powerSupply}, 50Hz With Auto Defrost.',
                      style: const pw.TextStyle(fontSize: 7.5)),
                ],
              ),
            ),
            _tc('', center: true),
            _tc(q.model.displayCapacityKw.toStringAsFixed(2), center: true),
            _tc('$hpQty', center: true),
            _tc('', center: true),
            _tc(hpRateStr, center: true),
            _tc(hpAmountStr.isEmpty ? 'Included' : hpAmountStr, center: true),
          ],
        ),
      );

      if (hasTank) {
        tableRows.add(
          pw.TableRow(
            children: [
              _tc((rowIdx++).toString().padLeft(2, '0'), center: true),
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 4),
                child: pw.Text(
                  '$tankCap  LTR Capacity, $innerMat $pressStr Tank, 3mm Shell, and 3mm Dish, , Thickness,19mm IC CLAD insulation.',
                  style: const pw.TextStyle(fontSize: 7.5),
                ),
              ),
              _tc('$tankCap', center: true),
              _tc('', center: true),
              _tc('$tankQty', center: true),
              _tc('', center: true),
              _tc(PriceCalculator.formatIndianCurrency(q.tankRate),
                  center: true),
              _tc(PriceCalculator.formatIndianCurrency(q.tankRate * tankQty),
                  center: true),
            ],
          ),
        );
      }
    }

    // Supplementary Items: ONLY those that are actually added!
    int supplementaryTotal = 0;
    if (q.extraPriceRows.isNotEmpty) {
      for (final it in q.extraPriceRows) {
        String desc = it.description.trim();
        final hadExtraInDesc = desc.toLowerCase().contains('extra');
        desc = desc
            .replaceAll(
                RegExp(r'\s*-\s*(Extra|Included)', caseSensitive: false), '')
            .trim();
        final isExtraSelection = it.amountType == PriceRowType.extra ||
            hadExtraInDesc ||
            (it.amountType == PriceRowType.customText &&
                it.customText.toLowerCase().contains('extra'));
        final isCharged = (it.amountType == PriceRowType.extra ||
                it.amountType == PriceRowType.amount) &&
            it.numericAmount > 0;
        final amt = isCharged
            ? PriceCalculator.formatIndianCurrency(it.numericAmount)
            : '';
        if (isCharged) {
          supplementaryTotal += it.numericAmount;
        }
        final qtyVal = int.tryParse(it.qty) ?? 0;
        final qtyStr =
            qtyVal > 0 ? '$qtyVal' : (it.qty.isNotEmpty ? it.qty : '1');
        final rateStr = it.systemRate.isNotEmpty
            ? it.systemRate
            : (isCharged
                ? (qtyVal > 0
                    ? PriceCalculator.formatIndianCurrency(
                        (it.numericAmount / qtyVal).round())
                    : amt)
                : '');
        tableRows.add(buildExtraRow(
          (rowIdx++).toString().padLeft(2, '0'),
          desc,
          qty: qtyStr,
          rateStr: rateStr,
          amtStr: amt,
          isExtra: isExtraSelection,
        ));
      }
    } else {
      // Check priceRows for supplementary items (skip HP and Tank)
      for (final r in q.priceRows) {
        final d = r.description.toLowerCase();
        if (d.contains('heat pump') ||
            d.contains('air source') ||
            d.contains('iz-')) continue;
        if (d.contains('tank') || d.contains('storage')) continue;
        if (r.description == '-' || r.description.trim().isEmpty) continue;

        String desc = r.description.trim();
        final hadExtraInDesc = desc.toLowerCase().contains('extra');
        desc = desc
            .replaceAll(
                RegExp(r'\s*-\s*(Extra|Included)', caseSensitive: false), '')
            .trim();
        final isExtraSelection =
            r.status == PriceRowStatus.extra || hadExtraInDesc;
        final isCharged = (r.status == PriceRowStatus.extra ||
                r.status == PriceRowStatus.priced) &&
            r.amount > 0;
        final amt =
            isCharged ? PriceCalculator.formatIndianCurrency(r.amount) : '';
        if (isCharged) {
          supplementaryTotal += r.amount;
        }
        final qtyStr = r.qty > 0 ? '${r.qty}' : '1';
        final rateStr =
            r.rate > 0 ? PriceCalculator.formatIndianCurrency(r.rate) : '';
        tableRows.add(buildExtraRow(
          (rowIdx++).toString().padLeft(2, '0'),
          desc,
          qty: qtyStr,
          rateStr: rateStr,
          amtStr: amt,
          isExtra: isExtraSelection,
        ));
      }
    }

    return pw.Column(
      children: [
        pw.Table(
          border: const pw.TableBorder(
            left: pw.BorderSide(color: PdfColors.black, width: 0.6),
            right: pw.BorderSide(color: PdfColors.black, width: 0.6),
            top: pw.BorderSide(color: PdfColors.black, width: 0.6),
            bottom: pw.BorderSide(color: PdfColors.black, width: 0.6),
            horizontalInside: pw.BorderSide(color: PdfColors.black, width: 0.6),
            verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.6),
          ),
          columnWidths: {
            0: const pw.FixedColumnWidth(26),
            1: const pw.FixedColumnWidth(215),
            2: const pw.FixedColumnWidth(42),
            3: const pw.FixedColumnWidth(38),
            4: const pw.FixedColumnWidth(24),
            5: const pw.FixedColumnWidth(42),
            6: const pw.FixedColumnWidth(58),
            7: const pw.FixedColumnWidth(62),
          },
          children: tableRows,
        ),

        // Totals Block directly beneath
        pw.Table(
          border: const pw.TableBorder(
            left: pw.BorderSide(color: PdfColors.black, width: 0.6),
            right: pw.BorderSide(color: PdfColors.black, width: 0.6),
            bottom: pw.BorderSide(color: PdfColors.black, width: 0.6),
            horizontalInside: pw.BorderSide(color: PdfColors.black, width: 0.6),
            verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.6),
          ),
          columnWidths: {
            0: const pw.FixedColumnWidth(445),
            1: const pw.FixedColumnWidth(62),
          },
          children: [
            pw.TableRow(
              children: [
                pw.Container(
                  alignment: pw.Alignment.centerRight,
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 2.5, horizontal: 8),
                  child: pw.Text('Sub Total',
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Container(
                  alignment: pw.Alignment.center,
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 2.5, horizontal: 4),
                  child: pw.Text(
                      PriceCalculator.formatIndianCurrency(q.subtotal),
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ),
              ],
            ),
            if (supplementaryTotal > 0)
              pw.TableRow(
                children: [
                  pw.Container(
                    alignment: pw.Alignment.centerRight,
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 2.5, horizontal: 8),
                    child: pw.Text('Supplementary Charges',
                        style: pw.TextStyle(
                            fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Container(
                    alignment: pw.Alignment.center,
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 2.5, horizontal: 4),
                    child: pw.Text(
                        PriceCalculator.formatIndianCurrency(
                            supplementaryTotal),
                        style: pw.TextStyle(
                            fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  ),
                ],
              ),
            pw.TableRow(
              children: [
                pw.Container(
                  alignment: pw.Alignment.centerRight,
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 2.5, horizontal: 8),
                  child: pw.Text('GST 18%',
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Container(
                  alignment: pw.Alignment.center,
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 2.5, horizontal: 4),
                  child: pw.Text(
                      PriceCalculator.formatIndianCurrency(q.gstAmount),
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ),
              ],
            ),
            pw.TableRow(
              children: [
                pw.Container(
                  alignment: pw.Alignment.centerRight,
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 2.5, horizontal: 8),
                  child: pw.Text('TOTAL',
                      style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          decoration: pw.TextDecoration.underline)),
                ),
                pw.Container(
                  alignment: pw.Alignment.center,
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 2.5, horizontal: 4),
                  child: pw.Text(
                      PriceCalculator.formatIndianCurrency(q.grandTotal),
                      style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          decoration: pw.TextDecoration.underline)),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ─── MERGED TANK SPECIFICATION TABLE (Page 4) ──────────────────────────────

  // ─── MERGED TANK SPECIFICATION TABLE (Page 4) ──────────────────────────────

  static pw.Widget _buildMergedTankSpecTable(GeneratorQuotation q) {
    final tanks = q.effectiveTanks;
    if (tanks.isEmpty) return pw.SizedBox.shrink();

    if (tanks.length == 1) {
      return _buildSingleTankTableExact(tanks.first);
    }

    return pw.Column(
      children: tanks
          .map((t) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: _buildSingleTankTableExact(t),
              ))
          .toList(),
    );
  }

  static pw.Widget _buildSingleTankTableExact(TankLineItem tank) {
    const double rowH = 19.5;
    const double col0W = 32.0;
    const double col1W = 110.0;
    const double col2W = 145.0;
    const double specW = 523.28 - col0W - col1W - col2W; // 236.28 pt

    final pressStr = tank.isPressurized ? 'Pressurized' : 'Non-Pressurized';
    final mat =
        tank.innerTankMaterial.isNotEmpty ? tank.innerTankMaterial : 'GI';
    final rawThick =
        tank.innerTankThickness.isNotEmpty ? tank.innerTankThickness : '3mm';
    final thick = RegExp(r'\d+\s*mm', caseSensitive: false)
            .firstMatch(rawThick)
            ?.group(0) ??
        '3mm';
    final cap = tank.capacityLitres;

    final insMat = tank.insulationMaterial.isNotEmpty &&
            tank.insulationMaterial.toLowerCase() != '19mm ic clad insulation'
        ? (tank.insulationMaterial.toLowerCase().contains('puff') ||
                tank.insulationMaterial.toLowerCase().contains('puf')
            ? 'PUF'
            : tank.insulationMaterial)
        : 'PUF';

    final all10Rows = [
      ('01', 'Capacity and Thickness', '$cap ltr, $thick Shell, $thick Dish.'),
      (
        '02',
        'Operating pressure',
        tank.isPressurized ? 'Up to 5 Bar' : 'Atmospheric'
      ),
      (
        '03',
        'Testing Pressure',
        tank.isPressurized ? '7 bar pressure' : 'Atmospheric'
      ),
      ('04', 'Hot Water Inlet/ outlet', '2 Inch,'),
      ('05', 'Heat Pump Circulation', '1 Inch,'),
      ('06', 'Outer Tank Insulation', insMat),
      ('07', 'Temperature drop', '3° C / 8 hour'),
      ('08', 'Inner and outer Tank', mat),
      ('09', 'Tank direction', 'Horizontal / Vertical'),
      ('10', 'Other', 'Solar Provision Additional Heat Pump Provision'),
    ];

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.6),
      ),
      child: pw.Column(
        children: [
          // Header Row
          pw.Container(
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#E8E8E8'),
              border: const pw.Border(
                bottom: pw.BorderSide(color: PdfColors.black, width: 0.6),
              ),
            ),
            child: pw.Row(
              children: [
                pw.Container(
                  width: col0W,
                  height: 22.0,
                  alignment: pw.Alignment.center,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      right: pw.BorderSide(color: PdfColors.black, width: 0.6),
                    ),
                  ),
                  child: pw.Text(
                    'SL\nNO',
                    style: pw.TextStyle(
                        fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Container(
                  width: col1W + col2W,
                  height: 22.0,
                  alignment: pw.Alignment.center,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      right: pw.BorderSide(color: PdfColors.black, width: 0.6),
                    ),
                  ),
                  child: pw.Text(
                    'DESCRIPTION',
                    style: pw.TextStyle(
                        fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Container(
                  width: specW,
                  height: 22.0,
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    'SPECIFICATION',
                    style: pw.TextStyle(
                        fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          // Body: Single Row with Col 0, Merged Col 1, Col 2, Col 3
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Col 0: SL NO 01..10
              pw.Column(
                children: all10Rows.asMap().entries.map((e) {
                  final isLast = e.key == all10Rows.length - 1;
                  return pw.Container(
                    width: col0W,
                    height: rowH,
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        right: const pw.BorderSide(
                            color: PdfColors.black, width: 0.6),
                        bottom: isLast
                            ? pw.BorderSide.none
                            : const pw.BorderSide(
                                color: PdfColors.black, width: 0.6),
                      ),
                    ),
                    child: pw.Text(e.value.$1,
                        style: const pw.TextStyle(fontSize: 7.5),
                        textAlign: pw.TextAlign.center),
                  );
                }).toList(),
              ),

              // Col 1: Big merged centered block spanning all 10 rows
              pw.Container(
                width: col1W,
                height: all10Rows.length * rowH,
                alignment: pw.Alignment.center,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    right: pw.BorderSide(color: PdfColors.black, width: 0.6),
                  ),
                ),
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      '$cap Ltr',
                      style: pw.TextStyle(
                          fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 1.5),
                    pw.Text('HOT WATER',
                        style: pw.TextStyle(
                            fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.center),
                    pw.SizedBox(height: 1.5),
                    pw.Text('STORAGE $mat',
                        style: pw.TextStyle(
                            fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.center),
                    pw.SizedBox(height: 1.5),
                    pw.Text(pressStr,
                        style: const pw.TextStyle(fontSize: 7.5),
                        textAlign: pw.TextAlign.center),
                    pw.SizedBox(height: 1.5),
                    pw.Text('TANK',
                        style: pw.TextStyle(
                            fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.center),
                  ],
                ),
              ),

              // Col 2: Description for all 10 rows
              pw.Column(
                children: all10Rows.asMap().entries.map((e) {
                  final isLast = e.key == all10Rows.length - 1;
                  return pw.Container(
                    width: col2W,
                    height: rowH,
                    alignment: pw.Alignment.centerLeft,
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2.5),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        right: const pw.BorderSide(
                            color: PdfColors.black, width: 0.6),
                        bottom: isLast
                            ? pw.BorderSide.none
                            : const pw.BorderSide(
                                color: PdfColors.black, width: 0.6),
                      ),
                    ),
                    child: pw.Text(e.value.$2,
                        style: const pw.TextStyle(fontSize: 7.5)),
                  );
                }).toList(),
              ),

              // Col 3: Specification for all 10 rows
              pw.Column(
                children: all10Rows.asMap().entries.map((e) {
                  final isLast = e.key == all10Rows.length - 1;
                  return pw.Container(
                    width: specW,
                    height: rowH,
                    alignment: pw.Alignment.centerLeft,
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2.5),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        bottom: isLast
                            ? pw.BorderSide.none
                            : const pw.BorderSide(
                                color: PdfColors.black, width: 0.6),
                      ),
                    ),
                    child: pw.Text(e.value.$3,
                        style: const pw.TextStyle(fontSize: 7.5)),
                  );
                }).toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── GENERIC PRICE TABLE (for non-hpWithTank quote types) ──────────────────

  static pw.Widget _buildGenericPriceTable(
      GeneratorQuotation quotation, QuoteTemplateConfig config,
      [GeneratorCompanySettings? settings]) {
    final hasDiscountCol = config.priceColumnKeys.contains('discount');
    final rows = quotation.priceRows;

    return pw.Column(
      children: [
        pw.Table(
          border: const pw.TableBorder(
            left: pw.BorderSide(color: PdfColors.black, width: 0.6),
            right: pw.BorderSide(color: PdfColors.black, width: 0.6),
            top: pw.BorderSide(color: PdfColors.black, width: 0.6),
            bottom: pw.BorderSide(color: PdfColors.black, width: 0.6),
            horizontalInside: pw.BorderSide(color: PdfColors.black, width: 0.6),
            verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.6),
          ),
          columnWidths: hasDiscountCol
              ? {
                  0: const pw.FixedColumnWidth(26),
                  1: const pw.FlexColumnWidth(3.0),
                  2: const pw.FixedColumnWidth(32),
                  3: const pw.FixedColumnWidth(55),
                  4: const pw.FixedColumnWidth(65),
                  5: const pw.FixedColumnWidth(70),
                }
              : {
                  0: const pw.FixedColumnWidth(26),
                  1: const pw.FlexColumnWidth(3.1),
                  2: const pw.FixedColumnWidth(35),
                  3: const pw.FixedColumnWidth(28),
                  4: const pw.FixedColumnWidth(65),
                  5: const pw.FixedColumnWidth(70),
                },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E8E8E8')),
              children: hasDiscountCol
                  ? [
                      _th('SR\nNO'),
                      _th('DESCRIPTION'),
                      _th('QTY'),
                      _th('RATE'),
                      _th('DISCOUNT'),
                      _th('TOTAL'),
                    ]
                  : [
                      _th('SR\nNO'),
                      _th('DESCRIPTION'),
                      _th('UNIT'),
                      _th('QTY'),
                      _th('RATE'),
                      _th('TOTAL'),
                    ],
            ),
            ...rows.asMap().entries.map((entry) {
              final idx = entry.key;
              final r = entry.value;
              final srText = r.serialNo.isNotEmpty
                  ? r.serialNo
                  : ((idx + 1) < 10 ? '0${idx + 1}' : '${idx + 1}');

              String rateStr;
              String totalStr;

              if (r.status == PriceRowStatus.included) {
                rateStr = 'Included';
                totalStr = 'Included';
              } else if (r.status == PriceRowStatus.extra) {
                rateStr = 'Extra';
                totalStr = 'Extra';
              } else if (r.status == PriceRowStatus.na) {
                rateStr = 'NA';
                totalStr = 'NA';
              } else if (r.status == PriceRowStatus.customText) {
                rateStr = r.customStatusText ?? 'Custom';
                totalStr = r.customStatusText ?? 'Custom';
              } else {
                rateStr = PriceCalculator.formatIndianCurrency(r.rate,
                    includeSymbol: false);
                totalStr = PriceCalculator.formatIndianCurrency(r.amount,
                    includeSymbol: false);
              }

              final dLower = r.description.toLowerCase();
              final isAioRow = quotation.quoteType == QuoteType.allInOneFloor ||
                  quotation.quoteType == QuoteType.allInOneWall ||
                  dLower.contains('all in one') ||
                  dLower.contains('aio') ||
                  r.metadata?['type'] == 'allInOne' ||
                  r.metadata?['type'] == 'wallMounted';

              AllInOneModel? aioModel;
              if (isAioRow) {
                final list = settings?.allInOneModels ?? [];
                final cap = r.systemLph ??
                    (dLower.contains('100')
                        ? 100
                        : (dLower.contains('300')
                            ? 300
                            : (dLower.contains('200') ? 200 : 200)));
                if (list.isNotEmpty) {
                  aioModel = list.cast<AllInOneModel?>().firstWhere(
                    (m) =>
                        m != null &&
                        (m.tankVolumeLitres == cap ||
                            dLower.contains(m.modelName.toLowerCase()) ||
                            m.modelName.toLowerCase().contains(dLower)),
                    orElse: () => null,
                  );
                }
                aioModel ??= quotation.allInOneModel;
              }

              final isHpRow = !isAioRow && (
                  quotation.quoteType == QuoteType.hpOnly ||
                  quotation.quoteType == QuoteType.hpWithTank ||
                  dLower.contains('heat pump') ||
                  dLower.contains('iz-') ||
                  r.metadata?['type'] == 'heatPump'
              );
              final isPoolRow = quotation.quoteType == QuoteType.swimmingPool ||
                  dLower.contains('swimming') ||
                  dLower.contains('pool') ||
                  r.metadata?['type'] == 'pool';

              String extraDesc = '';
              if (isAioRow && aioModel != null) {
                extraDesc = aioModel.description.trim();
              } else if (isPoolRow) {
                final poolList = settings?.poolModels ?? [];
                PoolHeatPumpModel? pm;
                if (poolList.isNotEmpty) {
                  pm = poolList.cast<PoolHeatPumpModel?>().firstWhere(
                    (m) => m != null && (dLower.contains(m.modelName.toLowerCase()) || m.modelName.toLowerCase().contains(dLower)),
                    orElse: () => null,
                  );
                }
                pm ??= quotation.poolModel;
                extraDesc = pm?.description.trim() ?? '';
              } else if (isHpRow) {
                final hpKw = r.hpKw ?? quotation.model.displayCapacityKw;
                final hpList = settings?.models ?? [];
                HeatPumpModel? hp;
                if (hpList.isNotEmpty) {
                  hp = hpList.cast<HeatPumpModel?>().firstWhere(
                    (m) => m != null && ((m.displayCapacityKw - hpKw).abs() < 0.1 || dLower.contains(m.modelName.toLowerCase())),
                    orElse: () => null,
                  );
                }
                hp ??= quotation.model;
                if (hp.makeModelLine.isNotEmpty && hp.makeModelLine.toLowerCase() != r.description.trim().toLowerCase()) {
                  extraDesc = hp.makeModelLine.trim();
                } else if (hp.descriptionLine.isNotEmpty && hp.descriptionLine.toLowerCase() != r.description.trim().toLowerCase()) {
                  extraDesc = hp.descriptionLine.trim();
                }
              }

              final shouldShowExtra = extraDesc.isNotEmpty &&
                  extraDesc.toLowerCase() != r.description.trim().toLowerCase();

              pw.Widget descWidget;
              if (shouldShowExtra) {
                descWidget = pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 4, vertical: 3),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        r.description,
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        extraDesc,
                        style: const pw.TextStyle(
                          fontSize: 7,
                          color: PdfColors.black,
                        ),
                      ),
                    ],
                  ),
                );
              } else {
                descWidget = _tc(r.description);
              }

              if (hasDiscountCol) {
                final discStr = r.discountAmount != null &&
                        r.discountAmount! > 0
                    ? PriceCalculator.formatIndianCurrency(r.discountAmount!,
                        includeSymbol: false)
                    : '-';
                return pw.TableRow(
                  children: [
                    _tc(srText, center: true),
                    descWidget,
                    _tc('${r.qty}', center: true),
                    _tc(rateStr, center: true),
                    _tc(discStr, center: true),
                    _tc(totalStr, center: true),
                  ],
                );
              } else {
                return pw.TableRow(
                  children: [
                    _tc(srText, center: true),
                    descWidget,
                    _tc(r.unitLabel ?? 'NOS', center: true),
                    _tc('${r.qty}', center: true),
                    _tc(rateStr, center: true),
                    _tc(totalStr, center: true),
                  ],
                );
              }
            }),
            ...quotation.extraPriceRows.asMap().entries.map((entry) {
              final idx = entry.key;
              final it = entry.value;
              final rowNum = rows.length + idx + 1;
              final srText = rowNum < 10 ? '0$rowNum' : '$rowNum';

              String desc = it.description.trim();
              final hadExtraInDesc = desc.toLowerCase().contains('extra');
              desc = desc
                  .replaceAll(
                      RegExp(r'\s*-\s*(Extra|Included)', caseSensitive: false), '')
                  .trim();
              final isExtraSelection = it.amountType == PriceRowType.extra ||
                  hadExtraInDesc ||
                  (it.amountType == PriceRowType.customText &&
                      it.customText.toLowerCase().contains('extra'));
              final isCharged = (it.amountType == PriceRowType.extra ||
                      it.amountType == PriceRowType.amount) &&
                  it.numericAmount > 0;
              final amt = isCharged
                  ? PriceCalculator.formatIndianCurrency(it.numericAmount,
                      includeSymbol: false)
                  : (isExtraSelection ? 'Extra' : 'Included');
              final qtyVal = int.tryParse(it.qty) ?? 0;
              final qtyStr =
                  qtyVal > 0 ? '$qtyVal' : (it.qty.isNotEmpty ? it.qty : '1');
              final rateStr = it.systemRate.isNotEmpty
                  ? it.systemRate
                  : (isCharged
                      ? (qtyVal > 0
                          ? PriceCalculator.formatIndianCurrency(
                              (it.numericAmount / qtyVal).round(),
                              includeSymbol: false)
                          : amt)
                      : (isExtraSelection ? 'Extra' : 'Included'));

              if (hasDiscountCol) {
                return pw.TableRow(
                  children: [
                    _tc(srText, center: true),
                    _tc(desc),
                    _tc(qtyStr, center: true),
                    _tc(rateStr, center: true),
                    _tc('-', center: true),
                    _tc(amt, center: true),
                  ],
                );
              } else {
                return pw.TableRow(
                  children: [
                    _tc(srText, center: true),
                    _tc(desc),
                    _tc('NOS', center: true),
                    _tc(qtyStr, center: true),
                    _tc(rateStr, center: true),
                    _tc(amt, center: true),
                  ],
                );
              }
            }),
          ],
        ),
        pw.Table(
          border: const pw.TableBorder(
            left: pw.BorderSide(color: PdfColors.black, width: 0.6),
            right: pw.BorderSide(color: PdfColors.black, width: 0.6),
            bottom: pw.BorderSide(color: PdfColors.black, width: 0.6),
            horizontalInside: pw.BorderSide(color: PdfColors.black, width: 0.6),
            verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.6),
          ),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.0),
            1: const pw.FixedColumnWidth(65),
            2: const pw.FixedColumnWidth(70),
          },
          children: [
            _buildTotalRow(
              'Sub Total',
              PriceCalculator.formatIndianCurrency(quotation.subtotal),
            ),
            _buildTotalRow(
              'GST %',
              PriceCalculator.formatIndianCurrency(quotation.gstAmount),
            ),
            _buildTotalRow(
              'TOTAL',
              PriceCalculator.formatIndianCurrency(quotation.grandTotal),
              isUnderlined: true,
            ),
          ],
        ),
      ],
    );
  }

  // ─── SPEC HELPERS ─────────────────────────────────────────────────────────

  static pw.Widget _buildHpSpecTable(
      GeneratorQuotation q, GeneratorCompanySettings settings) {
    final hpList = q.effectiveHeatPumps;
    final isMulti = hpList.length > 1;

    final titleModelText = isMulti
        ? hpList.map((h) => h.modelName).where((s) => s.isNotEmpty).join(', ')
        : q.model.modelName;

    final Map<int, pw.TableColumnWidth> colWidths = {
      0: const pw.FixedColumnWidth(28),
      1: pw.FixedColumnWidth(isMulti ? 165 : 185),
    };
    for (int i = 0; i < hpList.length; i++) {
      colWidths[i + 2] = const pw.FlexColumnWidth(1);
    }

    final headerChildren = <pw.Widget>[
      _th('SL'),
      _th('DESCRIPTION'),
    ];
    for (int i = 0; i < hpList.length; i++) {
      headerChildren.add(_th(isMulti ? '${i + 1}' : 'SPECIFICATION'));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'TECHNICAL SPECIFICATION FOR : ${settings.brandName}  HEAT PUMP –$titleModelText',
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 3),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
          columnWidths: colWidths,
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E8E8E8')),
              children: headerChildren,
            ),
            ..._buildMultiHpSpecRows(q, hpList, settings),
          ],
        ),
      ],
    );
  }

  static List<pw.TableRow> _buildMultiHpSpecRows(
      GeneratorQuotation q, List<HeatPumpLineItem> hpList, GeneratorCompanySettings settings) {
    final tankCap = q.tankCapacityLitres > 0
        ? '${q.tankCapacityLitres}'
        : (q.effectiveTanks.isNotEmpty
            ? '${q.effectiveTanks.first.capacityLitres}'
            : '500');

    // Resolve specs for single heat pump model from q.model or directly from settings module
    Map<String, String> activeSpecs = Map.from(q.model.specs);
    if (activeSpecs.isEmpty) {
      final res = QgModelSpecsResolver.resolve(
        modelId: q.model.id,
        modelName: q.model.modelName,
        kw: q.model.displayCapacityKw,
        settings: settings,
      );
      if (res.specs.isNotEmpty) {
        activeSpecs = Map.from(res.specs);
      }
    }

    // Resolve each HeatPumpLineItem's specs from Module Settings if missing
    final List<HeatPumpLineItem> resolvedHpList = hpList.map<HeatPumpLineItem>((h) {
      if (h.specs.isNotEmpty) return h;
      final resItem = QgModelSpecsResolver.resolve(
        modelId: h.id,
        modelName: h.modelName,
        kw: h.kw,
        settings: settings,
      );
      if (resItem.specs.isNotEmpty) {
        return h.copyWith(
          modelName: resItem.modelName.isNotEmpty ? resItem.modelName : h.modelName,
          kw: resItem.kw > 0 ? resItem.kw : h.kw,
          specs: Map<String, String>.from(resItem.specs),
        );
      }
      return h;
    }).toList();

    // If single heat pump and model has dynamic specs configured, render them directly
    if (resolvedHpList.length <= 1 && activeSpecs.isNotEmpty) {
      int idx = 1;
      return activeSpecs.entries.map((entry) {
        final sl = (idx < 10) ? '0$idx' : '$idx';
        idx++;
        String val = entry.value;
        if (entry.key.toLowerCase().contains('capacity in litre') ||
            entry.key.toLowerCase().contains('capacity in ltr')) {
          val = tankCap;
        }
        return pw.TableRow(
          children: [
            _tc(sl, center: true),
            _tc(entry.key),
            _tc(val, center: true),
          ],
        );
      }).toList();
    }

    // Dynamic Multi-HP column support: Gather all specification keys configured in Module Settings
    final specKeys = <String>[];
    for (final k in activeSpecs.keys) {
      if (!specKeys.contains(k)) specKeys.add(k);
    }
    for (final h in resolvedHpList) {
      for (final k in h.specs.keys) {
        if (!specKeys.contains(k)) specKeys.add(k);
      }
    }

    if (specKeys.isNotEmpty) {
      int idx = 1;
      return specKeys.map((key) {
        final sl = (idx < 10) ? '0$idx' : '$idx';
        idx++;
        return pw.TableRow(
          children: [
            _tc(sl, center: true),
            _tc(key),
            ...resolvedHpList.map((HeatPumpLineItem h) {
              String val = h.specs[key] ?? '-';
              if (key.toLowerCase().contains('capacity in litre') ||
                  key.toLowerCase().contains('capacity in ltr')) {
                val = tankCap;
              }
              return _tc(val, center: true);
            }),
          ],
        );
      }).toList();
    }

    debugPrint('[PdfQuotationBuilder] Using fallback rowsData for multi-HP - no Module Settings found');
    final rowsData = [
      [
        '01',
        'Size (W x D x H) mm',
        (HeatPumpLineItem h) => h.specs['Size (W x D x H)'] ?? '1410x748x1000'
      ],
      [
        '02',
        'Rated Heating Capacity',
        (HeatPumpLineItem h) => h.toModel().ratedHeatingCapacity
      ],
      ['03', 'Power Supply', (HeatPumpLineItem h) => h.toModel().powerSupply],
      [
        '04',
        'Rated Input Power',
        (HeatPumpLineItem h) =>
            h.specs['Rated Input Power'] ??
            (h.kw > 0 ? '${(h.kw * 0.23).toStringAsFixed(2)}kw' : '8.75kw')
      ],
      [
        '05',
        'Rated COP',
        (HeatPumpLineItem h) => h.specs['Rated COP'] ?? '4.34'
      ],
      [
        '06',
        'Rated Water Yield',
        (HeatPumpLineItem h) =>
            h.specs['Rated Water Yield'] ??
            (h.kw > 0 ? '${(h.kw * 21.5).round()} L/h' : '817 L/h')
      ],
      [
        '07',
        'Max Outlet Water Temperature',
        (HeatPumpLineItem h) =>
            h.specs['Max Outlet Water Temperature'] ?? '60°C'
      ],
      [
        '08',
        'Water Flow Noise',
        (HeatPumpLineItem h) => h.specs['Water Flow Noise'] ?? '<=59dB(A)'
      ],
      [
        '09',
        'Condenser',
        (HeatPumpLineItem h) =>
            h.specs['Condenser'] ?? 'Shell and tube heat exchanger'
      ],
      [
        '10',
        'Refrigerant',
        (HeatPumpLineItem h) => h.specs['Refrigerant'] ?? 'R134A/410A'
      ],
      [
        '11',
        'Operating ambient Temp',
        (HeatPumpLineItem h) => h.specs['Operating ambient Temp'] ?? '-15~43°C'
      ],
      ['12', 'Capacity In litre', (HeatPumpLineItem h) => tankCap],
      [
        '13',
        'Compressor',
        (HeatPumpLineItem h) => h.specs['Compressor'] ?? 'Double'
      ],
    ];

    return rowsData.map((row) {
      final sl = row[0] as String;
      final desc = row[1] as String;
      final valFn = row[2] as String Function(HeatPumpLineItem);

      return pw.TableRow(
        children: [
          _tc(sl, center: true),
          _tc(desc),
          ...hpList.map((h) => _tc(valFn(h), center: true)),
        ],
      );
    }).toList();
  }

  static pw.Widget _buildPoolSpecTable(PoolHeatPumpModel m) {
    if (m.specs.isNotEmpty) {
      int idx = 1;
      return pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
        columnWidths: {
          0: const pw.FixedColumnWidth(28),
          1: const pw.FlexColumnWidth(2.5),
          2: const pw.FlexColumnWidth(2.5),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E8E8E8')),
            children: [_th('SL'), _th('DESCRIPTION'), _th('SPECIFICATION')],
          ),
          ...m.specs.entries.map((entry) {
            final sl = (idx < 10) ? '0$idx' : '$idx';
            idx++;
            return pw.TableRow(
              children: [
                _tc(sl, center: true),
                _tc(entry.key),
                _tc(entry.value),
              ],
            );
          }),
        ],
      );
    }

    debugPrint('[PdfQuotationBuilder] Using fallback default specs for PoolHeatPumpModel (${m.modelName}) - no Module Settings found');
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
      columnWidths: {
        0: const pw.FixedColumnWidth(28),
        1: const pw.FlexColumnWidth(2.5),
        2: const pw.FlexColumnWidth(2.5),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E8E8E8')),
          children: [_th('SL'), _th('DESCRIPTION'), _th('SPECIFICATION')],
        ),
        pw.TableRow(children: [
          _tc('01', center: true),
          _tc('Model'),
          _tc(m.modelName)
        ]),
        pw.TableRow(children: [
          _tc('02', center: true),
          _tc('Heating Capacity'),
          _tc(m.heatingCapacity)
        ]),
        pw.TableRow(children: [
          _tc('03', center: true),
          _tc('Power Input'),
          _tc(m.powerInput)
        ]),
        pw.TableRow(children: [
          _tc('04', center: true),
          _tc('Power Supply'),
          _tc(m.powerSupply)
        ]),
        pw.TableRow(children: [
          _tc('05', center: true),
          _tc('Max Power Input / Current'),
          _tc('${m.maxPowerInput} / ${m.maxCurrent}')
        ]),
        pw.TableRow(children: [
          _tc('06', center: true),
          _tc('Water Flow Rate'),
          _tc(m.waterFlowRate)
        ]),
        pw.TableRow(
            children: [_tc('07', center: true), _tc('Noise'), _tc(m.noise)]),
        pw.TableRow(children: [
          _tc('08', center: true),
          _tc('Heat Exchanger'),
          _tc(m.heatExchanger)
        ]),
        pw.TableRow(children: [
          _tc('09', center: true),
          _tc('Refrigerant'),
          _tc(m.refrigerant)
        ]),
        pw.TableRow(children: [
          _tc('10', center: true),
          _tc('Ambient Working Temp'),
          _tc(m.workingTempRange)
        ]),
      ],
    );
  }

  static pw.Widget _buildAllInOneSpecTable(AllInOneModel m) {
    if (m.specs.isNotEmpty) {
      int idx = 1;
      return pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
        columnWidths: {
          0: const pw.FixedColumnWidth(28),
          1: const pw.FlexColumnWidth(2.5),
          2: const pw.FlexColumnWidth(2.5),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E8E8E8')),
            children: [_th('SL'), _th('DESCRIPTION'), _th('SPECIFICATION')],
          ),
          ...m.specs.entries.map((entry) {
            final sl = (idx < 10) ? '0$idx' : '$idx';
            idx++;
            return pw.TableRow(
              children: [
                _tc(sl, center: true),
                _tc(entry.key),
                _tc(entry.value),
              ],
            );
          }),
        ],
      );
    }

    debugPrint('[PdfQuotationBuilder] Using fallback default specs for AllInOneModel (${m.modelName}) - no Module Settings found');
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
      columnWidths: {
        0: const pw.FixedColumnWidth(28),
        1: const pw.FlexColumnWidth(2.5),
        2: const pw.FlexColumnWidth(2.5),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E8E8E8')),
          children: [_th('SL'), _th('DESCRIPTION'), _th('SPECIFICATION')],
        ),
        pw.TableRow(children: [
          _tc('01', center: true),
          _tc('Product Dimension'),
          _tc(m.productDimension)
        ]),
        pw.TableRow(children: [
          _tc('02', center: true),
          _tc('Tank Volume'),
          _tc('${m.tankVolumeLtr} Ltr')
        ]),
        pw.TableRow(children: [
          _tc('03', center: true),
          _tc('Power Supply'),
          _tc(m.powerSupply)
        ]),
        pw.TableRow(children: [
          _tc('04', center: true),
          _tc('Heating Rate / Water Yield'),
          _tc(m.waterYield)
        ]),
        pw.TableRow(children: [
          _tc('05', center: true),
          _tc('COP'),
          _tc(m.cop.toString())
        ]),
        pw.TableRow(children: [
          _tc('06', center: true),
          _tc('Compressor'),
          _tc(m.compressor)
        ]),
        pw.TableRow(children: [
          _tc('07', center: true),
          _tc('Refrigerant'),
          _tc(m.refrigerant)
        ]),
        pw.TableRow(children: [
          _tc('08', center: true),
          _tc('Max Outlet Water Temp'),
          _tc(m.maxOutletWaterTemp)
        ]),
        pw.TableRow(children: [
          _tc('09', center: true),
          _tc('Ambient Temperature'),
          _tc(m.ambientTemperature)
        ]),
        pw.TableRow(children: [
          _tc('10', center: true),
          _tc('Water Tank Material'),
          _tc(m.waterTankMaterial)
        ]),
        pw.TableRow(children: [
          _tc('11', center: true),
          _tc('Net Weight'),
          _tc(m.netWeight)
        ]),
      ],
    );
  }

  // ─── HELPER TABLE ROW BUILDERS ─────────────────────────────────────────────

  static pw.Widget _th(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 3),
      child: pw.Center(
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
      ),
    );
  }

  static pw.Widget _tc(String text,
      {bool center = false, bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 3.5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 7.5,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
      ),
    );
  }

  static pw.TableRow _buildTotalRow(
    String label,
    String amount, {
    bool isUnderlined = false,
  }) {
    return pw.TableRow(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        ),
        pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              decoration: isUnderlined
                  ? pw.TextDecoration.underline
                  : pw.TextDecoration.none,
            ),
          ),
        ),
        pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
          child: pw.Text(
            amount,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  static pw.TableRow _bankRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
        pw.Text(':-', style: const pw.TextStyle(fontSize: 8)),
        pw.Text(value,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  static Future<Uint8List?> _loadImageBytes(String? pathOrUrl) async {
    if (pathOrUrl == null || pathOrUrl.trim().isEmpty) return null;
    final trimmed = pathOrUrl.trim();
    try {
      // 1. Base64 data URI (e.g. data:image/png;base64,...)
      if (trimmed.startsWith('data:image')) {
        final commaIdx = trimmed.indexOf(',');
        if (commaIdx != -1) {
          return base64Decode(trimmed.substring(commaIdx + 1));
        }
      }

      // 2. Pure Base64 string
      if (trimmed.length > 100 &&
          !trimmed.contains('/') &&
          !trimmed.contains('\\') &&
          !trimmed.contains(':')) {
        try {
          return base64Decode(trimmed);
        } catch (_) {}
      }

      // 3. Asset path
      if (trimmed.startsWith('assets/')) {
        final data = await rootBundle.load(trimmed);
        return data.buffer.asUint8List();
      }

      // 4. Supabase Storage URL - bypasses browser CORS via Supabase client SDK
      if (trimmed.contains('/storage/v1/object/')) {
        try {
          final uri = Uri.parse(trimmed);
          final pathSegments = uri.pathSegments;
          final objIdx = pathSegments.indexOf('object');
          if (objIdx != -1) {
            int bucketIdx = objIdx + 1;
            if (bucketIdx < pathSegments.length &&
                (pathSegments[bucketIdx] == 'public' ||
                 pathSegments[bucketIdx] == 'authenticated' ||
                 pathSegments[bucketIdx] == 'sign')) {
              bucketIdx++;
            }
            if (bucketIdx < pathSegments.length) {
              final bucket = pathSegments[bucketIdx];
              final rawPath = pathSegments.sublist(bucketIdx + 1).join('/');
              final filePath = Uri.decodeComponent(rawPath);
              if (bucket.isNotEmpty && filePath.isNotEmpty) {
                final downloaded = await Supabase.instance.client.storage
                    .from(bucket)
                    .download(filePath);
                return downloaded;
              }
            }
          }
        } catch (_) {
          // Fall through to http.get
        }
      }

      // 5. HTTP / HTTPS / Blob URL
      if (trimmed.startsWith('http://') ||
          trimmed.startsWith('https://') ||
          trimmed.startsWith('blob:')) {
        final res = await http.get(Uri.parse(trimmed));
        if (res.statusCode == 200) return res.bodyBytes;
      }

      // 6. Local File (ONLY on non-web platforms to avoid Web UnsupportedError)
      if (!kIsWeb) {
        final file = File(trimmed);
        if (await file.exists()) {
          return await file.readAsBytes();
        }
      }
    } catch (e) {
      debugPrint('Error loading image bytes for $trimmed: $e');
    }
    return null;
  }
}
