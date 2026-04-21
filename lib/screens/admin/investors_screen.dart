import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';

import '../../providers/distribution_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/investor.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'investor_detail_screen.dart';

class InvestorsScreen extends StatefulWidget {
  const InvestorsScreen({super.key});

  @override
  State<InvestorsScreen> createState() => _InvestorsScreenState();
}

class _InvestorsScreenState extends State<InvestorsScreen> {
  void _openAddInvestor(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _AddInvestorSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    final isAr = context.locale.languageCode == 'ar';

    if (dist.isInvestorLoading || dist.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final activeInvestors = dist.investors.where((i) => i.status == 'active').toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildSummary(context, dist, activeInvestors),
          const SizedBox(height: 24),
          Expanded(
            child: activeInvestors.isEmpty
                ? Center(
                    child: Text(
                      'no_data'.tr(),
                      style: const TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    itemCount: activeInvestors.length,
                    itemBuilder: (ctx, idx) => _InvestorCard(
                      investor: activeInvestors[idx],
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFC8A96E),
        icon: const Icon(Icons.add, color: Colors.black),
        label: Text(
          'add_investor'.tr(),
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        onPressed: () => _openAddInvestor(context),
      ),
    );
  }

  Widget _buildSummary(BuildContext context, DistributionProvider dist, List<Investor> activeInvestors) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.heroGradient(context),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accent.withValues(alpha: 0.3),
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
              Text('total_investor_capital'.tr(), style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 22),
                onPressed: () => dist.loadAll(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            Formatters.formatCurrency(dist.totalInvestorCapital),
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.5),
          ),
          const Divider(color: Colors.white24, height: 32),
          Row(
            children: [
              _MiniSummaryItem(
                label: 'investor_profit_owed'.tr(),
                amount: dist.totalInvestorPayable,
                color: Colors.white,
                isNegative: true,
              ),
              const SizedBox(width: 24),
              _MiniSummaryItem(
                label: 'active_investors'.tr(),
                amount: activeInvestors.length.toDouble(),
                color: Colors.white70,
                isCurrency: false,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _FlowStat(label: 'VF FLOW', amount: dist.totalInvestorVfFlow, icon: Icons.phone_android),
              const SizedBox(width: 16),
              _FlowStat(label: 'INSTA FLOW', amount: dist.totalInvestorInstaFlow, icon: Icons.account_balance),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlowStat extends StatelessWidget {
  final String label;
  final double amount;
  final IconData icon;

  const _FlowStat({required this.label, required this.amount, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: Colors.white54),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(Formatters.formatNumber(amount), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _MiniSummaryItem extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final bool isCurrency;
  final bool isNegative;

  const _MiniSummaryItem({
    required this.label,
    required this.amount,
    required this.color,
    this.isCurrency = true,
    this.isNegative = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          isCurrency ? Formatters.formatCurrency(amount) : amount.toInt().toString(),
          style: TextStyle(
            color: isNegative ? const Color(0xFFFFBABA) : color,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _InvestorCard extends StatelessWidget {
  final Investor investor;

  const _InvestorCard({required this.investor});

  void _refreshPerformance(BuildContext context) {
    // Just re-triggers the FutureBuilder in _InvestorCard
    (context as Element).markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) {
    final dist = context.read<DistributionProvider>();
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => InvestorDetailScreen(investor: investor)),
      ),
      child: FutureBuilder<Map<String, dynamic>>(
        future: dist.getInvestorPerformance(investorId: investor.id),
        builder: (context, snapshot) {
          final perf = snapshot.data;
          final earned = perf?['totalEarned']?.toDouble() ?? 0.0;
          final payable = perf?['payableBalance']?.toDouble() ?? 0.0;
          final totalVf = perf?['totalVfFlow']?.toDouble() ?? 0.0;
          final totalInsta = perf?['totalInstaFlow']?.toDouble() ?? 0.0;

          return Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.panelGradient(context),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppTheme.lineColor(context).withValues(alpha: 0.5)),
              boxShadow: AppTheme.softShadow(context),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.person_pin, color: AppTheme.accent, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(investor.name, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                              Text(investor.phone.isEmpty ? 'investor'.tr() : investor.phone, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        _buildStatusBadge(context),
                      ],
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _investStat(context, 'invested_amount'.tr(), investor.investedAmount, isGold: true),
                        _investStat(context, 'profit_share'.tr(), investor.profitSharePercent, isPercent: true),
                      ],
                    ),
                  ),

                  Container(
                    margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.lineColor(context).withValues(alpha: 0.3)),
                    ),
                    child: snapshot.connectionState == ConnectionState.waiting
                      ? const Center(child: LinearProgressIndicator())
                      : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('CUMULATIVE PERFORMANCE', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                              const Icon(Icons.show_chart, color: AppTheme.accent, size: 14),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _perfRow(context, 'Lifetime VF Flow', totalVf),
                          _perfRow(context, 'Lifetime Insta Flow', totalInsta),
                          const Divider(height: 20, thickness: 0.5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('total_earned'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 13, fontWeight: FontWeight.w700)),
                              Text(Formatters.formatCurrency(earned), style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('payable_balance'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 14, fontWeight: FontWeight.w900)),
                              Text(
                                Formatters.formatCurrency(payable),
                                style: const TextStyle(color: AppTheme.accent, fontSize: 18, fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                        ],
                      ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.refresh, size: 16),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: () => _refreshPerformance(context),
                            label: Text('refresh'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              backgroundColor: AppTheme.accent,
                            ),
                            onPressed: () => _payProfit(context, payable),
                            child: Text('pay_profit'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _perfRow(BuildContext context, String label, double amount, {bool isNegative = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12, fontWeight: FontWeight.w500)),
          Text(
            Formatters.formatCurrency(amount),
            style: TextStyle(
              color: isNegative ? AppTheme.errorColor(context) : AppTheme.textPrimaryColor(context),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  void _payProfit(BuildContext context, double maxAmount) {
    if (maxAmount <= 0) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No profit to pay')));
       return;
    }
    showDialog(
      context: context,
      builder: (ctx) => _PayProfitDialog(investor: investor, maxAmount: maxAmount),
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    final status = investor.status;
    final color = status == 'active' ? AppTheme.positiveColor(context) : AppTheme.errorColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _investStat(BuildContext context, String label, double val, {bool isPercent = false, bool isGold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          isPercent ? '${val.toStringAsFixed(1)}%' : Formatters.formatCurrency(val),
          style: TextStyle(
            color: isGold ? const Color(0xFFC8A96E) : AppTheme.textPrimaryColor(context),
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _KeyValueRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: valueColor ?? Colors.white)),
        ],
      ),
    );
  }
}

class _AddInvestorSheet extends StatefulWidget {
  const _AddInvestorSheet();

  @override
  State<_AddInvestorSheet> createState() => _AddInvestorSheetState();
}

class _AddInvestorSheetState extends State<_AddInvestorSheet> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _phone = '';
  double _investedAmount = 0.0;
  double _initialBusinessCapital = 0.0;
  double _profitSharePercent = 0.0;
  String _investmentDateStr = '';
  int _periodDays = 30;
  String? _bankAccountId;
  String _notes = '';

  double _previewAvgBuy = 0.0;
  double _previewAvgSell = 0.0;
  double _previewVfProfit = 0.0;

  @override
  void initState() {
    super.initState();
    _investmentDateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  void _updatePreview() {
    if (_investmentDateStr.isEmpty) return;
    try {
      final endTs = DateTime.parse(_investmentDateStr).millisecondsSinceEpoch;
      final startTs = endTs - (30 * 24 * 60 * 60 * 1000);
      
      final prov = Provider.of<DistributionProvider>(context, listen: false);
      double sumBuy = 0;
      int countBuy = 0;
      double sumSell = 0;
      int countSell = 0;
      
      for (var tx in prov.ledger) {
        if (tx.timestamp.millisecondsSinceEpoch >= startTs && tx.timestamp.millisecondsSinceEpoch <= endTs) {
          if (tx.type.name == 'BUY_USDT') {
            sumBuy += tx.usdtPrice ?? 0;
            countBuy++;
          } else if (tx.type.name == 'SELL_USDT') {
            sumSell += tx.usdtPrice ?? 0;
            countSell++;
          }
        }
      }
      
      double avgBuy = countBuy > 0 ? (sumBuy/countBuy) : 0;
      double avgSell = countSell > 0 ? (sumSell/countSell) : 0;
      double profitPer1k = 0;
      if (avgBuy > 0 && avgSell > avgBuy) {
        profitPer1k = ((1000 / avgBuy) * avgSell - 1000) - 1;
      }
      
      setState(() {
        _previewAvgBuy = avgBuy;
        _previewAvgSell = avgSell;
        _previewVfProfit = profitPer1k;
      });
    } catch (_) {}
  }

  void _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) {
        return Theme(
          data: AppTheme.isDark(ctx) ? AppTheme.dark() : AppTheme.light(),
          child: child!,
        );
      },
    );
    if (d != null) {
      setState(() {
        _investmentDateStr = DateFormat('yyyy-MM-dd').format(d);
      });
      _updatePreview();
    }
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_bankAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('select_bank'.tr()), backgroundColor: AppTheme.errorColor(context)),
      );
      return;
    }
    _formKey.currentState!.save();

    final dist = Provider.of<DistributionProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    try {
      await dist.recordInvestorCapital(
        name: _name,
        phone: _phone,
        investedAmount: _investedAmount,
        initialBusinessCapital: _initialBusinessCapital,
        profitSharePercent: _profitSharePercent,
        investmentDate: _investmentDateStr,
        periodDays: _periodDays,
        bankAccountId: _bankAccountId!,
        notes: _notes,
        createdByUid: auth.currentUser!.uid,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('success'.tr()), backgroundColor: AppTheme.positiveColor(context)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.errorColor(context)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    final banks = dist.bankAccounts;
    
    double priorCapital = dist.investors.where((i) => i.status == 'active').fold(0.0, (s, i) => s + i.investedAmount);
    double cumulative = _initialBusinessCapital + priorCapital;
    double thresholdPreview = _initialBusinessCapital > 0 ? cumulative / 2 : 0;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(color: AppTheme.lineColor(context).withValues(alpha: 0.5)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('add_investor'.tr(), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.textPrimaryColor(context), letterSpacing: -0.5)),
              const SizedBox(height: 20),
              TextFormField(
                style: TextStyle(color: AppTheme.textPrimaryColor(context)),
                decoration: InputDecoration(labelText: 'name'.tr(), prefixIcon: const Icon(Icons.person_outline)),
                validator: (v) => v!.isEmpty ? 'required'.tr() : null,
                onSaved: (v) => _name = v!,
              ),
              const SizedBox(height: 12),
              TextFormField(
                style: TextStyle(color: AppTheme.textPrimaryColor(context)),
                decoration: InputDecoration(labelText: 'phone'.tr(), prefixIcon: const Icon(Icons.phone_outlined)),
                keyboardType: TextInputType.phone,
                onSaved: (v) => _phone = v ?? '',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                   Expanded(
                     child: TextFormField(
                      style: TextStyle(color: AppTheme.textPrimaryColor(context)),
                      decoration: InputDecoration(labelText: 'invested_amount'.tr(), prefixIcon: const Icon(Icons.payments_outlined)),
                      keyboardType: TextInputType.number,
                      validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'invalid'.tr() : null,
                      onSaved: (v) => _investedAmount = double.parse(v!),
                    ),
                   ),
                   const SizedBox(width: 12),
                   Expanded(
                     child: TextFormField(
                      style: TextStyle(color: AppTheme.textPrimaryColor(context)),
                      decoration: InputDecoration(labelText: 'share_percent'.tr(), prefixIcon: const Icon(Icons.percent)),
                      keyboardType: TextInputType.number,
                      validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'invalid'.tr() : null,
                      onSaved: (v) => _profitSharePercent = double.parse(v!),
                    ),
                   ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                style: TextStyle(color: AppTheme.textPrimaryColor(context)),
                decoration: InputDecoration(labelText: 'initial_business_capital'.tr(), prefixIcon: const Icon(Icons.account_balance_outlined)),
                keyboardType: TextInputType.number,
                validator: (v) => (double.tryParse(v ?? '') ?? -1) < 0 ? 'invalid'.tr() : null,
                onChanged: (v) => setState(() => _initialBusinessCapital = double.tryParse(v) ?? 0),
                onSaved: (v) => _initialBusinessCapital = double.parse(v!),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.lineColor(context)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, color: AppTheme.textMutedColor(context), size: 18),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('investment_date'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 10, fontWeight: FontWeight.bold)),
                          Text(_investmentDateStr, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: 'bank_account'.tr(), prefixIcon: const Icon(Icons.account_balance)),
                dropdownColor: AppTheme.surfaceColor(context),
                style: TextStyle(color: AppTheme.textPrimaryColor(context)),
                items: banks.map((b) => DropdownMenuItem(value: b.id, child: Text(b.bankName, style: const TextStyle(fontSize: 14)))).toList(),
                onChanged: (v) => setState(() => _bankAccountId = v),
              ),
              const SizedBox(height: 20),
              
              if (_investmentDateStr.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.lineColor(context).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PROJECTION PREVIEW', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                      const SizedBox(height: 12),
                      _ProjRow(label: 'Avg Buy/Sell', value: '${_previewAvgBuy.toStringAsFixed(2)} / ${_previewAvgSell.toStringAsFixed(2)}'),
                      _ProjRow(label: 'Profit/1000', value: Formatters.formatCurrency(_previewVfProfit), color: AppTheme.positiveColor(context)),
                      const Divider(height: 20),
                      _ProjRow(label: 'Threshold', value: Formatters.formatCurrency(thresholdPreview), color: AppTheme.accent),
                    ],
                  ),
                ),
                
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: dist.isInvestorLoading ? null : _submit,
                child: dist.isInvestorLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('confirm'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _ProjRow({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12, fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(color: color ?? AppTheme.textPrimaryColor(context), fontSize: 12, fontWeight: FontWeight.w900)),
        ],
      ),
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
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _bankAccountId;

  @override
  void initState() {
    super.initState();
    _amountCtrl.text = widget.maxAmount.toStringAsFixed(2);
  }

  void _submit() async {
    final amount = double.tryParse(_amountCtrl.text) ?? 0.0;
    if (amount <= 0 || _bankAccountId == null) return;
    
    final dist = Provider.of<DistributionProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    try {
      await dist.payInvestorProfit(
        investorId: widget.investor.id,
        amount: amount,
        bankAccountId: _bankAccountId!,
        createdByUid: auth.currentUser!.uid,
        notes: _notesCtrl.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('success'.tr()), 
            backgroundColor: AppTheme.positiveColor(context),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()), 
            backgroundColor: AppTheme.errorColor(context),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    final banks = dist.bankAccounts;

    return AlertDialog(
      backgroundColor: AppTheme.surfaceColor(context),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      title: Column(
        children: [
          Text('pay_profit'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 4),
          Text(widget.investor.name, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'amount'.tr(),
                suffixText: 'EGP',
                helperText: 'Max: ${Formatters.formatCurrency(widget.maxAmount)}',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'Source Bank',
                prefixIcon: const Icon(Icons.account_balance, size: 20),
              ),
              dropdownColor: AppTheme.surfaceColor(context),
              style: TextStyle(color: AppTheme.textPrimaryColor(context)),
              items: banks.map((b) => DropdownMenuItem(value: b.id, child: Text(b.bankName, style: const TextStyle(fontSize: 14)))).toList(),
              onChanged: (v) => setState(() => _bankAccountId = v),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesCtrl,
              style: TextStyle(color: AppTheme.textPrimaryColor(context)),
              decoration: InputDecoration(
                labelText: 'notes'.tr(),
                prefixIcon: const Icon(Icons.notes),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('cancel'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context), fontWeight: FontWeight.bold)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _bankAccountId == null || dist.isInvestorLoading ? null : _submit,
          child: dist.isInvestorLoading 
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text('confirm'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }
}
