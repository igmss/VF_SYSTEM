import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/auth_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../models/collector.dart';
import '../../models/retailer.dart';
import '../../theme/app_theme.dart';

class CollectorsScreen extends StatelessWidget {
  const CollectorsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    final auth = context.watch<AuthProvider>();
    final textPrimary = AppTheme.textPrimaryColor(context);
    final surface = AppTheme.surfaceColor(context);
    final isLight = !AppTheme.isDark(context);

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        title: Text('collectors'.tr(), style: TextStyle(color: textPrimary, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: textPrimary),
        actions: [
          if (auth.isAdmin)
            IconButton(
              tooltip: 'add_collector'.tr(),
              icon: Icon(Icons.person_add, color: isLight ? const Color(0xFF8C6239) : AppTheme.accent),
              onPressed: () => _showPickUserDialog(context),
            ),
        ],
      ),
      body: dist.collectors.isEmpty
          ? _empty(context)
          : Column(
              children: [
                _cashBanner(context, dist.totalCollectorCash),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: AppTheme.isDark(context)
                            ? AppTheme.panelGradient(context)
                            : const [Color(0xFFFFFBF4), Color(0xFFF4E8D7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppTheme.lineColor(context)),
                    ),
                    child: Text(
                      'See cash exposure, collector limits, and assignment operations in a more structured control panel.',
                      style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13, fontWeight: FontWeight.w600, height: 1.35),
                    ),
                  ),
                ),
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
            ),
    );
  }

  Widget _cashBanner(BuildContext context, double total) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: AppTheme.isDark(context)
                  ? const [Color(0xFF1F2937), Color(0xFF111827)]
                  : const [Color(0xFFFFF6E2), Color(0xFFF0DFC2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppTheme.isDark(context)
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFF8C6239).withValues(alpha: 0.18),
          ),
          boxShadow: [
            BoxShadow(
                color: AppTheme.isDark(context)
                    ? Colors.black.withValues(alpha: 0.24)
                    : const Color(0xFF8C6239).withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 10))
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.isDark(context)
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFF8C6239).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.delivery_dining, color: AppTheme.isDark(context) ? Colors.white : const Color(0xFF8C6239), size: 28),
            ),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('total_cash_in_hand'.tr(),
                  style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12, fontWeight: FontWeight.w600)),
              Text('${_fmt(total)} EGP',
                  style: TextStyle(
                      color: AppTheme.textPrimaryColor(context), fontSize: 24, fontWeight: FontWeight.w900)),
            ])
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

  /// Shows all COLLECTOR-role users (from users/ node) who are NOT yet
  /// in the collectors list. Admin taps one to instantly add them.
  void _showPickUserDialog(BuildContext context) async {
    final dist = context.read<DistributionProvider>();
    // Load all users from Firebase to find COLLECTOR-role ones
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: Color(0xFFA78BFA))),
    );

    try {
      final allUsers = await context.read<AuthProvider>().getAllUsers();
      Navigator.pop(context); // dismiss loading

      // Filter: role == COLLECTOR and not already in collectors list
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
      Navigator.pop(context); // dismiss loading if still shown
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
    // Show ALL active retailers — admin may collect more than the debt (credit)
    final retailers = dist.retailers;
    if (retailers.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('no_data'.tr())));
      return;
    }
    String selectedRetailerId = retailers.first.id;
    showDialog(
      context: context,
      builder: (ctx2) => StatefulBuilder(
        builder: (context2, setSt) {
          final selectedRetailer =
              retailers.firstWhere((r) => r.id == selectedRetailerId);
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
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                items: retailers
                    .map((r) => DropdownMenuItem(
                        value: r.id,
                        child: Text('${r.name} (${_fmt(r.pendingDebt)} EGP)')))
                    .toList(),
                onChanged: (v) =>
                    setSt(() => selectedRetailerId = v ?? selectedRetailerId),
              ),
              const SizedBox(height: 12),
              _tf(context, amtCtrl, 'amount_egp'.tr(), Icons.monetization_on,
                  keyboard: TextInputType.number,
                  onChanged: (_) => setSt(() {})),
              // Live breakdown
              if (entered > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: credit > 0
                          ? const Color(0xFF4ADE80).withOpacity(0.4)
                          : AppTheme.lineColor(context),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('↓ Debt Reduced',
                              style: TextStyle(
                                  color: AppTheme.textMutedColor(context), fontSize: 12)),
                          Text('${debtPaid.toStringAsFixed(0)} EGP',
                              style: const TextStyle(
                                  color: Color(0xFFFBBF24),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      if (credit > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('⊕ Credit Added',
                                style: TextStyle(
                                    color: AppTheme.textMutedColor(context), fontSize: 12)),
                            Text('+${credit.toStringAsFixed(0)} EGP',
                                style: const TextStyle(
                                    color: Color(0xFF4ADE80),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('invalid_amount'.tr()), backgroundColor: Colors.red),
                );
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

  void _showDepositDialog(BuildContext context, Collector collector,
      DistributionProvider dist, AuthProvider auth) {
    final amtCtrl = TextEditingController(
        text: collector.cashOnHand.toStringAsFixed(0));
    final banks = dist.bankAccounts;
    if (banks.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('no_data'.tr())));
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
              items: banks
                  .map((b) => DropdownMenuItem(value: b.id, child: Text(b.bankName)))
                  .toList(),
              onChanged: (v) => setSt(() => selectedBankId = v ?? selectedBankId),
            ),
            const SizedBox(height: 12),
            _tf(context, amtCtrl, 'amount_egp'.tr(), Icons.monetization_on,
                keyboard: TextInputType.number),
          ],
          onConfirm: () async {
            final amount = double.tryParse(amtCtrl.text) ?? 0;
            if (amount <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('invalid_amount'.tr()), backgroundColor: Colors.red),
              );
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

  void _showAssignRetailersDialog(
      BuildContext context, Collector collector, DistributionProvider dist) {
    final surface = AppTheme.surfaceColor(context);
    final allRetailers = dist.retailers;
    // Which retailer IDs are currently assigned to this collector?
    final Set<String> assigned = allRetailers
        .where((r) => r.assignedCollectorId == collector.uid)
        .map((r) => r.id)
        .toSet();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: surface,
          title: Text(
            '${'assign_retailers'.tr()} — ${collector.name}',
            style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 15),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: allRetailers.isEmpty
                ? Text('no_data'.tr(),
                    style: TextStyle(color: AppTheme.textMutedColor(context)))
                : ListView(
                    shrinkWrap: true,
                    children: allRetailers.map((r) {
                      final isChecked = assigned.contains(r.id);
                      final currentCollector =
                          r.assignedCollectorId != null &&
                                  r.assignedCollectorId != collector.uid
                              ? dist.collectors
                                  .where((c) =>
                                      c.uid == r.assignedCollectorId)
                                  .map((c) => c.name)
                                  .firstOrNull
                              : null;
                      return CheckboxListTile(
                        value: isChecked,
                        title: Text(r.name,
                            style: TextStyle(color: AppTheme.textPrimaryColor(context))),
                        subtitle: currentCollector != null
                            ? Text(
                                '${'assigned_to'.tr()}: $currentCollector',
                                style: const TextStyle(
                                    color: Colors.orange, fontSize: 11))
                            : Text(r.area,
                                style: TextStyle(
                                    color: AppTheme.textMutedColor(context), fontSize: 11)),
                        activeColor: const Color(0xFFA78BFA),
                        checkColor: AppTheme.textPrimaryColor(context),
                        onChanged: (val) => setSt(() {
                          if (val == true) {
                            assigned.add(r.id);
                          } else {
                            assigned.remove(r.id);
                          }
                        }),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('cancel'.tr(),
                  style: TextStyle(color: AppTheme.textMutedColor(context))),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final collectorUid = collector.uid;
                if (collectorUid == null || collectorUid.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('collector_no_uid'.tr()),
                      backgroundColor: Colors.red));
                  return;
                }
                // For each retailer, assign/unassign
                for (final r in allRetailers) {
                  final shouldBeAssigned = assigned.contains(r.id);
                  final currentlyAssigned =
                      r.assignedCollectorId == collectorUid;
                  if (shouldBeAssigned && !currentlyAssigned) {
                    await dist.assignRetailerToCollector(r.id, collectorUid);
                  } else if (!shouldBeAssigned && currentlyAssigned) {
                    await dist.assignRetailerToCollector(r.id, null);
                  }
                }
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('retailers_assigned'.tr())));
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA78BFA)),
              child: Text('save'.tr(),
                  style: TextStyle(color: AppTheme.textPrimaryColor(context))),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _tf(BuildContext context, TextEditingController c, String label, IconData icon,
      {TextInputType keyboard = TextInputType.text,
      void Function(String)? onChanged}) =>
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
            fillColor: AppTheme.textPrimaryColor(context).withValues(alpha: 0.06),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.1))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.1))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE63946))),
          ),
        ),
      );

  static String _fmt(double v) {
    return NumberFormat('#,##0.00', 'en_US').format(v);
  }
}

