part of 'collector_dashboard.dart';

class _RetailersTab extends StatelessWidget {
  final List<Retailer> retailers;
  final Collector? collector;
  final List<BankAccount> bankAccounts;

  const _RetailersTab({
    required this.retailers,
    required this.collector,
    required this.bankAccounts,
  });

  @override
  Widget build(BuildContext context) {
    if (retailers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store_outlined, color: AppTheme.textMutedColor(context).withValues(alpha: 0.15), size: 64),
            const SizedBox(height: 14),
            Text('no_assigned_retailers'.tr(),
                style: TextStyle(color: AppTheme.textMutedColor(context).withValues(alpha: 0.5), fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('contact_admin_to_assign'.tr(),
                style: TextStyle(color: AppTheme.textMutedColor(context).withValues(alpha: 0.3), fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: retailers.length,
      itemBuilder: (context, i) {
        final r = retailers[i];
        return _RetailerCard(
          retailer: r,
          collector: collector,
          bankAccounts: bankAccounts,
        );
      },
    );
  }
}

class _RetailerCard extends StatelessWidget {
  final Retailer retailer;
  final Collector? collector;
  final List<BankAccount> bankAccounts;

  const _RetailerCard({
    required this.retailer,
    required this.collector,
    required this.bankAccounts,
  });

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    final debt = retailer.pendingDebt;
    final debtColor = debt > 0 ? AppTheme.warningColor(context) : AppTheme.positiveColor(context);
    final isBusy = dist.isCollecting;
    final isLight = !AppTheme.isDark(context);

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RetailerDetailsScreen(retailer: retailer),
        ),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isLight
                ? const [Color(0xFFFFFEFB), Color(0xFFF6EFE2)]
                : AppTheme.panelGradient(context),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppTheme.lineColor(context)),
          boxShadow: AppTheme.softShadow(context),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: debtColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.store, color: debtColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(retailer.name,
                            style: TextStyle(
                                color: AppTheme.textPrimaryColor(context),
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        Text(retailer.area.isEmpty ? retailer.phone : '${retailer.area} • ${retailer.phone}',
                            style: TextStyle(
                                color: AppTheme.textMutedColor(context), fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: AppTheme.lineColor(context).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatColumn(context, 'total_assigned'.tr(), retailer.totalAssigned, AppTheme.textPrimaryColor(context).withValues(alpha: 0.8)),
                    Container(width: 1, height: 30, color: AppTheme.lineColor(context)),
                    _buildStatColumn(context, 'collected'.tr(), retailer.totalCollected, AppTheme.positiveColor(context)),
                    Container(width: 1, height: 30, color: AppTheme.lineColor(context)),
                    _buildStatColumn(context, 'pending_debt'.tr(), debt, debtColor),
                  ],
                ),
              ),
              if (debt > 0) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: isBusy
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.payments_outlined, size: 16),
                    label: Text(isBusy ? 'processing'.tr() : 'collect_from'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: debtColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    onPressed: isBusy ? null : () => _showCollectDialog(context, retailer, collector),
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: AppTheme.positiveColor(context), size: 16),
                      const SizedBox(width: 6),
                      Text('fully_collected'.tr(),
                          style: TextStyle(
                              color: AppTheme.positiveColor(context), fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatColumn(BuildContext context, String label, double amount, Color color) {
    return Column(
      children: [
        Text(
          '${amount.toStringAsFixed(0)} ${'currency'.tr()}',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: AppTheme.textMutedColor(context),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  void _showCollectDialog(
      BuildContext context, Retailer retailer, Collector? collector) {
    if (collector == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('no_collector_record'.tr()), backgroundColor: Colors.red),
      );
      return;
    }
    
    final ctrl = TextEditingController(text: retailer.pendingDebt.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final dist = Provider.of<DistributionProvider>(ctx);
          final entered  = double.tryParse(ctrl.text) ?? 0.0;
          final debt     = retailer.pendingDebt;
          final debtPaid = entered > debt ? debt : entered;
          final credit   = entered > debt ? entered - debt : 0.0;
          final currentColor = debt > 0 ? AppTheme.warningColor(context) : AppTheme.positiveColor(context);
          final isSubmitting = dist.isCollecting;

          return AlertDialog(
            backgroundColor: AppTheme.surfaceColor(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            title: Text(
              '${'collect_from'.tr()} ${retailer.name}',
              style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w800),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${'pending_debt'.tr()}: ${debt.toStringAsFixed(0)} ${'currency'.tr()}',
                  style: TextStyle(color: AppTheme.textMutedColor(context), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold),
                  onChanged: (_) => setSt(() {}),
                  decoration: InputDecoration(
                    labelText: 'amount'.tr(),
                    suffixText: 'currency'.tr(),
                    filled: true,
                    fillColor: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
                  ),
                ),
                if (entered > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.lineColor(context).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: credit > 0
                            ? AppTheme.positiveColor(context).withValues(alpha: 0.4)
                            : AppTheme.lineColor(context),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _breakdownRow(
                          context,
                          'debt_reduced'.tr(),
                          '${debtPaid.toStringAsFixed(0)} ${'currency'.tr()}',
                          AppTheme.warningColor(context),
                        ),
                        if (credit > 0) ...[
                          const SizedBox(height: 4),
                          _breakdownRow(
                            context,
                            'credit_added'.tr(),
                            '+${credit.toStringAsFixed(0)} ${'currency'.tr()}',
                            AppTheme.positiveColor(context),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: Text('cancel'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context))),
              ),
              ElevatedButton(
                onPressed: isSubmitting ? null : () async {
                  final amount = double.tryParse(ctrl.text) ?? 0;
                  if (amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('invalid_amount'.tr()), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      backgroundColor: AppTheme.surfaceColor(context),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      title: Text('confirm_action'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold)),
                      content: Text(
                        amount > debt
                            ? 'collect_confirm_msg_with_credit'.tr(args: [
                                amount.toStringAsFixed(0),
                                retailer.name,
                                debt.toStringAsFixed(0),
                                (amount - debt).toStringAsFixed(0)
                              ])
                            : 'collect_confirm_msg'.tr(args: [
                                amount.toStringAsFixed(0),
                                retailer.name
                              ]),
                        style: TextStyle(color: AppTheme.textMutedColor(context)),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: Text('cancel'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context))),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(c, true),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: currentColor,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                          child: Text('confirm'.tr(), style: const TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );

                  if (confirm != true) return;

                  try {
                    await Provider.of<DistributionProvider>(context, listen: false)
                        .collectFromRetailer(
                          collectorId: collector.id,
                          retailerId: retailer.id,
                          amount: amount,
                          createdByUid: Provider.of<AuthProvider>(context, listen: false).currentUser?.uid ?? '',
                        );
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('collect_success'.tr())));
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('error_with_msg'.tr(args: [e.toString()])), backgroundColor: Colors.red),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: currentColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text('collect'.tr(), style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _breakdownRow(BuildContext context, String label, String value, Color color) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13, fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      );
}
