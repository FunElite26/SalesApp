import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/pm_tokens.dart';
import '../../providers/pm_providers.dart';
import '../../data/models/pm_checklist_item.dart';
import '../widgets/pm_button.dart';
import '../widgets/pm_card.dart';
import '../widgets/pm_badge.dart';
import '../../../admin/providers/inventory_provider.dart';
import '../../../../core/models/inventory_item.dart';

class PmSwhChecklistTab extends ConsumerStatefulWidget {
  final String projectId;
  final VoidCallback onRefresh;

  const PmSwhChecklistTab({
    super.key,
    required this.projectId,
    required this.onRefresh,
  });

  @override
  ConsumerState<PmSwhChecklistTab> createState() => _PmSwhChecklistTabState();
}

class _PmSwhChecklistTabState extends ConsumerState<PmSwhChecklistTab> {
  final ScrollController _hScrollCtrl = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _hScrollCtrl.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pm = context.pm;
    final itemsAsync = ref.watch(pmChecklistItemsProvider(widget.projectId));

    return itemsAsync.when(
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
      error: (err, _) => Center(child: Text('Error: $err', style: TextStyle(color: pm.destructive))),
      data: (items) {
        final filteredItems = items.where((it) {
          if (_searchQuery.trim().isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          return it.itemName.toLowerCase().contains(q) ||
              (it.remark != null && it.remark!.toLowerCase().contains(q));
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text('SWH & Heat Pump Technical Checklist', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: pm.foreground)),
                    const SizedBox(width: 8),
                    PmBadge(label: '${filteredItems.length} Items', variant: PmBadgeVariant.secondary),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (items.isNotEmpty) ...[
                      SizedBox(
                        width: 220,
                        height: 36,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) => setState(() => _searchQuery = val),
                          style: TextStyle(fontSize: 13, color: pm.foreground),
                          decoration: InputDecoration(
                            hintText: 'Search checklist...',
                            hintStyle: TextStyle(fontSize: 13, color: pm.mutedForeground),
                            prefixIcon: Icon(LucideIcons.search, size: 14, color: pm.mutedForeground),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(LucideIcons.x, size: 14, color: pm.mutedForeground),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            isDense: true,
                            filled: true,
                            fillColor: pm.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(pm.radiusMd),
                              borderSide: BorderSide(color: pm.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(pm.radiusMd),
                              borderSide: BorderSide(color: pm.border),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    PmButton(
                      size: PmButtonSize.sm,
                      onPressed: () => _showAddEditModal(context, ref),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.plus, size: 14),
                          SizedBox(width: 6),
                          Text('Add Item'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              PmCard(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    children: [
                      Icon(LucideIcons.listCheck, size: 40, color: pm.mutedForeground.withOpacity(0.5)),
                      const SizedBox(height: 10),
                      Text('No checklist items added for this installation yet.', style: TextStyle(color: pm.mutedForeground)),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () => _showAddEditModal(context, ref),
                        borderRadius: BorderRadius.circular(9999),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF005CE6),
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: const Text(
                            '+ Add Checklist Item',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              PmCard(
                padding: EdgeInsets.zero,
                child: Scrollbar(
                  controller: _hScrollCtrl,
                  thumbVisibility: true,
                  trackVisibility: true,
                  child: SingleChildScrollView(
                    controller: _hScrollCtrl,
                    scrollDirection: Axis.horizontal,
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 1200),
                      child: DataTable(
                    headingRowColor: WidgetStateProperty.all(pm.secondary.withOpacity(0.6)),
                    columns: const [
                      DataColumn(label: Text('SR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('ITEM NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                      DataColumn(numeric: true, label: Text('REQ QTY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('CUSTOMER SCOPE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('OUR SCOPE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                      DataColumn(numeric: true, label: Text('DISPATCH QTY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('DISPATCHED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                      DataColumn(numeric: true, label: Text('INSTALLED QTY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('INSTALLED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                      DataColumn(numeric: true, label: Text('BALANCE QTY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('REMARK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('ACTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                    ],
                    rows: filteredItems.map((item) {
                      final balQty = item.reqQty - item.dispatchQty;
                      return DataRow(
                        cells: [
                          DataCell(Text('#${item.srNo}', style: TextStyle(fontSize: 11, color: pm.mutedForeground, fontWeight: FontWeight.bold))),
                          DataCell(Text(item.itemName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                          DataCell(Text('${item.reqQty}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                          DataCell(Checkbox(
                            value: item.customerScope,
                            onChanged: (val) async {
                              final newCust = val ?? false;
                              await ref.read(pmLedgerRepositoryProvider).updateChecklistItem(item.id, {
                                'customer_scope': newCust,
                                if (newCust) 'our_scope': false,
                              });
                              ref.invalidate(pmChecklistItemsProvider(widget.projectId));
                            },
                          )),
                          DataCell(Checkbox(
                            value: item.ourScope,
                            onChanged: (val) async {
                              final newOur = val ?? false;
                              await ref.read(pmLedgerRepositoryProvider).updateChecklistItem(item.id, {
                                'our_scope': newOur,
                                if (newOur) 'customer_scope': false,
                              });
                              ref.invalidate(pmChecklistItemsProvider(widget.projectId));
                            },
                          )),
                          DataCell(Text('${item.dispatchQty}', style: const TextStyle(fontSize: 12))),
                          DataCell(Checkbox(
                            value: item.dispatchYesNo,
                            onChanged: (val) async {
                              await ref.read(pmLedgerRepositoryProvider).updateChecklistItem(item.id, {'dispatch_yes_no': val ?? false});
                              ref.invalidate(pmChecklistItemsProvider(widget.projectId));
                            },
                          )),
                          DataCell(Text('${item.installedQty}', style: const TextStyle(fontSize: 12))),
                          DataCell(Checkbox(
                            value: item.installationYesNo,
                            onChanged: (val) async {
                              await ref.read(pmLedgerRepositoryProvider).updateChecklistItem(item.id, {'installation_yes_no': val ?? false});
                              ref.invalidate(pmChecklistItemsProvider(widget.projectId));
                            },
                          )),
                          DataCell(Text(
                            '$balQty',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: balQty > 0 ? pm.warning : pm.success),
                          )),
                          DataCell(Text(item.remark ?? '-', style: TextStyle(fontSize: 12, color: pm.mutedForeground))),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(LucideIcons.pencil, size: 14),
                                  onPressed: () => _showAddEditModal(context, ref, item),
                                ),
                                IconButton(
                                  icon: Icon(LucideIcons.trash2, size: 14, color: pm.destructive),
                                  onPressed: () async {
                                    await ref.read(pmLedgerRepositoryProvider).deleteChecklistItem(item.id);
                                    ref.invalidate(pmChecklistItemsProvider(widget.projectId));
                                    widget.onRefresh();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showAddEditModal(BuildContext context, WidgetRef ref, [PmChecklistItem? item]) {
    showDialog(
      context: context,
      builder: (ctx) => _ChecklistDialog(
        projectId: widget.projectId,
        item: item,
        onSaved: () {
          ref.invalidate(pmChecklistItemsProvider(widget.projectId));
          widget.onRefresh();
        },
      ),
    );
  }
}

class _ChecklistDialog extends ConsumerStatefulWidget {
  final String projectId;
  final PmChecklistItem? item;
  final VoidCallback onSaved;

  const _ChecklistDialog({
    required this.projectId,
    this.item,
    required this.onSaved,
  });

  @override
  ConsumerState<_ChecklistDialog> createState() => _ChecklistDialogState();
}

class _ChecklistDialogState extends ConsumerState<_ChecklistDialog> {
  final _formKey = GlobalKey<FormState>();
  final _itemNameCtrl = TextEditingController();
  final _reqQtyCtrl = TextEditingController(text: '1');
  final _dispatchQtyCtrl = TextEditingController(text: '0');
  final _installedQtyCtrl = TextEditingController(text: '0');
  final _remarkCtrl = TextEditingController();
  bool _customerScope = false;
  bool _ourScope = true;
  bool _dispatchYesNo = false;
  bool _installationYesNo = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.item != null) {
      _itemNameCtrl.text = widget.item!.itemName;
      _reqQtyCtrl.text = widget.item!.reqQty.toString();
      _customerScope = widget.item!.customerScope;
      _ourScope = widget.item!.ourScope;
      _dispatchQtyCtrl.text = widget.item!.dispatchQty.toString();
      _dispatchYesNo = widget.item!.dispatchYesNo;
      _installedQtyCtrl.text = widget.item!.installedQty.toString();
      _installationYesNo = widget.item!.installationYesNo;
      _remarkCtrl.text = widget.item!.remark ?? '';
    }
  }

  @override
  void dispose() {
    _itemNameCtrl.dispose();
    _reqQtyCtrl.dispose();
    _dispatchQtyCtrl.dispose();
    _installedQtyCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final reqQ = double.tryParse(_reqQtyCtrl.text) ?? 0.0;
      final dispQ = double.tryParse(_dispatchQtyCtrl.text) ?? 0.0;

      final data = {
        'project_id': widget.projectId,
        'item_name': _itemNameCtrl.text.trim(),
        'req_qty': reqQ,
        'customer_scope': _customerScope,
        'our_scope': _ourScope,
        'dispatch_qty': dispQ,
        'dispatch_yes_no': _dispatchYesNo,
        'installed_qty': double.tryParse(_installedQtyCtrl.text) ?? 0.0,
        'installation_yes_no': _installationYesNo,
        'dispatch_balance_qty': reqQ - dispQ,
        'remark': _remarkCtrl.text.trim(),
      };

      if (widget.item != null) {
        await ref.read(pmLedgerRepositoryProvider).updateChecklistItem(widget.item!.id, data);
      } else {
        await ref.read(pmLedgerRepositoryProvider).addChecklistItem(data);
      }

      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pm = context.pm;
    final inventoryAsync = ref.watch(inventoryProvider);
    final inventoryItems = inventoryAsync.valueOrNull ?? [];

    return Dialog(
      backgroundColor: pm.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(pm.radiusLg)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(widget.item != null ? 'Edit Checklist Item' : 'Add Checklist Item',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: pm.foreground)),
                      IconButton(icon: const Icon(LucideIcons.x, size: 16), onPressed: () => Navigator.of(context).pop()),
                    ],
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return RawAutocomplete<InventoryItem>(
                        textEditingController: _itemNameCtrl,
                        focusNode: FocusNode(),
                        optionsBuilder: (TextEditingValue textVal) {
                          if (textVal.text.isEmpty) {
                            return inventoryItems.take(20);
                          }
                          final q = textVal.text.toLowerCase();
                          return inventoryItems.where((it) {
                            return it.itemName.toLowerCase().contains(q) ||
                                (it.hsnSac != null && it.hsnSac!.toLowerCase().contains(q)) ||
                                (it.uom != null && it.uom!.toLowerCase().contains(q));
                          });
                        },
                        displayStringForOption: (InventoryItem it) => it.itemName,
                        onSelected: (InventoryItem it) {
                          _itemNameCtrl.text = it.itemName;
                        },
                        fieldViewBuilder: (ctx, textCtrl, focusNode, onSubmitted) {
                          return TextFormField(
                            controller: textCtrl,
                            focusNode: focusNode,
                            validator: (v) {
                              final trimmed = v?.trim() ?? '';
                              if (trimmed.isEmpty) return 'Item name is required';
                              if (inventoryItems.isNotEmpty) {
                                final matches = inventoryItems.any((it) => it.itemName.toLowerCase() == trimmed.toLowerCase());
                                if (!matches) {
                                  return 'Must be an existing inventory item';
                                }
                              }
                              return null;
                            },
                            decoration: InputDecoration(
                              labelText: 'Item Name / Description (Strictly Inventory)*',
                              hintText: 'Search inventory item...',
                              isDense: true,
                              prefixIcon: const Icon(LucideIcons.search, size: 16),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(pm.radiusMd)),
                            ),
                          );
                        },
                        optionsViewBuilder: (ctx, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 8,
                              borderRadius: BorderRadius.circular(pm.radiusMd),
                              color: pm.card,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: 220,
                                  maxWidth: constraints.maxWidth,
                                ),
                                child: ListView.separated(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  separatorBuilder: (_, __) => Divider(height: 1, color: pm.border),
                                  itemBuilder: (ctx, index) {
                                    final option = options.elementAt(index);
                                    return InkWell(
                                      onTap: () => onSelected(option),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    option.itemName,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                      color: pm.foreground,
                                                    ),
                                                  ),
                                                  if (option.hsnSac != null || option.uom != null)
                                                    Text(
                                                      [
                                                        if (option.hsnSac != null) 'HSN: ${option.hsnSac}',
                                                        if (option.uom != null) 'Unit: ${option.uom}',
                                                      ].join(' • '),
                                                      style: TextStyle(fontSize: 11, color: pm.mutedForeground),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            if (option.price > 0)
                                              Text(
                                                '₹${option.price.toStringAsFixed(0)}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: pm.primary,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _reqQtyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Required Qty',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(pm.radiusMd)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _dispatchQtyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Dispatched Qty',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(pm.radiusMd)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          title: const Text('Our Scope', style: TextStyle(fontSize: 12)),
                          value: _ourScope,
                          onChanged: (val) {
                            setState(() {
                              _ourScope = val ?? false;
                              if (_ourScope) _customerScope = false;
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          title: const Text('Customer Scope', style: TextStyle(fontSize: 12)),
                          value: _customerScope,
                          onChanged: (val) {
                            setState(() {
                              _customerScope = val ?? false;
                              if (_customerScope) _ourScope = false;
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: _remarkCtrl,
                    decoration: InputDecoration(
                      labelText: 'Remark / Notes',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(pm.radiusMd)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  PmButton(
                    isLoading: _isLoading,
                    onPressed: _save,
                    child: Text(widget.item != null ? 'Update Item' : 'Save Item'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
