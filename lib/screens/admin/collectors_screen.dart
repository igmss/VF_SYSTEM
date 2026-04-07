import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/auth_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../models/collector.dart';
import '../../models/retailer.dart';
import '../../theme/app_theme.dart';
import 'collector_details_screen.dart';

part 'collector_card.dart';
part 'collector_dialogs.dart';

class CollectorsScreen extends StatelessWidget {
  const CollectorsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    final auth = context.watch<AuthProvider>();
    final textPrimary = AppTheme.textPrimaryColor(context);
    final surface = AppTheme.surfaceColor(context);

    final isEmbedded = auth.isAdmin || auth.isFinance;

    final bodyContent = dist.collectors.isEmpty
          ? _empty(context)
          : Column(
              children: [
                _cashBanner(context, dist.totalCollectorCash, auth.isAdmin),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                    itemCount: dist.collectors.length,
                    itemBuilder: (ctx, i) => _CollectorCard(
                      collector: dist.collectors[i],
                      isAdmin: auth.isAdmin || auth.isFinance,
                      onCollect: () => _showCollectDialog(ctx, dist.collectors[i], dist, auth),
                      onDeposit: () => _showDepositDialog(ctx, dist.collectors[i], dist, auth),
                      onEdit: auth.isAdmin ? () => _showEditDialog(ctx, dist.collectors[i], dist) : null,
                      onAssignRetailers: auth.isAdmin
                          ? () => _showAssignRetailersDialog(ctx, dist.collectors[i], dist)
                          : null,
                    ),
                  ),
                ),
              ],
            );

    if (isEmbedded) {
      return Scaffold(
        backgroundColor: AppTheme.scaffoldBg(context),
        body: bodyContent,
      );
    } else {
      return Scaffold(
        backgroundColor: AppTheme.scaffoldBg(context),
        appBar: AppBar(
          backgroundColor: surface,
          elevation: 0,
          title: Text('collectors'.tr(), style: TextStyle(color: textPrimary, fontWeight: FontWeight.w800)),
          iconTheme: IconThemeData(color: textPrimary),
        ),
        body: bodyContent,
      );
    }
  }

  Widget _cashBanner(BuildContext context, double total, bool isAdmin) => Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: AppTheme.isDark(context)
                  ? const [Color(0xFF1F2937), Color(0xFF111827)]
                  : const [Color(0xFF8C6239), Color(0xFF6B4524)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: AppTheme.isDark(context)
                    ? Colors.black.withValues(alpha: 0.24)
                    : const Color(0xFF8C6239).withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 8))
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.delivery_dining, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('total_cash_in_hand'.tr(),
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w500)),
                      Text('${_fmt(total)} EGP',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                    ]),
                  ],
                ),
                if (isAdmin)
                  IconButton(
                    tooltip: 'add_collector'.tr(),
                    padding: const EdgeInsets.all(10),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      foregroundColor: Colors.white,
                      highlightColor: Colors.white.withValues(alpha: 0.25),
                    ),
                    icon: const Icon(Icons.person_add, size: 24),
                    onPressed: () => _showPickUserDialog(context),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white.withValues(alpha: 0.7), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Monitor cash exposure, limits, and assign retailers in real-time.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _empty(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delivery_dining_outlined, size: 60, color: AppTheme.textMutedColor(context).withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text('no_data'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context))),
          ],
        ),
      );

  void _showPickUserDialog(BuildContext context) async {
    final dist = context.read<DistributionProvider>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: Color(0xFFA78BFA))),
    );

    try {
      final allUsers = await context.read<AuthProvider>().getAllUsers();
      Navigator.pop(context);

      final unlinked = allUsers.where((u) {
        if (u.role.name != 'COLLECTOR') return false;
        return !dist.collectors.any((c) => c.uid == u.uid);
      }).toList();

      if (unlinked.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('all_collectors_linked'.tr()),
            backgroundColor: const Color(0xFF4ADE80),
          ),
        );
        return;
      }

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surfaceColor(context),
          title: Text('select_collector_user'.tr(),
              style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 15)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: unlinked.map((u) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFA78BFA).withOpacity(0.15),
                  child: Text(u.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(color: Color(0xFFA78BFA))),
                ),
                title: Text(u.name,
                    style: TextStyle(color: AppTheme.textPrimaryColor(context))),
                subtitle: Text(u.email,
                    style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12)),
                onTap: () async {
                  Navigator.pop(context);
                  await dist.ensureCollectorRecord(
                    uid: u.uid,
                    name: u.name,
                    email: u.email,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${u.name} added as collector')),
                  );
                },
              )).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('cancel'.tr(),
                  style: TextStyle(color: AppTheme.textMutedColor(context))),
            ),
          ],
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showEditDialog(BuildContext context, Collector collector, DistributionProvider dist) {
    final nameCtrl = TextEditingController(text: collector.name);
    final phoneCtrl = TextEditingController(text: collector.phone);
    final limitCtrl = TextEditingController(text: collector.cashLimit.toStringAsFixed(0));
    
    showDialog(
      context: context,
      builder: (_) => _Dialog(
        title: 'Edit Collector',
        fields: [
          _tf(context, nameCtrl, 'name'.tr(), Icons.person),
          _tf(context, phoneCtrl, 'phone'.tr(), Icons.phone, keyboard: TextInputType.phone),
          _tf(context, limitCtrl, 'Cash Limit (EGP)', Icons.account_balance_wallet, keyboard: TextInputType.number),
        ],
        onConfirm: () async {
          final newLimit = double.tryParse(limitCtrl.text) ?? 50000.0;
          await dist.updateCollector(
            collector.copyWith(
              name: nameCtrl.text.trim(),
              phone: phoneCtrl.text.trim(),
              cashLimit: newLimit,
            ),
          );
          return true;
        },
      ),
    );
  }

  void _showCollectDialog(BuildContext context, Collector collector,
      DistributionProvider dist, AuthProvider auth) {
    final amtCtrl = TextEditingController();
    final retailers = dist.retailers;
    if (retailers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('no_data'.tr())));
      return;
    }
    String selectedRetailerId = retailers.first.id;
    showDialog(
      context: context,
      builder: (ctx2) => StatefulBuilder(
        builder: (context2, setSt) {
          final selectedRetailer = retailers.firstWhere((r) => r.id == selectedRetailerId);
          final entered   = double.tryParse(amtCtrl.text) ?? 0.0;
          final debt      = selectedRetailer.pendingDebt;
          final debtPaid  = entered > debt ? debt : entered;
          final credit    = entered > debt ? entered - debt : 0.0;

          return _Dialog(
            title: 'collect_from_retailer'.tr(args: [collector.name]),
            fields: [
              DropdownButtonFormField<String>(
                value: selectedRetailerId,
                dropdownColor: AppTheme.surfaceColor(context),
                style: TextStyle(color: AppTheme.textPrimaryColor(context)),
                decoration: InputDecoration(
                  labelText: 'retailers'.tr(),
                  labelStyle: TextStyle(color: AppTheme.textMutedColor(context)),
                  filled: true,
                  fillColor: AppTheme.textPrimaryColor(context).withValues(alpha: 0.06),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                items: retailers.map((r) => DropdownMenuItem(
                  value: r.id,
                  child: Text('${r.name} (${_fmt(r.pendingDebt)} EGP)'))).toList(),
                onChanged: (v) => setSt(() => selectedRetailerId = v ?? selectedRetailerId),
              ),
              const SizedBox(height: 12),
              _tf(context, amtCtrl, 'amount_egp'.tr(), Icons.monetization_on,
                  keyboard: TextInputType.number,
                  onChanged: (_) => setSt(() {})),
              if (entered > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: credit > 0 ? const Color(0xFF4ADE80).withOpacity(0.4) : AppTheme.lineColor(context)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('↓ Debt Reduced', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12)),
                          Text('${debtPaid.toStringAsFixed(0)} EGP', style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      if (credit > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('⊕ Credit Added', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12)),
                            Text('+${credit.toStringAsFixed(0)} EGP', style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
            onConfirm: () async {
              final amount = double.tryParse(amtCtrl.text) ?? 0;
              if (amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('invalid_amount'.tr()), backgroundColor: Colors.red));
                return false;
              }
              await dist.collectFromRetailer(
                collectorId: collector.id,
                retailerId: selectedRetailerId,
                amount: amount,
                createdByUid: auth.currentUser?.uid ?? 'system',
              );
              return true;
            },
          );
        },
      ),
    );
  }

  void _showDepositDialog(BuildContext context, Collector collector, DistributionProvider dist, AuthProvider auth) {
    final amtCtrl = TextEditingController(text: collector.cashOnHand.toStringAsFixed(0));
    final banks = dist.bankAccounts;
    if (banks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('no_data'.tr())));
      return;
    }
    String selectedBankId = banks.first.id;
    showDialog(
      context: context,
      builder: (ctx2) => StatefulBuilder(
        builder: (context2, setSt) => _Dialog(
          title: 'deposit_to_bank_action'.tr(args: [collector.name]),
          fields: [
            DropdownButtonFormField<String>(
              value: selectedBankId,
              dropdownColor: AppTheme.surfaceColor(context),
              style: TextStyle(color: AppTheme.textPrimaryColor(context)),
              decoration: InputDecoration(
                labelText: 'banks'.tr(),
                labelStyle: TextStyle(color: AppTheme.textMutedColor(context)),
                filled: true,
                fillColor: AppTheme.textPrimaryColor(context).withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: banks.map((b) => DropdownMenuItem(value: b.id, child: Text(b.bankName))).toList(),
              onChanged: (v) => setSt(() => selectedBankId = v ?? selectedBankId),
            ),
            const SizedBox(height: 12),
            _tf(context, amtCtrl, 'amount_egp'.tr(), Icons.monetization_on, keyboard: TextInputType.number),
          ],
          onConfirm: () async {
            final amount = double.tryParse(amtCtrl.text) ?? 0;
            if (amount <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('invalid_amount'.tr()), backgroundColor: Colors.red));
              return false;
            }
            await dist.depositToBank(
              collectorId: collector.id,
              bankAccountId: selectedBankId,
              amount: amount,
              createdByUid: auth.currentUser?.uid ?? 'system',
            );
            return true;
          },
        ),
      ),
    );
  }

  void _showAssignRetailersDialog(BuildContext context, Collector collector, DistributionProvider dist) {
    final surface = AppTheme.surfaceColor(context);
    final allRetailers = dist.retailers;
    final Set<String> assigned = allRetailers
        .where((r) => r.assignedCollectorId == collector.uid)
        .map((r) => r.id).toSet();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: surface,
          title: Text('${'assign_retailers'.tr()} — ${collector.name}',
            style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 15)),
          content: SizedBox(
            width: double.maxFinite,
            child: allRetailers.isEmpty
                ? Text('no_data'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context)))
                : ListView(
                    shrinkWrap: true,
                    children: allRetailers.map((r) {
                      final isChecked = assigned.contains(r.id);
                      final currentCollector = r.assignedCollectorId != null && r.assignedCollectorId != collector.uid
                          ? dist.collectors.where((c) => c.uid == r.assignedCollectorId).map((c) => c.name).firstOrNull : null;
                      return CheckboxListTile(
                        value: isChecked,
                        title: Text(r.name, style: TextStyle(color: AppTheme.textPrimaryColor(context))),
                        subtitle: currentCollector != null
                            ? Text('${'assigned_to'.tr()}: $currentCollector', style: const TextStyle(color: Colors.orange, fontSize: 11))
                            : Text(r.area, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11)),
                        activeColor: const Color(0xFFA78BFA),
                        checkColor: AppTheme.textPrimaryColor(context),
                        onChanged: (val) => setSt(() {
                          if (val == true) assigned.add(r.id);
                          else assigned.remove(r.id);
                        }),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('cancel'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context))),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final collectorUid = collector.uid;
                if (collectorUid == null || collectorUid.isEmpty) { return; }
                for (final r in allRetailers) {
                  final shouldBeAssigned = assigned.contains(r.id);
                  final currentlyAssigned = r.assignedCollectorId == collectorUid;
                  if (shouldBeAssigned && !currentlyAssigned) await dist.assignRetailerToCollector(r.id, collectorUid);
                  else if (!shouldBeAssigned && currentlyAssigned) await dist.assignRetailerToCollector(r.id, null);
                }
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('retailers_assigned'.tr())));
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA78BFA)),
              child: Text('save'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context))),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _tf(BuildContext context, TextEditingController c, String label, IconData icon,
      {TextInputType keyboard = TextInputType.text, void Function(String)? onChanged}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          style: TextStyle(color: AppTheme.textPrimaryColor(context)),
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: AppTheme.textMutedColor(context)),
            prefixIcon: Icon(icon, color: AppTheme.textMutedColor(context), size: 20),
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );

  static String _fmt(double v) {
    return NumberFormat('#,##0.00', 'en_US').format(v);
  }
}
