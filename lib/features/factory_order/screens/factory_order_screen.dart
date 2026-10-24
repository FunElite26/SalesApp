// lib/features/factory_order/screens/factory_order_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/factory_order.dart';
import '../../../core/models/customer.dart';
import '../../../core/models/product.dart';
import '../../../core/models/pipeline.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../pipelines/providers/pipelines_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/models/user_role.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/services/notification_backend_helper.dart';
import '../../../core/widgets/pdf_preview_screen.dart';
import '../../../core/router/app_router.dart';

enum FactoryCustomFieldType {
  text,
  integer,
  dropdown;

  String get label {
    switch (this) {
      case FactoryCustomFieldType.text:
        return 'Text';
      case FactoryCustomFieldType.integer:
        return 'Integer';
      case FactoryCustomFieldType.dropdown:
        return 'Dropdown';
    }
  }

  static FactoryCustomFieldType fromString(String? val) {
    if (val == 'integer') return FactoryCustomFieldType.integer;
    if (val == 'dropdown') return FactoryCustomFieldType.dropdown;
    return FactoryCustomFieldType.text;
  }
}

class FactoryCustomFieldDef {
  final String id;
  String label;
  FactoryCustomFieldType type;
  String placeholder;
  bool isRequired;
  List<String> options;

  FactoryCustomFieldDef({
    required this.id,
    required this.label,
    required this.type,
    this.placeholder = '',
    this.isRequired = false,
    this.options = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'type': type.name,
    'placeholder': placeholder,
    'is_required': isRequired,
    'options': options,
  };

  factory FactoryCustomFieldDef.fromJson(Map<String, dynamic> json) => FactoryCustomFieldDef(
    id: json['id'] as String? ?? UniqueKey().toString(),
    label: json['label'] as String? ?? '',
    type: FactoryCustomFieldType.fromString(json['type'] as String?),
    placeholder: json['placeholder'] as String? ?? '',
    isRequired: json['is_required'] as bool? ?? false,
    options: (json['options'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        [],
  );

  FactoryCustomFieldDef copyWith({
    String? id,
    String? label,
    FactoryCustomFieldType? type,
    String? placeholder,
    bool? isRequired,
    List<String>? options,
  }) {
    return FactoryCustomFieldDef(
      id: id ?? this.id,
      label: label ?? this.label,
      type: type ?? this.type,
      placeholder: placeholder ?? this.placeholder,
      isRequired: isRequired ?? this.isRequired,
      options: options ?? List.from(this.options),
    );
  }
}

class FactoryOrderScreen extends ConsumerStatefulWidget {
  final String pipelineId;

  const FactoryOrderScreen({super.key, required this.pipelineId});

  @override
  ConsumerState<FactoryOrderScreen> createState() => _FactoryOrderScreenState();
}

class _FactoryOrderScreenState extends ConsumerState<FactoryOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  DateTime? _expectedCompletionDate;
  DateTime? _boqDispatchDate;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  FactoryOrder? _existingOrder;
  SalesPipeline? _pipeline;
  List<FactoryOrderItem> _items = [];
  List<Map<String, dynamic>> _catalogItems = [];

  // Custom Fields state
  String _customSectionTitle = 'Additional Details';
  List<FactoryCustomFieldDef> _customFieldDefs = [];
  final Map<String, TextEditingController> _customControllers = {};
  final Map<String, String> _customDropdownValues = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final controller in _customControllers.values) {
      controller.dispose();
    }
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final supabase = ref.read(supabaseClientProvider);

      // Load catalog items
      final catalogData = await supabase
          .from('manufacturing_items')
          .select('id, name, description')
          .order('name');
      _catalogItems = List<Map<String, dynamic>>.from(catalogData);

      final pipelineData = await supabase
          .from('sales_pipelines')
          .select('*, products(*), customers(*)')
          .eq('id', widget.pipelineId)
          .single();
      _pipeline = SalesPipeline.fromJson(pipelineData);

      // Fetch BOQ dispatch date
      final boqData = await supabase
          .from('boqs')
          .select('tentative_dispatch_date')
          .eq('pipeline_id', widget.pipelineId)
          .maybeSingle();

      if (boqData != null && boqData['tentative_dispatch_date'] != null) {
        _boqDispatchDate = DateTime.tryParse(boqData['tentative_dispatch_date'] as String);
      }

      // Load existing factory order
      final foData = await supabase
          .from('factory_orders')
          .select()
          .eq('pipeline_id', widget.pipelineId)
          .maybeSingle();

      if (foData != null) {
        _existingOrder = FactoryOrder.fromJson(foData);
        _isEditing = _existingOrder!.status != FactoryOrderStatus.completed;
        _notesController.text = _existingOrder!.factoryNotes ?? '';
        _expectedCompletionDate = _existingOrder!.expectedCompletionDate;
        _items = List<FactoryOrderItem>.from(_existingOrder!.items);
      } else {
        _isEditing = true;
        _items = [];
      }

      // Load custom field template and values
      await _loadCustomFields();
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

  Future<void> _loadCustomFields() async {
    final productId = _pipeline?.productId;
    final prefs = await SharedPreferences.getInstance();

    final existingSpecs = _existingOrder?.productionSpecs;
    if (existingSpecs != null && existingSpecs.isNotEmpty) {
      if (existingSpecs['custom_fields_title'] is String &&
          (existingSpecs['custom_fields_title'] as String).trim().isNotEmpty) {
        _customSectionTitle = (existingSpecs['custom_fields_title'] as String).trim();
      }
      if (existingSpecs['custom_fields_defs'] is List) {
        _customFieldDefs = (existingSpecs['custom_fields_defs'] as List)
            .map((e) => FactoryCustomFieldDef.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    }

    if (_customFieldDefs.isEmpty && productId != null) {
      try {
        final supabase = ref.read(supabaseClientProvider);
        final templateData = await supabase
            .from('factory_custom_fields_templates')
            .select()
            .eq('product_id', productId)
            .maybeSingle();

        if (templateData != null) {
          if (templateData['section_title'] != null &&
              (templateData['section_title'] as String).trim().isNotEmpty) {
            _customSectionTitle = (templateData['section_title'] as String).trim();
          }
          if (templateData['fields'] is List) {
            _customFieldDefs = (templateData['fields'] as List)
                .map((e) => FactoryCustomFieldDef.fromJson(
                    Map<String, dynamic>.from(e as Map)))
                .toList();
          }
        }
      } catch (_) {
        // Fallback to local SharedPreferences
        final cached =
            prefs.getString('factory_custom_fields_template_$productId');
        if (cached != null) {
          try {
            final json = jsonDecode(cached) as Map<String, dynamic>;
            _customSectionTitle =
                json['section_title'] as String? ?? 'Additional Details';
            if (json['fields'] is List) {
              _customFieldDefs = (json['fields'] as List)
                  .map((e) => FactoryCustomFieldDef.fromJson(
                      Map<String, dynamic>.from(e as Map)))
                  .toList();
            }
          } catch (_) {}
        }
      }
    }

    // Populate controllers and dropdown values
    for (final def in _customFieldDefs) {
      final existingVal = existingSpecs?['custom_fields']?[def.label] ??
          existingSpecs?[def.label];
      if (def.type == FactoryCustomFieldType.dropdown) {
        _customDropdownValues[def.id] = existingVal?.toString() ?? '';
      } else {
        _customControllers[def.id] =
            TextEditingController(text: existingVal?.toString() ?? '');
      }
    }
  }

  Future<void> _saveOrder(FactoryOrderStatus status) async {
    if (!_formKey.currentState!.validate()) return;

    final role = ref.read(currentProfileProvider)?.primaryRole;

    // Only factory / admin can set it to in_production
    if (status == FactoryOrderStatus.inProduction &&
        role != UserRole.factory &&
        role != UserRole.admin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only factory team can start production'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (status == FactoryOrderStatus.completed &&
        _expectedCompletionDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an expected completion date first.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final customFieldsMap = <String, dynamic>{};
    for (final def in _customFieldDefs) {
      final val = def.type == FactoryCustomFieldType.dropdown
          ? _customDropdownValues[def.id]
          : _customControllers[def.id]?.text.trim();
      if (val != null && val.toString().trim().isNotEmpty) {
        customFieldsMap[def.label] = val;
      }
    }

    final specs = <String, dynamic>{
      'custom_fields': customFieldsMap,
      'custom_fields_title': _customSectionTitle,
      'custom_fields_defs': _customFieldDefs.map((d) => d.toJson()).toList(),
    };

    setState(() => _isSaving = true);

    try {
      final supabase = ref.read(supabaseClientProvider);

      final data = {
        'pipeline_id': widget.pipelineId,
        'production_specs': specs,
        'factory_notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'expected_completion_date': _expectedCompletionDate?.toIso8601String(),
        'status': status.dbValue,
        'items': _items.map((i) => i.toJson()).toList(),
      };

      final wasCompleted =
          _existingOrder?.status == FactoryOrderStatus.completed;

      String orderId;
      if (_existingOrder != null) {
        await supabase
            .from('factory_orders')
            .update(data)
            .eq('id', _existingOrder!.id);
        orderId = _existingOrder!.id;
      } else {
        final res = await supabase
            .from('factory_orders')
            .insert(data)
            .select('id')
            .single();
        orderId = (res as Map)['id'] as String;
      }

      // Generate and upload PDF if completed
      if (status == FactoryOrderStatus.completed) {
        await _generateAndUploadPdf(orderId, showPrintDialog: false);
      }

      if (status == FactoryOrderStatus.completed && !wasCompleted) {
        // Advance pipeline
        await supabase.from('sales_pipelines').update(
            {'current_step': 'purchase_order'}).eq('id', widget.pipelineId);

        final customerName = _pipeline?.customer?.companyName ?? '';
        final productName = _pipeline?.product?.name ?? 'product';
        final custSuffix = customerName.isNotEmpty ? ' (Customer: $customerName)' : '';

        // Notify sales executive who created the pipeline
        if (_pipeline?.createdBy != null && _pipeline!.createdBy.isNotEmpty) {
          await NotificationBackendHelper.notifyUser(
            supabase: supabase,
            userId: _pipeline!.createdBy,
            title: 'Factory Order Completed',
            body:
                'The factory order for $productName$custSuffix has been completed by the factory team.',
            type: 'step_unlocked',
            relatedPipelineId: widget.pipelineId,
          );
        }

        // Notify admin team
        final adminUsers = await supabase
            .from('profiles')
            .select('id')
            .eq('role', 'admin')
            .eq('is_active', true);

        final Set<String> adminIds = {};
        for (final u in (adminUsers as List<dynamic>)) {
          final adminId = (u as Map)['id']?.toString();
          if (adminId != null && adminId.isNotEmpty && adminId != _pipeline?.createdBy) {
            adminIds.add(adminId);
          }
        }

        for (final adminId in adminIds) {
          await NotificationBackendHelper.notifyUser(
            supabase: supabase,
            userId: adminId,
            title: 'Factory Order Completed',
            body:
                'The factory order for $productName$custSuffix has been completed.',
            type: 'step_unlocked',
            relatedPipelineId: widget.pipelineId,
          );
        }

        // Notify purchase team
        final purchaseUsers = await supabase
            .from('profiles')
            .select('id')
            .eq('role', 'purchase')
            .eq('is_active', true);

        final Set<String> purchaseIds = {};
        for (final u in (purchaseUsers as List<dynamic>)) {
          final pId = (u as Map)['id']?.toString();
          if (pId != null && pId.isNotEmpty) {
            purchaseIds.add(pId);
          }
        }

        for (final pId in purchaseIds) {
          await NotificationBackendHelper.notifyUser(
            supabase: supabase,
            userId: pId,
            title: 'New Material Requisition Assigned',
            body:
                'Factory order completed$custSuffix. Material Requisition step is now available.',
            type: 'step_unlocked',
            relatedPipelineId: widget.pipelineId,
          );
        }

        // Audit log
        await supabase.from('step_audit_log').insert({
          'pipeline_id': widget.pipelineId,
          'step_name': 'factory_order',
          'action': 'confirmed',
          'performed_by': supabase.auth.currentUser!.id,
        });
      } else if (wasCompleted) {
        // Audit log for update
        await supabase.from('step_audit_log').insert({
          'pipeline_id': widget.pipelineId,
          'step_name': 'factory_order',
          'action': 'updated',
          'performed_by': supabase.auth.currentUser!.id,
        });
      }

      ref.invalidate(pipelineDetailProvider(widget.pipelineId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == FactoryOrderStatus.completed
                  ? '✓ Factory Order completed! Material Requisition step unlocked.'
                  : '✓ Factory Order updated.',
            ),
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

  Future<void> _saveCustomFieldsTemplate(
      String newTitle, List<FactoryCustomFieldDef> newDefs) async {
    final productId = _pipeline?.productId;
    if (productId == null) return;

    final finalTitle =
        newTitle.trim().isEmpty ? 'Additional Details' : newTitle.trim();

    try {
      final supabase = ref.read(supabaseClientProvider);
      final prefs = await SharedPreferences.getInstance();

      final payload = {
        'product_id': productId,
        'product_name': _pipeline?.product?.name ?? '',
        'section_title': finalTitle,
        'fields': newDefs.map((d) => d.toJson()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Save locally
      await prefs.setString(
          'factory_custom_fields_template_$productId', jsonEncode(payload));

      // Save to Supabase
      try {
        await supabase.from('factory_custom_fields_templates').upsert(
              payload,
              onConflict: 'product_id',
            );
      } catch (err) {
        debugPrint('Supabase template upsert error (cached locally): $err');
      }

      if (mounted) {
        setState(() {
          _customSectionTitle = finalTitle;
          _customFieldDefs = List.from(newDefs);

          // Ensure controllers for each field
          for (final def in _customFieldDefs) {
            if (def.type == FactoryCustomFieldType.dropdown) {
              _customDropdownValues.putIfAbsent(def.id, () => '');
            } else {
              _customControllers.putIfAbsent(
                  def.id, () => TextEditingController());
            }
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✓ Custom fields saved for ${_pipeline?.product?.name ?? "product"}'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving template: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showManageCustomFieldsSheet() {
    final titleController = TextEditingController(text: _customSectionTitle);
    List<FactoryCustomFieldDef> tempDefs =
        _customFieldDefs.map((d) => d.copyWith()).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              height: MediaQuery.of(ctx).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Configure Custom Fields',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Product: ${_pipeline?.product?.name ?? "Current Product"}',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 20),

                  // Section Title Setting
                  const Text(
                    'Section Title (In Form & PDF Export)',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Additional Details, Technical Specs',
                      isDense: true,
                      prefixIcon: Icon(Icons.title, size: 18),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Fields List Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Fields (${tempDefs.length})',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          _showEditFieldDialog(
                            onSave: (newField) {
                              setSheetState(() {
                                tempDefs.add(newField);
                              });
                            },
                          );
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Field'),
                      ),
                    ],
                  ),

                  // Fields List
                  Expanded(
                    child: tempDefs.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.tune,
                                      size: 48, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No custom fields configured for this product yet.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      _showEditFieldDialog(
                                        onSave: (newField) {
                                          setSheetState(() {
                                            tempDefs.add(newField);
                                          });
                                        },
                                      );
                                    },
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Add First Field'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: tempDefs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, idx) {
                              final field = tempDefs[idx];
                              IconData typeIcon;
                              Color iconColor;
                              switch (field.type) {
                                case FactoryCustomFieldType.integer:
                                  typeIcon = Icons.numbers;
                                  iconColor = AppColors.info;
                                  break;
                                case FactoryCustomFieldType.dropdown:
                                  typeIcon =
                                      Icons.arrow_drop_down_circle_outlined;
                                  iconColor = AppColors.accent;
                                  break;
                                case FactoryCustomFieldType.text:
                                  typeIcon = Icons.text_fields;
                                  iconColor = AppColors.primary;
                                  break;
                              }

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: iconColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(typeIcon,
                                          size: 20, color: iconColor),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  field.label,
                                                  style: const TextStyle(
                                                    fontFamily: 'Inter',
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppColors.textPrimary,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (field.isRequired) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.error
                                                        .withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(4),
                                                  ),
                                                  child: const Text(
                                                    'Required',
                                                    style: TextStyle(
                                                      fontFamily: 'Inter',
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: AppColors.error,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            field.type ==
                                                    FactoryCustomFieldType.dropdown
                                                ? 'Dropdown • ${field.options.join(", ")}'
                                                : '${field.type.label}${field.placeholder.isNotEmpty ? " • Placeholder: ${field.placeholder}" : ""}',
                                            style: const TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 18, color: AppColors.primary),
                                      tooltip: 'Edit Field',
                                      onPressed: () {
                                        _showEditFieldDialog(
                                          fieldToEdit: field,
                                          onSave: (updated) {
                                            setSheetState(() {
                                              tempDefs[idx] = updated;
                                            });
                                          },
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18, color: AppColors.error),
                                      tooltip: 'Delete Field',
                                      onPressed: () {
                                        setSheetState(() {
                                          tempDefs.removeAt(idx);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),

                  // Bottom Save Action
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _saveCustomFieldsTemplate(
                            titleController.text, tempDefs);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Save & Apply Configuration'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) => titleController.dispose());
  }

  void _showEditFieldDialog({
    FactoryCustomFieldDef? fieldToEdit,
    required Function(FactoryCustomFieldDef) onSave,
  }) {
    final labelCtrl = TextEditingController(text: fieldToEdit?.label ?? '');
    final placeholderCtrl =
        TextEditingController(text: fieldToEdit?.placeholder ?? '');
    final optionsCtrl =
        TextEditingController(text: fieldToEdit?.options.join(', ') ?? '');
    var selectedType = fieldToEdit?.type ?? FactoryCustomFieldType.text;
    var isRequired = fieldToEdit?.isRequired ?? false;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(
                fieldToEdit == null ? 'Add Custom Field' : 'Edit Custom Field',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Label
                        const Text(
                          'Field Label *',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: labelCtrl,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Tank Capacity, Boom Length',
                            isDense: true,
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Field label is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // Field Type
                        const Text(
                          'Field Type *',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<FactoryCustomFieldType>(
                          initialValue: selectedType,
                          decoration: const InputDecoration(
                            isDense: true,
                          ),
                          items: FactoryCustomFieldType.values.map((t) {
                            return DropdownMenuItem(
                              value: t,
                              child: Text(t.label),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDlgState(() => selectedType = val);
                            }
                          },
                        ),
                        const SizedBox(height: 14),

                        // Placeholder
                        const Text(
                          'Placeholder / Hint',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: placeholderCtrl,
                          decoration: const InputDecoration(
                            hintText: 'e.g. 500 Liters, 4 Meters',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Options (if Dropdown)
                        if (selectedType == FactoryCustomFieldType.dropdown) ...[
                          const Text(
                            'Dropdown Choices * (Comma Separated)',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: optionsCtrl,
                            decoration: const InputDecoration(
                              hintText: 'e.g. 3M, 4M, 6M, 8M',
                              isDense: true,
                            ),
                            validator: (v) {
                              if (selectedType ==
                                      FactoryCustomFieldType.dropdown &&
                                  (v == null || v.trim().isEmpty)) {
                                return 'Please enter at least one choice';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Required Switch
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Required Field',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'Must be filled before completing order',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          value: isRequired,
                          onChanged: (v) => setDlgState(() => isRequired = v),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    final optionsList = optionsCtrl.text
                        .split(',')
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toList();

                    final newField = FactoryCustomFieldDef(
                      id: fieldToEdit?.id ??
                          'fld_${DateTime.now().millisecondsSinceEpoch}',
                      label: labelCtrl.text.trim(),
                      type: selectedType,
                      placeholder: placeholderCtrl.text.trim(),
                      isRequired: isRequired,
                      options: optionsList,
                    );

                    onSave(newField);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save Field'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showChangeQtyDialog(int idx, FactoryOrderItem item) {
    final currentQty = item.qty.toInt() <= 0 ? 1 : item.qty.toInt();
    final controller = TextEditingController(text: currentQty.toString());
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Change Quantity',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: Color(0xFF1E1B4B),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.itemName,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Quantity (units)',
                hintText: 'Enter quantity',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(controller.text.trim());
              if (val != null && val > 0) {
                setState(() {
                  _items[idx] = FactoryOrderItem(
                    itemName: item.itemName,
                    qty: val.toDouble(),
                    remarks: item.remarks,
                  );
                });
                Navigator.pop(ctx);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid quantity (minimum 1)'),
                    backgroundColor: AppColors.error,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddManufacturingItemSheet() {
    final searchController = TextEditingController();
    String searchText = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            // Filter catalog items
            final filtered = _catalogItems.where((item) {
              final name = item['name'].toString().toLowerCase();
              return name.contains(searchText.toLowerCase());
            }).toList();

            final exactMatch = _catalogItems.any((item) =>
                item['name'].toString().trim().toLowerCase() ==
                searchText.trim().toLowerCase());

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Select Item to Manufacture',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search catalog items...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                searchController.clear();
                                setModalState(() {
                                  searchText = '';
                                });
                              },
                            )
                          : null,
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        searchText = val;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (c, idx) {
                        final item = filtered[idx];
                        return ListTile(
                          title: Text(
                            item['name'] ?? '',
                            style: const TextStyle(
                                fontFamily: 'Inter', fontWeight: FontWeight.w600),
                          ),
                          subtitle: item['description'] != null
                              ? Text(item['description'],
                                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12))
                              : null,
                          trailing: const Icon(Icons.add, color: AppColors.primary),
                          onTap: () {
                            setState(() {
                              _items.add(FactoryOrderItem(
                                itemName: item['name'] as String,
                                qty: 1,
                              ));
                            });
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                  if (searchText.trim().isNotEmpty && !exactMatch) ...[
                    const Divider(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final name = searchText.trim();
                          try {
                            final supabase = ref.read(supabaseClientProvider);
                            final response = await supabase
                                .from('manufacturing_items')
                                .insert({'name': name})
                                .select('id, name, description')
                                .single();
                            
                            final newItem = Map<String, dynamic>.from(response as Map);
                            setState(() {
                              _catalogItems.add(newItem);
                              _items.add(FactoryOrderItem(
                                itemName: newItem['name'] as String,
                                qty: 1,
                              ));
                            });
                            
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('✓ "$name" added to catalog!'),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                            }
                            Navigator.pop(ctx);
                          } catch (e) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                  content: Text('Error: $e'),
                                  backgroundColor: AppColors.error),
                            );
                          }
                        },
                        icon: const Icon(Icons.add_to_photos_outlined),
                        label: Text('Create & Select "$searchText"'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    ).then((_) => searchController.dispose());
  }

  Future<void> _generateAndUploadPdf(String orderId, {bool showPrintDialog = true}) async {
    final supabase = ref.read(supabaseClientProvider);
    final foData = await supabase
        .from('factory_orders')
        .select()
        .eq('id', orderId)
        .single();
    final factoryOrder = FactoryOrder.fromJson(foData);

    // Fetch latest pipeline data with customer and product details
    final pipelineData = await supabase
        .from('sales_pipelines')
        .select('*, customers(*), products(*)')
        .eq('id', factoryOrder.pipelineId)
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
          .eq('document_type', 'factory_order')
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
    final pdfBytes = await PdfService.generateFactoryOrderPdf(
      factoryOrder: factoryOrder,
      customer: customer,
      product: product,
      templateConfig: templateConfig,
    );

    // Write audit log
    await supabase.from('step_audit_log').insert({
      'pipeline_id': widget.pipelineId,
      'step_name': 'factory_order',
      'action': 'pdf_generated',
      'performed_by': supabase.auth.currentUser!.id,
    });

    if (showPrintDialog && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PdfPreviewScreen(
            pdfBytes: pdfBytes,
            fileName: '${factoryOrder.orderNumber.replaceAll('/', '_')}.pdf',
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

    final profile = ref.watch(currentProfileProvider);
    final role = profile?.primaryRole;
    final isCompleted = _existingOrder?.status == FactoryOrderStatus.completed;
    final enabled = _isEditing && role != UserRole.purchase;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isCompleted && !_isEditing
            ? 'Factory Order (Completed)'
            : 'Factory Order'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (isCompleted && !_isEditing) ...[
            TextButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: const Icon(Icons.edit, color: Colors.white, size: 16),
              label: const Text('Edit Details',
                  style: TextStyle(color: Colors.white, fontFamily: 'Inter')),
            ),
            IconButton(
              icon: const Icon(Icons.print, color: Colors.white),
              onPressed: () => _generateAndUploadPdf(_existingOrder!.id),
            ),
          ],
          if (_isEditing && isCompleted)
            TextButton(
              onPressed: _isSaving
                  ? null
                  : () => _saveOrder(FactoryOrderStatus.completed),
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
            // Tentative Dispatch Date Alert Banner
            if (_boqDispatchDate != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active, color: AppColors.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tentative Dispatch Scheduled',
                            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary),
                          ),
                          Text(
                            'Dispatch Target: ${DateFormat('dd MMMM yyyy').format(_boqDispatchDate!)}',
                            style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Header card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
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
                  Text(
                    _pipeline?.product?.name ?? '',
                    style: const TextStyle(
                        fontFamily: 'Inter', color: AppColors.textSecondary),
                  ),
                  if (_existingOrder != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _existingOrder!.orderNumber,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusChip(status: _existingOrder!.status),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Expected completion date
            const Text(
              'Expected Completion Date',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: !enabled
                  ? null
                  : () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _expectedCompletionDate ??
                            DateTime.now().add(const Duration(days: 30)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setState(() => _expectedCompletionDate = date);
                      }
                    },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        color: AppColors.textSecondary, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      _expectedCompletionDate != null
                          ? DateFormat('dd MMM yyyy')
                              .format(_expectedCompletionDate!)
                          : 'Select date...',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: _expectedCompletionDate != null
                            ? AppColors.textPrimary
                            : AppColors.textDisabled,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Manufacturing Items Section
            const Text(
              'Items to Manufacture',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No manufacturing items added yet.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ..._items.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                final currentQty = item.qty.toInt() <= 0 ? 1 : item.qty.toInt();

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          item.itemName,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Stepper: [-]  [Qty]  [+]
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Decrement button (-)
                            InkWell(
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                              onTap: !enabled || currentQty <= 1
                                  ? null
                                  : () {
                                      setState(() {
                                        _items[idx] = FactoryOrderItem(
                                          itemName: item.itemName,
                                          qty: (currentQty - 1).toDouble(),
                                          remarks: item.remarks,
                                        );
                                      });
                                    },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                child: Icon(
                                  Icons.remove,
                                  size: 16,
                                  color: !enabled || currentQty <= 1
                                      ? Colors.grey.shade400
                                      : const Color(0xFF1E1B4B),
                                ),
                              ),
                            ),
                            // Click to change Qty (strictly integer, no decimals)
                            InkWell(
                              onTap: !enabled ? null : () => _showChangeQtyDialog(idx, item),
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 44),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.symmetric(
                                    vertical: BorderSide(color: Colors.grey.shade300),
                                  ),
                                ),
                                child: Text(
                                  '$currentQty',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E1B4B),
                                  ),
                                ),
                              ),
                            ),
                            // Increment button (+)
                            InkWell(
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                              onTap: !enabled
                                  ? null
                                  : () {
                                      setState(() {
                                        _items[idx] = FactoryOrderItem(
                                          itemName: item.itemName,
                                          qty: (currentQty + 1).toDouble(),
                                          remarks: item.remarks,
                                        );
                                      });
                                    },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                child: Icon(
                                  Icons.add,
                                  size: 16,
                                  color: !enabled
                                      ? Colors.grey.shade400
                                      : const Color(0xFF1E1B4B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (enabled) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                          tooltip: 'Remove Item',
                          onPressed: () {
                            setState(() {
                              _items.removeAt(idx);
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                );
              }),
            if (enabled) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _showAddManufacturingItemSheet,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Item to Manufacture'),
                ),
              ),
            ],
            const SizedBox(height: 24),

            // ─── Custom Product Fields Section ─────────────────────
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _customSectionTitle,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (role == UserRole.admin)
                        TextButton.icon(
                          onPressed: _showManageCustomFieldsSheet,
                          icon: const Icon(Icons.tune, size: 16),
                          label: const Text(
                            'Configure Fields',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_customFieldDefs.isEmpty && role == UserRole.admin)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.border,
                            style: BorderStyle.solid),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.tune,
                                  size: 18, color: AppColors.primary),
                              SizedBox(width: 8),
                              Text(
                                'No custom fields configured for this product',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tap "Configure Fields" above to set up fields for ${_pipeline?.product?.name ?? "this product"} (e.g. Tank Capacity, Boom Length, Voltage, etc.).',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ..._customFieldDefs.map((field) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                field.label,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (field.isRequired)
                                const Text(
                                  ' *',
                                  style: TextStyle(
                                    color: AppColors.error,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (field.type == FactoryCustomFieldType.dropdown)
                            DropdownButtonFormField<String>(
                              value: (_customDropdownValues[field.id]?.isNotEmpty ?? false) &&
                                      field.options.contains(_customDropdownValues[field.id])
                                  ? _customDropdownValues[field.id]
                                  : null,
                              decoration: InputDecoration(
                                hintText: field.placeholder.isNotEmpty
                                    ? field.placeholder
                                    : 'Select ${field.label}...',
                              ),
                              items: field.options.map((opt) {
                                return DropdownMenuItem(
                                  value: opt,
                                  child: Text(opt),
                                );
                              }).toList(),
                              onChanged: enabled
                                  ? (val) => setState(() =>
                                      _customDropdownValues[field.id] =
                                          val ?? '')
                                  : null,
                              validator: (val) {
                                if (field.isRequired &&
                                    (val == null || val.trim().isEmpty)) {
                                  return 'Please select ${field.label}';
                                }
                                return null;
                              },
                            )
                          else if (field.type == FactoryCustomFieldType.integer)
                            TextFormField(
                              controller: _customControllers[field.id],
                              enabled: enabled,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: InputDecoration(
                                hintText: field.placeholder.isNotEmpty
                                    ? field.placeholder
                                    : 'Enter ${field.label}...',
                              ),
                              validator: (val) {
                                if (field.isRequired &&
                                    (val == null || val.trim().isEmpty)) {
                                  return 'Please enter ${field.label}';
                                }
                                return null;
                              },
                            )
                          else
                            TextFormField(
                              controller: _customControllers[field.id],
                              enabled: enabled,
                              keyboardType: TextInputType.text,
                              decoration: InputDecoration(
                                hintText: field.placeholder.isNotEmpty
                                    ? field.placeholder
                                    : 'Enter ${field.label}...',
                              ),
                              validator: (val) {
                                if (field.isRequired &&
                                    (val == null || val.trim().isEmpty)) {
                                  return 'Please enter ${field.label}';
                                }
                                return null;
                              },
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),

            // Notes
            const Text(
              'Factory Notes',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _notesController,
              maxLines: 5,
              enabled: enabled,
              decoration: const InputDecoration(
                hintText: 'Add internal production notes...',
              ),
            ),
            const SizedBox(height: 24),

            // Actions
            if ((!isCompleted || _isEditing) && role != UserRole.purchase) ...[
              if (role == UserRole.factory || role == UserRole.admin)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () => _saveOrder(FactoryOrderStatus.completed),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.done_all),
                    label: Text(_isSaving
                        ? 'Saving...'
                        : (isCompleted
                            ? 'Save Changes & Print'
                            : 'Mark as Complete & Unlock Material Requisition')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              if (!isCompleted)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isSaving
                        ? null
                        : () => _saveOrder(FactoryOrderStatus.inProduction),
                    child: const Text('Save / Update'),
                  ),
                ),
            ],
            if (isCompleted && !_isEditing)
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
                        'Factory order completed. Material Requisition step is unlocked.',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.success,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () =>
                          _generateAndUploadPdf(_existingOrder!.id),
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

class _StatusChip extends StatelessWidget {
  final FactoryOrderStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    Color bg;
    switch (status) {
      case FactoryOrderStatus.pending:
        color = AppColors.warning;
        bg = AppColors.warningLight;
        break;
      case FactoryOrderStatus.inProduction:
        color = AppColors.info;
        bg = AppColors.infoLight;
        break;
      case FactoryOrderStatus.completed:
        color = AppColors.success;
        bg = AppColors.successLight;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
