import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';

import '../../providers/distribution_provider.dart';
import '../../models/financial_transaction.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

class DailyFlowScreen extends StatefulWidget {
  const DailyFlowScreen({super.key});

  @override
  State<DailyFlowScreen> createState() => _DailyFlowScreenState();
}

class _DailyFlowScreenState extends State<DailyFlowScreen> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DistributionProvider>();

    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Process Ledger
    final dailyMap = <String, Map<String, double>>{};
    double totalVf = 0;
    double totalInsta = 0;

    for (final tx in provider.ledger) {
      if (tx.type != FlowType.DISTRIBUTE_VFCASH && tx.type != FlowType.DISTRIBUTE_INSTAPAY) continue;
      
      final dt = tx.timestamp;
      final dateKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

      if (!dailyMap.containsKey(dateKey)) {
        dailyMap[dateKey] = {'vf': 0.0, 'insta': 0.0};
      }

      if (tx.type == FlowType.DISTRIBUTE_VFCASH) {
        dailyMap[dateKey]!['vf'] = (dailyMap[dateKey]!['vf'] ?? 0) + tx.amount;
        totalVf += tx.amount;
      } else {
        dailyMap[dateKey]!['insta'] = (dailyMap[dateKey]!['insta'] ?? 0) + tx.amount;
        totalInsta += tx.amount;
      }
    }

    final sortedDates = dailyMap.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildSummary(context, totalVf, totalInsta),
          const SizedBox(height: 16),
          Expanded(
            child: sortedDates.isEmpty
                ? Center(
                    child: Text('no_data'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context))),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    itemCount: sortedDates.length,
                    itemBuilder: (ctx, idx) {
                      final date = sortedDates[idx];
                      final vf = dailyMap[date]!['vf'] ?? 0.0;
                      final insta = dailyMap[date]!['insta'] ?? 0.0;
                      return _buildDailyCard(context, date, vf, insta);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context, double totalVf, double totalInsta) {
    final total = totalVf + totalInsta;
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
              Text(
                'daily_flow'.tr().toUpperCase(),
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1),
              ),
              const Icon(Icons.bar_chart, color: Colors.white70, size: 24),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            Formatters.formatCurrency(total),
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.5),
          ),
          const Text(
            'Total Historical Gross Flow',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const Divider(color: Colors.white24, height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _FlowStat(label: 'VF FLOW', amount: totalVf, icon: Icons.phone_android),
              const SizedBox(width: 16),
              _FlowStat(label: 'INSTA FLOW', amount: totalInsta, icon: Icons.account_balance),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDailyCard(BuildContext context, String date, double vf, double insta) {
    final total = vf + insta;
    final dt = DateTime.parse(date);
    final isToday = dt.year == DateTime.now().year && dt.month == DateTime.now().month && dt.day == DateTime.now().day;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.softShadow(context),
        border: Border.all(color: isToday ? AppTheme.accent.withValues(alpha: 0.5) : AppTheme.lineColor(context)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isToday ? AppTheme.accent.withValues(alpha: 0.1) : AppTheme.surfaceRaisedColor(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.calendar_today, color: isToday ? AppTheme.accent : AppTheme.textMutedColor(context), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DateFormat('dd MMM, yyyy').format(dt), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold, fontSize: 16)),
                      if (isToday)
                        Text('Today', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Total Flow', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11)),
                  Text(Formatters.formatCurrency(total), style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w900, fontSize: 16)),
                ],
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              Expanded(
                child: _buildMiniStatCard(context, 'VF Cash', vf, Icons.phone_android, Colors.red[400]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStatCard(context, 'InstaPay', insta, Icons.account_balance, Colors.purple[400]),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildMiniStatCard(BuildContext context, String label, double amount, IconData icon, Color? iconColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaisedColor(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor ?? AppTheme.textMutedColor(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11)),
                const SizedBox(height: 4),
                Text(
                  Formatters.formatCurrency(amount),
                  style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w800, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          )
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
          color: Colors.black.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white54, size: 14),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              Formatters.formatCurrency(amount),
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: -0.5),
            ),
          ],
        ),
      ),
    );
  }
}
