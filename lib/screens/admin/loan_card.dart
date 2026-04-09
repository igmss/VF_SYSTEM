part of 'loans_screen.dart';

class _LoanCard extends StatelessWidget {
  final Loan loan;
  final VoidCallback onRepay;

  const _LoanCard({required this.loan, required this.onRepay});

  @override
  Widget build(BuildContext context) {
    final progress = loan.principalAmount > 0 ? loan.amountRepaid / loan.principalAmount : 0.0;
    final isFullyRepaid = loan.status == LoanStatus.fully_repaid;
    final color = isFullyRepaid ? AppTheme.positiveColor(context) : AppTheme.accent;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.15)),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loan.borrowerName, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 17, fontWeight: FontWeight.w800)),
                    if (loan.borrowerPhone.isNotEmpty)
                      Text(loan.borrowerPhone, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13)),
                  ],
                ),
              ),
              _StatusBadge(status: loan.status),
            ],
          ),
          const SizedBox(height: 16),
          _SourceLabel(type: loan.sourceType, label: loan.sourceLabel),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _AmountStat(label: 'principal_amount'.tr(), amount: loan.principalAmount, color: AppTheme.textPrimaryColor(context)),
              _AmountStat(label: 'outstanding_balance'.tr(), amount: loan.outstandingBalance, color: AppTheme.warningColor(context), isEnd: true),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: color.withValues(alpha: 0.1),
              color: color,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Issued: ${DateFormat('MMM dd, yyyy').format(loan.issuedAt)}',
                  style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11),
                ),
              ),
              if (!isFullyRepaid)
                ElevatedButton.icon(
                  onPressed: onRepay,
                  icon: const Icon(Icons.payment, size: 16, color: Colors.white),
                  label: Text('record_repayment'.tr(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final LoanStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isFull = status == LoanStatus.fully_repaid;
    final color = isFull ? AppTheme.positiveColor(context) : AppTheme.warningColor(context);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        (isFull ? 'fully_repaid' : 'active_loan').tr().toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
      ),
    );
  }
}

class _SourceLabel extends StatelessWidget {
  final LoanSourceType type;
  final String label;
  const _SourceLabel({required this.type, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          type == LoanSourceType.bank ? Icons.account_balance : Icons.delivery_dining,
          size: 14,
          color: AppTheme.textMutedColor(context),
        ),
        const SizedBox(width: 6),
        Text(
          'From: $label',
          style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _AmountStat extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final bool isEnd;

  const _AmountStat({required this.label, required this.amount, required this.color, this.isEnd = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: isEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(
          '${NumberFormat('#,##0.00', 'en_US').format(amount)} EGP',
          style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}
