import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../providers/distribution_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/investor.dart';
import '../../utils/formatters.dart';
import '../../theme/app_theme.dart';

class InvestorDetailScreen extends StatelessWidget {
  final Investor investor;

  const InvestorDetailScreen({super.key, required this.investor});

  void _withdrawCapital(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _WithdrawCapitalDialog(investor: investor),
    );
  }

  void _payProfit(BuildContext context, double payable) {
    showDialog(
      context: context,
      builder: (ctx) => _PayProfitDialog(investor: investor, maxAmount: payable),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    return FutureBuilder<Map<String, dynamic>>(
      future: dist.getInvestorPerformance(investorId: investor.id),
      builder: (context, perfSnap) {
        final isLoading = perfSnap.connectionState == ConnectionState.waiting;
        final hasError = perfSnap.hasError;
        final perf = perfSnap.data ?? {};
        final double totalEarned = (perf['totalEarned'] ?? 0.0).toDouble();
        final double totalPaid = (perf['totalPaid'] ?? 0.0).toDouble();
        final double payable = (perf['payableBalance'] ?? 0.0).toDouble();
        final List<dynamic> dailyBreakdown = List<dynamic>.from(perf['dailyBreakdown'] ?? []);

        return Scaffold(
          backgroundColor: AppTheme.scaffoldBg(context),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            title: Text(investor.name,
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimaryColor(context),
                    fontSize: 20,
                    letterSpacing: -0.5)),
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new,
                  color: AppTheme.textPrimaryColor(context), size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.refresh_rounded,
                    color: AppTheme.textMutedColor(context), size: 22),
                onPressed: () {
                  (context as Element).markNeedsBuild();
                },
              ),
            ],
          ),
          body: isLoading
              ? const Center(child: CircularProgressIndicator())
              : hasError
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              perfSnap.error?.toString() ?? 'Unknown error',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // — Header Card —
                      _buildHeader(context, totalEarned, totalPaid, payable),
                      const SizedBox(height: 20),
                      // — Pay Profit Button —
                      if (payable > 0)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFC8A96E),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                          icon: const Icon(Icons.payments_outlined, size: 18),
                          label: Text(
                            'pay_profit'.tr() +
                                ' (${Formatters.formatCurrency(payable)})',
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 14),
                          ),
                          onPressed: () => _payProfit(context, payable),
                        ),
                      if (payable > 0) const SizedBox(height: 16),
                      // — Daily History label —
                      Row(
                        children: [
                          Icon(Icons.bar_chart,
                              color: AppTheme.textMutedColor(context), size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'profit_history'.tr().toUpperCase(),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.textMutedColor(context),
                                letterSpacing: 1.0),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Divider(
                                  color: AppTheme.lineColor(context)
                                      .withValues(alpha: 0.5))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // — Daily Breakdown List —
                      Expanded(
                        child: dailyBreakdown.isEmpty
                            ? Center(
                                child: Text('no_data'.tr(),
                                    style: const TextStyle(
                                        color: Colors.white54)))
                            : ListView.builder(
                                itemCount: dailyBreakdown.length,
                                itemBuilder: (ctx, idx) => _DailyProfitCard(
                                  day: Map<String, dynamic>.from(
                                      dailyBreakdown[idx]),
                                  sharePercent:
                                      investor.profitSharePercent.toDouble(),
                                ),
                              ),
                      ),
                      // — Withdraw Capital Button —
                      if (investor.status == 'active') ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.errorColor(context),
                            side: BorderSide(
                                color: AppTheme.errorColor(context)
                                    .withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                          icon: const Icon(Icons.outbound_outlined, size: 20),
                          label: Text('withdraw_capital'.tr(),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 14)),
                          onPressed: () => _withdrawCapital(context),
                        ),
                      ],
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, double totalEarned, double totalPaid, double payable) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.heroGradient(context),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accent.withValues(alpha: 0.25),
            blurRadius: 32,
            offset: const Offset(0, 16),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('invested_amount'.tr(),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${investor.profitSharePercent}% ${'profit_share'.tr()}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            Formatters.formatCurrency(investor.investedAmount),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5),
          ),
          const SizedBox(height: 4),
          Text(investor.investmentDate,
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
          const Divider(color: Colors.white24, height: 28),
          Row(
            children: [
              _Stat(label: 'lifetime_earned'.tr(), value: Formatters.formatCurrency(totalEarned), color: Colors.white),
              const SizedBox(width: 24),
              _Stat(label: 'total_paid'.tr(), value: Formatters.formatCurrency(totalPaid), color: Colors.white70),
              const SizedBox(width: 24),
              _Stat(
                label: 'payable'.tr(),
                value: Formatters.formatCurrency(payable),
                color: payable > 0 ? const Color(0xFFC8A96E) : Colors.white54,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _DailyProfitCard extends StatelessWidget {
  final Map<String, dynamic> day;
  final double sharePercent;

  const _DailyProfitCard({required this.day, required this.sharePercent});

  @override
  Widget build(BuildContext context) {
    final date = day['date'] as String? ?? '';
    final double profit = (day['profit'] ?? 0.0).toDouble();
    final double vfExcess = (day['vfExcess'] ?? 0.0).toDouble();
    final double instaExcess = (day['instaExcess'] ?? 0.0).toDouble();
    final double vfProfit = (day['vfProfit'] ?? 0.0).toDouble();
    final double instaProfit = (day['instaProfit'] ?? 0.0).toDouble();
    final double excessFlow = (day['excessFlow'] ?? 0.0).toDouble();
    final bool hasProfit = profit > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.panelGradient(context),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasProfit
              ? const Color(0xFFC8A96E).withValues(alpha: 0.3)
              : AppTheme.lineColor(context).withValues(alpha: 0.4),
        ),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // — Date —
            SizedBox(
              width: 52,
              child: Text(
                date.length >= 5 ? date.substring(5) : date,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimaryColor(context)),
              ),
            ),
            const SizedBox(width: 12),
            // — VF & Insta Excess —
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (vfExcess > 0)
                    _ChannelRow(
                      icon: Icons.phone_android,
                      label: 'VF',
                      excess: vfExcess,
                      profit: vfProfit,
                      sharePercent: sharePercent,
                    ),
                  if (instaExcess > 0) ...[
                    if (vfExcess > 0) const SizedBox(height: 4),
                    _ChannelRow(
                      icon: Icons.account_balance,
                      label: 'Insta',
                      excess: instaExcess,
                      profit: instaProfit,
                      sharePercent: sharePercent,
                    ),
                  ],
                  if (!hasProfit)
                    Text(
                      'Below hurdle',
                      style: TextStyle(
                          color: AppTheme.textMutedColor(context),
                          fontSize: 11),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // — Total Profit —
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  hasProfit
                      ? '+${Formatters.formatCurrency(profit)}'
                      : '—',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: hasProfit
                        ? AppTheme.positiveColor(context)
                        : AppTheme.textMutedColor(context),
                  ),
                ),
                if (excessFlow > 0)
                  Text(
                    '${Formatters.formatNumber(excessFlow)} excess',
                    style: TextStyle(
                        fontSize: 9,
                        color: AppTheme.textMutedColor(context),
                        fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double excess;
  final double profit;
  final double sharePercent;

  const _ChannelRow({
    required this.icon,
    required this.label,
    required this.excess,
    required this.profit,
    required this.sharePercent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 11, color: AppTheme.accentSoft),
        const SizedBox(width: 4),
        Text(
          '$label: ${Formatters.formatNumber(excess)} excess',
          style: TextStyle(
              fontSize: 11,
              color: AppTheme.textMutedColor(context),
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 4),
        Text(
          '→ ${Formatters.formatCurrency(profit)}',
          style: TextStyle(
              fontSize: 11,
              color: AppTheme.accentSoft,
              fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _PayProfitDialog extends StatefulWidget {
  final Investor investor;
  final double maxAmount;
  const _PayProfitDialog({required this.investor, required this.maxAmount});
  @override
  State<_PayProfitDialog> createState() => _PayProfitDialogState();
}

class _PayProfitDialogState extends State<_PayProfitDialog> {
  final _formKey = GlobalKey<FormState>();
  double _amount = 0.0;
  String? _bankAccountId;
  String _notes = '';

  void _submit() async {
    if (!_formKey.currentState!.validate() || _bankAccountId == null) return;
    _formKey.currentState!.save();

    final dist = Provider.of<DistributionProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      await dist.payInvestorProfit(
        investorId: widget.investor.id,
        amount: _amount,
        bankAccountId: _bankAccountId!,
        notes: _notes.isEmpty ? 'Investor Profit Payment' : _notes,
        createdByUid: auth.currentUser!.uid,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('success'.tr()), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    final banks = dist.bankAccounts;
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E28),
      title: Text('pay_profit'.tr(),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Max: ${Formatters.formatCurrency(widget.maxAmount)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: widget.maxAmount.toStringAsFixed(2),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    labelText: 'Amount',
                    border: OutlineInputBorder(),
                    labelStyle: TextStyle(color: Colors.white54)),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final val = double.tryParse(v ?? '') ?? 0;
                  if (val <= 0 || val > widget.maxAmount) return 'invalid'.tr();
                  return null;
                },
                onSaved: (v) => _amount = double.parse(v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                    labelText: 'bank_account'.tr(),
                    border: const OutlineInputBorder(),
                    labelStyle: const TextStyle(color: Colors.white54)),
                dropdownColor: const Color(0xFF2A2A35),
                style: const TextStyle(color: Colors.white),
                items: banks
                    .map((b) =>
                        DropdownMenuItem(value: b.id, child: Text(b.bankName)))
                    .toList(),
                onChanged: (v) => setState(() => _bankAccountId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                    labelStyle: TextStyle(color: Colors.white54)),
                onSaved: (v) => _notes = v ?? '',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('cancel'.tr(),
              style: const TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC8A96E),
              foregroundColor: Colors.black),
          onPressed: _bankAccountId == null || dist.isInvestorLoading
              ? null
              : _submit,
          child: dist.isInvestorLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text('confirm'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }
}

class _WithdrawCapitalDialog extends StatefulWidget {
  final Investor investor;
  const _WithdrawCapitalDialog({required this.investor});
  @override
  State<_WithdrawCapitalDialog> createState() => _WithdrawCapitalDialogState();
}

class _WithdrawCapitalDialogState extends State<_WithdrawCapitalDialog> {
  final _formKey = GlobalKey<FormState>();
  double _amount = 0.0;
  String? _bankAccountId;
  String _notes = '';

  void _submit() async {
    if (!_formKey.currentState!.validate() || _bankAccountId == null) return;
    _formKey.currentState!.save();
    final dist = Provider.of<DistributionProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      await dist.withdrawInvestorCapital(
        investorId: widget.investor.id,
        amount: _amount,
        bankAccountId: _bankAccountId!,
        notes: _notes,
        createdByUid: auth.currentUser!.uid,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('success'.tr()), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    final banks = dist.bankAccounts;
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E28),
      title: Text('withdraw_capital'.tr(),
          style: const TextStyle(color: Colors.white)),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Max: ${Formatters.formatCurrency(widget.investor.investedAmount)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 12),
              TextFormField(
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    labelText: 'Amount', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final val = double.tryParse(v ?? '') ?? 0;
                  if (val <= 0 || val > widget.investor.investedAmount)
                    return 'invalid'.tr();
                  return null;
                },
                onSaved: (v) => _amount = double.parse(v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                    labelText: 'bank_account'.tr(),
                    border: const OutlineInputBorder()),
                dropdownColor: const Color(0xFF2A2A35),
                style: const TextStyle(color: Colors.white),
                items: banks
                    .map((b) =>
                        DropdownMenuItem(value: b.id, child: Text(b.bankName)))
                    .toList(),
                onChanged: (v) => setState(() => _bankAccountId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    labelText: 'Notes', border: OutlineInputBorder()),
                onSaved: (v) => _notes = v ?? 'Capital Withdrawal',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              Text('cancel'.tr(), style: const TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE63946)),
          onPressed: _bankAccountId == null || dist.isInvestorLoading
              ? null
              : _submit,
          child: dist.isInvestorLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text('confirm'.tr(),
                  style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
