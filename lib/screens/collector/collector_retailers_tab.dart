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
    final vfDebt = retailer.pendingDebt;
    final ipDebt = retailer.instaPayPendingDebt;
    final totalDebt = vfDebt + ipDebt;
    final debtColor = totalDebt > 0 ? AppTheme.warningColor(context) : AppTheme.positiveColor(context);
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
              const SizedBox(height: 12),
              // VF Section
              _buildSectionHeader(context, Icons.phonelink_ring_rounded, 'Vodafone Cash', AppTheme.warningColor(context)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor(context).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.warningColor(context).withValues(alpha: 0.1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(child: _buildStatColumn(context, 'assigned'.tr(), retailer.totalAssigned, AppTheme.textPrimaryColor(context).withValues(alpha: 0.7))),
                    Container(width: 1, height: 24, color: AppTheme.warningColor(context).withValues(alpha: 0.1)),
                    Expanded(child: _buildStatColumn(context, 'collected'.tr(), retailer.totalCollected, AppTheme.positiveColor(context))),
                    Container(width: 1, height: 24, color: AppTheme.warningColor(context).withValues(alpha: 0.1)),
                    Expanded(child: _buildStatColumn(context, 'debt'.tr(), retailer.pendingDebt, AppTheme.warningColor(context))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // InstaPay Section
              _buildSectionHeader(context, Icons.account_balance_rounded, 'InstaPay', AppTheme.positiveColor(context)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                decoration: BoxDecoration(
                  color: AppTheme.positiveColor(context).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.positiveColor(context).withValues(alpha: 0.1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(child: _buildStatColumn(context, 'assigned'.tr(), retailer.instaPayTotalAssigned, AppTheme.textPrimaryColor(context).withValues(alpha: 0.7))),
                    Container(width: 1, height: 24, color: AppTheme.positiveColor(context).withValues(alpha: 0.1)),
                    Expanded(child: _buildStatColumn(context, 'collected'.tr(), retailer.instaPayTotalCollected, AppTheme.positiveColor(context))),
                    Container(width: 1, height: 24, color: AppTheme.positiveColor(context).withValues(alpha: 0.1)),
                    Expanded(child: _buildStatColumn(context, 'debt'.tr(), retailer.instaPayPendingDebt, AppTheme.positiveColor(context))),
                  ],
                ),
              ),
              if (totalDebt > 0) ...[
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

  Widget _buildSectionHeader(BuildContext context, IconData icon, String title, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildStatColumn(BuildContext context, String label, double amount, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${amount.toStringAsFixed(0)} ${'currency'.tr()}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: AppTheme.textMutedColor(context).withValues(alpha: 0.6),
            fontSize: 9,
            fontWeight: FontWeight.w700,
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
    
    final vfDebt = retailer.pendingDebt;
    final ipDebt = retailer.instaPayPendingDebt;

    final vfCtrl = TextEditingController(text: vfDebt > 0 ? vfDebt.toStringAsFixed(0) : '0');
    final ipCtrl = TextEditingController(text: ipDebt > 0 ? ipDebt.toStringAsFixed(0) : '0');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final dist = Provider.of<DistributionProvider>(ctx);
          final enteredVf = double.tryParse(vfCtrl.text) ?? 0.0;
          final enteredIp = double.tryParse(ipCtrl.text) ?? 0.0;
          final totalAmount = enteredVf + enteredIp;

          final vfApplied = enteredVf > vfDebt ? vfDebt : enteredVf;
          final vfCredit  = enteredVf > vfDebt ? enteredVf - vfDebt : 0.0;
          
          final ipApplied = enteredIp > ipDebt ? ipDebt : enteredIp;
          // Note: InstaPay usually doesn't have "credit" in the same way, 
          // but we follow the backend which validates ipAmount <= ipPendingDebt.
          // If user enters more than IP debt, we should probably warn or cap it.

          final isSubmitting = dist.isCollecting;
          final primaryColor = (vfDebt > 0 || ipDebt > 0) ? AppTheme.warningColor(context) : AppTheme.positiveColor(context);

          return AlertDialog(
            backgroundColor: AppTheme.surfaceColor(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            title: Text(
              '${'collect_from'.tr()} ${retailer.name}',
              style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w800),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (vfDebt > 0 && ipDebt > 0) ...[
                    _debtInfo(context, 'VF Pending', vfDebt),
                    const SizedBox(height: 8),
                    _tf(context, vfCtrl, 'Collect for VF', Icons.phone_android, () => setSt(() {})),
                    const SizedBox(height: 16),
                    _debtInfo(context, 'InstaPay Pending', ipDebt, isIp: true),
                    const SizedBox(height: 8),
                    _tf(context, ipCtrl, 'Collect for InstaPay', Icons.payment, () => setSt(() {})),
                  ] else if (ipDebt > 0) ...[
                    _debtInfo(context, 'InstaPay Pending', ipDebt, isIp: true),
                    const SizedBox(height: 8),
                    _tf(context, ipCtrl, 'Amount', Icons.payment, () => setSt(() {})),
                  ] else ...[
                    _debtInfo(context, 'VF Pending', vfDebt),
                    const SizedBox(height: 8),
                    _tf(context, vfCtrl, 'Amount', Icons.phone_android, () => setSt(() {})),
                  ],

                  if (totalAmount > 0) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.lineColor(context).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.lineColor(context)),
                      ),
                      child: Column(
                        children: [
                          if (enteredVf > 0) ...[
                            _breakdownRow(context, 'VF Applied', '${vfApplied.toStringAsFixed(0)} EGP', AppTheme.warningColor(context)),
                            if (vfCredit > 0)
                              _breakdownRow(context, 'VF Credit Added', '+${vfCredit.toStringAsFixed(0)} EGP', AppTheme.positiveColor(context)),
                          ],
                          if (enteredIp > 0)
                            _breakdownRow(context, 'InstaPay Applied', '${ipApplied.toStringAsFixed(0)} EGP', AppTheme.positiveColor(context)),
                          const Divider(),
                          _breakdownRow(context, 'Total Collection', '${totalAmount.toStringAsFixed(0)} EGP', AppTheme.textPrimaryColor(context), isBold: true),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: Text('cancel'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context))),
              ),
              ElevatedButton(
                onPressed: isSubmitting ? null : () async {
                  if (totalAmount <= 0) return;
                  
                  // Validation
                  if (enteredIp > ipDebt + 0.01) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('InstaPay amount exceeds pending debt.'), backgroundColor: Colors.red),
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
                        'Confirm collection of ${totalAmount.toStringAsFixed(0)} EGP from ${retailer.name}?',
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
                              backgroundColor: primaryColor,
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
                          amount: totalAmount,
                          vfAmount: enteredVf,
                          instaPayAmount: enteredIp,
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
                    backgroundColor: primaryColor,
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

  Widget _debtInfo(BuildContext context, String label, double amount, {bool isIp = false}) => Row(
    children: [
      Icon(isIp ? Icons.payment : Icons.phone_android, size: 14, color: isIp ? Colors.green : Colors.orange),
      const SizedBox(width: 6),
      Text(
        '$label: ${amount.toStringAsFixed(0)} EGP',
        style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12, fontWeight: FontWeight.bold),
      ),
    ],
  );

  Widget _tf(BuildContext context, TextEditingController ctrl, String label, IconData icon, VoidCallback onUpdate) => TextField(
    controller: ctrl,
    keyboardType: TextInputType.number,
    style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold),
    onChanged: (_) => onUpdate(),
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18),
      filled: true,
      fillColor: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
    ),
  );

  Widget _breakdownRow(BuildContext context, String label, String value, Color color, {bool isBold = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13, fontWeight: isBold ? FontWeight.w800 : FontWeight.w600)),
          Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: isBold ? FontWeight.w900 : FontWeight.bold)),
        ],
      );
}
