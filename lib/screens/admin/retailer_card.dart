part of 'retailers_screen.dart';

class _RetailerCard extends StatelessWidget {
  final Retailer retailer;
  final bool isAdmin;
  final VoidCallback onDistribute;
  final VoidCallback onReturn;
  final VoidCallback onEdit;

  const _RetailerCard({
    required this.retailer,
    required this.isAdmin,
    required this.onDistribute,
    required this.onReturn,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final pct = retailer.totalAssigned > 0
        ? (retailer.totalCollected / retailer.totalAssigned).clamp(0.0, 1.0)
        : 0.0;

    final daysSince = DateTime.now().difference(retailer.lastUpdatedAt).inDays;
    final hasDebt   = retailer.pendingDebt > 0;

    Color ageBadgeColor;
    String ageBadgeLabel;
    IconData ageBadgeIcon;

    if (!hasDebt) {
      ageBadgeColor = Colors.transparent;
      ageBadgeLabel = '';
      ageBadgeIcon  = Icons.check;
    } else if (daysSince < 7) {
      ageBadgeColor = AppTheme.positiveColor(context);
      ageBadgeLabel = 'Fresh';
      ageBadgeIcon  = Icons.check_circle_outline;
    } else if (daysSince <= 30) {
      ageBadgeColor = AppTheme.warningColor(context);
      ageBadgeLabel = 'Aging';
      ageBadgeIcon  = Icons.access_time_rounded;
    } else {
      ageBadgeColor = const Color(0xFFE63946);
      ageBadgeLabel = 'Overdue';
      ageBadgeIcon  = Icons.warning_amber_rounded;
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
          color: hasDebt && daysSince > 30
              ? const Color(0xFFE63946).withValues(alpha: 0.4)
              : AppTheme.lineColor(context),
          width: hasDebt && daysSince > 30 ? 1.5 : 1.0,
        ),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RetailerDetailsScreen(retailer: retailer))),
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor(context).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.store, color: AppTheme.warningColor(context), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(retailer.name,
                      style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w900, fontSize: 16)),
                  Text('${retailer.phone}${retailer.area.isNotEmpty ? ' • ${retailer.area}' : ''}',
                      style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12, fontWeight: FontWeight.w500)),
                  if (retailer.discountPer1000 != 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('Rate: ${retailer.discountPer1000} EGP / 1K',
                          style: TextStyle(color: AppTheme.warningColor(context), fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                ]),
              ),
              if (hasDebt)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: ageBadgeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: ageBadgeColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(ageBadgeIcon, color: ageBadgeColor, size: 12),
                      const SizedBox(width: 6),
                      Text(ageBadgeLabel,
                          style: TextStyle(color: ageBadgeColor, fontSize: 10, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
            ]),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _stat(context, 'assigned'.tr(), retailer.totalAssigned, AppTheme.infoColor(context)),
                _stat(context, 'collected'.tr(), retailer.totalCollected, AppTheme.positiveColor(context)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('debt'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11, fontWeight: FontWeight.w600)),
                    Text('${_f(retailer.pendingDebt)} EGP',
                        style: TextStyle(color: AppTheme.warningColor(context), fontWeight: FontWeight.w900, fontSize: 14)),
                    if (hasDebt)
                      Text(daysSince == 0 ? 'today' : '$daysSince d ago',
                          style: TextStyle(color: ageBadgeColor.withValues(alpha: 0.8), fontSize: 10, fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
            if (retailer.credit > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.positiveColor(context).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.positiveColor(context).withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.account_balance_wallet, color: AppTheme.positiveColor(context), size: 14),
                    const SizedBox(width: 6),
                    Text('Credit: ${_f(retailer.credit)} EGP',
                        style: TextStyle(color: AppTheme.positiveColor(context), fontSize: 11, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: AppTheme.lineColor(context),
                color: AppTheme.positiveColor(context),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${(pct * 100).toStringAsFixed(0)}% ${'collected'.tr()}',
                    style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11, fontWeight: FontWeight.w600)),
                if (isAdmin)
                  Row(
                    children: [
                      IconButton(icon: Icon(Icons.edit, size: 18, color: AppTheme.textMutedColor(context)), onPressed: onEdit),
                      IconButton(icon: Icon(Icons.add_circle_outline, size: 18, color: AppTheme.warningColor(context)), onPressed: onDistribute),
                      if (retailer.pendingDebt > 0)
                        IconButton(icon: const Icon(Icons.keyboard_return, size: 18, color: Color(0xFFE63946)), onPressed: onReturn),
                    ],
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, double val, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11, fontWeight: FontWeight.w600)),
          Text('${_f(val)} EGP',
              style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14)),
        ],
      );

  String _f(double v) => NumberFormat('#,##0.00', 'en_US').format(v);
}
