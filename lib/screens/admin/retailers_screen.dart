import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/auth_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../providers/app_provider.dart';
import '../../models/retailer.dart';
import 'retailer_details_screen.dart';
import 'credit_return_dialog.dart';

class RetailersScreen extends StatelessWidget {
  const RetailersScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16162A),
        title: Text('retailers'.tr(), style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (auth.isAdmin)
            IconButton(
              icon: const Icon(Icons.build_outlined, color: Colors.orange),
              tooltip: 'Fix Rounding (One-Time)',
              onPressed: () async {
                final fixed = await dist.roundAllRetailerAssignments();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(fixed == 0
                        ? 'All assignments already rounded ✅'
                        : 'Fixed $fixed retailer(s) — amounts rounded up ✅'),
                    backgroundColor: fixed == 0 ? Colors.green : Colors.orange,
                  ),
                );
              },
            ),
          if (auth.isAdmin)
            IconButton(
              icon: const Icon(Icons.add, color: Color(0xFFE63946)),
              onPressed: () => _showAddDialog(context),
            ),
        ],
      ),
      body: dist.retailers.isEmpty
          ? _empty()
          : Column(
              children: [
                _debtBanner(dist.totalRetailerDebt),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: dist.retailers.length,
                    itemBuilder: (ctx, i) => InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RetailerDetailsScreen(
                              retailer: dist.retailers[i],
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: _RetailerCard(
                        retailer: dist.retailers[i],
                        isAdmin: auth.isAdmin || auth.isFinance,
                        onDistribute: () => _showDistributeDialog(ctx, dist.retailers[i], dist, auth),
                        onReturn: () => _showCreditReturnDialog(ctx, dist.retailers[i]),
                        onEdit: () => _showEditDialog(ctx, dist.retailers[i]),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _debtBanner(double total) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFFBBF24).withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.store, color: Colors.white, size: 30),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('total_outstanding_debt'.tr(),
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
            const Icon(Icons.store_outlined, size: 60, color: Colors.white24),
            const SizedBox(height: 12),
            Text('no_data'.tr(), style: const TextStyle(color: Colors.white38)),
          ],
        ),
      );

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final areaCtrl = TextEditingController();
    final discountCtrl = TextEditingController(text: '0');
    showDialog(
      context: context,
      builder: (_) => _Dialog(
        title: 'add_retailer'.tr(),
        fields: [
          _tf(nameCtrl, 'retailer_name'.tr(), Icons.store),
          _tf(phoneCtrl, 'phone'.tr(), Icons.phone, keyboard: TextInputType.phone),
          _tf(areaCtrl, 'area'.tr(), Icons.location_on),
          _tf(discountCtrl, 'Discount per 1,000 EGP', Icons.percent, keyboard: const TextInputType.numberWithOptions(signed: true, decimal: true)),
        ],
        onConfirm: () {
          final discount = double.tryParse(discountCtrl.text) ?? 0.0;
          context.read<DistributionProvider>().addRetailer(
                Retailer(
                  name: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  area: areaCtrl.text.trim(),
                  discountPer1000: discount,
                ),
              );
        },
      ),
    );
  }

  void _showEditDialog(BuildContext context, Retailer retailer) {
    final nameCtrl = TextEditingController(text: retailer.name);
    final phoneCtrl = TextEditingController(text: retailer.phone);
    final areaCtrl = TextEditingController(text: retailer.area);
    final discountCtrl = TextEditingController(text: retailer.discountPer1000.toString());
    showDialog(
      context: context,
      builder: (_) => _Dialog(
        title: 'Edit Retailer',
        fields: [
          _tf(nameCtrl, 'retailer_name'.tr(), Icons.store),
          _tf(phoneCtrl, 'phone'.tr(), Icons.phone, keyboard: TextInputType.phone),
          _tf(areaCtrl, 'area'.tr(), Icons.location_on),
          _tf(discountCtrl, 'Discount per 1,000 EGP', Icons.percent, keyboard: const TextInputType.numberWithOptions(signed: true, decimal: true)),
        ],
        onConfirm: () {
          final discount = double.tryParse(discountCtrl.text) ?? 0.0;
          context.read<DistributionProvider>().updateRetailer(
                retailer.copyWith(
                  name: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  area: areaCtrl.text.trim(),
                  discountPer1000: discount,
                ),
              );
        },
      ),
    );
  }

  void _showDistributeDialog(BuildContext context, Retailer retailer,
      DistributionProvider dist, AuthProvider auth) {
    final amtCtrl = TextEditingController();
    final feesCtrl = TextEditingController();
    bool isExternalWallet = false;
    final appProvider = context.read<AppProvider>();
    // Only show numbers that have a positive balance
    final numbers = appProvider.mobileNumbers;
    if (numbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('no_data'.tr())));
      return;
    }
    String selectedId = numbers.first.id;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final selectedNum = numbers.firstWhere((n) => n.id == selectedId);
          final availableBalance = selectedNum.currentBalance;
          return _Dialog(
            title: 'distribute_vf_cash'.tr(args: [retailer.name]),
            fields: [
              // Show balance for each number in the dropdown
              DropdownButtonFormField<String>(
                value: selectedId,
                dropdownColor: const Color(0xFF1E1E3A),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'from'.tr(),
                  labelStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                items: numbers.map((n) => DropdownMenuItem(
                  value: n.id,
                  child: Text(
                    '${n.phoneNumber}  (${n.currentBalance.toStringAsFixed(0)} EGP)',
                  ),
                )).toList(),
                onChanged: (v) => setSt(() => selectedId = v ?? selectedId),
              ),
              const SizedBox(height: 8),
              // Show available balance warning
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: availableBalance <= 0
                      ? Colors.red.withOpacity(0.1)
                      : const Color(0xFF4ADE80).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: availableBalance <= 0
                        ? Colors.red.withOpacity(0.4)
                        : const Color(0xFF4ADE80).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      availableBalance <= 0
                          ? Icons.warning_amber
                          : Icons.account_balance_wallet,
                      size: 16,
                      color: availableBalance <= 0 ? Colors.orange : const Color(0xFF4ADE80),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'available: ${availableBalance.toStringAsFixed(0)} EGP',
                      style: TextStyle(
                        color: availableBalance <= 0 ? Colors.orange : const Color(0xFF4ADE80),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _tf(amtCtrl, 'amount_egp'.tr(), Icons.monetization_on,
                  keyboard: TextInputType.number,
                  onChanged: (val) {
                    if (isExternalWallet) {
                      final amt = double.tryParse(val) ?? 0.0;
                      double calcFee = amt * 0.005;
                      if (calcFee > 15.0) calcFee = 15.0;
                      feesCtrl.text = calcFee.toStringAsFixed(2);
                    }
                  }),
              CheckboxListTile(
                title: const Text('External Wallet (Charge Fees)', style: TextStyle(color: Colors.white, fontSize: 13)),
                value: isExternalWallet,
                activeColor: const Color(0xFFE63946),
                checkColor: Colors.white,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (val) {
                  setSt(() {
                    isExternalWallet = val ?? false;
                    if (isExternalWallet) {
                      final amt = double.tryParse(amtCtrl.text) ?? 0.0;
                      double calcFee = amt * 0.005;
                      if (calcFee > 15.0) calcFee = 15.0;
                      feesCtrl.text = calcFee.toStringAsFixed(2);
                    } else {
                      feesCtrl.text = ''; // Clear fees if unchecked
                    }
                  });
                },
              ),
              _tf(feesCtrl, 'Vodafone Fees (Optional)'.tr(), Icons.money_off,
                  keyboard: TextInputType.number),
            ],
            onConfirm: () {
              final num = numbers.firstWhere((n) => n.id == selectedId);
              final amount = double.tryParse(amtCtrl.text) ?? 0;
              final fees = double.tryParse(feesCtrl.text) ?? 0;

              if (amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('invalid_amount'.tr()),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              if (amount + fees > num.currentBalance) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'insufficient_vf_balance'.tr(
                        args: [num.phoneNumber, num.currentBalance.toStringAsFixed(0)],
                      ),
                    ),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 4),
                  ),
                );
                return;
              }
              dist.distributeVfCash(
                retailerId: retailer.id,
                fromVfNumberId: num.id,
                fromVfPhone: num.phoneNumber,
                amount: amount,
                fees: fees,
                chargeFeesToRetailer: isExternalWallet,
                createdByUid: auth.currentUser?.uid ?? 'system',
              );
            },
          );
        },
      ),
    );
  }

  void _showCreditReturnDialog(BuildContext context, Retailer retailer) {
    showDialog(
      context: context,
      builder: (ctx) => CreditReturnDialog(retailer: retailer),
    );
  }

  static Widget _tf(TextEditingController c, String label, IconData icon,
      {TextInputType keyboard = TextInputType.text, void Function(String)? onChanged}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          style: const TextStyle(color: Colors.white),
          onChanged: onChanged,
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

class _RetailerCard extends StatelessWidget {
  final Retailer retailer;
  final bool isAdmin;
  final VoidCallback onDistribute;
  final VoidCallback onReturn;
  final VoidCallback onEdit;

  const _RetailerCard({
    required this.retailer,
    required this.isAdmin,
    required this.onDistribute,
    required this.onReturn,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final pct = retailer.totalAssigned > 0
        ? (retailer.totalCollected / retailer.totalAssigned).clamp(0.0, 1.0)
        : 0.0;

    // ── Debt Aging ───────────────────────────────────────────────────────────
    final daysSince = DateTime.now().difference(retailer.lastUpdatedAt).inDays;
    final hasDebt   = retailer.pendingDebt > 0;

    Color ageBadgeColor;
    String ageBadgeLabel;
    IconData ageBadgeIcon;

    if (!hasDebt) {
      // No debt — no aging badge needed
      ageBadgeColor = Colors.transparent;
      ageBadgeLabel = '';
      ageBadgeIcon  = Icons.check;
    } else if (daysSince < 7) {
      ageBadgeColor = const Color(0xFF4ADE80);   // green
      ageBadgeLabel = 'Fresh';
      ageBadgeIcon  = Icons.check_circle_outline;
    } else if (daysSince <= 30) {
      ageBadgeColor = const Color(0xFFFBBF24);   // amber
      ageBadgeLabel = 'Aging';
      ageBadgeIcon  = Icons.access_time_rounded;
    } else {
      ageBadgeColor = const Color(0xFFE63946);   // red
      ageBadgeLabel = 'Overdue';
      ageBadgeIcon  = Icons.warning_amber_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasDebt && daysSince > 30
              ? const Color(0xFFE63946).withOpacity(0.35)
              : const Color(0xFFFBBF24).withOpacity(0.2),
          width: hasDebt && daysSince > 30 ? 1.5 : 1.0,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFBBF24).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.store, color: Color(0xFFFBBF24), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(retailer.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text('${retailer.phone}${retailer.area.isNotEmpty ? ' · ${retailer.area}' : ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              if (retailer.discountPer1000 != 0)
                Text('Rate: ${retailer.discountPer1000} EGP / 1K',
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
          // ── Age badge ────────────────────────────────────────────────
          if (hasDebt)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: ageBadgeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: ageBadgeColor.withOpacity(0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(ageBadgeIcon, color: ageBadgeColor, size: 12),
                  const SizedBox(width: 4),
                  Text(ageBadgeLabel,
                      style: TextStyle(
                          color: ageBadgeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          const SizedBox(width: 8),
          if (isAdmin) ...[
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white54, size: 18),
              onPressed: onEdit,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            TextButton(
              onPressed: onDistribute,
              child: Text('assign'.tr(), style: const TextStyle(color: Color(0xFFFBBF24))),
            ),
            if (retailer.pendingDebt > 0)
              TextButton(
                onPressed: onReturn,
                child: const Text('Return', style: TextStyle(color: Color(0xFFE63946))),
              ),
          ],
        ]),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _stat('assigned'.tr(), retailer.totalAssigned, const Color(0xFF4CC9F0)),
            _stat('collected'.tr(), retailer.totalCollected, const Color(0xFF4ADE80)),
            // Debt stat with days-ago sub-label
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('debt'.tr(), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                Text('${_f(retailer.pendingDebt)} EGP',
                    style: const TextStyle(
                        color: Color(0xFFFF6B6B),
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                if (hasDebt)
                  Text(
                    daysSince == 0 ? 'today' : '$daysSince d ago',
                    style: TextStyle(
                        color: ageBadgeColor.withOpacity(0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: pct,
          backgroundColor: Colors.white10,
          color: const Color(0xFF4ADE80),
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 4),
        Text('${(pct * 100).toStringAsFixed(0)}% ' + 'collected'.tr(),
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ]),
    );
  }

  Widget _stat(String label, double val, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          Text('${_f(val)} EGP',
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      );

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
