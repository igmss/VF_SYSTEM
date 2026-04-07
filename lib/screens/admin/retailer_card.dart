part of 'retailers_screen.dart';

class _RetailerCard extends StatelessWidget {
  final Retailer retailer;
  final bool isAdmin;
  final VoidCallback onDistribute;
  final VoidCallback onInstaPayDistribute;
  final VoidCallback onReturn;
  final VoidCallback onEdit;

  const _RetailerCard({
    required this.retailer,
    required this.isAdmin,
    required this.onDistribute,
    required this.onInstaPayDistribute,
    required this.onReturn,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final daysSince = DateTime.now().difference(retailer.lastUpdatedAt).inDays;
    final hasVfDebt = retailer.pendingDebt > 0;
    final hasIpDebt = retailer.instaPayPendingDebt > 0;
    final hasAnyDebt = hasVfDebt || hasIpDebt;

    Color ageBadgeColor;
    String ageBadgeLabel;
    IconData ageBadgeIcon;

    if (!hasAnyDebt) {
      ageBadgeColor = Colors.transparent;
      ageBadgeLabel = '';
      ageBadgeIcon = Icons.check;
    } else if (daysSince < 7) {
      ageBadgeColor = AppTheme.positiveColor(context);
      ageBadgeLabel = 'Fresh';
      ageBadgeIcon = Icons.check_circle_outline;
    } else if (daysSince <= 30) {
      ageBadgeColor = AppTheme.warningColor(context);
      ageBadgeLabel = 'Aging';
      ageBadgeIcon = Icons.access_time_rounded;
    } else {
      ageBadgeColor = const Color(0xFFE63946);
      ageBadgeLabel = 'Overdue';
      ageBadgeIcon = Icons.warning_amber_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.panelGradient(context),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: hasAnyDebt && daysSince > 30
              ? const Color(0xFFE63946).withValues(alpha: 0.4)
              : AppTheme.lineColor(context),
          width: hasAnyDebt && daysSince > 30 ? 1.5 : 1.0,
        ),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: InkWell(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => RetailerDetailsScreen(retailer: retailer))),
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.warningColor(context).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.store,
                        color: AppTheme.warningColor(context), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(retailer.name,
                            style: TextStyle(
                                color: AppTheme.textPrimaryColor(context),
                                fontWeight: FontWeight.w900,
                                fontSize: 16)),
                        Text(
                            '${retailer.phone}${retailer.area.isNotEmpty ? ' • ${retailer.area}' : ''}',
                            style: TextStyle(
                                color: AppTheme.textMutedColor(context),
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  if (hasAnyDebt)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: ageBadgeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: ageBadgeColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(ageBadgeIcon, color: ageBadgeColor, size: 12),
                          const SizedBox(width: 6),
                          Text(ageBadgeLabel,
                              style: TextStyle(
                                  color: ageBadgeColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),

              // Vodafone Cash Section
              _buildChannelSection(
                context,
                title: 'Vodafone Cash',
                icon: Icons.phonelink_ring_rounded,
                iconColor: AppTheme.warningColor(context),
                assigned: retailer.totalAssigned,
                collected: retailer.totalCollected,
                debt: retailer.pendingDebt,
                rateLabel: retailer.discountPer1000 != 0
                    ? '${retailer.discountPer1000} / 1K'
                    : null,
              ),

              const SizedBox(height: 20),
              
              // Divider
              Container(
                height: 1,
                width: double.infinity,
                color: AppTheme.lineColor(context).withValues(alpha: 0.5),
              ),
              
              const SizedBox(height: 20),

              // InstaPay Section
              _buildChannelSection(
                context,
                title: 'InstaPay',
                icon: Icons.account_balance_rounded,
                iconColor: AppTheme.positiveColor(context),
                assigned: retailer.instaPayTotalAssigned,
                collected: retailer.instaPayTotalCollected,
                debt: retailer.instaPayPendingDebt,
                rateLabel: retailer.instaPayProfitPer1000 != 0
                    ? '${retailer.instaPayProfitPer1000} / 1K'
                    : null,
              ),

              if (retailer.credit > 0) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.positiveColor(context).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.positiveColor(context).withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.account_balance_wallet_rounded,
                          color: AppTheme.positiveColor(context), size: 16),
                      const SizedBox(width: 8),
                      Text('Credit Balance: ${_f(retailer.credit)} EGP',
                          style: TextStyle(
                              color: AppTheme.positiveColor(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Footer Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Updated ${daysSince == 0 ? 'today' : '$daysSince d ago'}',
                    style: TextStyle(
                        color: AppTheme.textMutedColor(context),
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                  if (isAdmin)
                    Row(
                      children: [
                        _actionBtn(context, Icons.edit, onEdit, AppTheme.textMutedColor(context).withValues(alpha: 0.6)),
                        const SizedBox(width: 8),
                        _actionBtn(context, Icons.add_circle_outline, onDistribute, AppTheme.warningColor(context), 'VF'),
                        const SizedBox(width: 8),
                        _actionBtn(context, Icons.payment_rounded, onInstaPayDistribute, AppTheme.positiveColor(context), 'IP'),
                        const SizedBox(width: 8),
                        if (hasAnyDebt)
                          _actionBtn(context, Icons.keyboard_return_rounded, onReturn, const Color(0xFFE63946)),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChannelSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color iconColor,
    required double assigned,
    required double collected,
    required double debt,
    String? rateLabel,
  }) {
    final pct = assigned > 0 ? (collected / assigned).clamp(0.0, 1.0) : 0.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 16),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    color: AppTheme.textPrimaryColor(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
            if (rateLabel != null) ...[
              const Spacer(),
              Text(rateLabel,
                  style: TextStyle(
                      color: iconColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900)),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _stat(context, 'assigned'.tr(), assigned, AppTheme.infoColor(context)),
            _stat(context, 'collected'.tr(), collected, AppTheme.positiveColor(context)),
            _stat(context, 'debt'.tr(), debt, iconColor),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: AppTheme.lineColor(context),
            color: iconColor,
            minHeight: 4,
          ),
        ),
      ],
    );
  }

  Widget _stat(BuildContext context, String label, double val, Color color) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: AppTheme.textMutedColor(context),
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(_f(val),
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w900, fontSize: 13)),
        ],
      );

  Widget _actionBtn(BuildContext context, IconData icon, VoidCallback onTap, Color color, [String? label]) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
            ],
          ],
        ),
      ),
    );
  }

  String _f(double v) => NumberFormat('#,##0.00', 'en_US').format(v);
}
