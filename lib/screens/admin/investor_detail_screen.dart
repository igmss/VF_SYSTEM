import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../providers/distribution_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/investor.dart';
import '../../models/investor_profit_snapshot.dart';
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

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    final snaps = dist.validInvestorSnapshotsFor(investor.id);
    
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(investor.name, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textPrimaryColor(context), fontSize: 20, letterSpacing: -0.5)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: AppTheme.textPrimaryColor(context), size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, dist),
            const SizedBox(height: 32),
            Row(
              children: [
                Icon(Icons.history, color: AppTheme.textMutedColor(context), size: 16),
                const SizedBox(width: 8),
                Text(
                  'profit_history'.tr().toUpperCase(),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.textMutedColor(context), letterSpacing: 1.0),
                ),
                const SizedBox(width: 12),
                Expanded(child: Divider(color: AppTheme.lineColor(context).withValues(alpha: 0.5))),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: snaps.isEmpty
                  ? Center(child: Text('no_data'.tr(), style: const TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      itemCount: snaps.length,
                      itemBuilder: (ctx, idx) => _SnapshotCard(snapshot: snaps[idx]),
                    ),
            ),
            if (investor.status == 'active')
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 8),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.errorColor(context),
                    side: BorderSide(color: AppTheme.errorColor(context).withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: const Icon(Icons.outbound_outlined, size: 20),
                  label: Text('withdraw_capital'.tr(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                  onPressed: () => _withdrawCapital(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, DistributionProvider dist) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.heroGradient(context),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(36),
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
              Text('invested_amount'.tr(), style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
              Text(investor.investmentDate, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            Formatters.formatCurrency(investor.investedAmount),
            style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -0.5),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildMiniStat('profit_share'.tr(), '${investor.profitSharePercent}%'),
              const SizedBox(width: 32),
              _buildMiniStat('investor_profit_owed'.tr(), Formatters.formatCurrency(
                dist.validInvestorSnapshotsFor(investor.id)
                    .where((s) => !s.isPaid)
                    .fold<double>(0, (s, e) => s + e.investorProfit),
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  final InvestorProfitSnapshot snapshot;

  const _SnapshotCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.panelGradient(context),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.lineColor(context).withValues(alpha: 0.5)),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(snapshot.date, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppTheme.textPrimaryColor(context))),
                      const SizedBox(height: 2),
                      Text('Financial Snapshot', style: TextStyle(fontSize: 10, color: AppTheme.textMutedColor(context), fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                    ],
                  ),
                  _buildStatusPill(context),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.5),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _infoRow(context, 'Total Daily Flow', snapshot.totalDailyFlow),
                  _infoRow(context, 'Eligible Amount', snapshot.eligibleTotal),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ChannelBox(
                          label: 'Vodafone Cash',
                          flow: snapshot.vfShare,
                          profit: snapshot.vfProfit,
                          icon: Icons.phone_android,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ChannelBox(
                          label: 'InstaPay',
                          flow: snapshot.instaShare,
                          profit: snapshot.instaProfit,
                          icon: Icons.account_balance,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24, thickness: 0.5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('NET PROFIT', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                      Text(
                        Formatters.formatCurrency(snapshot.investorProfit),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.positiveColor(context)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPill(BuildContext context) {
    final paid = snapshot.isPaid;
    final color = paid ? AppTheme.positiveColor(context) : AppTheme.warningColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        (paid ? 'paid' : 'unpaid').tr().toUpperCase(),
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, double amount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12, fontWeight: FontWeight.w500)),
          Text(Formatters.formatCurrency(amount), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ChannelBox extends StatelessWidget {
  final String label;
  final double flow;
  final double profit;
  final IconData icon;

  const _ChannelBox({required this.label, required this.flow, required this.profit, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lineColor(context).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: AppTheme.accentSoft),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 10, color: AppTheme.textMutedColor(context), fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            Formatters.formatNumber(flow),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.textPrimaryColor(context)),
          ),
          Text(
            '+ ${Formatters.formatNumber(profit)} Profit',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.positiveColor(context)),
          ),
        ],
      ),
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
          SnackBar(content: Text('success'.tr()), backgroundColor: Colors.green),
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
      title: Text('withdraw_capital'.tr(), style: const TextStyle(color: Colors.white)),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Max: ${Formatters.formatCurrency(widget.investor.investedAmount)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextFormField(
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: 'Amount', border: const OutlineInputBorder()),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final val = double.tryParse(v ?? '') ?? 0;
                  if (val <= 0 || val > widget.investor.investedAmount) return 'invalid'.tr();
                  return null;
                },
                onSaved: (v) => _amount = double.parse(v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: 'bank_account'.tr(), border: const OutlineInputBorder()),
                dropdownColor: const Color(0xFF2A2A35),
                style: const TextStyle(color: Colors.white),
                items: banks.map((b) => DropdownMenuItem(value: b.id, child: Text(b.bankName))).toList(),
                onChanged: (v) => setState(() => _bankAccountId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: 'Notes', border: const OutlineInputBorder()),
                onSaved: (v) => _notes = v ?? 'Capital Withdrawal',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('cancel'.tr(), style: const TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE63946)),
          onPressed: _bankAccountId == null || dist.isInvestorLoading ? null : _submit,
          child: dist.isInvestorLoading 
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('confirm'.tr(), style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
