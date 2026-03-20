import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/auth_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../models/collector.dart';
import '../../models/retailer.dart';

class CollectorsScreen extends StatelessWidget {
  const CollectorsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16162A),
        title: Text('collectors'.tr(), style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (auth.isAdmin)
            IconButton(
              tooltip: 'add_collector'.tr(),
              icon: const Icon(Icons.person_add, color: Color(0xFFE63946)),
              onPressed: () => _showPickUserDialog(context),
            ),
        ],
      ),
      body: dist.collectors.isEmpty
          ? _empty()
          : Column(
              children: [
                _cashBanner(dist.totalCollectorCash),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
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

  Widget _cashBanner(double total) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFA78BFA), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFA78BFA).withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.delivery_dining, color: Colors.white, size: 30),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('total_cash_in_hand'.tr(),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text('${_fmt(total)} EGP',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            ])
          ],
        ),
      );

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.delivery_dining_outlined, size: 60, color: Colors.white24),
            const SizedBox(height: 12),
            Text('no_data'.tr(), style: const TextStyle(color: Colors.white38)),
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
          backgroundColor: const Color(0xFF16162A),
          title: Text('select_collector_user'.tr(),
              style: const TextStyle(color: Colors.white, fontSize: 15)),
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
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text(u.email,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
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
              onPressed: () => Navigator.pop(ctx),
              child: Text('cancel'.tr(),
                  style: const TextStyle(color: Colors.white38)),
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
          _tf(nameCtrl, 'name'.tr(), Icons.person),
          _tf(phoneCtrl, 'phone'.tr(), Icons.phone, keyboard: TextInputType.phone),
          _tf(limitCtrl, 'Cash Limit (EGP)', Icons.account_balance_wallet, keyboard: TextInputType.number),
        ],
        onConfirm: () {
          final newLimit = double.tryParse(limitCtrl.text) ?? 50000.0;
          dist.updateCollector(
            collector.copyWith(
              name: nameCtrl.text.trim(),
              phone: phoneCtrl.text.trim(),
              cashLimit: newLimit,
            ),
          );
        },
      ),
    );
  }

  void _showCollectDialog(BuildContext ctx, Collector collector,
      DistributionProvider dist, AuthProvider auth) {
    final amtCtrl = TextEditingController();
    final retailers = dist.retailers.where((r) => r.pendingDebt > 0).toList();
    if (retailers.isEmpty) {
      ScaffoldMessenger.of(ctx)
          .showSnackBar(SnackBar(content: Text('no_data'.tr())));
      return;
    }
    String selectedRetailerId = retailers.first.id;
    showDialog(
      context: ctx,
      builder: (ctx2) => StatefulBuilder(
        builder: (ctx2, setSt) => _Dialog(
          title: 'collect_from_retailer'.tr(args: [collector.name]),
          fields: [
            DropdownButtonFormField<String>(
              value: selectedRetailerId,
              dropdownColor: const Color(0xFF1E1E3A),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'retailers'.tr(),
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: retailers
                  .map((r) => DropdownMenuItem(
                      value: r.id,
                      child: Text('${r.name} (${_fmt(r.pendingDebt)} EGP)')))
                  .toList(),
              onChanged: (v) => setSt(() => selectedRetailerId = v ?? selectedRetailerId),
            ),
            const SizedBox(height: 12),
            _tf(amtCtrl, 'amount_egp'.tr(), Icons.monetization_on,
                keyboard: TextInputType.number),
          ],
          onConfirm: () {
            dist.collectFromRetailer(
              collectorId: collector.id,
              retailerId: selectedRetailerId,
              amount: double.tryParse(amtCtrl.text) ?? 0,
              createdByUid: auth.currentUser?.uid ?? 'system',
            );
          },
        ),
      ),
    );
  }

  void _showDepositDialog(BuildContext ctx, Collector collector,
      DistributionProvider dist, AuthProvider auth) {
    final amtCtrl = TextEditingController(
        text: collector.cashOnHand.toStringAsFixed(0));
    final banks = dist.bankAccounts;
    if (banks.isEmpty) {
      ScaffoldMessenger.of(ctx)
          .showSnackBar(SnackBar(content: Text('no_data'.tr())));
      return;
    }
    String selectedBankId = banks.first.id;
    showDialog(
      context: ctx,
      builder: (ctx2) => StatefulBuilder(
        builder: (ctx2, setSt) => _Dialog(
          title: 'deposit_to_bank_action'.tr(args: [collector.name]),
          fields: [
            DropdownButtonFormField<String>(
              value: selectedBankId,
              dropdownColor: const Color(0xFF1E1E3A),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'banks'.tr(),
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: banks
                  .map((b) => DropdownMenuItem(value: b.id, child: Text(b.bankName)))
                  .toList(),
              onChanged: (v) => setSt(() => selectedBankId = v ?? selectedBankId),
            ),
            const SizedBox(height: 12),
            _tf(amtCtrl, 'amount_egp'.tr(), Icons.monetization_on,
                keyboard: TextInputType.number),
          ],
          onConfirm: () {
            dist.depositToBank(
              collectorId: collector.id,
              bankAccountId: selectedBankId,
              amount: double.tryParse(amtCtrl.text) ?? 0,
              createdByUid: auth.currentUser?.uid ?? 'system',
            );
          },
        ),
      ),
    );
  }

  void _showAssignRetailersDialog(
      BuildContext context, Collector collector, DistributionProvider dist) {
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
          backgroundColor: const Color(0xFF16162A),
          title: Text(
            '${'assign_retailers'.tr()} — ${collector.name}',
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: allRetailers.isEmpty
                ? Text('no_data'.tr(),
                    style: const TextStyle(color: Colors.white38))
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
                            style: const TextStyle(color: Colors.white)),
                        subtitle: currentCollector != null
                            ? Text(
                                '${'assigned_to'.tr()}: $currentCollector',
                                style: const TextStyle(
                                    color: Colors.orange, fontSize: 11))
                            : Text(r.area,
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11)),
                        activeColor: const Color(0xFFA78BFA),
                        checkColor: Colors.white,
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
              onPressed: () => Navigator.pop(ctx),
              child: Text('cancel'.tr(),
                  style: const TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
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
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _tf(TextEditingController c, String label, IconData icon,
      {TextInputType keyboard = TextInputType.text}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white54),
            prefixIcon: Icon(icon, color: Colors.white38, size: 20),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
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
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCritical ? Colors.red.withOpacity(0.4) : const Color(0xFFA78BFA).withOpacity(0.2),
          width: isCritical ? 2 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFA78BFA).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.delivery_dining, color: Color(0xFFA78BFA), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(collector.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text(collector.phone,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
          if (onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white54, size: 18),
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
                    color: isCritical ? Colors.redAccent : const Color(0xFFA78BFA),
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
              ),
              Text(
                'limit: ${_f(collector.cashLimit)}',
                style: const TextStyle(color: Colors.white24, fontSize: 10),
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
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation<Color>(
                isCritical ? Colors.redAccent : const Color(0xFFA78BFA)),
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
                    foregroundColor: const Color(0xFFA78BFA),
                    side: const BorderSide(color: Color(0xFFA78BFA)),
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
  final VoidCallback onConfirm;

  const _Dialog({required this.title, required this.fields, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF16162A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 18),
            ...fields,
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('cancel'.tr(), style: const TextStyle(color: Colors.white38)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () { Navigator.pop(context); onConfirm(); },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE63946),
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