class _CollectorCard extends StatelessWidget {
  final Collector collector;
  final bool isAdmin;
  final VoidCallback onCollect;
  final VoidCallback onDeposit;
  final VoidCallback? onEdit;
  final VoidCallback? onAssignRetailers;

  const _CollectorCard({
    required this.collector,
    required this.isAdmin,
    required this.onCollect,
    required this.onDeposit,
    this.onEdit,
    this.onAssignRetailers,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (collector.cashOnHand / collector.cashLimit).clamp(0.0, 1.0);
    final isCritical = collector.cashOnHand >= collector.cashLimit;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.isDark(context)
              ? [AppTheme.surfaceColor(context), AppTheme.surfaceRaisedColor(context)]
              : const [Color(0xFFFFFEFB), Color(0xFFF6EFE2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCritical
              ? Colors.red.withOpacity(0.4)
              : (AppTheme.isDark(context)
                  ? Colors.white.withOpacity(0.08)
                  : const Color(0xFF8C6239).withOpacity(0.18)),
          width: isCritical ? 2 : 1,
        ),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (AppTheme.isDark(context) ? AppTheme.accent : const Color(0xFF8C6239)).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.delivery_dining, color: AppTheme.isDark(context) ? AppTheme.accent : const Color(0xFF8C6239), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(collector.name,
                  style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold)),
              Text(collector.phone,
                  style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12)),
            ]),
          ),
          if (onEdit != null)
            IconButton(
              icon: Icon(Icons.edit, color: AppTheme.textMutedColor(context), size: 18),
              onPressed: onEdit,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_f(collector.cashOnHand)} EGP',
                style: TextStyle(
                    color: isCritical ? Colors.redAccent : (AppTheme.isDark(context) ? AppTheme.accent : const Color(0xFF8C6239)),
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
              ),
              Text(
                'limit: ${_f(collector.cashLimit)}',
                style: TextStyle(color: AppTheme.textMutedColor(context).withValues(alpha: 0.6), fontSize: 10),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 6,
            backgroundColor: AppTheme.lineColor(context),
            valueColor: AlwaysStoppedAnimation<Color>(
                isCritical ? Colors.redAccent : (AppTheme.isDark(context) ? AppTheme.accent : const Color(0xFF8C6239))),
          ),
        ),
        const SizedBox(height: 16),
        if (isAdmin)
          Column(children: [
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCollect,
                  icon: const Icon(Icons.arrow_downward, size: 14),
                  label: Text('collected'.tr(), style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4ADE80),
                    side: const BorderSide(color: Color(0xFF4ADE80)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDeposit,
                  icon: const Icon(Icons.account_balance, size: 14),
                  label: Text('deposit'.tr(), style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4CC9F0),
                    side: const BorderSide(color: Color(0xFF4CC9F0)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ]),
            if (onAssignRetailers != null) ...[                           
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onAssignRetailers,
                  icon: const Icon(Icons.store_outlined, size: 14),
                  label: Text('assign_retailers'.tr(),
                      style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.isDark(context) ? AppTheme.accent : const Color(0xFF8C6239),
                    side: BorderSide(color: AppTheme.isDark(context) ? AppTheme.accent : const Color(0xFF8C6239)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ]),
      ]),
    );
  }

  String _f(double v) {
    return NumberFormat('#,##0.00', 'en_US').format(v);
  }
}

class _Dialog extends StatelessWidget {
  final String title;
  final List<Widget> fields;
  final Future<bool> Function() onConfirm;

  const _Dialog({required this.title, required this.fields, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceColor(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 18),
            ...fields,
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('cancel'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context))),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final shouldClose = await onConfirm();
                    if (shouldClose && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.isDark(context) ? AppTheme.accent : const Color(0xFF8C6239),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('save'.tr(), style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

