import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
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

    final auth = context.watch<AuthProvider>();
    final isEmbedded = auth.isAdmin || auth.isFinance;

    final bodyContent = dist.ledger.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 60,
                      color: AppTheme.textMutedColor(context)
                          .withValues(alpha: 0.6)),
                  const SizedBox(height: 12),
                  Text('no_data'.tr(),
                      style:
                          TextStyle(color: AppTheme.textMutedColor(context))),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: AppTheme.isDark(context)
                            ? AppTheme.panelGradient(context)
                            : const [Color(0xFFFFFBF4), Color(0xFFF2E5D2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.lineColor(context)),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: _LedgerStat(label: 'Entries', value: dist.ledger.length.toString())),
                        Expanded(child: _LedgerStat(label: 'Latest', value: DateFormat('dd MMM').format(dist.ledger.first.timestamp))),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                    itemCount: dist.ledger.length,
                    itemBuilder: (ctx, i) => _LedgerTile(tx: dist.ledger[i]),
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
          backgroundColor: AppTheme.surfaceColor(context),
          elevation: 0,
          title: Text('financial_ledger'.tr(),
              style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w800)),
          iconTheme: IconThemeData(color: AppTheme.textPrimaryColor(context)),
        ),
        body: bodyContent,
      );
    }
  }
}

class _LedgerTile extends StatelessWidget {
  final FinancialTransaction tx;

  const _LedgerTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final color = _color(context, tx.type);
    final icon = _icon(tx.type);
    final fmt = NumberFormat('#,##0.00');
    final dateFmt = DateFormat('dd MMM, HH:mm');

    // Detect deleted labels
    final fromDeleted = tx.fromLabel?.contains('[Deleted Account]') == true;
    final toDeleted = tx.toLabel?.contains('[Deleted Account]') == true;
    final anyDeleted = fromDeleted || toDeleted;

    String label = tx.type.label.tr();
    if (tx.type == FlowType.FUND_BANK || tx.type == FlowType.DEPOSIT_TO_BANK) {
      if (tx.fromLabel != null && tx.fromLabel!.isNotEmpty) {
        label = '${tx.type.label.tr()} from ${tx.fromLabel} (${tx.toLabel})';
      } else {
        label = '${tx.type.label.tr()} (${tx.toLabel})';
      }
    } else if (tx.type == FlowType.DEPOSIT_TO_VFCASH) {
      label = 'Deposit to VF (${tx.toLabel})';
    } else if (tx.type == FlowType.BUY_USDT) {
      label = 'Buy USDT (${tx.fromLabel})';
    } else if (tx.type == FlowType.BANK_DEDUCTION) {
      label = 'Bank Deduction (${tx.fromLabel})';
    } else if (tx.type == FlowType.CREDIT_RETURN) {
      label = 'Credit Return (${tx.fromLabel})';
    } else if (tx.type == FlowType.CREDIT_RETURN_FEE) {
      label = 'Credit Return Fee (${tx.fromLabel})';
    } else if (tx.type == FlowType.VFCASH_RETAIL_PROFIT) {
      label = 'VF Retail Profit (${tx.toLabel})';
    } else if (tx.type == FlowType.INTERNAL_VF_TRANSFER) {
      label = 'Internal Transfer (${tx.fromLabel} → ${tx.toLabel})';
    } else if (tx.type == FlowType.INTERNAL_VF_TRANSFER_FEE) {
      label = 'Internal Transfer Fee (${tx.fromLabel})';
    } else if (tx.type == FlowType.DISTRIBUTE_INSTAPAY) {
      label = 'InstaPay Distribution (${tx.toLabel})';
    } else if (tx.type == FlowType.INSTAPAY_DIST_PROFIT) {
      label = 'InstaPay Profit (${tx.toLabel})';
    } else if (tx.type == FlowType.COLLECT_INSTAPAY_CASH) {
      label = 'InstaPay Collection (${tx.fromLabel})';
    }

