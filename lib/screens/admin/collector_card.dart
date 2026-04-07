part of 'collectors_screen.dart';

class _CollectorCard extends StatelessWidget {
  final Collector collector;
  final bool isAdmin;
  final VoidCallback onCollect;
  final VoidCallback onDeposit;
  final VoidCallback? onEdit;
  final VoidCallback? onAssignRetailers;

  const _CollectorCard({
    required this.collector,
    required this.isAdmin,
    required this.onCollect,
    required this.onDeposit,
    this.onEdit,
    this.onAssignRetailers,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (collector.cashOnHand / collector.cashLimit).clamp(0.0, 1.0);
    final isCritical = collector.cashOnHand >= collector.cashLimit;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CollectorDetailsScreen(collector: collector),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.isDark(context) ? AppTheme.surfaceColor(context) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isCritical
              ? Colors.red.withOpacity(0.4)
              : AppTheme.lineColor(context),
          width: isCritical ? 1.5 : 1,
        ),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: (isCritical ? Colors.red : (AppTheme.isDark(context) ? AppTheme.accent : const Color(0xFF8C6239))).withOpacity(0.1),
                  child: Icon(Icons.delivery_dining, 
                      color: isCritical ? Colors.red : (AppTheme.isDark(context) ? AppTheme.accent : const Color(0xFF8C6239)), 
                      size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(collector.name,
                          style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.phone, size: 12, color: AppTheme.textMutedColor(context)),
                          const SizedBox(width: 4),
                          Text(collector.phone,
                              style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13)),
                        ],
                      ),
                    ]
                  ),
                ),
                if (onEdit != null)
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.lineColor(context).withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.edit, color: AppTheme.textPrimaryColor(context), size: 18),
                      onPressed: onEdit,
                      padding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ),
          
          Divider(height: 1, color: AppTheme.lineColor(context)),
          
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cash in Hand', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(
                      '${_f(collector.cashOnHand)} EGP',
                      style: TextStyle(
                          color: isCritical ? Colors.redAccent : AppTheme.textPrimaryColor(context),
                          fontWeight: FontWeight.w900,
                          fontSize: 18),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Limit', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(
                      '${_f(collector.cashLimit)} EGP',
                      style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: percent,
                minHeight: 8,
                backgroundColor: AppTheme.lineColor(context),
                valueColor: AlwaysStoppedAnimation<Color>(
                    isCritical ? Colors.redAccent : const Color(0xFF4ADE80)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          if (isAdmin)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.lineColor(context).withOpacity(0.3),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onCollect,
                          icon: const Icon(Icons.arrow_downward, size: 16),
                          label: Text('collected'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4ADE80).withOpacity(0.15),
                            foregroundColor: const Color(0xFF16A34A),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onDeposit,
                          icon: const Icon(Icons.account_balance_wallet, size: 16),
                          label: Text('deposit'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CC9F0).withOpacity(0.15),
                            foregroundColor: const Color(0xFF0284C7),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (onAssignRetailers != null) ...[                           
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: onAssignRetailers,
                        icon: const Icon(Icons.store_outlined, size: 18),
                        label: Text('assign_retailers'.tr(),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.isDark(context) ? Colors.white70 : const Color(0xFF8C6239),
                          backgroundColor: AppTheme.isDark(context) ? Colors.white.withOpacity(0.05) : const Color(0xFF8C6239).withOpacity(0.05),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    ));
  }

  String _f(double v) {
    return NumberFormat('#,##0.00', 'en_US').format(v);
  }
}
