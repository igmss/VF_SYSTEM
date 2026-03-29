import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../models/retailer.dart';
import '../../models/financial_transaction.dart';
import '../../providers/distribution_provider.dart';
import '../../providers/auth_provider.dart';
import 'credit_return_dialog.dart';


class RetailerDetailsScreen extends StatefulWidget {
  final Retailer retailer;

  const RetailerDetailsScreen({
    super.key,
    required this.retailer,
  });

  @override
  State<RetailerDetailsScreen> createState() => _RetailerDetailsScreenState();
}

class _RetailerDetailsScreenState extends State<RetailerDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _fmt(double v) => NumberFormat('#,##0.00', 'en_US').format(v);

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    final auth = context.watch<AuthProvider>();
    
    // Always use the latest retailer data if it updated in the background
    final retailer = dist.retailers.firstWhere(
      (r) => r.id == widget.retailer.id,
      orElse: () => widget.retailer,
    );

    // Filter ledger for this specific retailer
    final List<FinancialTransaction> allTxs = dist.ledger.where((tx) {
      final isAssigned =
          tx.type == FlowType.DISTRIBUTE_VFCASH && tx.toId == retailer.id;
      final isCollected =
          tx.type == FlowType.COLLECT_CASH && tx.fromId == retailer.id;
      final isCreditReturn =
          tx.type == FlowType.CREDIT_RETURN && tx.fromId == retailer.id;
      final isCreditReturnFee =
          tx.type == FlowType.CREDIT_RETURN_FEE && tx.fromId == retailer.id;
      return isAssigned || isCollected || isCreditReturn || isCreditReturnFee;
    }).toList();

    final List<FinancialTransaction> assignedTxs = allTxs
        .where((tx) => tx.type == FlowType.DISTRIBUTE_VFCASH)
        .toList();

    final List<FinancialTransaction> collectedTxs = allTxs
        .where((tx) =>
            tx.type == FlowType.COLLECT_CASH ||
            tx.type == FlowType.CREDIT_RETURN ||
            tx.type == FlowType.CREDIT_RETURN_FEE)
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor(context),
        elevation: 0,
        title: Text(retailer.name, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: AppTheme.textPrimaryColor(context)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.accent,
          indicatorWeight: 3,
          labelColor: AppTheme.textPrimaryColor(context),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelColor: AppTheme.textMutedColor(context),
          tabs: [
            Tab(text: 'all_with_count'.tr(args: [allTxs.length.toString()])),
            Tab(text: 'assigned_with_count'.tr(args: [assignedTxs.length.toString()])),
            Tab(text: 'collected_with_count'.tr(args: [collectedTxs.length.toString()])),
          ],
        ),
      ),
      body: Column(
        children: [
          // Summary Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.panelGradient(context),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
              border: Border(bottom: BorderSide(color: AppTheme.lineColor(context))),
              boxShadow: AppTheme.softShadow(context),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(child: _buildSummaryStat(context, 'assigned'.tr(), retailer.totalAssigned, AppTheme.infoColor(context))),
                    Expanded(child: _buildSummaryStat(context, 'collected'.tr(), retailer.totalCollected, AppTheme.positiveColor(context))),
                    Expanded(child: _buildSummaryStat(context, 'debt'.tr(), retailer.pendingDebt, AppTheme.warningColor(context))),
                  ],
                ),
                if ((auth.currentUser?.isAdmin ?? false) && retailer.pendingDebt > 0) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.keyboard_return, size: 18),
                      label: Text('credit_return_vf'.tr()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.positiveColor(context),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      onPressed: () => _showCreditReturnDialog(context, retailer),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTransactionList(allTxs),
                _buildTransactionList(assignedTxs),
                _buildTransactionList(collectedTxs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStat(BuildContext context, String label, double val, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 10, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('${_fmt(val)} ${'currency'.tr()}',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList(List<FinancialTransaction> txs) {
    if (txs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_outlined, color: AppTheme.textMutedColor(context).withValues(alpha: 0.1), size: 64),
            const SizedBox(height: 14),
            Text('no_data'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context).withValues(alpha: 0.5), fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: txs.length,
      itemBuilder: (context, index) {
        final tx = txs[index];
        final isAssigned = tx.type == FlowType.DISTRIBUTE_VFCASH;
        final isCreditReturn = tx.type == FlowType.CREDIT_RETURN;
        final isCreditReturnFee = tx.type == FlowType.CREDIT_RETURN_FEE;
        final txColor = isAssigned
            ? AppTheme.infoColor(context)
            : isCreditReturnFee
                ? AppTheme.warningColor(context)
                : AppTheme.positiveColor(context);

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: AppTheme.panelGradient(context),
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: txColor.withValues(alpha: 0.2)),
            boxShadow: AppTheme.softShadow(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: txColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isAssigned
                              ? Icons.arrow_downward
                              : isCreditReturnFee
                                  ? Icons.receipt_long_outlined
                                  : Icons.check_circle_outline,
                          color: txColor,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                        Text(
                          isAssigned
                              ? 'assigned'.tr()
                              : isCreditReturn
                                  ? 'credit_return'.tr()
                                  : isCreditReturnFee
                                      ? 'return_fee'.tr()
                                      : 'collected'.tr(),
                          style: TextStyle(
                            color: txColor,
                            fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    DateFormat('MMM d, yyyy \u2022 HH:mm').format(tx.timestamp),
                    style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Text(
                            isAssigned
                                ? '${'from'.tr()}: ${tx.fromLabel ?? 'Unknown Number'}'
                                : isCreditReturn || isCreditReturnFee
                                    ? '${'to'.tr()} ${'vf_cash'.tr()}: ${tx.toLabel ?? 'Unknown Number'}'
                                    : '${'by'.tr()}: ${tx.toLabel ?? 'Unknown Collector'}',
                          style: TextStyle(
                              color: AppTheme.textPrimaryColor(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                        if (tx.notes != null && tx.notes!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            tx.notes!,
                            style: TextStyle(
                                color: AppTheme.textMutedColor(context), fontSize: 12),
                          ),
                        ]
                      ],
                    ),
                  ),
                  Text(
                    '${_fmt(tx.amount)} ${'currency'.tr()}',
                    style: TextStyle(
                      color: AppTheme.textPrimaryColor(context),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCreditReturnDialog(BuildContext context, Retailer retailer) {
    showDialog(
      context: context,
      builder: (_) => CreditReturnDialog(retailer: retailer),
    );
  }
}
