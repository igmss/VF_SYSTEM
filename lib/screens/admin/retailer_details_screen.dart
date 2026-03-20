import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../models/retailer.dart';
import '../../models/financial_transaction.dart';
import '../../models/models.dart';
import '../../providers/distribution_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/app_provider.dart';

class RetailerDetailsScreen extends StatefulWidget {
  final Retailer retailer;

  const RetailerDetailsScreen({
    Key? key,
    required this.retailer,
  }) : super(key: key);

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
      return isAssigned || isCollected;
    }).toList();

    final List<FinancialTransaction> assignedTxs = allTxs
        .where((tx) => tx.type == FlowType.DISTRIBUTE_VFCASH)
        .toList();

    final List<FinancialTransaction> collectedTxs = allTxs
        .where((tx) => tx.type == FlowType.COLLECT_CASH)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16162A),
        title: Text(retailer.name, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFE63946),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: [
            Tab(text: 'All (${allTxs.length})'),
            Tab(text: 'Assigned (${assignedTxs.length})'),
            Tab(text: 'Collected (${collectedTxs.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Summary Header
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF16162A),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(child: _buildSummaryStat('assigned'.tr(), retailer.totalAssigned, const Color(0xFF4CC9F0))),
                    Expanded(child: _buildSummaryStat('collected'.tr(), retailer.totalCollected, const Color(0xFF4ADE80))),
                    Expanded(child: _buildSummaryStat('debt'.tr(), retailer.pendingDebt, const Color(0xFFFF6B6B))),
                  ],
                ),
                Builder(builder: (ctx) {
                  debugPrint('Retailer: ${retailer.name}, isAdmin: ${auth.currentUser?.isAdmin}, Debt: ${retailer.pendingDebt}');
                  return const SizedBox.shrink();
                }),
                if ((auth.currentUser?.isAdmin ?? false) && retailer.pendingDebt > 0) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.keyboard_return, size: 16),
                      label: Text('Credit Return (VF Cash)'.tr()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4ADE80),
                        side: const BorderSide(color: Color(0xFF4ADE80)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => _showCreditReturnDialog(context, retailer, dist),
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

  Widget _buildSummaryStat(String label, double val, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 9),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('${_fmt(val)} EGP',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList(List<FinancialTransaction> txs) {
    if (txs.isEmpty) {
      return Center(
        child: Text('no_data'.tr(), style: const TextStyle(color: Colors.white38)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: txs.length,
      itemBuilder: (context, index) {
        final tx = txs[index];
        final isAssigned = tx.type == FlowType.DISTRIBUTE_VFCASH;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E3A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isAssigned
                  ? const Color(0xFF4CC9F0).withOpacity(0.3)
                  : const Color(0xFF4ADE80).withOpacity(0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isAssigned
                            ? Icons.arrow_downward
                            : Icons.check_circle_outline,
                        color: isAssigned
                            ? const Color(0xFF4CC9F0)
                            : const Color(0xFF4ADE80),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isAssigned ? 'Assigned' : 'Collected',
                        style: TextStyle(
                          color: isAssigned
                              ? const Color(0xFF4CC9F0)
                              : const Color(0xFF4ADE80),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    DateFormat('MMM d, yyyy • HH:mm').format(tx.timestamp),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAssigned
                              ? 'From: ${tx.fromLabel ?? 'Unknown Number'}'
                              : 'By: ${tx.toLabel ?? 'Unknown Collector'}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500),
                        ),
                        if (tx.notes != null && tx.notes!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            tx.notes!,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12),
                          ),
                        ]
                      ],
                    ),
                  ),
                  Text(
                    '${_fmt(tx.amount)} EGP',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
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

  void _showCreditReturnDialog(BuildContext context, Retailer retailer, DistributionProvider dist) {
    final appProvider = context.read<AppProvider>();
    if (appProvider.mobileNumbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No VF Numbers available to receive cash.')),
      );
      return;
    }

    final amountCtrl = TextEditingController(text: retailer.pendingDebt.toStringAsFixed(0));
    final feesCtrl = TextEditingController(text: '0');
    MobileNumber selectedNumber = appProvider.mobileNumbers.firstWhere((n) => n.isDefault, orElse: () => appProvider.mobileNumbers.first);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF16162A),
          title: Text('Credit Return (VF Cash)', style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Retailer: ${retailer.name}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                Text('Debt: ${_fmt(retailer.pendingDebt)} EGP', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 16),
                
                // Select VF Number
                const Text('Select VF Number Receiving Cash', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<MobileNumber>(
                      value: selectedNumber,
                      dropdownColor: const Color(0xFF16162A),
                      isExpanded: true,
                      style: const TextStyle(color: Colors.white),
                      items: appProvider.mobileNumbers.map((n) {
                        return DropdownMenuItem(
                          value: n,
                          child: Text('${n.phoneNumber}${n.isDefault ? " (Default)" : ""}', style: const TextStyle(fontSize: 14)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedNumber = val);
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Settlement Amount (Debt Reduction)',
                    labelStyle: const TextStyle(color: Colors.white54),
                    suffixText: 'EGP',
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: feesCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Additional Fees (Keep separated)',
                    labelStyle: const TextStyle(color: Colors.white54),
                    suffixText: 'EGP',
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Note: The retailer debt will decrease by the "Settlement Amount". The VF number balance will increase by both (Amount + Fees).',
                  style: TextStyle(color: Colors.white38, fontSize: 10, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('cancel'.tr(), style: const TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text) ?? 0;
                final fees = double.tryParse(feesCtrl.text) ?? 0;
                if (amount <= 0) return;

                final auth = context.read<AuthProvider>();
                try {
                  await dist.creditReturn(
                    retailerId: retailer.id,
                    vfNumberId: selectedNumber.id,
                    vfPhone: selectedNumber.phoneNumber,
                    amount: amount,
                    fees: fees,
                    createdByUid: auth.currentUser?.uid ?? 'admin',
                  );
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Credit return recorded successfully')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4ADE80)),
              child: const Text('Confirm Return', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
