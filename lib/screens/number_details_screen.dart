import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/async_button.dart';

class NumberDetailsScreen extends StatefulWidget {
  final MobileNumber number;

  const NumberDetailsScreen({
    Key? key,
    required this.number,
  }) : super(key: key);

  @override
  State<NumberDetailsScreen> createState() => _NumberDetailsScreenState();
}

class _NumberDetailsScreenState extends State<NumberDetailsScreen> {
  late List<CashTransaction> _transactions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    try {
      final transactions = await context
          .read<AppProvider>()
          .getTransactionsForNumber(widget.number.phoneNumber);
      
      setState(() {
        _transactions = transactions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Find the current live version of this number from the provider
    final provider = context.watch<AppProvider>();
    final currentNum = provider.mobileNumbers.firstWhere(
      (n) => n.id == widget.number.id,
      orElse: () => widget.number,
    );

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(currentNum.phoneNumber),
            if (currentNum.name?.isNotEmpty == true)
              Text(currentNum.name!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal)),
          ],
        ),
        elevation: 0,
        actions: [
          if (!currentNum.isDefault)
            AsyncTextButton.icon(
              onPressed: () async {
                await provider.setDefaultNumber(currentNum.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('set_default_msg'.tr())),
                  );
                }
              },
              icon: Icon(Icons.star_border, color: AppTheme.textPrimaryColor(context)),
              label: Text('set_default'.tr(),
                  style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 12)),
            ),
          PopupMenuButton<String>(
            onSelected: (val) async {
              if (val == 'edit') {
                final ctrl = TextEditingController(text: currentNum.name ?? '');
                final bool? save = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Edit Name'),
                    content: TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Main Vodafone Cash',
                        prefixIcon: Icon(Icons.label),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('cancel'.tr()),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('save'.tr()),
                      ),
                    ],
                  ),
                );
                if (save == true && mounted) {
                  final newName = ctrl.text.trim();
                  await provider.updateMobileNumber(
                    currentNum.copyWith(name: newName.isEmpty ? null : newName),
                  );
                }
              } else if (val == 'delete') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('delete_confirm'.tr()),
                    content: Text('delete_number_msg'.tr(args: [currentNum.phoneNumber])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text('cancel'.tr())),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text('delete'.tr(),
                              style: const TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await provider.deleteMobileNumber(currentNum.id);
                  if (mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (ctx) => [
               PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, color: AppTheme.textPrimaryColor(context), size: 20),
                    const SizedBox(width: 8),
                    Text('Edit Name', style: TextStyle(color: AppTheme.textPrimaryColor(context))),
                  ],
                ),
              ),
               PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(Icons.delete, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text('delete'.tr(), style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildAdvancedHeader(context, provider, currentNum),
            _buildDailyReport(context, provider, currentNum),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedHeader(
      BuildContext context, AppProvider provider, MobileNumber num) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        children: [
          Text('current_balance'.tr().toUpperCase(),
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          Text(
            '${num.currentBalance.toStringAsFixed(2)} EGP',
            style: const TextStyle(
                color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildHeaderStat('incoming_today'.tr(), num.inDailyUsed,
                    num.inDailyLimit, Colors.greenAccent),
              ),
              Container(width: 1, height: 40, color: Colors.white24),
              Expanded(
                child: _buildHeaderStat('outgoing_today'.tr(), num.outDailyUsed,
                    num.outDailyLimit, Colors.orangeAccent),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildHeaderStat('incoming_month'.tr(), num.inMonthlyUsed,
                    num.inMonthlyLimit, Colors.greenAccent.withOpacity(0.7)),
              ),
              Container(width: 1, height: 40, color: Colors.white24),
              Expanded(
                child: _buildHeaderStat('outgoing_month'.tr(), num.outMonthlyUsed,
                    num.outMonthlyLimit, Colors.orangeAccent.withOpacity(0.7)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStat(String label, double used, double limit, Color color) {
    final remaining = (limit - used).clamp(0, double.infinity);
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          '${remaining.toInt()}',
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        Text(
          'left_of'.tr(args: [limit.toInt().toString()]),
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildDailyReport(
      BuildContext context, AppProvider provider, MobileNumber num) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 100),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_transactions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 100),
        child: Center(
            child: Text('no_activity'.tr(),
                style: TextStyle(color: AppTheme.textMutedColor(context)))),
      );
    }

    // Grouping logic
    final Map<String, List<CashTransaction>> grouped = {};
    for (var tx in _transactions) {
      final dateKey = DateFormat('yyyy-MM-dd').format(tx.timestamp);
      if (!grouped.containsKey(dateKey)) grouped[dateKey] = [];
      grouped[dateKey]!.add(tx);
    }

    final sortedDates = grouped.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // Descending

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'daily_activity_journal'.tr(),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimaryColor(context)),
          ),
          const SizedBox(height: 16),
          ...sortedDates.map((dateStr) {
            final dayTx = grouped[dateStr]!;
            double dayIn = 0;
            double dayOut = 0;
            for (var tx in dayTx) {
              if (tx.side == 1) dayIn += tx.amount; else dayOut += tx.amount;
            }

            final date = DateTime.parse(dateStr);
            final formattedDate = DateFormat('EEEE, MMM d').format(date);

            return _buildDaySection(formattedDate, dayIn, dayOut, dayTx);
          }).toList(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildDaySection(
      String date, double dailyIn, double dailyOut, List<CashTransaction> txs) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          // Day Summary Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceRaisedColor(context),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(date,
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimaryColor(context))),
                Row(
                  children: [
                    _buildTinyTag('+$dailyIn', Colors.green),
                    const SizedBox(width: 8),
                    _buildTinyTag('-$dailyOut', Colors.red),
                  ],
                ),
              ],
            ),
          ),
          // Transactions list for the day
          ...txs.map((tx) => _buildTransactionItem(tx)).toList(),
        ],
      ),
    );
  }

  Widget _buildTinyTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTransactionItem(CashTransaction tx) {
    final isIncoming = tx.side == 1;
    return ListTile(
      dense: true,
      leading: Icon(
        isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
        size: 16,
        color: isIncoming ? Colors.green : Colors.red,
      ),
      title: Text(
        '${isIncoming ? "+" : "-"}${tx.amount.toStringAsFixed(2)} ${tx.currency}',
        style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimaryColor(context)),
      ),
      subtitle: Text(
        '${tx.paymentMethod} • ${DateFormat('HH:mm').format(tx.timestamp)}',
        style: TextStyle(fontSize: 11, color: AppTheme.textMutedColor(context)),
      ),
      trailing: Text(
        tx.bybitOrderId.substring(0, 6),
        style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 10),
      ),
    );
  }

  Widget _buildLimitCard(
    BuildContext context,
    String label,
    double used,
    double limit,
    double percentage,
    bool isExceeded,
  ) {
    final color = isExceeded ? Colors.red : Colors.blue;
    final remaining = (limit - used).clamp(0, double.infinity);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.lineColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                '${remaining.toStringAsFixed(2)} ${'remaining'.tr()}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentage,
              minHeight: 8,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${used.toStringAsFixed(2)} / ${limit.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[400],
                ),
          ),
        ],
      ),
    );
  }
}

