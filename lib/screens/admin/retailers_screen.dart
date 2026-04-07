import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../providers/app_provider.dart';
import '../../models/retailer.dart';
import 'retailer_details_screen.dart';
import 'credit_return_dialog.dart';
import '../../theme/app_theme.dart';

part 'retailer_card.dart';
part 'retailer_dialogs.dart';

class RetailersScreen extends StatelessWidget {
  const RetailersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    final auth = context.watch<AuthProvider>();
    final textPrimary = AppTheme.textPrimaryColor(context);
    final surface = AppTheme.surfaceColor(context);

    final isEmbedded = auth.isAdmin || auth.isFinance;

    final bodyContent = dist.retailers.isEmpty
          ? _empty(context)
          : Column(
              children: [
                _debtBanner(context, dist.totalRetailerDebt, auth.isAdmin),
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
                      'Track retailer debt, assignment quality, and repayment flow from one cleaner workspace.',
                      style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13, fontWeight: FontWeight.w600, height: 1.35),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                    itemCount: dist.retailers.length,
                    itemBuilder: (ctx, i) => _RetailerCard(
                      retailer: dist.retailers[i],
                      isAdmin: auth.isAdmin || auth.isFinance,
                      onDistribute: () => _showDistributeDialog(ctx, dist.retailers[i], dist, auth),
                      onReturn: () => _showCreditReturnDialog(ctx, dist.retailers[i]),
                      onEdit: () => _showEditDialog(ctx, dist.retailers[i]),
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
          title: Text('retailers'.tr(), style: TextStyle(color: textPrimary, fontWeight: FontWeight.w800)),
          iconTheme: IconThemeData(color: textPrimary),
        ),
        body: bodyContent,
      );
    }
  }

  Widget _debtBanner(BuildContext context, double total, bool isAdmin) => Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [AppTheme.warningColor(context), AppTheme.warningColor(context).withValues(alpha: 0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
                color: AppTheme.warningColor(context).withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8))
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.store, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('total_outstanding_debt'.tr(),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${_fmt(total)} EGP',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              ]),
            ),
            if (isAdmin) ...[
              IconButton(
                icon: const Icon(Icons.build_outlined, color: Colors.white),
                tooltip: 'Fix Rounding',
                padding: const EdgeInsets.all(10),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  highlightColor: Colors.white.withValues(alpha: 0.25),
                ),
                onPressed: () async {
                  final dist = context.read<DistributionProvider>();
                  final fixed = await dist.roundAllRetailerAssignments();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(fixed == 0
                          ? 'All assignments already rounded.'
                          : 'Fixed $fixed retailer(s).'),
                      backgroundColor: fixed == 0 ? Colors.green : Colors.orange,
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add, color: Colors.white),
                tooltip: 'Add Retailer',
                padding: const EdgeInsets.all(10),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  highlightColor: Colors.white.withValues(alpha: 0.25),
                ),
                onPressed: () => _showAddDialog(context),
              ),
            ],
          ],
        ),
      );

  Widget _empty(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store_outlined, size: 64, color: AppTheme.textMutedColor(context).withValues(alpha: 0.15)),
            const SizedBox(height: 16),
            Text('no_data'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context).withValues(alpha: 0.5), fontSize: 16, fontWeight: FontWeight.bold)),
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
          _tf(context, nameCtrl, 'retailer_name'.tr(), Icons.store),
          _tf(context, phoneCtrl, 'phone'.tr(), Icons.phone, keyboard: TextInputType.phone),
          _tf(context, areaCtrl, 'area'.tr(), Icons.location_on),
          _tf(context, discountCtrl, 'Discount per 1,000 EGP', Icons.percent, keyboard: const TextInputType.numberWithOptions(signed: true, decimal: true)),
        ],
        onConfirm: () async {
          final discount = double.tryParse(discountCtrl.text) ?? 0.0;
          await context.read<DistributionProvider>().addRetailer(
                Retailer(
                  name: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  area: areaCtrl.text.trim(),
                  discountPer1000: discount,
                ),
              );
          return true;
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
          _tf(context, nameCtrl, 'retailer_name'.tr(), Icons.store),
          _tf(context, phoneCtrl, 'phone'.tr(), Icons.phone, keyboard: TextInputType.phone),
          _tf(context, areaCtrl, 'area'.tr(), Icons.location_on),
          _tf(context, discountCtrl, 'Discount per 1,000 EGP', Icons.percent, keyboard: const TextInputType.numberWithOptions(signed: true, decimal: true)),
        ],
        onConfirm: () async {
          final discount = double.tryParse(discountCtrl.text) ?? 0.0;
          await context.read<DistributionProvider>().updateRetailer(
                retailer.copyWith(
                  name: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  area: areaCtrl.text.trim(),
                  discountPer1000: discount,
                ),
              );
          return true;
        },
      ),
    );
  }

  void _showDistributeDialog(BuildContext context, Retailer retailer,
      DistributionProvider dist, AuthProvider auth) {
    final amtCtrl = TextEditingController();
    final feesCtrl = TextEditingController();
    bool isExternalWallet = false;
    bool applyCredit = false;
    final appProvider = context.read<AppProvider>();
    final numbers = appProvider.mobileNumbers;
    if (numbers.isEmpty) { return; }
    String selectedId = numbers.first.id;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final isSubmitting = ctx.watch<DistributionProvider>().isDistributing;
          final selectedNum = numbers.firstWhere((n) => n.id == selectedId);
          final availableBalance = selectedNum.currentBalance;
          return _Dialog(
            title: 'distribute_vf_cash'.tr(args: [retailer.name]),
            fields: [
              DropdownButtonFormField<String>(
                value: selectedId,
                dropdownColor: AppTheme.surfaceColor(context),
                style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: 'from'.tr(),
                  filled: true,
                  fillColor: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
                ),
                items: numbers.map((n) => DropdownMenuItem(
                  value: n.id,
                  child: Text('${n.phoneNumber}  (${n.currentBalance.toStringAsFixed(0)} EGP)'),
                )).toList(),
                onChanged: (v) => setSt(() => selectedId = v ?? selectedId),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: availableBalance <= 0 ? Colors.red.withValues(alpha: 0.08) : AppTheme.positiveColor(context).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: availableBalance <= 0 ? Colors.red.withValues(alpha: 0.3) : AppTheme.positiveColor(context).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(availableBalance <= 0 ? Icons.warning_amber : Icons.account_balance_wallet,
                      size: 16, color: availableBalance <= 0 ? Colors.orange : AppTheme.positiveColor(context)),
                    const SizedBox(width: 10),
                    Text('available: ${availableBalance.toStringAsFixed(0)} EGP',
                      style: TextStyle(color: availableBalance <= 0 ? Colors.orange : AppTheme.positiveColor(context), fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _tf(ctx, amtCtrl, 'amount_egp'.tr(), Icons.monetization_on,
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
                title: Text('External Wallet (Charge Fees)', style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 13, fontWeight: FontWeight.w600)),
                value: isExternalWallet,
                activeColor: AppTheme.accent,
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
                    } else { feesCtrl.text = ''; }
                  });
                },
              ),
              _tf(ctx, feesCtrl, 'Vodafone Fees (Optional)'.tr(), Icons.money_off, keyboard: TextInputType.number),
              if (retailer.credit > 0)
                CheckboxListTile(
                  title: Text('Use Retailer Credit (${retailer.credit.toStringAsFixed(0)} EGP)', style: TextStyle(color: AppTheme.positiveColor(context), fontSize: 13, fontWeight: FontWeight.bold)),
                  value: applyCredit,
                  activeColor: AppTheme.positiveColor(context),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (val) => setSt(() => applyCredit = val ?? false),
                ),
            ],
            confirmLabel: 'Assign',
            isLoading: isSubmitting,
            onConfirm: () async {
              final num = numbers.firstWhere((n) => n.id == selectedId);
              final amount = double.tryParse(amtCtrl.text) ?? 0;
              final fees = double.tryParse(feesCtrl.text) ?? 0;
              if (amount <= 0) return false;
              try {
                await dist.distributeVfCash(
                  retailerId: retailer.id, fromVfNumberId: num.id, fromVfPhone: num.phoneNumber,
                  amount: amount, fees: fees, chargeFeesToRetailer: isExternalWallet,
                  applyCredit: applyCredit, createdByUid: auth.currentUser?.uid ?? 'system',
                );
                return true;
              } catch (e) { return false; }
            },
          );
        },
      ),
    );
  }

  void _showCreditReturnDialog(BuildContext context, Retailer retailer) {
    showDialog(context: context, builder: (ctx) => CreditReturnDialog(retailer: retailer));
  }

  static Widget _tf(BuildContext context, TextEditingController c, String label, IconData icon,
      {TextInputType keyboard = TextInputType.text, void Function(String)? onChanged}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold),
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 20),
            filled: true,
          ),
        ),
      );

  static String _fmt(double v) {
    return NumberFormat('#,##0.00', 'en_US').format(v);
  }
}
