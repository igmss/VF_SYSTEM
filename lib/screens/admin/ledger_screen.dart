import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/auth_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../models/financial_transaction.dart';

class LedgerScreen extends StatelessWidget {
  const LedgerScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16162A),
        title: Text('financial_ledger'.tr(),
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: dist.ledger.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.receipt_long_outlined,
                      size: 60, color: Colors.white24),
                  const SizedBox(height: 12),
                  Text('no_data'.tr(),
                      style: const TextStyle(color: Colors.white38)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: dist.ledger.length,
              itemBuilder: (ctx, i) => _LedgerTile(tx: dist.ledger[i]),
            ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  final FinancialTransaction tx;

  const _LedgerTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final color   = _color(tx.type);
    final icon    = _icon(tx.type);
    final fmt     = NumberFormat('#,##0.00');
    final dateFmt = DateFormat('dd MMM, HH:mm');

    // Detect deleted labels
    final fromDeleted  = tx.fromLabel?.contains('[Deleted Account]') == true;
    final toDeleted    = tx.toLabel?.contains('[Deleted Account]') == true;
    final anyDeleted   = fromDeleted || toDeleted;

    String label = tx.type.label.tr();
    if (tx.type == FlowType.FUND_BANK || tx.type == FlowType.DEPOSIT_TO_BANK) {
      if (tx.fromLabel != null && tx.fromLabel!.isNotEmpty) {
        label = '${tx.type.label.tr()} from ${tx.fromLabel} (${tx.toLabel})';
      } else {
        label = '${tx.type.label.tr()} (${tx.toLabel})';
      }
    } else if (tx.type == FlowType.BUY_USDT) {
      label = 'Buy USDT (${tx.fromLabel})';
    } else if (tx.type == FlowType.BANK_DEDUCTION) {
      label = 'Bank Deduction (${tx.fromLabel})';
    } else if (tx.type == FlowType.CREDIT_RETURN) {
      label = 'Credit Return (${tx.fromLabel})';
    } else if (tx.type == FlowType.CREDIT_RETURN_FEE) {
      label = 'Credit Return Fee (${tx.fromLabel})';
    }

    // Clean label for display (strip the suffix — we'll show a badge instead)
    String cleanLabel(String? raw) =>
        (raw ?? '').replaceAll(' [Deleted Account]', '').trim();

    return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF16162A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: anyDeleted
                ? Colors.red.withOpacity(0.25)
                : color.withOpacity(0.15),
          ),
        ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Icon Bubble ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),

          // ── Labels + Date ──────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type label
                Text(
                  label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),

                // From → To row
                if (tx.type != FlowType.FUND_BANK &&
                    tx.type != FlowType.DEPOSIT_TO_BANK &&
                    tx.type != FlowType.BUY_USDT &&
                    tx.type != FlowType.BANK_DEDUCTION &&
                    tx.type != FlowType.CREDIT_RETURN &&
                    tx.type != FlowType.CREDIT_RETURN_FEE) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (tx.fromLabel != null)
                        _labelChip(
                          '← ${cleanLabel(tx.fromLabel)}',
                          fromDeleted,
                        ),
                      if (tx.toLabel != null)
                        _labelChip(
                          '→ ${cleanLabel(tx.toLabel)}',
                          toDeleted,
                        ),
                    ],
                  ),
                ],

                // Payment method
                if (tx.paymentMethod != null) ...[
                  const SizedBox(height: 2),
                  Text(tx.paymentMethod!,
                      style:
                          const TextStyle(color: Colors.white24, fontSize: 10)),
                ],

                // Notes
                if (tx.notes != null && tx.notes!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tx.notes!,
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontStyle: FontStyle.italic),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // Date
                const SizedBox(height: 3),
                Text(
                  dateFmt.format(tx.timestamp),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),

          // ── Amount ────────────────────────────────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${fmt.format(tx.amount)} EGP',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              if (tx.usdtQuantity != null)
                Text(
                  '${tx.usdtQuantity!.toStringAsFixed(2)} USDT',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              const SizedBox(height: 6),
              _buildAdminActions(context),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdminActions(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!(auth.currentUser?.isAdmin ?? false)) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tx.type == FlowType.COLLECT_CASH || 
            tx.type == FlowType.DEPOSIT_TO_BANK ||
            tx.type == FlowType.CREDIT_RETURN)
          _buildCorrectButton(context),
      ],
    );
  }

  Widget _buildCorrectButton(BuildContext context) {
    return InkWell(
      onTap: () => _showCorrectionDialog(context),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.edit_note, color: Colors.orangeAccent, size: 14),
            const SizedBox(width: 4),
            Text(
              context.locale.languageCode == 'ar' ? 'تعديل' : 'Correct',
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  void _showCorrectionDialog(BuildContext context) {
    debugPrint('Opening Correction Dialog for tx: ${tx.id}');
    final ctrl = TextEditingController(text: tx.amount.toStringAsFixed(0));
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16162A),
        title: Text('Correct Transaction', style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Original Amount: ${tx.amount.toStringAsFixed(0)} EGP',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Correct Amount',
                labelStyle: const TextStyle(color: Colors.white54),
                suffixText: 'EGP',
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Reason',
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('cancel'.tr(), style: const TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newAmount = double.tryParse(ctrl.text) ?? 0;
              if (newAmount == tx.amount) {
                Navigator.pop(ctx);
                return;
              }
              final dist = context.read<DistributionProvider>();
              final auth = context.read<AuthProvider>();
              
              try {
                await dist.correctTransaction(
                  originalTx: tx,
                  correctAmount: newAmount,
                  adminUid: auth.currentUser?.uid ?? '',
                  reason: reasonCtrl.text.isEmpty ? null : reasonCtrl.text,
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Correction applied successfully')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
            child: const Text('Apply Fix', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Renders a small label pill; red + strikethrough-style if deleted.
  Widget _labelChip(String text, bool deleted) {
    if (!deleted) {
      return Text(
        text,
        style: const TextStyle(color: Colors.white54, fontSize: 11),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.block_rounded, color: Colors.redAccent, size: 10),
          const SizedBox(width: 4),
          Text(
            '$text  •  Deleted Account',
            style: const TextStyle(
              color: Colors.redAccent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _color(FlowType t) {
    switch (t) {
      case FlowType.FUND_BANK:           return const Color(0xFF4CC9F0);
      case FlowType.BUY_USDT:            return const Color(0xFFFBBF24);
      case FlowType.SELL_USDT:           return const Color(0xFF4ADE80);
      case FlowType.DISTRIBUTE_VFCASH:   return const Color(0xFFE63946);
      case FlowType.COLLECT_CASH:        return const Color(0xFFA78BFA);
      case FlowType.DEPOSIT_TO_BANK:     return const Color(0xFF4CC9F0);
      case FlowType.EXPENSE_VFCASH_FEE:  return const Color(0xFFFF9800);
      case FlowType.ADMIN_ADJUSTMENT:    return Colors.orangeAccent;
      case FlowType.CREDIT_RETURN:       return const Color(0xFF4ADE80);
      case FlowType.CREDIT_RETURN_FEE:   return const Color(0xFFFBBF24);
      case FlowType.BANK_DEDUCTION:      return const Color(0xFFE63946);
    }
  }

  IconData _icon(FlowType t) {
    switch (t) {
      case FlowType.FUND_BANK:           return Icons.add_card;
      case FlowType.BUY_USDT:            return Icons.arrow_upward;
      case FlowType.SELL_USDT:           return Icons.arrow_downward;
      case FlowType.DISTRIBUTE_VFCASH:   return Icons.phone_android;
      case FlowType.COLLECT_CASH:        return Icons.delivery_dining;
      case FlowType.DEPOSIT_TO_BANK:     return Icons.account_balance;
      case FlowType.EXPENSE_VFCASH_FEE:  return Icons.money_off;
      case FlowType.ADMIN_ADJUSTMENT:    return Icons.admin_panel_settings;
      case FlowType.CREDIT_RETURN:       return Icons.keyboard_return;
      case FlowType.CREDIT_RETURN_FEE:   return Icons.add_chart;
      case FlowType.BANK_DEDUCTION:      return Icons.remove_circle_outline;
    }
  }
}
