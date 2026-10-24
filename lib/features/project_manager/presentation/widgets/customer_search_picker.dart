import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/models/customer.dart';
import '../../../../core/router/app_router.dart';
import '../../../customers/providers/customers_provider.dart';
import '../../providers/pm_providers.dart';
import '../../providers/pm_company_provider.dart';
import '../theme/pm_tokens.dart';
import 'pm_button.dart';

class CustomerSearchPicker extends ConsumerStatefulWidget {
  final Customer? selectedCustomer;
  final ValueChanged<Customer> onCustomerSelected;

  const CustomerSearchPicker({
    super.key,
    required this.selectedCustomer,
    required this.onCustomerSelected,
  });

  @override
  ConsumerState<CustomerSearchPicker> createState() => _CustomerSearchPickerState();
}

class _CustomerSearchPickerState extends ConsumerState<CustomerSearchPicker> {
  void _openSearchDialog() {
    showDialog<Customer>(
      context: context,
      builder: (ctx) => _CustomerSearchModal(
        onSelected: (customer) {
          Navigator.of(ctx).pop(customer);
        },
      ),
    ).then((result) {
      if (result != null) {
        widget.onCustomerSelected(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pm = context.pm;
    final customer = widget.selectedCustomer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Linked Customer (Required)*',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: pm.foreground,
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                // Deep link to existing create customer flow
                final created = await context.push<Customer>(AppRoutes.createCustomer);
                if (created != null) {
                  widget.onCustomerSelected(created);
                } else {
                  // Refresh customers list so if created without return, it's immediately available
                  ref.read(customersNotifierProvider.notifier).refresh();
                }
              },
              icon: const Icon(LucideIcons.plus, size: 14),
              label: const Text(
                'New Customer',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _openSearchDialog,
          borderRadius: BorderRadius.circular(pm.radiusMd),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: pm.card,
              borderRadius: BorderRadius.circular(pm.radiusMd),
              border: Border.all(
                color: customer == null ? pm.border : pm.primary.withOpacity(0.4),
                width: customer == null ? 1 : 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.building2,
                  size: 18,
                  color: customer == null ? pm.mutedForeground : pm.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: customer == null
                      ? Text(
                          'Select an existing customer from SalesApp...',
                          style: TextStyle(
                            fontSize: 13,
                            color: pm.mutedForeground,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer.companyName,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: pm.foreground,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${customer.contactPerson ?? "No contact"} • ${customer.phone ?? "No phone"}',
                              style: TextStyle(
                                fontSize: 12,
                                color: pm.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                ),
                Icon(LucideIcons.chevronDown, size: 16, color: pm.mutedForeground),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CustomerSearchModal extends ConsumerStatefulWidget {
  final ValueChanged<Customer> onSelected;

  const _CustomerSearchModal({required this.onSelected});

  @override
  ConsumerState<_CustomerSearchModal> createState() => _CustomerSearchModalState();
}

class _CustomerSearchModalState extends ConsumerState<_CustomerSearchModal> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pm = context.pm;
    final customersState = ref.watch(customersNotifierProvider);

    return Dialog(
      backgroundColor: pm.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(pm.radiusLg)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select Customer',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: pm.foreground,
                      fontFamily: 'Inter',
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Search input
              TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (val) {
                  setState(() => _query = val.trim());
                  ref.read(customersNotifierProvider.notifier).search(val);
                },
                style: TextStyle(fontSize: 14, color: pm.foreground),
                decoration: InputDecoration(
                  prefixIcon: const Icon(LucideIcons.search, size: 16),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(LucideIcons.x, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                            ref.read(customersNotifierProvider.notifier).search('');
                          },
                        )
                      : null,
                  hintText: 'Search customer name, contact, phone...',
                  hintStyle: TextStyle(color: pm.mutedForeground, fontSize: 13),
                  isDense: true,
                  filled: true,
                  fillColor: pm.secondary.withOpacity(0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(pm.radiusMd),
                    borderSide: BorderSide(color: pm.border),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Results list
              Expanded(
                child: customersState.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Center(
                    child: Text('Error loading customers: $err', style: TextStyle(color: pm.destructive)),
                  ),
                  data: (customers) {
                    final existingProjectsAsync = ref.watch(pmProjectsListProvider);
                    final existingCustomerIds = existingProjectsAsync.valueOrNull
                            ?.map((p) => p.customerId)
                            .toSet() ??
                        {};

                    final filtered = customers.where((c) {
                      // Check if customer's ledger is already created for this company.
                      // If yes, don't show name. If no, show name.
                      if (existingCustomerIds.contains(c.id)) {
                        return false;
                      }
                      if (_query.isNotEmpty) {
                        final q = _query.toLowerCase();
                        return c.companyName.toLowerCase().contains(q) ||
                            (c.contactPerson?.toLowerCase().contains(q) ?? false) ||
                            (c.phone?.toLowerCase().contains(q) ?? false) ||
                            (c.address?.toLowerCase().contains(q) ?? false);
                      }
                      return true;
                    }).toList();

                    if (filtered.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.users, size: 36, color: pm.mutedForeground.withOpacity(0.5)),
                            const SizedBox(height: 10),
                            Text(
                              'No customers found matching "$_query"',
                              style: TextStyle(color: pm.mutedForeground, fontSize: 13),
                            ),
                            const SizedBox(height: 12),
                            PmButton(
                              size: PmButtonSize.sm,
                              onPressed: () async {
                                Navigator.of(context).pop();
                                final created = await context.push<Customer>(AppRoutes.createCustomer);
                                if (created != null) {
                                  widget.onSelected(created);
                                }
                              },
                              child: const Text('+ Create Customer in SalesApp'),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(color: pm.border.withOpacity(0.5), height: 1),
                      itemBuilder: (ctx, i) {
                        final c = filtered[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          title: Text(
                            c.companyName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: pm.foreground,
                            ),
                          ),
                          subtitle: Text(
                            '${c.contactPerson ?? "No contact"} • ${c.phone ?? "No phone"}\n${c.address ?? ""}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: pm.mutedForeground,
                            ),
                          ),
                          trailing: const Icon(LucideIcons.arrowRight, size: 16),
                          onTap: () => widget.onSelected(c),
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
