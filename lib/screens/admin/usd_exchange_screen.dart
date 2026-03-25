import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/app_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../models/financial_transaction.dart';

class UsdExchangeScreen extends StatelessWidget {
  const UsdExchangeScreen({Key? key}) : super(key: key);



  static const _gold  = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    final auth = context.watch<AuthProvider>();
    final balance = dist.usdtBalance;
    final lastPrice = dist.usdtLastPrice;
    final totalEgp = dist.totalUsdExchangeBalance;

    // Filter ledger: only BUY_USDT and SELL_USDT entries
    final history = dist.ledger
        .where((t) => t.type == FlowType.BUY_USDT || t.type == FlowType.SELL_USDT)
        .take(30)
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor(context),
        elevation: 0,
        title: Text('USD Exchange', style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: AppTheme.textPrimaryColor(context)),
      ),
      body: dist.isLoading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : Column(
              children: [
                _buildHeader(context, balance, totalEgp),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: AppTheme.isDark(context)
                            ? AppTheme.panelGradient(context)
                            : const [Color(0xFFFFFBF3), Color(0xFFF4E8CF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppTheme.lineColor(context)),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: _MiniStat(label: 'Holdings', value: '${_fmt(balance)} USDT')),
                        Expanded(child: _MiniStat(label: 'EGP Value', value: '${_fmt(totalEgp)} EGP')),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: history.isEmpty
                      ? _buildEmpty(context)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                          itemCount: history.length + 1,
                          itemBuilder: (ctx, i) {
                            if (i == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10, top: 4),
                                child: Text(
                                  'recent_activity'.tr(),
                                  style: TextStyle(
                                    color: AppTheme.textPrimaryColor(context),
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            }
                            final tx = history[i - 1];
                            return _TxCard(tx: tx);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader(BuildContext context, double balance, double totalEgp) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.currency_exchange, color: AppTheme.textPrimaryColor(context), size: 28),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'USD Exchange',
                style: TextStyle(color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.7), fontSize: 13),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _fmt(balance),
                    style: TextStyle(
                      color: AppTheme.textPrimaryColor(context),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'USDT',
                    style: TextStyle(
                      color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.7),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '≈ ${_fmt(totalEgp)} EGP',
                style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.currency_exchange, size: 56, color: AppTheme.lineColor(context)),
          const SizedBox(height: 12),
          Text(
            'No transactions yet',
            style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 15),
          ),
        ],
      ),
    );
  }

  void _showSetBalanceDialog(BuildContext context, DistributionProvider dist, double current) {
    final ctrl = TextEditingController(text: current.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Set USDT Balance',
            style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: AppTheme.textPrimaryColor(context)),
          decoration: InputDecoration(
            labelText: 'Balance (USDT)',
            labelStyle: TextStyle(color: AppTheme.textMutedColor(context)),
            suffixText: 'USDT',
            suffixStyle: TextStyle(color: AppTheme.textMutedColor(context)),
            filled: true,
            fillColor: AppTheme.textPrimaryColor(context).withValues(alpha: 0.06),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _gold),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final val = double.tryParse(ctrl.text) ?? 0;
              dist.setUsdExchangeBalance(val);
              Navigator.pop(context);
            },
            child: Text('Save', style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) => NumberFormat('#,##0.00', 'en_US').format(v);
}

// ─── Transaction Card ────────────────────────────────────────────────────────

class _TxCard extends StatelessWidget {
  final FinancialTransaction tx;
  const _TxCard({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isBuy = tx.type == FlowType.BUY_USDT;
    final color = isBuy ? AppTheme.positiveColor(context) : AppTheme.warningColor(context);
    final icon  = isBuy ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;
    final label = isBuy ? 'Buy USDT' : 'Sell USDT';
    final sign  = isBuy ? '+' : '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.isDark(context)
              ? AppTheme.panelGradient(context)
              : const [Color(0xFFFFFEFB), Color(0xFFF6EFE2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.18)),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w600, fontSize: 14)),
                if (tx.fromLabel != null || tx.toLabel != null)
                  Text(
                    isBuy
                        ? '${tx.fromLabel ?? ''} → ${tx.toLabel ?? 'USD Exchange'}'
                        : '${tx.fromLabel ?? 'USD Exchange'} → ${tx.toLabel ?? ''}',
                    style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$sign${NumberFormat('#,##0.00', 'en_US').format(tx.amount)} EGP',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (tx.usdtQuantity != null && tx.usdtQuantity! > 0)
                Text(
                  '${tx.usdtQuantity!.toStringAsFixed(2)} USDT',
                  style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 10),
                ),
              Text(
                DateFormat('dd/MM HH:mm').format(tx.timestamp),
                style: TextStyle(color: AppTheme.textMutedColor(context).withValues(alpha: 0.6), fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 14, fontWeight: FontWeight.w800)),
      ],
    );
  }
}