    // Clean label for display (strip the suffix — we'll show a badge instead)
    String cleanLabel(String? raw) =>
        (raw ?? '').replaceAll(' [Deleted Account]', '').trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.isDark(context)
              ? AppTheme.panelGradient(context)
              : const [Color(0xFFFFFEFB), Color(0xFFF7F0E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: anyDeleted
              ? Colors.red.withValues(alpha: 0.25)
              : color.withValues(alpha: 0.15),
        ),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Icon Bubble ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
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
                  style: TextStyle(
                      color: AppTheme.textPrimaryColor(context),
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),

                // From → To row
                if (tx.type != FlowType.FUND_BANK &&
                    tx.type != FlowType.DEPOSIT_TO_BANK &&
                    tx.type != FlowType.DEPOSIT_TO_VFCASH &&
                    tx.type != FlowType.BUY_USDT &&
                    tx.type != FlowType.BANK_DEDUCTION &&
                    tx.type != FlowType.CREDIT_RETURN &&
                    tx.type != FlowType.CREDIT_RETURN_FEE &&
                    tx.type != FlowType.VFCASH_RETAIL_PROFIT &&
                    tx.type != FlowType.INTERNAL_VF_TRANSFER &&
                    tx.type != FlowType.INTERNAL_VF_TRANSFER_FEE &&
                    tx.type != FlowType.DISTRIBUTE_INSTAPAY &&
                    tx.type != FlowType.INSTAPAY_DIST_PROFIT &&
                    tx.type != FlowType.COLLECT_INSTAPAY_CASH) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (tx.fromLabel != null)
                        _labelChip(context, '← ${cleanLabel(tx.fromLabel)}', fromDeleted),
                      if (tx.toLabel != null)
                        _labelChip(context, '→ ${cleanLabel(tx.toLabel)}', toDeleted),
                    ],
                  ),
                ],

                // Payment method
                if (tx.paymentMethod != null) ...[
                  const SizedBox(height: 2),
                  Text(tx.paymentMethod!,
                      style: TextStyle(
                          color: AppTheme.textMutedColor(context)
                              .withValues(alpha: 0.6),
                          fontSize: 10)),
                ],

                // Notes
                if (tx.notes != null && tx.notes!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tx.notes!,
                    style: TextStyle(
                        color: AppTheme.textMutedColor(context),
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
                  style: TextStyle(
                      color: AppTheme.textMutedColor(context), fontSize: 11),
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
                  style: TextStyle(
                      color: AppTheme.textMutedColor(context), fontSize: 11),
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
          color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.lineColor(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.edit_note, color: Colors.orangeAccent, size: 14),
            const SizedBox(width: 4),
            Text(
              context.locale.languageCode == 'ar' ? 'تعديل' : 'Correct',
              style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
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
        backgroundColor: AppTheme.surfaceColor(context),
        title: Text('Correct Transaction',
            style: TextStyle(color: AppTheme.textPrimaryColor(context))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Original Amount: ${tx.amount.toStringAsFixed(0)} EGP',
              style: TextStyle(
                  color:
                      AppTheme.textPrimaryColor(context).withValues(alpha: 0.7),
                  fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: AppTheme.textPrimaryColor(context)),
              decoration: InputDecoration(
                labelText: 'Correct Amount',
                labelStyle: TextStyle(color: AppTheme.textMutedColor(context)),
                suffixText: 'EGP',
                filled: true,
                fillColor:
                    AppTheme.textPrimaryColor(context).withValues(alpha: 0.06),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              style: TextStyle(color: AppTheme.textPrimaryColor(context)),
              decoration: InputDecoration(
                labelText: 'Reason',
                labelStyle: TextStyle(color: AppTheme.textMutedColor(context)),
                filled: true,
                fillColor:
                    AppTheme.textPrimaryColor(context).withValues(alpha: 0.06),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('cancel'.tr(),
                style: TextStyle(color: AppTheme.textMutedColor(context))),
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
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Correction applied successfully')),
                );
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('Error: $e'), backgroundColor: Colors.red),
                );
              }
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
            child: Text('Apply Fix',
                style: TextStyle(color: AppTheme.textPrimaryColor(context))),
          ),
        ],
      ),
    );
  }

  /// Renders a small label pill; red + strikethrough-style if deleted.
  Widget _labelChip(BuildContext context, String text, bool deleted) {
    if (!deleted) {
      return Text(
        text,
        style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
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

  Color _color(BuildContext context, FlowType t) {
    switch (t) {
      case FlowType.FUND_BANK:
        return AppTheme.infoColor(context);
      case FlowType.BUY_USDT:
        return AppTheme.warningColor(context);
      case FlowType.SELL_USDT:
        return AppTheme.positiveColor(context);
      case FlowType.DISTRIBUTE_VFCASH:
        return const Color(0xFFE63946);
      case FlowType.COLLECT_CASH:
        return const Color(0xFFA78BFA);
      case FlowType.DEPOSIT_TO_BANK:
        return AppTheme.infoColor(context);
      case FlowType.DEPOSIT_TO_VFCASH:
        return AppTheme.positiveColor(context);
      case FlowType.EXPENSE_VFCASH_FEE:
        return const Color(0xFFFF9800);
      case FlowType.ADMIN_ADJUSTMENT:
        return Colors.orangeAccent;
      case FlowType.CREDIT_RETURN:
        return AppTheme.positiveColor(context);
      case FlowType.CREDIT_RETURN_FEE:
        return AppTheme.warningColor(context);
      case FlowType.VFCASH_RETAIL_PROFIT:
        return const Color(0xFF2A9D8F);
      case FlowType.BANK_DEDUCTION:
        return const Color(0xFFE63946);
      case FlowType.INTERNAL_VF_TRANSFER:
        return const Color(0xFF3861FB);
      case FlowType.INTERNAL_VF_TRANSFER_FEE:
        return AppTheme.warningColor(context);
      case FlowType.DISTRIBUTE_INSTAPAY:
        return const Color(0xFF1B5E20);
      case FlowType.INSTAPAY_DIST_PROFIT:
        return const Color(0xFF2E7D32);
      case FlowType.COLLECT_INSTAPAY_CASH:
        return const Color(0xFF43A047);
      case FlowType.EXPENSE_INSTAPAY_FEE:
        return AppTheme.warningColor(context);
    }
  }

  IconData _icon(FlowType t) {
    switch (t) {
      case FlowType.FUND_BANK:
        return Icons.add_card;
      case FlowType.BUY_USDT:
        return Icons.arrow_upward;
      case FlowType.SELL_USDT:
        return Icons.arrow_downward;
      case FlowType.DISTRIBUTE_VFCASH:
        return Icons.phone_android;
      case FlowType.COLLECT_CASH:
        return Icons.delivery_dining;
      case FlowType.DEPOSIT_TO_BANK:
        return Icons.account_balance;
      case FlowType.DEPOSIT_TO_VFCASH:
        return Icons.phone_android;
      case FlowType.EXPENSE_VFCASH_FEE:
        return Icons.money_off;
      case FlowType.ADMIN_ADJUSTMENT:
        return Icons.admin_panel_settings;
      case FlowType.CREDIT_RETURN:
        return Icons.keyboard_return;
      case FlowType.CREDIT_RETURN_FEE:
        return Icons.add_chart;
      case FlowType.VFCASH_RETAIL_PROFIT:
        return Icons.trending_up;
      case FlowType.BANK_DEDUCTION:
        return Icons.remove_circle_outline;
      case FlowType.INTERNAL_VF_TRANSFER:
        return Icons.sync_alt_rounded;
      case FlowType.INTERNAL_VF_TRANSFER_FEE:
        return Icons.money_off;
      case FlowType.DISTRIBUTE_INSTAPAY:
        return Icons.payment;
      case FlowType.INSTAPAY_DIST_PROFIT:
        return Icons.trending_up;
      case FlowType.COLLECT_INSTAPAY_CASH:
        return Icons.check_circle_outline;
      case FlowType.EXPENSE_INSTAPAY_FEE:
        return Icons.money_off;
    }
  }
}

class _LedgerStat extends StatelessWidget {
  final String label;
  final String value;

  const _LedgerStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 15, fontWeight: FontWeight.w800)),
      ],
    );
  }
}
