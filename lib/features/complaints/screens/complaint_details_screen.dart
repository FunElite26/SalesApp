// lib/features/complaints/screens/complaint_details_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../data/models/complaint_model.dart';
import '../data/models/complaint_part_order.dart';
import '../providers/complaints_provider.dart';
import '../providers/part_orders_provider.dart';
import '../services/complaint_pdf_service.dart';
import '../widgets/signature_pad_widget.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/admin/providers/inventory_provider.dart';
import '../../../core/models/inventory_item.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pdf_preview_screen.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../core/widgets/searchable_dropdown.dart';

class ComplaintDetailsScreen extends ConsumerStatefulWidget {
  final String complaintId;

  const ComplaintDetailsScreen({super.key, required this.complaintId});

  @override
  ConsumerState<ComplaintDetailsScreen> createState() => _ComplaintDetailsScreenState();
}

class _ComplaintDetailsScreenState extends ConsumerState<ComplaintDetailsScreen> {
  final ImagePicker _picker = ImagePicker();

  Widget _buildImage(String url, {double? height, double? width, BoxFit fit = BoxFit.cover}) {
    if (url.startsWith('data:image')) {
      final base64Str = url.split(',').last;
      return Image.memory(
        base64Decode(base64Str),
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      height: height,
      width: width,
      fit: fit,
      placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
      errorWidget: (context, url, error) => const Icon(Icons.broken_image, size: 40),
    );
  }

  Widget _buildPhotoList(String? urlsString, {bool canRemove = false, required Complaint complaint}) {
    if (urlsString == null || urlsString.isEmpty) return const SizedBox.shrink();
    final urls = urlsString.split('|||').where((e) => e.trim().isNotEmpty).toList();
    if (urls.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        itemBuilder: (context, index) {
          final url = urls[index].trim();
          return Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: () => _showImagePreviewDialog(context, url),
                child: Container(
                  width: 120,
                  margin: const EdgeInsets.only(right: 12, top: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _buildImage(url, height: 112, width: 120, fit: BoxFit.cover),
                  ),
                ),
              ),
              if (canRemove)
                Positioned(
                  top: 0,
                  right: 4,
                  child: GestureDetector(
                    onTap: () {
                      ref.read(complaintsProvider.notifier).removeAfterPhoto(complaint.id, index);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: const Icon(Icons.close, color: Colors.white, size: 16),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showImagePreviewDialog(BuildContext context, String imageStr) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black.withOpacity(0.85),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(maxHeight: 400),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InteractiveViewer(
                  child: imageStr.startsWith('http')
                      ? _buildImage(imageStr, fit: BoxFit.contain)
                      : Image.memory(
                          base64Decode(imageStr.contains('base64,') ? imageStr.split('base64,').last : imageStr),
                          fit: BoxFit.contain,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _launchMaps(String address) async {
    final query = Uri.encodeComponent(address);
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch Google Maps')),
        );
      }
    }
  }

  Future<void> _makeCall(String phone) async {
    final url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void _showAfterPhotoSourceSheet(Complaint complaint) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select After-Solve Photo Source', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF6D28D9)),
              title: const Text('Take Photo with Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAfterPhoto(complaint, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF6D28D9)),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAfterPhoto(complaint, ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAfterPhoto(Complaint complaint, ImageSource source) async {
    try {
      final XFile? photo = await _picker.pickImage(source: source, imageQuality: 70);
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        final base64Str = base64Encode(bytes);
        final dataUrl = 'data:image/jpeg;base64,$base64Str';
        
        final supabase = ref.read(supabaseClientProvider);
        final publicUrl = await StorageService.uploadImage(
          supabase: supabase,
          base64OrPath: dataUrl,
          folder: 'after_photos',
        );

        if (publicUrl != null) {
          await ref.read(complaintsProvider.notifier).updateAfterPhoto(complaint.id, publicUrl);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('After-solve photo uploaded successfully!'), backgroundColor: Color(0xFF10B981)),
            );
          }
        } else {
          throw Exception('Failed to upload image to storage');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error taking photo: $e')),
        );
      }
    }
  }

  Future<void> _takeSignature(Complaint complaint) async {
    final signatureData = await showDialog<String>(
      context: context,
      builder: (ctx) => const SignaturePadDialog(title: 'Customer Digital Signature'),
    );

    if (signatureData != null && signatureData.isNotEmpty) {
      try {
        final supabase = ref.read(supabaseClientProvider);
        final publicUrl = await StorageService.uploadImage(
          supabase: supabase,
          base64OrPath: signatureData,
          folder: 'signatures',
        );

        if (publicUrl != null) {
          await ref.read(complaintsProvider.notifier).saveCustomerSignature(complaint.id, publicUrl);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Customer signature saved successfully!'), backgroundColor: Color(0xFF10B981)),
            );
          }
        } else {
          throw Exception('Failed to upload signature to storage');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving signature: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _takeTechnicianSignature(Complaint complaint) async {
    final signatureData = await showDialog<String>(
      context: context,
      builder: (ctx) => const SignaturePadDialog(title: 'Technician Digital Signature'),
    );

    if (signatureData != null && signatureData.isNotEmpty) {
      try {
        final supabase = ref.read(supabaseClientProvider);
        final publicUrl = await StorageService.uploadImage(
          supabase: supabase,
          base64OrPath: signatureData,
          folder: 'signatures',
        );

        if (publicUrl != null) {
          await ref.read(complaintsProvider.notifier).saveTechnicianSignature(complaint.id, publicUrl);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Technician signature saved successfully!'), backgroundColor: Color(0xFF10B981)),
            );
          }
        } else {
          throw Exception('Failed to upload technician signature to storage');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving technician signature: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _confirmDeleteComplaint(BuildContext context, WidgetRef ref, Complaint complaint) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Complaint?'),
        content: Text('Are you sure you want to permanently delete ticket ${complaint.ticketNumber}? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(complaintsProvider.notifier).deleteComplaint(complaint.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Complaint ${complaint.ticketNumber} deleted.'), backgroundColor: AppColors.error),
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  void _showReassignModal(Complaint complaint, List<TechnicianInfo> technicians) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        String searchQuery = '';
        final searchCtrl = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filteredTechs = technicians.where((t) {
              if (searchQuery.isEmpty) return true;
              final q = searchQuery.toLowerCase();
              return t.name.toLowerCase().contains(q) ||
                  (t.phone ?? '').contains(q) ||
                  (t.email ?? '').toLowerCase().contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Assign Technician (${complaint.ticketNumber})',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search technician by name or phone...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                searchCtrl.clear();
                                setModalState(() => searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                    onChanged: (val) => setModalState(() => searchQuery = val.trim()),
                  ),
                  const SizedBox(height: 12),
                  if (filteredTechs.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text('No matching technician staff found.'),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: filteredTechs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final tech = filteredTechs[idx];
                          final isCurrentlyAssigned = complaint.technicianId == tech.id;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isCurrentlyAssigned ? const Color(0xFF10B981) : AppColors.primary,
                              child: Text(
                                tech.name.isNotEmpty ? tech.name[0].toUpperCase() : 'T',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(tech.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${tech.status} • ${tech.phone ?? "No phone"}'),
                            trailing: isCurrentlyAssigned
                                ? const Chip(
                                    label: Text('Assigned', style: TextStyle(fontSize: 11, color: Colors.white)),
                                    backgroundColor: Color(0xFF10B981),
                                  )
                                : ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                                    onPressed: () {
                                      ref.read(complaintsProvider.notifier).assignTechnician(complaint.id, tech);
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Assigned to ${tech.name}!'),
                                          backgroundColor: const Color(0xFF10B981),
                                        ),
                                      );
                                    },
                                    child: const Text('Assign', style: TextStyle(color: Colors.white)),
                                  ),
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

  String _formatProductName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'IZYHEAT Solar System';
    }
    final trimmed = name.trim();
    if (trimmed.length > 25 && RegExp(r'^[0-9a-fA-F\-]+$').hasMatch(trimmed)) {
      return 'IZYHEAT Solar System';
    }
    return trimmed;
  }
  Future<DateTime> _getCustomerPurchaseDate(String customerId, [String? productName]) async {
    final supabase = ref.read(supabaseClientProvider);

    // 1. Check customer notes for [OLD_CUSTOMER_DATA:...]
    try {
      if (customerId.isNotEmpty) {
        final cust = await supabase
            .from('customers')
            .select('notes, created_at')
            .eq('id', customerId)
            .maybeSingle();

        if (cust != null) {
          final notes = cust['notes']?.toString() ?? '';
          if (notes.contains('[OLD_CUSTOMER_DATA:')) {
            final sIdx = notes.indexOf('[OLD_CUSTOMER_DATA:') + '[OLD_CUSTOMER_DATA:'.length;
            final eIdx = notes.lastIndexOf(']');
            if (eIdx > sIdx) {
              final jsonStr = notes.substring(sIdx, eIdx).trim();
              final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
              final prods = decoded['products'] as List? ?? [];
              final target = (productName ?? '').trim().toLowerCase();

              // First priority: matching product purchase_date
              for (final p in prods) {
                final pName = (p['name'] as String? ?? '').trim().toLowerCase();
                if (target.isEmpty || pName == target || pName.contains(target) || target.contains(pName)) {
                  final pDateStr = p['purchase_date'] as String?;
                  if (pDateStr != null && pDateStr.isNotEmpty) {
                    final parsed = DateTime.tryParse(pDateStr);
                    if (parsed != null) return parsed;
                  }
                }
              }

              // Second priority: any product's purchase_date in this record
              for (final p in prods) {
                final pDateStr = p['purchase_date'] as String?;
                if (pDateStr != null && pDateStr.isNotEmpty) {
                  final parsed = DateTime.tryParse(pDateStr);
                  if (parsed != null) return parsed;
                }
              }

              // Third priority: customer_since date
              final sinceStr = decoded['customer_since'] as String?;
              if (sinceStr != null && sinceStr.isNotEmpty) {
                final parsed = DateTime.tryParse(sinceStr);
                if (parsed != null) return parsed;
              }
            }
          }

          // Fourth priority: customer createdAt if it looks older than now
          if (cust['created_at'] != null) {
            final parsed = DateTime.tryParse(cust['created_at'].toString());
            if (parsed != null && parsed.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
              return parsed;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error reading customer purchase date from notes: $e');
    }

    // 2. Check warranty cards
    try {
      var query = supabase
          .from('warranty_cards')
          .select('start_date, product_name, generated_date, created_at')
          .eq('customer_id', customerId);
      if (productName != null && productName.isNotEmpty) {
        query = query.ilike('product_name', '%$productName%');
      }
      final wc = await query.order('created_at', ascending: false).limit(1).maybeSingle();
      if (wc != null) {
        final dateStr = wc['generated_date'] ?? wc['start_date'] ?? wc['created_at'];
        if (dateStr != null) {
          final parsed = DateTime.tryParse(dateStr.toString());
          if (parsed != null) return parsed;
        }
      }
    } catch (_) {}

    try {
      final wcFallback = await supabase
          .from('warranty_cards')
          .select('start_date, generated_date, created_at')
          .eq('customer_id', customerId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (wcFallback != null) {
        final dateStr = wcFallback['generated_date'] ?? wcFallback['start_date'] ?? wcFallback['created_at'];
        if (dateStr != null) {
          final parsed = DateTime.tryParse(dateStr.toString());
          if (parsed != null) return parsed;
        }
      }
    } catch (_) {}

    // 3. Check sales pipelines
    try {
      final pipe = await supabase
          .from('sales_pipelines')
          .select('created_at')
          .eq('customer_id', customerId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (pipe != null && pipe['created_at'] != null) {
        final parsed = DateTime.tryParse(pipe['created_at']);
        if (parsed != null) return parsed;
      }
    } catch (_) {}

    return DateTime.now().subtract(const Duration(days: 60));
  }

  void _showAddDefectedPartsDialog(Complaint complaint, {ComplaintPartOrder? existingOrder}) async {
    List<InventoryItem> inventoryItems = ref.read(inventoryProvider).valueOrNull ?? [];

    if (inventoryItems.isEmpty) {
      try {
        inventoryItems = await ref.read(inventoryProvider.future);
      } catch (e) {
        debugPrint('Inventory provider future fetch: $e');
      }
    }

    if (inventoryItems.isEmpty) {
      try {
        final supabase = ref.read(supabaseClientProvider);
        final data = await supabase.from('inventory_items').select().order('item_name');
        inventoryItems = (data as List).map((json) => InventoryItem.fromJson(json)).toList();
      } catch (e) {
        debugPrint('Direct inventory query: $e');
      }
    }

    // Comprehensive fallback so order sheet opens in one click even on fresh/empty database
    if (inventoryItems.isEmpty) {
      final now = DateTime.now();
      inventoryItems = [
        InventoryItem(id: 'cat_comp', itemName: 'Compressor Unit', price: 14500, warrantyMonths: 36, createdAt: now),
        InventoryItem(id: 'cat_pcb', itemName: 'Main PCB Controller Board', price: 4200, warrantyMonths: 12, createdAt: now),
        InventoryItem(id: 'cat_fan', itemName: 'Axial Fan Motor & Blades', price: 2800, warrantyMonths: 12, createdAt: now),
        InventoryItem(id: 'cat_exv', itemName: 'Electronic Expansion Valve', price: 2100, warrantyMonths: 12, createdAt: now),
        InventoryItem(id: 'cat_elem', itemName: 'Titanium Heating Element', price: 2600, warrantyMonths: 12, createdAt: now),
        InventoryItem(id: 'cat_sensor', itemName: 'Water & Coil Temp Sensor Probe', price: 850, warrantyMonths: 12, createdAt: now),
        InventoryItem(id: 'cat_prv', itemName: 'Safety Pressure Relief Valve (PRV)', price: 950, warrantyMonths: 12, createdAt: now),
        InventoryItem(id: 'cat_pump', itemName: 'Circulation Booster Pump', price: 5400, warrantyMonths: 24, createdAt: now),
        InventoryItem(id: 'cat_anode', itemName: 'Magnesium Anode Rod', price: 1100, warrantyMonths: 12, createdAt: now),
        InventoryItem(id: 'cat_switch', itemName: 'High / Low Pressure Switch', price: 1350, warrantyMonths: 12, createdAt: now),
        InventoryItem(id: 'cat_capacitor', itemName: 'Running Capacitor (50uF/60uF)', price: 750, warrantyMonths: 12, createdAt: now),
        InventoryItem(id: 'cat_gas', itemName: 'Refrigerant R410A / R134a Gas Can', price: 3200, warrantyMonths: 6, createdAt: now),
      ];
    }

    DateTime purchaseDate = await _getCustomerPurchaseDate(complaint.customerId, complaint.productName);
    final profile = ref.read(currentProfileProvider);
    final String techName = profile?.fullName ?? 'Technician';

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DefectedPartsOrderSheet(
        complaint: complaint,
        inventoryItems: inventoryItems,
        purchaseDate: purchaseDate,
        techName: techName,
        existingOrder: existingOrder,
      ),
    );
  }

  void _promptSealAfter(BuildContext context, WidgetRef ref, Complaint complaint) {
    final controller = TextEditingController(text: complaint.sealNumberAfter ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: Color(0xFF6D28D9)),
            SizedBox(width: 8),
            Text('Seal (After Service)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter security seal number affixed after service completion (Optional):', style: TextStyle(fontSize: 12, color: Colors.black87)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Seal Number (After Service)',
                hintText: 'e.g. SL-9042',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6D28D9)),
            onPressed: () async {
              Navigator.pop(ctx);
              final updated = complaint.copyWith(
                sealNumberAfter: controller.text.trim().isEmpty ? null : controller.text.trim(),
              );
              await ref.read(complaintsProvider.notifier).updateComplaint(updated);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Seal number updated successfully!'), backgroundColor: Color(0xFF10B981)),
                );
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDeletePartOrder(BuildContext context, ComplaintPartOrder order, String complaintId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Part Order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete Order #${order.id.substring(0, 8).toUpperCase()}? This action cannot be undone.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(partOrdersServiceProvider).deletePartOrder(
                  orderId: order.id,
                  complaintId: complaintId,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Part order deleted successfully.'),
                      backgroundColor: Color(0xFF10B981),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete order: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildPartOrdersSection(Complaint complaint, bool canOrder) {
    final partOrdersAsync = ref.watch(partOrdersForComplaintProvider(complaint.id));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: Color(0xFF6D28D9), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Defected Parts & Orders',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (canOrder) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6D28D9),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add, size: 16, color: Colors.white),
                  label: const Text('Order Parts', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => _showAddDefectedPartsDialog(complaint),
                ),
              ],
            ],
          ),
          const Divider(height: 20),
          partOrdersAsync.when(
            data: (orders) {
              if (orders.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, color: Colors.grey.shade400, size: 18),
                      const SizedBox(width: 8),
                      Text('No replacement parts ordered for this ticket.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                    ],
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, idx) {
                  final ord = orders[idx];
                  Color statusColor = const Color(0xFFF59E0B);
                  String statusText = 'Payment Pending';
                  IconData statusIcon = Icons.pending_actions;

                  if (ord.paymentStatus == 'paid') {
                    statusColor = const Color(0xFF10B981);
                    statusText = 'Paid ✓ (Replaced)';
                    statusIcon = Icons.check_circle;
                  } else if (ord.paymentStatus == 'not_required' || ord.isWarranty) {
                    statusColor = const Color(0xFF059669);
                    statusText = 'Free Warranty Replacement ✓';
                    statusIcon = Icons.verified;
                  }

                  final canModify = canOrder && ord.paymentStatus != 'paid';

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Order #${ord.id.substring(0, 8).toUpperCase()}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(statusIcon, color: statusColor, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusText,
                                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            if (canModify) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF6D28D9)),
                                tooltip: 'Edit Order',
                                onPressed: () => _showAddDefectedPartsDialog(complaint, existingOrder: ord),
                              ),
                              IconButton(
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                tooltip: 'Delete Order',
                                onPressed: () => _confirmDeletePartOrder(context, ord, complaint.id),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...ord.items.map((item) {
                          final isWar = (item['is_warranty'] as bool?) ?? false;
                          final price = (item['total_price'] as num?)?.toDouble() ?? 0.0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '• ${item['item_name']} (x${item['quantity']}) - ${item['reason'] ?? ''}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                Text(
                                  isWar ? '₹0 (Warranty)' : '₹${price.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isWar ? const Color(0xFF059669) : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const Divider(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Placed: ${DateFormat('dd MMM, hh:mm a').format(ord.createdAt)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            Text(
                              'Total: ₹${ord.totalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Text('Error loading part orders: $err', style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final complaints = ref.watch(complaintsProvider);
    final profile = ref.watch(currentProfileProvider);
    final techniciansAsync = ref.watch(availableTechniciansProvider);
    ref.watch(inventoryProvider);

    final complaint = complaints.firstWhere(
      (c) => c.id == widget.complaintId,
      orElse: () => Complaint(
        id: widget.complaintId,
        ticketNumber: '#CMP-000',
        customerId: '',
        customerName: 'Unknown Customer',
        customerPhone: '',
        customerAddress: '',
        priority: 'Medium Priority',
        title: 'Service Request',
        description: '',
        tatRemaining: '24h',
        createdAt: DateTime.now(),
      ),
    );

    final isManagerOnly = (profile?.roles.contains(UserRole.manager) ?? false) && !(profile?.roles.contains(UserRole.admin) ?? false);
    final isAdminOrCoordinator = !isManagerOnly &&
        ((profile?.primaryRole == UserRole.admin || (profile?.roles.contains(UserRole.admin) ?? false)) ||
            (profile?.primaryRole == UserRole.serviceHead || (profile?.roles.contains(UserRole.serviceHead) ?? false)));
    final isTechnician = profile?.primaryRole == UserRole.technician;
    final isClosed = complaint.status == 'closed' || complaint.status == 'resolved';
    final hasCustomerSignature = complaint.customerSignatureUrl != null && complaint.customerSignatureUrl!.isNotEmpty;
    final hasTechSignature = complaint.technicianSignatureUrl != null && complaint.technicianSignatureUrl!.isNotEmpty;
    final hasAfterPhoto = complaint.afterImageUrl != null && complaint.afterImageUrl!.isNotEmpty;

    final partOrdersAsync = ref.watch(partOrdersForComplaintProvider(complaint.id));
    final partOrders = partOrdersAsync.valueOrNull ?? [];
    final hasPendingPaymentOrders = partOrders.any((o) => o.paymentStatus == 'pending');
    final allResolutionItemsCaptured = hasCustomerSignature && hasTechSignature && hasAfterPhoto;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              complaint.ticketNumber,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              _formatProductName(complaint.productName),
              style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF6D28D9),
        elevation: 0,
        actions: [
          if (!isClosed && !isManagerOnly)
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.white),
              tooltip: 'Edit Complaint',
              onPressed: () => context.push('/complaints/edit/${complaint.id}'),
            ),
          if ((profile?.primaryRole == UserRole.admin || (profile?.roles.contains(UserRole.admin) ?? false)) && !isManagerOnly)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              tooltip: 'Delete Complaint (Admin Only)',
              onPressed: () => _confirmDeleteComplaint(context, ref, complaint),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status & Priority Banner
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(
                  label: Text(complaint.status.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                  backgroundColor: isClosed ? const Color(0xFF10B981) : const Color(0xFF6D28D9),
                ),
                Chip(
                  label: Text(complaint.priority, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                  backgroundColor: Colors.red.shade50,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Customer Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person, color: Color(0xFF6D28D9)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          complaint.customerName,
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (complaint.customerPhone.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.phone, color: Color(0xFF10B981)),
                          onPressed: () => _makeCall(complaint.customerPhone),
                        ),
                    ],
                  ),
                  const Divider(),
                  Text('Mobile: ${complaint.customerPhone}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('Address: ${complaint.customerAddress}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4C1D95),
                        side: const BorderSide(color: Color(0xFF6D28D9)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('Navigate in Google Maps', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => _launchMaps(complaint.customerAddress),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Issue & Product Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Issue & Product Details', style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.bold)),
                  const Divider(),
                  _detailRow('Product Name', _formatProductName(complaint.productName)),
                  _detailRow('Issue Category', complaint.title),
                  if (complaint.errorCode != null && complaint.errorCode!.isNotEmpty)
                    _detailRow('Error Code', '${complaint.errorCode}${complaint.errorDescription != null ? " - ${complaint.errorDescription}" : ""}'),
                  if (complaint.sealNumberBefore != null && complaint.sealNumberBefore!.isNotEmpty)
                    _detailRow('Seal (Before Service)', complaint.sealNumberBefore!),
                  if (complaint.sealNumberAfter != null && complaint.sealNumberAfter!.isNotEmpty)
                    _detailRow('Seal (After Service)', complaint.sealNumberAfter!),
                  _detailRow('Description', complaint.description.isNotEmpty ? complaint.description : 'No additional notes.'),
                  const SizedBox(height: 12),
                  if (complaint.beforeImageUrl != null && complaint.beforeImageUrl!.trim().isNotEmpty) ...[
                    Text(
                      'Issue Photos (${complaint.beforeImageUrl!.split('|||').where((p) => p.trim().isNotEmpty).length}):',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 110,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: complaint.beforeImageUrl!.split('|||').where((p) => p.trim().isNotEmpty).length,
                        itemBuilder: (context, idx) {
                          final photoStr = complaint.beforeImageUrl!.split('|||').where((p) => p.trim().isNotEmpty).toList()[idx].trim();
                          Widget imgWidget;
                          if (photoStr.startsWith('http')) {
                            imgWidget = _buildImage(photoStr, fit: BoxFit.cover);
                          } else {
                            try {
                              final cleanBase64 = photoStr.contains('base64,') ? photoStr.split('base64,').last : photoStr;
                              imgWidget = Image.memory(base64Decode(cleanBase64), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40));
                            } catch (_) {
                              imgWidget = const Icon(Icons.image, size: 40);
                            }
                          }
                          return GestureDetector(
                            onTap: () => _showImagePreviewDialog(context, photoStr),
                            child: Container(
                              margin: const EdgeInsets.only(right: 10),
                              width: 110,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: imgWidget,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Issue Photos:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No image uploaded',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Technician Assignment Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Assigned Technician', style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.bold)),
                      if (isAdminOrCoordinator && !isClosed)
                        TextButton.icon(
                          icon: const Icon(Icons.swap_horiz, size: 16),
                          label: Text(complaint.technicianName != null ? 'Reassign' : 'Assign Tech'),
                          onPressed: () {
                            techniciansAsync.whenData((list) => _showReassignModal(complaint, list));
                          },
                        ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFF6D28D9).withOpacity(0.1),
                        child: const Icon(Icons.person, color: Color(0xFF6D28D9)),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(complaint.technicianName ?? 'Unassigned', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(complaint.technicianId != null ? 'Assigned Field Staff' : 'Pending dispatch', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Defected Parts & Replacement Orders Section
            _buildPartOrdersSection(complaint, (!isClosed && (isTechnician || isAdminOrCoordinator))),
            const SizedBox(height: 20),

            // Admin / Coordinator Action Panel
            if (isAdminOrCoordinator && complaint.status == 'resolved') ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Admin Actions', style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.check_circle, color: Colors.white),
                        label: const Text('Approve & Close Complaint', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          ref.read(complaintsProvider.notifier).approveComplaint(complaint.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Complaint approved and closed.'), backgroundColor: Color(0xFF10B981)),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Technician Action Panel (ONLY Visible to Technician role)
            if (!isClosed && isTechnician) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF6D28D9).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Service Resolution Actions', style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),

                    if (hasPendingPaymentOrders) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber.shade400),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.payment_outlined, color: Colors.amber, size: 22),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Customer payment is pending for replacement parts. Final resolution actions will unlock once payment is completed by customer.',
                                style: TextStyle(fontSize: 12, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasAfterPhoto ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: Icon(hasAfterPhoto ? Icons.check_circle : Icons.camera_alt, color: Colors.white, size: 18),
                      label: Text(
                        hasAfterPhoto ? 'After-Solve Photo(s) Uploaded ✓' : 'Upload After-Solve Photo(s)',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      onPressed: hasPendingPaymentOrders ? null : () => _showAfterPhotoSourceSheet(complaint),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasTechSignature ? const Color(0xFF10B981) : const Color(0xFF4F46E5),
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: Icon(hasTechSignature ? Icons.check_circle : Icons.draw_outlined, color: Colors.white, size: 18),
                      label: Text(
                        hasTechSignature ? 'Technician Signature Captured ✓' : 'Take Technician Signature',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      onPressed: hasPendingPaymentOrders ? null : () => _takeTechnicianSignature(complaint),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasCustomerSignature ? const Color(0xFF10B981) : const Color(0xFF7C3AED),
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: Icon(hasCustomerSignature ? Icons.check_circle : Icons.draw_outlined, color: Colors.white, size: 18),
                      label: Text(
                        hasCustomerSignature ? 'Customer Signature Captured ✓' : 'Take Customer Signature',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      onPressed: hasPendingPaymentOrders ? null : () => _takeSignature(complaint),
                    ),
                    const SizedBox(height: 10),

                    // Optional Seal Number After Service
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6D28D9),
                        side: const BorderSide(color: Color(0xFF6D28D9)),
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.lock_outline, size: 18),
                      label: Text(
                        complaint.sealNumberAfter != null && complaint.sealNumberAfter!.isNotEmpty
                            ? 'Seal (After): ${complaint.sealNumberAfter} (Edit)'
                            : 'Record Seal Number (After Service) - Optional',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: hasPendingPaymentOrders ? null : () => _promptSealAfter(context, ref, complaint),
                    ),
                    const SizedBox(height: 14),

                    if (!allResolutionItemsCaptured && !hasPendingPaymentOrders) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Required to unlock closure:\n${[
                            if (!hasAfterPhoto) '• After-Solve Photo',
                            if (!hasTechSignature) '• Technician Signature',
                            if (!hasCustomerSignature) '• Customer Signature',
                          ].join('\n')}',
                          style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (allResolutionItemsCaptured && !hasPendingPaymentOrders) ? const Color(0xFF10B981) : Colors.grey.shade400,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.task_alt, color: Colors.white),
                        label: const Text('Mark Resolution Submitted', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        onPressed: (allResolutionItemsCaptured && !hasPendingPaymentOrders)
                            ? () async {
                                await ref.read(complaintsProvider.notifier).completeComplaint(complaint.id);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Resolution submitted! Pending Service Head approval.'), backgroundColor: Color(0xFF10B981)),
                                  );
                                }
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (complaint.beforeImageUrl != null || complaint.afterImageUrl != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (complaint.beforeImageUrl != null && complaint.beforeImageUrl!.trim().isNotEmpty) ...[
                      const Text('BEFORE ISSUE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
                      const SizedBox(height: 4),
                      _buildPhotoList(complaint.beforeImageUrl, complaint: complaint),
                      const SizedBox(height: 16),
                    ] else ...[
                      const Text('BEFORE ISSUE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
                      const SizedBox(height: 4),
                      Text('No image uploaded', style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontStyle: FontStyle.italic)),
                      const SizedBox(height: 16),
                    ],
                    if (complaint.afterImageUrl != null && complaint.afterImageUrl!.isNotEmpty) ...[
                      const Text('AFTER ISSUE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                      const SizedBox(height: 4),
                      _buildPhotoList(complaint.afterImageUrl, canRemove: !isClosed && isTechnician, complaint: complaint),
                    ],
                  ],
                ),
              ),
            ],

            // Service Head / Admin Approval Panel (When complaint is marked done by Tech)
            if (complaint.status == 'pending_approval' && isAdminOrCoordinator) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.shade400),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.hourglass_top, color: Colors.amber),
                        SizedBox(width: 8),
                        Text('Resolution Submitted by Technician', style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.bold, color: Colors.amber)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text('Technician has resolved issue and captured customer signature. Click below to approve and close complaint.', style: TextStyle(fontSize: 12, color: Colors.black87)),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.check_circle, color: Colors.white),
                        label: const Text('Approve & Mark Completed Permanently', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        onPressed: () async {
                          await ref.read(complaintsProvider.notifier).approveComplaint(complaint.id);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Complaint approved & permanently closed!'), backgroundColor: Color(0xFF10B981)),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Completion Report PDF Action Panel (When Closed)
            if (isClosed) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF10B981)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified, color: Color(0xFF10B981)),
                        SizedBox(width: 8),
                        Text('Service Completion Report', style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('Official report generated with customer signature confirmation.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6D28D9)),
                            icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 18),
                            label: const Text('View PDF', style: TextStyle(color: Colors.white)),
                            onPressed: () async {
                              final pdfBytes = await ComplaintPdfService.generateCompletionReportPdf(complaint);
                              if (mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (ctx) => PdfPreviewScreen(
                                      pdfBytes: pdfBytes,
                                      fileName: 'CompletionReport_${complaint.ticketNumber.replaceAll(RegExp(r'[/\\?%*:|"<>]'), '_')}.pdf',
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                            icon: const Icon(Icons.share, color: Colors.white, size: 18),
                            label: const Text('Share PDF', style: TextStyle(color: Colors.white)),
                            onPressed: () => ComplaintPdfService.shareCompletionReport(complaint),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }
}

class _DefectedPartsOrderSheet extends ConsumerStatefulWidget {
  final Complaint complaint;
  final List<InventoryItem> inventoryItems;
  final DateTime purchaseDate;
  final String techName;
  final ComplaintPartOrder? existingOrder;

  const _DefectedPartsOrderSheet({
    required this.complaint,
    required this.inventoryItems,
    required this.purchaseDate,
    required this.techName,
    this.existingOrder,
  });

  @override
  ConsumerState<_DefectedPartsOrderSheet> createState() => _DefectedPartsOrderSheetState();
}

class _DefectedPartsOrderSheetState extends ConsumerState<_DefectedPartsOrderSheet> {
  final List<Map<String, dynamic>> _orderItems = [];
  InventoryItem? _selectedItem;
  int _qty = 1;
  String _selectedReason = 'Voltage issue';
  final List<String> _reasonOptions = [
    'Voltage issue',
    'System Warranty over',
    'Other person serviced the system',
    'Component failure / burnout',
    'Physical or weather damage',
    'Aging / Wear & Tear',
    'Other',
  ];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.inventoryItems.isNotEmpty) {
      _selectedItem = widget.inventoryItems.first;
    }
    if (widget.existingOrder != null) {
      for (final item in widget.existingOrder!.items) {
        _orderItems.add(Map<String, dynamic>.from(item));
      }
    }
  }

  bool _checkItemWarranty(InventoryItem item) {
    final expiry = widget.purchaseDate.add(Duration(days: item.warrantyMonths * 30));
    return DateTime.now().isBefore(expiry);
  }

  void _addItem() {
    if (_selectedItem == null) return;
    final inWarranty = _checkItemWarranty(_selectedItem!);
    final unitPrice = inWarranty ? 0.0 : _selectedItem!.price;

    setState(() {
      final existingIndex = _orderItems.indexWhere((item) =>
          (item['inventory_id'] == _selectedItem!.id ||
              (item['item_name'] as String).trim().toLowerCase() ==
                  _selectedItem!.itemName.trim().toLowerCase()) &&
          item['is_warranty'] == inWarranty);

      if (existingIndex != -1) {
        final existing = _orderItems[existingIndex];
        final oldQty = (existing['quantity'] as num?)?.toInt() ?? 1;
        final newQty = oldQty + _qty;
        existing['quantity'] = newQty;
        existing['total_price'] = unitPrice * newQty;
        existing['reason'] = _selectedReason;
      } else {
        final totalPrice = unitPrice * _qty;
        _orderItems.add({
          'item_name': _selectedItem!.itemName,
          'inventory_id': _selectedItem!.id,
          'quantity': _qty,
          'unit_price': unitPrice,
          'total_price': totalPrice,
          'is_warranty': inWarranty,
          'warranty_months': _selectedItem!.warrantyMonths,
          'reason': _selectedReason,
        });
      }
      _qty = 1;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Updated ${_selectedItem!.itemName} in order list'),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  void _submitOrder() async {
    if (_orderItems.isEmpty || _isSubmitting) return;
    setState(() => _isSubmitting = true);

    final grandTotal = _orderItems.fold<double>(
      0.0,
      (sum, i) => sum + ((i['total_price'] as num?)?.toDouble() ?? 0.0),
    );

    try {
      if (widget.existingOrder != null) {
        await ref.read(partOrdersServiceProvider).updatePartOrder(
          orderId: widget.existingOrder!.id,
          complaintId: widget.complaint.id,
          items: _orderItems,
          totalAmount: grandTotal,
          isWarranty: grandTotal <= 0,
        );

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Order #${widget.existingOrder!.id.substring(0, 8).toUpperCase()} updated successfully!'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      } else {
        await ref.read(partOrdersServiceProvider).createPartOrder(
          complaintId: widget.complaint.id,
          customerId: widget.complaint.customerId.isNotEmpty ? widget.complaint.customerId : null,
          customerName: widget.complaint.customerName,
          items: _orderItems,
          totalAmount: grandTotal,
          isWarranty: grandTotal <= 0,
          createdBy: widget.techName,
        );

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(grandTotal <= 0
                  ? 'Defected item order submitted! Covered under warranty.'
                  : 'Defected item order submitted! Total: ₹${grandTotal.toStringAsFixed(2)} - Sent to customer for payment.'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final grandTotal = _orderItems.fold<double>(
      0.0,
      (sum, i) => sum + ((i['total_price'] as num?)?.toDouble() ?? 0.0),
    );
    final inWarranty = _selectedItem != null ? _checkItemWarranty(_selectedItem!) : false;
    final isEditing = widget.existingOrder != null;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.88,
        color: Colors.white,
        child: Column(
          children: [
            // Fixed Modal Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6D28D9).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(isEditing ? Icons.edit_note_rounded : Icons.build_circle_outlined, color: const Color(0xFF6D28D9), size: 24),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isEditing ? 'Edit Part Order #${widget.existingOrder!.id.substring(0, 8).toUpperCase()}' : 'Defected Item & Parts Order', style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(isEditing ? 'Update replacement items in this order' : 'Order genuine parts from company inventory', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Customer Purchase Date (Read-only, locked from warranty card)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_outlined, size: 18, color: Color(0xFF059669)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Customer Purchase Date: ${DateFormat('dd MMM yyyy').format(widget.purchaseDate)}',
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                ),
                                const Text(
                                  'Verified from official warranty records (Locked)',
                                  style: TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock, size: 12, color: Colors.black54),
                                SizedBox(width: 4),
                                Text('Locked', style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Defect Reason Dropdown (Selected once overall at top)
                    DropdownButtonFormField<String>(
                      initialValue: _selectedReason,
                      decoration: InputDecoration(
                        labelText: 'Reason for Part Replacement *',
                        prefixIcon: const Icon(Icons.build_circle_outlined, color: Color(0xFF6D28D9)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      items: _reasonOptions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedReason = val);
                      },
                    ),
                    const SizedBox(height: 14),

                    // Searchable Inventory Dropdown
                    SearchableDropdown<InventoryItem>(
                      label: 'Select Defected Item from Inventory *',
                      value: _selectedItem,
                      items: widget.inventoryItems,
                      itemLabel: (item) => item.itemName,
                      itemSubtitle: (item) => 'Price: ₹${item.price.toStringAsFixed(2)} | Warranty: ${item.warrantyMonths}m',
                      onChanged: (item) {
                        setState(() => _selectedItem = item);
                      },
                      decoration: InputDecoration(
                        labelText: 'Select Defected Item from Inventory *',
                        hintText: 'Search parts catalog...',
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF6D28D9)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Warranty Indicator for Selected Item
                    if (_selectedItem != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: inWarranty ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: inWarranty ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              inWarranty ? Icons.verified_user : Icons.warning_amber_rounded,
                              color: inWarranty ? const Color(0xFF059669) : const Color(0xFFDC2626),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    inWarranty
                                        ? 'UNDER WARRANTY (Free Replacement - ₹0)'
                                        : 'OUT OF WARRANTY (Chargeable to Customer)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: inWarranty ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                    ),
                                  ),
                                  Text(
                                    'Warranty period: ${_selectedItem!.warrantyMonths} months | Catalog price: ₹${_selectedItem!.price.toStringAsFixed(2)}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Quantity controls and Add to Order List button
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.white,
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove, size: 18),
                                onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                              ),
                              Text('$_qty', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              IconButton(
                                icon: const Icon(Icons.add, size: 18),
                                onPressed: () => setState(() => _qty++),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6D28D9),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.add, color: Colors.white, size: 18),
                            label: const Text('Add to Order List', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: _selectedItem == null ? null : _addItem,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Items to Order List
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Items to Order (${_orderItems.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        if (_orderItems.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() => _orderItems.clear()),
                            child: const Text('Clear All', style: TextStyle(color: Colors.red, fontSize: 12)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_orderItems.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: const Center(
                          child: Text(
                            'No items added yet.\nSelect an item above and tap "Add to Order List".',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      ..._orderItems.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final item = entry.value;
                        final isWar = item['is_warranty'] as bool;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item['item_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text('Qty: ${item['quantity']} | Reason: ${item['reason']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                    const SizedBox(height: 4),
                                    Text(
                                      isWar ? 'FREE under Warranty' : '₹${(item['total_price'] as num).toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isWar ? const Color(0xFF059669) : const Color(0xFFB91C1C),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                onPressed: () => setState(() => _orderItems.removeAt(idx)),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),

            // Fixed Bottom Bar (No overflow!)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, -4)),
                  ],
                ),
                child: Row(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Cost to Customer:', style: TextStyle(fontSize: 11, color: Colors.black54)),
                        Text(
                          grandTotal <= 0 ? '₹0.00 (Warranty Covered)' : '₹${grandTotal.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: grandTotal <= 0 ? const Color(0xFF059669) : const Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6D28D9),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: _isSubmitting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Icon(isEditing ? Icons.check_circle_outline : Icons.send_rounded, color: Colors.white, size: 18),
                        label: Text(isEditing ? 'Update Order' : 'Place Order to Company', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        onPressed: (_orderItems.isEmpty || _isSubmitting) ? null : _submitOrder,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
