part of 'collector_dashboard.dart';

class _HistoryTab extends StatelessWidget {
  final Collector? collector;

  const _HistoryTab({required this.collector});

  @override
  Widget build(BuildContext context) {
    if (collector == null) {
      return Center(child: Text('no_collector_record'.tr()));
    }

    final dist = context.watch<DistributionProvider>();
    final isLight = !AppTheme.isDark(context);
    final textMuted = AppTheme.textMutedColor(context);

    // Filter ledger for transactions where this collector was either the source or destination
    final history = dist.ledger.where((tx) {
      final isMyCollect = tx.type == FlowType.COLLECT_CASH && tx.toId == collector!.id;
      final isMyBankDeposit = tx.type == FlowType.DEPOSIT_TO_BANK && tx.fromId == collector!.id;
      final isMyVfDeposit = tx.type == FlowType.DEPOSIT_TO_VFCASH && tx.fromId == collector!.id;
      return isMyCollect || isMyBankDeposit || isMyVfDeposit;
    }).toList();

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_outlined, size: 64, color: textMuted.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('no_data'.tr(), style: TextStyle(color: textMuted)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final tx = history[index];
        final isInbound = tx.type == FlowType.COLLECT_CASH;
        final color = isInbound ? AppTheme.positiveColor(context) : AppTheme.errorColor(context);
        final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(tx.timestamp);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.lineColor(context)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isInbound ? Icons.arrow_downward : Icons.arrow_upward,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3, // Give the title more share
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.type.label.tr(),
                      style: TextStyle(
                        color: AppTheme.textPrimaryColor(context),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${isInbound ? "from".tr() : "to".tr()}: ${isInbound ? (tx.fromLabel ?? 'Retailer') : (tx.toLabel ?? 'Bank / VF')}',
                      style: TextStyle(color: textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(dateStr, style: TextStyle(color: textMuted, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2, // Amount column
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isInbound ? "+" : "-"}${tx.amount.toStringAsFixed(0)} ${'currency'.tr()}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.end,
                    ),
                    if (tx.notes != null && tx.notes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          tx.notes!,
                          style: TextStyle(color: textMuted, fontSize: 10, fontStyle: FontStyle.italic),
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
