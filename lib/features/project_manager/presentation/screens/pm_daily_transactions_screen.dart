import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/providers/supabase_provider.dart';
import '../theme/pm_tokens.dart';
import '../widgets/pm_card.dart';
import '../widgets/pm_badge.dart';
import '../widgets/pm_button.dart';
import '../widgets/pm_stat_card.dart';
import '../../data/models/pm_daily_transaction.dart';
import '../../providers/pm_company_provider.dart';
import '../../providers/pm_providers.dart';

class PmDailyTransactionsScreen extends ConsumerStatefulWidget {
  const PmDailyTransactionsScreen({super.key});

  @override
  ConsumerState<PmDailyTransactionsScreen> createState() => _PmDailyTransactionsScreenState();
}

class _PmDailyTransactionsScreenState extends ConsumerState<PmDailyTransactionsScreen> {
  final _searchController = TextEditingController();
  final _currencyFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  final _dateFmt = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentQuery = ref.read(dailyTransactionsFilterProvider).searchQuery;
      if (currentQuery.isNotEmpty) {
        ref.read(dailyTransactionsFilterProvider.notifier).update(
              (s) => s.copyWith(searchQuery: ''),
            );
      }
    });
  }

  @override
  void dispose() {
    try {
      ref.read(dailyTransactionsFilterProvider.notifier).update(
            (s) => s.copyWith(searchQuery: ''),
          );
    } catch (_) {}
    _searchController.dispose();
    super.dispose();
  }

  void _openTransactionDialog([PmDailyTransaction? editing]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DailyTransactionDialog(editing: editing),
    );
  }

  Future<void> _confirmDelete(PmDailyTransaction tx) async {
    final pm = context.pm;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Transaction?'),
        content: Text('Are you sure you want to delete entry #${tx.srNo} (${tx.partyName})? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: pm.destructive),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final repo = ref.read(pmDailyTransactionsRepositoryProvider);
        await repo.deleteTransaction(tx.id);
        ref.invalidate(pmDailyTransactionsListProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transaction deleted successfully.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete transaction: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pm = context.pm;
    final filter = ref.watch(dailyTransactionsFilterProvider);
    final txAsync = ref.watch(pmDailyTransactionsListProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: pm.background,
        body: SafeArea(
        child: Column(
          children: [
            // Top Nav Header
            Container(
              decoration: BoxDecoration(
                color: pm.card,
                border: Border(bottom: BorderSide(color: pm.border)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  if (context.canPop()) ...[
                    IconButton(
                      icon: const Icon(LucideIcons.arrowLeft, size: 20),
                      onPressed: () => context.pop(),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily Transactions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: pm.foreground,
                        ),
                      ),
                      Text(
                        'Day-Book & Cashflow Register',
                        style: TextStyle(fontSize: 12, color: pm.mutedForeground),
                      ),
                    ],
                  ),
                  const Spacer(),
                  PmButton(
                    onPressed: () => _openTransactionDialog(),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.plus, size: 14),
                        SizedBox(width: 6),
                        Text('Add Entry'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: txAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.triangleAlert, size: 40, color: pm.destructive),
                      const SizedBox(height: 12),
                      Text('Error loading day-book: $err', style: TextStyle(color: pm.mutedForeground)),
                      const SizedBox(height: 12),
                      PmButton(
                        variant: PmButtonVariant.outline,
                        onPressed: () => ref.invalidate(pmDailyTransactionsListProvider),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.refreshCw, size: 14),
                            SizedBox(width: 6),
                            Text('Retry'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                data: (transactions) {
                  // Calculate Summary Totals
                  double totalCredit = 0;
                  double totalDebit = 0;
                  for (final t in transactions) {
                    totalCredit += t.creditAmount;
                    totalDebit += t.debitAmount;
                  }
                  final netBalance = totalCredit - totalDebit;

                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(pmDailyTransactionsListProvider),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // KPI Stat Cards Row
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isMobile = constraints.maxWidth < 750;
                            final cards = [
                              PmStatCard(
                                title: 'Total Inflow (Credits)',
                                value: _currencyFmt.format(totalCredit),
                                icon: Icon(LucideIcons.arrowDownLeft, color: pm.success, size: 20),
                                accentColor: pm.success,
                              ),
                              PmStatCard(
                                title: 'Total Outflow (Debits)',
                                value: _currencyFmt.format(totalDebit),
                                icon: Icon(LucideIcons.arrowUpRight, color: pm.destructive, size: 20),
                                accentColor: pm.destructive,
                              ),
                              PmStatCard(
                                title: 'Net Cash Balance',
                                value: _currencyFmt.format(netBalance),
                                icon: Icon(LucideIcons.wallet, color: netBalance >= 0 ? pm.success : pm.destructive, size: 20),
                                accentColor: netBalance >= 0 ? pm.success : pm.destructive,
                              ),
                              PmStatCard(
                                title: 'Entries Count',
                                value: transactions.length.toString(),
                                icon: Icon(LucideIcons.receipt, color: pm.primary, size: 20),
                                accentColor: pm.primary,
                              ),
                            ];

                            if (!isMobile) {
                              return Row(
                                children: cards.map((c) => Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6),
                                    child: c,
                                  ),
                                )).toList(),
                              );
                            }

                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: cards.map((c) => SizedBox(
                                width: (constraints.maxWidth - 12) / 2,
                                child: c,
                              )).toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // Timeframe & Filter Bar
                        PmCard(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Timeframe Segmented Chips
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: ['Today', 'Week', 'Month', 'Lifetime', 'Custom'].map((tf) {
                                    final isSelected = filter.timeframe == tf;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(tf),
                                        selected: isSelected,
                                        selectedColor: pm.primary,
                                        labelStyle: TextStyle(
                                          color: isSelected ? pm.primaryForeground : pm.mutedForeground,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                          fontSize: 12,
                                        ),
                                        onSelected: (selected) {
                                          if (selected) {
                                            if (tf == 'Custom') {
                                              _pickCustomDateRange();
                                            } else {
                                              ref.read(dailyTransactionsFilterProvider.notifier).update(
                                                    (s) => s.copyWith(timeframe: tf, startDate: null, endDate: null),
                                                  );
                                            }
                                          }
                                        },
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Search & Secondary Filter Chips
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      decoration: InputDecoration(
                                        hintText: 'Search party, firm, transaction...',
                                        hintStyle: TextStyle(color: pm.mutedForeground, fontSize: 13),
                                        prefixIcon: Icon(LucideIcons.search, size: 16, color: pm.mutedForeground),
                                        suffixIcon: _searchController.text.isNotEmpty
                                            ? IconButton(
                                                icon: Icon(LucideIcons.x, size: 16, color: pm.mutedForeground),
                                                onPressed: () {
                                                  _searchController.clear();
                                                  setState(() {});
                                                  ref.read(dailyTransactionsFilterProvider.notifier).update(
                                                        (s) => s.copyWith(searchQuery: ''),
                                                      );
                                                },
                                              )
                                            : null,
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide(color: pm.border),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide(color: pm.border),
                                        ),
                                      ),
                                      onChanged: (val) {
                                        setState(() {});
                                        ref.read(dailyTransactionsFilterProvider.notifier).update(
                                              (s) => s.copyWith(searchQuery: val.trim()),
                                            );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Nature Dropdown (All, Sale, Purchase, Expense)
                                  DropdownButtonHideUnderline(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: pm.border),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: DropdownButton<String>(
                                        value: filter.entryNature,
                                        isDense: true,
                                        items: const [
                                          DropdownMenuItem(value: 'ALL', child: Text('All Types', style: TextStyle(fontSize: 13))),
                                          DropdownMenuItem(value: 'Sale', child: Text('Sale', style: TextStyle(fontSize: 13))),
                                          DropdownMenuItem(value: 'Purchase', child: Text('Purchase', style: TextStyle(fontSize: 13))),
                                          DropdownMenuItem(value: 'Expense', child: Text('Expense', style: TextStyle(fontSize: 13))),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) {
                                            ref.read(dailyTransactionsFilterProvider.notifier).update(
                                                  (s) => s.copyWith(entryNature: val),
                                                );
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Flow Dropdown (All, credit, debit)
                                  DropdownButtonHideUnderline(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: pm.border),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: DropdownButton<String>(
                                        value: filter.flowType,
                                        isDense: true,
                                        items: const [
                                          DropdownMenuItem(value: 'ALL', child: Text('Flow: All', style: TextStyle(fontSize: 13))),
                                          DropdownMenuItem(value: 'credit', child: Text('Credit (+)', style: TextStyle(fontSize: 13))),
                                          DropdownMenuItem(value: 'debit', child: Text('Debit (-)', style: TextStyle(fontSize: 13))),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) {
                                            ref.read(dailyTransactionsFilterProvider.notifier).update(
                                                  (s) => s.copyWith(flowType: val),
                                                );
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Entries List / Table
                        if (transactions.isEmpty)
                          PmCard(
                            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(LucideIcons.inbox, size: 48, color: pm.mutedForeground),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No transactions found for selected period',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: pm.foreground,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Change filters or tap "+ Add Entry" to record cash movements.',
                                    style: TextStyle(fontSize: 13, color: pm.mutedForeground),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ...transactions.map((tx) => _buildTransactionCard(context, tx)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildTransactionCard(BuildContext context, PmDailyTransaction tx) {
    final pm = context.pm;
    final isCredit = tx.type == PmTransactionFlow.credit;
    final amount = isCredit ? tx.creditAmount : tx.debitAmount;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PmCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sr No & Flow Icon Badge
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isCredit
                    ? pm.successSurface
                    : pm.destructive.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(
                  isCredit ? LucideIcons.arrowDownLeft : LucideIcons.arrowUpRight,
                  color: isCredit ? pm.success : pm.destructive,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Main Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        tx.partyName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: pm.foreground,
                        ),
                      ),
                      const SizedBox(width: 8),
                      PmBadge(
                        label: tx.entryNature.displayName,
                        variant: tx.entryNature == PmEntryNature.sale
                            ? PmBadgeVariant.success
                            : tx.entryNature == PmEntryNature.purchase
                                ? PmBadgeVariant.info
                                : PmBadgeVariant.warning,
                      ),
                      const Spacer(),
                      Text(
                        '${isCredit ? "+" : "-"} ${_currencyFmt.format(amount)}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isCredit ? pm.success : pm.destructive,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  Row(
                    children: [
                      Text(
                        '${_dateFmt.format(tx.date)}  •  ${tx.paymentMode}',
                        style: TextStyle(fontSize: 12, color: pm.mutedForeground),
                      ),
                      if (tx.firmName.isNotEmpty) ...[
                        Text('  •  ', style: TextStyle(color: pm.mutedForeground)),
                        Text(
                          tx.firmName,
                          style: TextStyle(fontSize: 12, color: pm.mutedForeground),
                        ),
                      ],
                      if (tx.transactionName.isNotEmpty) ...[
                        Text('  •  ', style: TextStyle(color: pm.mutedForeground)),
                        Text(
                          tx.transactionName,
                          style: TextStyle(fontSize: 12, color: pm.primary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ],
                  ),

                  if (tx.remark != null && tx.remark!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      tx.remark!,
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: pm.mutedForeground),
                    ),
                  ],
                ],
              ),
            ),

            // Row actions
            PopupMenuButton<String>(
              icon: Icon(LucideIcons.ellipsisVertical, size: 16, color: pm.mutedForeground),
              onSelected: (action) {
                if (action == 'edit') {
                  _openTransactionDialog(tx);
                } else if (action == 'delete') {
                  _confirmDelete(tx);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(LucideIcons.pencil, size: 15),
                      SizedBox(width: 8),
                      Text('Edit Entry'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(LucideIcons.trash2, size: 15, color: pm.destructive),
                      const SizedBox(width: 8),
                      Text('Delete Entry', style: TextStyle(color: pm.destructive)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      ref.read(dailyTransactionsFilterProvider.notifier).update(
            (s) => s.copyWith(
              timeframe: 'Custom',
              startDate: picked.start,
              endDate: picked.end,
            ),
          );
    }
  }
}

// -----------------------------------------------------------------------------
// ADD / EDIT TRANSACTION DIALOG
// -----------------------------------------------------------------------------
class _DailyTransactionDialog extends ConsumerStatefulWidget {
  final PmDailyTransaction? editing;

  const _DailyTransactionDialog({this.editing});

  @override
  ConsumerState<_DailyTransactionDialog> createState() => _DailyTransactionDialogState();
}

class _DailyTransactionDialogState extends ConsumerState<_DailyTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _date;
  late TextEditingController _srNoController;
  late TextEditingController _partyController;
  late TextEditingController _firmController;
  late TextEditingController _txNameController;
  late TextEditingController _amountController;
  late TextEditingController _remarkController;

  String _paymentMode = 'Cash';
  PmEntryNature _nature = PmEntryNature.sale;
  PmTransactionFlow _flow = PmTransactionFlow.credit;
  bool _saving = false;

  final List<String> _modes = ['Cash', 'Cheque', 'RTGS / NEFT', 'UPI', 'Bank Transfer', 'Other'];

  @override
  void initState() {
    super.initState();
    final edit = widget.editing;
    _date = edit?.date ?? DateTime.now();
    _srNoController = TextEditingController(text: edit != null ? edit.srNo.toString() : '1');
    _partyController = TextEditingController(text: edit?.partyName ?? '');
    _firmController = TextEditingController(text: edit?.firmName ?? '');
    _txNameController = TextEditingController(text: edit?.transactionName ?? '');
    final amt = edit != null
        ? (edit.type == PmTransactionFlow.credit ? edit.creditAmount : edit.debitAmount)
        : 0.0;
    _amountController = TextEditingController(text: amt > 0 ? amt.toStringAsFixed(0) : '');
    _remarkController = TextEditingController(text: edit?.remark ?? '');
    if (edit != null) {
      _paymentMode = edit.paymentMode;
      _nature = edit.entryNature;
      _flow = edit.type;
    } else {
      _fetchNextSrNo();
    }
  }

  Future<void> _fetchNextSrNo() async {
    try {
      final repo = ref.read(pmDailyTransactionsRepositoryProvider);
      final company = ref.read(pmActiveCompanyProvider);
      final nextSr = await repo.getNextSrNo(company.id, _date);
      if (mounted) {
        _srNoController.text = nextSr.toString();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _srNoController.dispose();
    _partyController.dispose();
    _firmController.dispose();
    _txNameController.dispose();
    _amountController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _openPartySearchDialog() async {
    final selected = await showDialog<PmPartyOption>(
      context: context,
      builder: (ctx) => const _PartySearchDialog(),
    );
    if (selected != null) {
      setState(() {
        _partyController.text = selected.name;
        if (selected.firmName != null &&
            selected.firmName!.isNotEmpty &&
            _firmController.text.trim().isEmpty) {
          _firmController.text = selected.firmName!;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final repo = ref.read(pmDailyTransactionsRepositoryProvider);
      final company = ref.read(pmActiveCompanyProvider);
      final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;

      final data = <String, dynamic>{
        'company_id': company.id,
        'date': _date.toIso8601String().split('T').first,
        'sr_no': int.tryParse(_srNoController.text.trim()) ?? 1,
        'firm_name': _firmController.text.trim(),
        'party_name': _partyController.text.trim(),
        'payment_mode': _paymentMode,
        'transaction_name': _txNameController.text.trim(),
        'entry_nature': _nature.dbValue,
        'type': _flow.dbValue,
        'debit_amount': _flow == PmTransactionFlow.debit ? amount : 0.0,
        'credit_amount': _flow == PmTransactionFlow.credit ? amount : 0.0,
        'remark': _remarkController.text.trim().isEmpty ? null : _remarkController.text.trim(),
      };

      if (widget.editing != null) {
        await repo.updateTransaction(widget.editing!.id, data);
      } else {
        await repo.createTransaction(data);
      }

      ref.invalidate(pmDailyTransactionsListProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.editing != null
                  ? 'Transaction updated successfully.'
                  : 'Transaction added successfully.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save transaction: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pm = context.pm;
    final isEdit = widget.editing != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Transaction' : 'New Transaction Entry'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date & Sr No
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() => _date = picked);
                            if (!isEdit) _fetchNextSrNo();
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date *',
                            prefixIcon: Icon(LucideIcons.calendar, size: 16),
                          ),
                          child: Text(DateFormat('dd MMM yyyy').format(_date)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _srNoController,
                        decoration: const InputDecoration(labelText: 'Sr No *'),
                        keyboardType: TextInputType.number,
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Flow Selector: Credit (+) or Debit (-)
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<PmTransactionFlow>(
                        value: PmTransactionFlow.credit,
                        groupValue: _flow,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('Credit (Inflow +)', style: TextStyle(fontSize: 13, color: pm.success)),
                        onChanged: (v) {
                          if (v != null) setState(() => _flow = v);
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<PmTransactionFlow>(
                        value: PmTransactionFlow.debit,
                        groupValue: _flow,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('Debit (Outflow -)', style: TextStyle(fontSize: 13, color: pm.destructive)),
                        onChanged: (v) {
                          if (v != null) setState(() => _flow = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Amount
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹) *',
                    prefixText: '₹ ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Please enter amount';
                    if (double.tryParse(v) == null) return 'Enter a valid number';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Party Name with Click-to-Search
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Party / Customer / Vendor Name *',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                    InkWell(
                      onTap: _openPartySearchDialog,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.search, size: 14, color: Color(0xFF2563EB)),
                            SizedBox(width: 4),
                            Text(
                              'Click to Search List',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _partyController,
                  decoration: InputDecoration(
                    hintText: 'Click to search or type party name...',
                    prefixIcon: const Icon(LucideIcons.user, size: 16),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_partyController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            tooltip: 'Clear',
                            onPressed: () {
                              setState(() => _partyController.clear());
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.search, size: 20, color: Color(0xFF2563EB)),
                          tooltip: 'Search Party / Customer / Vendor',
                          onPressed: _openPartySearchDialog,
                        ),
                      ],
                    ),
                  ),
                  onTap: () {
                    if (_partyController.text.isEmpty) {
                      _openPartySearchDialog();
                    }
                  },
                  validator: (v) => v == null || v.trim().isEmpty ? 'Please enter party name' : null,
                ),
                const SizedBox(height: 12),

                // Firm Name
                TextFormField(
                  controller: _firmController,
                  decoration: const InputDecoration(
                    labelText: 'Firm Name',
                    prefixIcon: Icon(LucideIcons.building, size: 16),
                  ),
                ),
                const SizedBox(height: 12),

                // Entry Nature & Payment Mode
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<PmEntryNature>(
                        value: _nature,
                        decoration: const InputDecoration(labelText: 'Nature *'),
                        items: PmEntryNature.values.map((n) {
                          return DropdownMenuItem(value: n, child: Text(n.displayName));
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _nature = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _paymentMode,
                        decoration: const InputDecoration(labelText: 'Payment Mode *'),
                        items: _modes.map((m) {
                          return DropdownMenuItem(value: m, child: Text(m));
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _paymentMode = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Transaction Name / Description
                TextFormField(
                  controller: _txNameController,
                  decoration: const InputDecoration(
                    labelText: 'Transaction Purpose / Tag *',
                    hintText: 'e.g. Advance Payment, Material, Transport',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                // Remark
                TextFormField(
                  controller: _remarkController,
                  decoration: const InputDecoration(
                    labelText: 'Remarks / Notes',
                    hintText: 'Optional remarks...',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: pm.primary),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(isEdit ? 'Save Changes' : 'Add Entry'),
        ),
      ],
    );
  }
}

// ─── SEARCHABLE PARTY / CUSTOMER / VENDOR PICKER ─────────────────────────────

class PmPartyOption {
  final String name;
  final String? firmName;
  final String? phone;
  final String category; // 'Customer', 'Vendor', 'Project', 'Party', 'Custom'

  const PmPartyOption({
    required this.name,
    this.firmName,
    this.phone,
    required this.category,
  });

  Color get categoryColor {
    switch (category) {
      case 'Customer':
        return const Color(0xFF2563EB); // Blue
      case 'Vendor':
        return const Color(0xFF0D9488); // Teal
      case 'Project':
        return const Color(0xFF7C3AED); // Purple
      default:
        return const Color(0xFFD97706); // Amber
    }
  }
}

final pmDailyTransactionPartiesProvider = FutureProvider.autoDispose<List<PmPartyOption>>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final activeCompany = ref.watch(pmActiveCompanyProvider);
  final Map<String, PmPartyOption> uniqueMap = {};

  // 1. Fetch CRM Customers
  try {
    final custRes = await supabase
        .from('customers')
        .select('id, customer_name, company_name, phone')
        .isFilter('deleted_at', null)
        .order('customer_name', ascending: true);
    for (final c in (custRes as List)) {
      final name = (c['customer_name'] as String? ?? '').trim();
      final comp = (c['company_name'] as String? ?? '').trim();
      final phone = (c['phone'] as String? ?? '').trim();
      final primaryName = name.isNotEmpty ? name : comp;
      if (primaryName.isNotEmpty) {
        uniqueMap.putIfAbsent(
          primaryName.toLowerCase(),
          () => PmPartyOption(
            name: primaryName,
            firmName: comp.isNotEmpty && comp != primaryName ? comp : null,
            phone: phone.isNotEmpty ? phone : null,
            category: 'Customer',
          ),
        );
      }
    }
  } catch (_) {}

  // 2. Fetch Vendors from pm_purchases for active company
  try {
    final vendRes = await supabase
        .from('pm_purchases')
        .select('site_name, party_name, firm_name, mobile_number')
        .eq('company_id', activeCompany.id)
        .order('site_name', ascending: true);
    for (final v in (vendRes as List)) {
      final site = (v['site_name'] as String? ?? '').trim();
      final party = (v['party_name'] as String? ?? '').trim();
      final firm = (v['firm_name'] as String? ?? '').trim();
      final phone = (v['mobile_number'] as String? ?? '').trim();
      final name = site.isNotEmpty ? site : party;
      if (name.isNotEmpty) {
        uniqueMap.putIfAbsent(
          name.toLowerCase(),
          () => PmPartyOption(
            name: name,
            firmName: firm.isNotEmpty ? firm : (party.isNotEmpty && party != name ? party : null),
            phone: phone.isNotEmpty ? phone : null,
            category: 'Vendor',
          ),
        );
      }
    }
  } catch (_) {}

  // 3. Fetch Sites/Projects from pm_projects for active company
  try {
    final projRes = await supabase
        .from('pm_projects')
        .select('site_name')
        .eq('company_id', activeCompany.id)
        .order('site_name', ascending: true);
    for (final p in (projRes as List)) {
      final site = (p['site_name'] as String? ?? '').trim();
      if (site.isNotEmpty) {
        uniqueMap.putIfAbsent(
          site.toLowerCase(),
          () => PmPartyOption(
            name: site,
            category: 'Project',
          ),
        );
      }
    }
  } catch (_) {}

  // 4. Fetch distinct party names from existing pm_daily_transactions
  try {
    final txRes = await supabase
        .from('pm_daily_transactions')
        .select('party_name, firm_name')
        .eq('company_id', activeCompany.id)
        .order('created_at', ascending: false)
        .limit(200);
    for (final t in (txRes as List)) {
      final party = (t['party_name'] as String? ?? '').trim();
      final firm = (t['firm_name'] as String? ?? '').trim();
      if (party.isNotEmpty) {
        uniqueMap.putIfAbsent(
          party.toLowerCase(),
          () => PmPartyOption(
            name: party,
            firmName: firm.isNotEmpty ? firm : null,
            category: 'Party',
          ),
        );
      }
    }
  } catch (_) {}

  final list = uniqueMap.values.toList();
  list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return list;
});

class _PartySearchDialog extends ConsumerStatefulWidget {
  const _PartySearchDialog();

  @override
  ConsumerState<_PartySearchDialog> createState() => _PartySearchDialogState();
}

class _PartySearchDialogState extends ConsumerState<_PartySearchDialog> {
  final _searchController = TextEditingController();
  String _query = '';
  String _selectedCategory = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final partiesAsync = ref.watch(pmDailyTransactionPartiesProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(LucideIcons.users, color: Color(0xFF2563EB), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Party / Customer / Vendor',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Search across customers, vendors, and past parties',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Color(0xFF94A3B8)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Search Box
              TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search by name, company, or phone...',
                  prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF2563EB)),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                  ),
                ),
                onChanged: (val) => setState(() => _query = val.trim()),
              ),
              const SizedBox(height: 12),

              // Category Filter Chips
              partiesAsync.maybeWhen(
                data: (parties) {
                  final categories = ['All', 'Customer', 'Vendor', 'Project', 'Party'];
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: categories.map((cat) {
                        final isSelected = _selectedCategory == cat;
                        final count = cat == 'All'
                            ? parties.length
                            : parties.where((p) => p.category == cat).length;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(
                              '$cat ($count)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.white : const Color(0xFF475569),
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: const Color(0xFF2563EB),
                            backgroundColor: const Color(0xFFF1F5F9),
                            onSelected: (val) {
                              if (val) setState(() => _selectedCategory = cat);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 6),

              // Filtered list
              Expanded(
                child: partiesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error loading parties: $e')),
                  data: (parties) {
                    final q = _query.toLowerCase();
                    final filtered = parties.where((p) {
                      final matchCat = _selectedCategory == 'All' || p.category == _selectedCategory;
                      if (!matchCat) return false;
                      if (q.isEmpty) return true;
                      final name = p.name.toLowerCase();
                      final firm = (p.firmName ?? '').toLowerCase();
                      final phone = (p.phone ?? '').toLowerCase();
                      return name.contains(q) || firm.contains(q) || phone.contains(q);
                    }).toList();

                    final hasExactMatch = filtered.any((p) => p.name.toLowerCase() == q);

                    if (filtered.isEmpty && (_query.isEmpty || hasExactMatch)) {
                      return const Center(
                        child: Text(
                          'No parties found.',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: filtered.length + (_query.isNotEmpty && !hasExactMatch ? 1 : 0),
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF8FAFC)),
                      itemBuilder: (context, index) {
                        // Custom Typed Query Option at top
                        if (_query.isNotEmpty && !hasExactMatch && index == 0) {
                          return ListTile(
                            leading: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.add, color: Color(0xFF2563EB), size: 20),
                            ),
                            title: Text(
                              'Use "$_query" as party name',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                            ),
                            subtitle: const Text('Add as new or custom party', style: TextStyle(fontSize: 12)),
                            onTap: () {
                              Navigator.pop(context, PmPartyOption(name: _query, category: 'Custom'));
                            },
                          );
                        }

                        final itemIndex = (_query.isNotEmpty && !hasExactMatch) ? index - 1 : index;
                        final p = filtered[itemIndex];

                        final subtitleParts = [
                          if (p.firmName != null && p.firmName!.isNotEmpty) 'Firm: ${p.firmName}',
                          if (p.phone != null && p.phone!.isNotEmpty) '📞 ${p.phone}',
                        ];

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: p.categoryColor.withValues(alpha: 0.12),
                            child: Text(
                              p.name.isNotEmpty ? p.name[0].toUpperCase() : 'P',
                              style: TextStyle(
                                color: p.categoryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          title: Text(
                            p.name,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1E293B)),
                          ),
                          subtitle: subtitleParts.isNotEmpty
                              ? Text(
                                  subtitleParts.join(' • '),
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                )
                              : null,
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: p.categoryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: p.categoryColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              p.category.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: p.categoryColor,
                              ),
                            ),
                          ),
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

