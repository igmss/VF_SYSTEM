import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/auth_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../models/loan.dart';
import '../../models/bank_account.dart';
import '../../models/collector.dart';
import '../../theme/app_theme.dart';

part 'loan_card.dart';
part 'loan_dialogs.dart';

class LoansScreen extends StatelessWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    final auth = context.watch<AuthProvider>();
    
    final totalPrincipal = dist.loans.fold<double>(0, (sum, l) => sum + l.principalAmount);
    final totalRepaid = dist.loans.fold<double>(0, (sum, l) => sum + l.amountRepaid);
    final totalOutstanding = dist.totalOutstandingLoans;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      body: Column(
        children: [
          _SummaryHeader(
            totalPrincipal: totalPrincipal,
            totalRepaid: totalRepaid,
            totalOutstanding: totalOutstanding,
          ),
          Expanded(
            child: dist.loans.isEmpty
                ? _empty(context)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    physics: const BouncingScrollPhysics(),
                    itemCount: dist.loans.length,
                    itemBuilder: (ctx, i) => _LoanCard(
                      loan: dist.loans[i],
                      onRepay: () => _showRepaymentDialog(ctx, dist.loans[i], dist, auth),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showIssueLoanDialog(context, dist, auth),
        backgroundColor: AppTheme.accent,
        icon: const Icon(Icons.add_circle_outline, color: Colors.white),
        label: Text('issue_loan'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.volunteer_activism_outlined, size: 64, color: AppTheme.textMutedColor(context).withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('no_data'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 16)),
          ],
        ),
      );
}

class _SummaryHeader extends StatelessWidget {
  final double totalPrincipal;
  final double totalRepaid;
  final double totalOutstanding;

  const _SummaryHeader({
    required this.totalPrincipal,
    required this.totalRepaid,
    required this.totalOutstanding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.panelGradient(context),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppTheme.lineColor(context)),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatItem(label: 'total_outstanding'.tr(), amount: totalOutstanding, color: AppTheme.warningColor(context), isLarge: true),
              _StatItem(label: 'total_repaid'.tr(), amount: totalRepaid, color: AppTheme.positiveColor(context)),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: totalPrincipal > 0 ? totalRepaid / totalPrincipal : 0,
              backgroundColor: AppTheme.lineColor(context),
              color: AppTheme.positiveColor(context),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${((totalPrincipal > 0 ? totalRepaid / totalPrincipal : 0) * 100).toStringAsFixed(1)}% Recovered',
                  style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11, fontWeight: FontWeight.bold)),
              Text('Principal: ${NumberFormat('#,##0', 'en_US').format(totalPrincipal)} EGP',
                  style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final bool isLarge;

  const _StatItem({required this.label, required this.amount, required this.color, this.isLarge = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('${NumberFormat('#,##0', 'en_US').format(amount)} EGP',
            style: TextStyle(color: color, fontSize: isLarge ? 24 : 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
      ],
    );
  }
}
