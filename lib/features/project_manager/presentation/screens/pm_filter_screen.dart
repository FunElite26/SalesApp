import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:printing/printing.dart';
import '../theme/pm_tokens.dart';
import '../../providers/pm_mode_provider.dart';
import '../../providers/pm_company_provider.dart';
import '../../providers/pm_providers.dart';
import '../../data/services/pm_pdf_service.dart';
import '../../data/services/pm_excel_service.dart';
import '../widgets/pm_button.dart';
import '../widgets/pm_card.dart';
import '../widgets/pm_badge.dart';

class PmFilterScreen extends ConsumerStatefulWidget {
  const PmFilterScreen({super.key});

  @override
  ConsumerState<PmFilterScreen> createState() => _PmFilterScreenState();
}

class _PmFilterScreenState extends ConsumerState<PmFilterScreen> {
  String _selectedCategory = 'ALL';
  final _minBalanceCtrl = TextEditingController();
  final _maxBalanceCtrl = TextEditingController();
  bool _onlyPending = false;
  final _searchCtrl = TextEditingController();
  final _currency = NumberFormat('#,##,##0', 'en_IN');

  final List<String> _categories = [
    'ALL',
    'Heat Pump',
    'SWH',
    'Solar Water Heater',
    'Solar System',
    'Commercial SWH',
    'Boom Barrier',
    'Vendor Supply',
  ];

  @override
  Widget build(BuildContext context) {
    final pm = context.pm;
    final mode = ref.watch(pmRecordModeProvider);
    final isPurchase = mode.isPurchase;
    final activeCompany = ref.watch(pmActiveCompanyProvider);

    final AsyncValue<List<dynamic>> recordsAsync = isPurchase
        ? ref.watch(pmPurchasesListProvider)
        : ref.watch(pmProjectsListProvider);

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
        title: const Text('Filter Records', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, size: 18),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/pm');
            }
          },
        ),
      ),
      body: SafeArea(
        child: recordsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error: $err', style: TextStyle(color: pm.destructive))),
          data: (records) {
            // Filter logic
            final filtered = records.where((dynamic r) {
              if (_selectedCategory != 'ALL' && r.orderType != _selectedCategory) {
                return false;
              }
              final bal = (r.balance as num).toDouble();
              if (_onlyPending && bal <= 0) {
                return false;
              }
              final minB = double.tryParse(_minBalanceCtrl.text);
              if (minB != null && bal < minB) {
                return false;
              }
              final maxB = double.tryParse(_maxBalanceCtrl.text);
              if (maxB != null && bal > maxB) {
                return false;
              }
              if (_searchCtrl.text.isNotEmpty) {
                final q = _searchCtrl.text.toLowerCase().trim();
                final site = (r.siteName ?? '').toString().toLowerCase();
                final party = (r.partyPrintName ?? '').toString().toLowerCase();
                final mob = (r.mobileNumber ?? '').toString().toLowerCase();
                return site.contains(q) || party.contains(q) || mob.contains(q);
              }
              return true;
            }).toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Navigation Bar with Back Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        onTap: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/pm');
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.arrowLeft, size: 16, color: Color(0xFF0F172A)),
                              SizedBox(width: 8),
                              Text(
                                'Back to Directory',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Results count badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(9999),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Text(
                          '${filtered.length} Found',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF005CE6),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Filter Criteria Card
                  PmCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Filter Parameters', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: pm.foreground)),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectedCategory = 'ALL';
                                  _minBalanceCtrl.clear();
                                  _maxBalanceCtrl.clear();
                                  _onlyPending = false;
                                  _searchCtrl.clear();
                                });
                              },
                              icon: const Icon(LucideIcons.rotateCcw, size: 14),
                              label: const Text('Reset', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Category Dropdown
                        DropdownButtonFormField<String>(
                          value: _selectedCategory,
                          items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13)))).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedCategory = val);
                          },
                          decoration: InputDecoration(
                            labelText: 'Order Category / Type',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(pm.radiusMd)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _minBalanceCtrl,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: 'Min Balance (₹)',
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(pm.radiusMd)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: _maxBalanceCtrl,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: 'Max Balance (₹)',
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(pm.radiusMd)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _searchCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Quick Search (Name, Party, Mobile)',
                            prefixIcon: const Icon(LucideIcons.search, size: 16),
                            suffixIcon: _searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(LucideIcons.x, size: 16),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(pm.radiusMd)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        CheckboxListTile(
                          title: const Text('Only Accounts with Pending Balance (> ₹0)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          value: _onlyPending,
                          onChanged: (val) => setState(() => _onlyPending = val ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Results Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text('Matching Results', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: pm.foreground)),
                          const SizedBox(width: 8),
                          PmBadge(label: '${filtered.length} Found', variant: PmBadgeVariant.defaultVariant),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          PmButton(
                            variant: PmButtonVariant.outline,
                            size: PmButtonSize.sm,
                            onPressed: () async {
                              final pdfBytes = await PmPdfService.generateDirectoryPdf(
                                records: filtered,
                                companyName: activeCompany.name,
                                isPurchase: isPurchase,
                              );
                              await Printing.layoutPdf(onLayout: (_) => pdfBytes, name: 'Filtered_Records.pdf');
                            },
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.fileText, size: 14),
                                SizedBox(width: 6),
                                Text('PDF'),
                              ],
                            ),
                          ),
                          PmButton(
                            variant: PmButtonVariant.outline,
                            size: PmButtonSize.sm,
                            onPressed: () {
                              final bytes = PmExcelService.exportDirectoryToExcel(records: filtered, isPurchase: isPurchase);
                              if (bytes != null) {
                                Printing.sharePdf(bytes: bytes, filename: 'Filtered_Records.xlsx');
                              }
                            },
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.fileSpreadsheet, size: 14),
                                SizedBox(width: 6),
                                Text('Excel'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Results List
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final rec = filtered[i];
                      final bal = (rec.balance as num).toDouble();

                      return PmCard(
                        padding: const EdgeInsets.all(14),
                        onTap: () {
                          context.push('/pm/projects/${rec.id}${isPurchase ? "?mode=purchase" : ""}');
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text('#${rec.idNo}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: pm.mutedForeground)),
                                      const SizedBox(width: 6),
                                      PmBadge(label: rec.orderType, variant: PmBadgeVariant.secondary),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(rec.siteName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: pm.foreground)),
                                  Text(
                                    '${rec.partyPrintName ?? "No party"} • ${rec.mobileNumber ?? "No phone"}',
                                    style: TextStyle(fontSize: 12, color: pm.mutedForeground),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('₹${_currency.format(rec.orderValue)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                Text(
                                  'Bal: ₹${_currency.format(bal)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: bal > 0 ? pm.success : (bal < 0 ? pm.destructive : pm.mutedForeground),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
