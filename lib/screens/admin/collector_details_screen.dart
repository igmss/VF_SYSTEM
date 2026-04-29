import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import '../../models/collector.dart';
import '../../models/financial_transaction.dart';
import '../../providers/distribution_provider.dart';
import '../../providers/auth_provider.dart';

class CollectorDetailsScreen extends StatefulWidget {
  final Collector collector;

  const CollectorDetailsScreen({
    super.key,
    required this.collector,
  });

  @override
  State<CollectorDetailsScreen> createState() => _CollectorDetailsScreenState();
}

class _CollectorDetailsScreenState extends State<CollectorDetailsScreen>
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
    
    // Always use the latest collector data if it updated in the background
    final collector = dist.collectors.firstWhere(
      (c) => c.id == widget.collector.id,
      orElse: () => widget.collector,
    );

    // Filter ledger for this specific collector
    final List<FinancialTransaction> allTxs = dist.ledger.where((tx) {
      final isCollection = (tx.type == FlowType.COLLECT_CASH ||
              tx.type == FlowType.COLLECT_VFCASH ||
              tx.type == FlowType.COLLECT_INSTAPAY) &&
          tx.toId == collector.id;
      final isDeposit = (tx.type == FlowType.DEPOSIT_TO_BANK ||
              tx.type == FlowType.DEPOSIT_TO_VFCASH) &&
          tx.fromId == collector.id;

      // Include Margin Profits assigned to this collector
      final isProfit = (tx.type == FlowType.INSTAPAY_DIST_PROFIT ||
              tx.type == FlowType.VFCASH_RETAIL_PROFIT) &&
          tx.toId == collector.id;

      return isCollection || isDeposit || isProfit;
    }).toList();

    final List<FinancialTransaction> collectedTxs = allTxs
        .where((tx) =>
            tx.type == FlowType.COLLECT_CASH ||
            tx.type == FlowType.COLLECT_VFCASH ||
            tx.type == FlowType.COLLECT_INSTAPAY)
        .toList();

    final List<FinancialTransaction> depositedTxs = allTxs
        .where((tx) =>
            tx.type == FlowType.DEPOSIT_TO_BANK ||
            tx.type == FlowType.DEPOSIT_TO_VFCASH)
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor(context),
        elevation: 0,
        title: Text(collector.name, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: AppTheme.textPrimaryColor(context)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.accent,
          indicatorWeight: 3,
          labelColor: AppTheme.textPrimaryColor(context),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelColor: AppTheme.textMutedColor(context),
          tabs: [
            Tab(text: 'All (${allTxs.length})'),
            Tab(text: 'Collections (${collectedTxs.length})'),
            Tab(text: 'Deposits (${depositedTxs.length})'),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(child: _buildSummaryStat(context, 'Total Collected', collector.totalCollected, AppTheme.positiveColor(context))),
                Expanded(child: _buildSummaryStat(context, 'Total Deposited', collector.totalDeposited, AppTheme.infoColor(context))),
                Expanded(child: _buildSummaryStat(context, 'Cash On Hand', collector.cashOnHand, AppTheme.warningColor(context))),
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
                _buildTransactionList(collectedTxs),
                _buildTransactionList(depositedTxs),
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
            child: Text('${_fmt(val)} EGP',
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
        final isCollection = tx.type == FlowType.COLLECT_CASH ||
            tx.type == FlowType.COLLECT_VFCASH ||
            tx.type == FlowType.COLLECT_INSTAPAY;
        final isVfDeposit = tx.type == FlowType.DEPOSIT_TO_VFCASH;
        final isProfit = tx.type == FlowType.INSTAPAY_DIST_PROFIT ||
            tx.type == FlowType.VFCASH_RETAIL_PROFIT;

        final txColor = isCollection
            ? AppTheme.positiveColor(context)
            : isProfit
                ? AppTheme.positiveColor(context)
                : isVfDeposit
                    ? AppTheme.positiveColor(context)
                    : AppTheme.infoColor(context);

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
                          isCollection
                              ? Icons.arrow_downward
                              : isProfit
                                  ? Icons.trending_up
                                  : isVfDeposit
                                      ? Icons.phone_android
                                      : Icons.account_balance,
                          color: txColor,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        tx.type.label.tr(),
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
                          isCollection
                              ? 'From: ${tx.fromLabel ?? 'Unknown Retailer'}'
                              : isVfDeposit
                                  ? 'To: ${tx.toLabel ?? 'Unknown VF Number'}'
                                  : 'To: ${tx.toLabel ?? 'Unknown Bank'}',
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
                    '${_fmt(tx.amount)} EGP',
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
}
