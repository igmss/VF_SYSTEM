import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/app_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../models/financial_transaction.dart';

class UsdExchangeScreen extends StatelessWidget {
  const UsdExchangeScreen({Key? key}) : super(key: key);

  static const _bg    = Color(0xFF0F0F1A);
  static const _card  = Color(0xFF16162A);
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
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF16162A),
        title: const Text('USD Exchange', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),

      ),
      body: dist.isLoading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : Column(
              children: [
                _buildHeader(balance, totalEgp),
                const SizedBox(height: 4),
                Expanded(
                  child: history.isEmpty
                      ? _buildEmpty()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: history.length + 1,
                          itemBuilder: (ctx, i) {
                            if (i == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10, top: 4),
                                child: Text(
                                  'recent_activity'.tr(),
                                  style: const TextStyle(
                                    color: Colors.white,
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

  Widget _buildHeader(double balance, double totalEgp) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
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
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.currency_exchange, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'USD Exchange',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _fmt(balance),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'USDT',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '≈ ${_fmt(totalEgp)} EGP',
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.currency_exchange, size: 56, color: Colors.white12),
          SizedBox(height: 12),
          Text(
            'No transactions yet',
            style: TextStyle(color: Colors.white38, fontSize: 15),
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
        backgroundColor: const Color(0xFF16162A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Set USDT Balance',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Balance (USDT)',
            labelStyle: const TextStyle(color: Colors.white54),
            suffixText: 'USDT',
            suffixStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
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
            child: Text('cancel'.tr(), style: const TextStyle(color: Colors.white38)),
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
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    final color = isBuy ? const Color(0xFF4ADE80) : const Color(0xFFF59E0B);
    final icon  = isBuy ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;
    final label = isBuy ? 'Buy USDT' : 'Sell USDT';
    final sign  = isBuy ? '+' : '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.18)),
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
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                if (tx.fromLabel != null || tx.toLabel != null)
                  Text(
                    isBuy
                        ? '${tx.fromLabel ?? ''} → ${tx.toLabel ?? 'USD Exchange'}'
                        : '${tx.fromLabel ?? 'USD Exchange'} → ${tx.toLabel ?? ''}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
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
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              Text(
                DateFormat('dd/MM HH:mm').format(tx.timestamp),
                style: const TextStyle(color: Colors.white24, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
