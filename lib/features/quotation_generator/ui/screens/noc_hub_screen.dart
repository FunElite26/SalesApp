// lib/features/quotation_generator/ui/screens/noc_hub_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/pdf_preview_screen.dart';
import '../../data/qg_noc_repository.dart';
import '../../models/qg_noc_builder_state.dart';
import '../../models/qg_noc_document.dart';
import '../../services/pdf_noc_builder.dart';

class NocHubScreen extends ConsumerStatefulWidget {
  const NocHubScreen({super.key});

  @override
  ConsumerState<NocHubScreen> createState() => _NocHubScreenState();
}

class _NocHubScreenState extends ConsumerState<NocHubScreen> {
  final _searchController = TextEditingController();
  NocStatus? _selectedStatusFilter;
  List<QgNocDocument> _documents = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final docs = await QgNocRepository.listNocs(
        search: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
        status: _selectedStatusFilter,
      );
      if (mounted) {
        setState(() {
          _documents = docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Installation & Commissioning NOC Hub',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF1E1B4B),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadDocuments,
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF174895),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Generate NOC', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => context.push('/qg/noc/builder'),
      ),
      body: Column(
        children: [
          // Search & Filter Header
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by Customer, NOC #, Quotation #...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                              _loadDocuments();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _loadDocuments(),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All Statuses', null),
                      _buildFilterChip('Issued', NocStatus.issued),
                      _buildFilterChip('Draft', NocStatus.draft),
                      _buildFilterChip('Signed', NocStatus.signed),
                      _buildFilterChip('Archived', NocStatus.archived),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Document List Body
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                              const SizedBox(height: 12),
                              Text('Failed to load NOCs: $_errorMessage', textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadDocuments,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _documents.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.description_outlined, size: 64, color: Colors.grey.shade400),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No NOC Documents Found',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Create a new No Objection Certificate for installation & commissioning.',
                                    style: TextStyle(color: AppColors.textSecondary),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  ElevatedButton.icon(
                                    onPressed: () => context.push('/qg/noc/builder'),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Generate First NOC'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF174895),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadDocuments,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _documents.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final doc = _documents[index];
                                return _buildNocCard(context, doc);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, NocStatus? status) {
    final isSelected = _selectedStatusFilter == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          setState(() {
            _selectedStatusFilter = status;
          });
          _loadDocuments();
        },
        selectedColor: const Color(0xFF174895).withValues(alpha: 0.15),
        checkmarkColor: const Color(0xFF174895),
        labelStyle: TextStyle(
          color: isSelected ? const Color(0xFF174895) : AppColors.textPrimary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildNocCard(BuildContext context, QgNocDocument doc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateStr = DateFormat('dd MMM yyyy').format(doc.issuedDate);

    Color statusColor;
    switch (doc.status) {
      case NocStatus.issued:
        statusColor = const Color(0xFF286B37);
        break;
      case NocStatus.signed:
        statusColor = Colors.teal;
        break;
      case NocStatus.draft:
        statusColor = Colors.orange;
        break;
      case NocStatus.archived:
        statusColor = Colors.grey;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Number, Version, Status
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        doc.nocNumber,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF174895),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'v${doc.version}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    doc.status.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Customer Name & Site Address
            Text(
              doc.customerName,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            if (doc.siteAddress.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                doc.siteAddress,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 10),

            // Product & Equipment Summary
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 16, color: Color(0xFF286B37)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${doc.productName} • ${doc.equipmentSummary}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Text(
                    dateStr,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Action Buttons
            Row(
              children: [
                // View PDF Button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _viewNocPdf(context, doc),
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('View PDF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF174895),
                      side: const BorderSide(color: Color(0xFF174895)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                if (doc.status == NocStatus.draft) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => context.push('/qg/noc/builder?documentId=${doc.id}'),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit Draft'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _viewNocPdf(BuildContext context, QgNocDocument doc) async {
    try {
      // Build PDF from payload snapshot
      final payload = QgNocPayload(
        companyName: doc.companySnapshot['company_name']?.toString() ?? 'INSIYA TRADING CORPORATION',
        companyAddress: doc.companySnapshot['short_address']?.toString() ?? '',
        companyEmail: doc.companySnapshot['email']?.toString() ?? '',
        companyPhone: doc.companySnapshot['phone']?.toString() ?? '',
        companyWebsite: doc.companySnapshot['website']?.toString() ?? '',
        salutation: 'M/s',
        customerName: doc.customerName,
        address: doc.siteAddress,
        productName: doc.productName,
        subject: 'No Objection Certificate for Installation & Commissioning of ${doc.productName}.',
        date: doc.issuedDate,
        equipmentLabel: doc.productName,
        equipmentLines: doc.equipmentLines,
        workType: '${doc.productName} Installation work',
        wiring: 'Done',
        testing: 'Done',
        remark: 'All Installation & Commissioning work Completed as per work order',
        confirmations: doc.confirmations.isNotEmpty
            ? doc.confirmations
            : (await QgNocRepository.instance.getProfileForProduct(doc.productName))
                .confirmationLines
                .map((l) => l.replaceAll('{Product}', doc.productName))
                .toList(),
        closingSentence: doc.closingSentence ??
            'This NOC is issued upon request for installation and operation of the ${doc.productName} System.',
        wordingMode: doc.wordingMode,
        quotationNumber: doc.quotationNumber,
      );

      final pdfBytes = await PdfNocBuilder.buildNocPdf(payload);

      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PdfPreviewScreen(
              pdfBytes: pdfBytes,
              fileName: '${doc.nocNumber.replaceAll('/', '_')}.pdf',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating PDF view: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }
}
