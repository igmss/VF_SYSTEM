part of 'bank_accounts_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Swipeable Bank Card
// ─────────────────────────────────────────────────────────────────────────────

class _BankSwipeCard extends StatelessWidget {
  final BankAccount account;
  final bool isAdmin;
  final VoidCallback onFund;
  final VoidCallback onCorrect;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  const _BankSwipeCard({
    required this.account,
    required this.isAdmin,
    required this.onFund,
    required this.onCorrect,
    required this.onDelete,
    required this.onSetDefault,
  });

  @override
  Widget build(BuildContext context) {
    final isDefault = account.isDefaultForBuy;
    final fmt = NumberFormat('#,##0.00', 'en_US');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: isDefault
              ? (AppTheme.isDark(context)
                  ? [const Color(0xFF0D2137), const Color(0xFF0A1628)]
                  : [const Color(0xFFDCEEF9), const Color(0xFFEBF5FC)])
              : [AppTheme.surfaceRaisedColor(context), AppTheme.surfaceColor(context)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: isDefault
              ? _kBlue.withOpacity(0.45)
              : AppTheme.textPrimaryColor(context).withValues(alpha: 0.06),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDefault ? _kBlue : Colors.black).withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top Row ────────────────────────────────────────────────────
          Row(
            children: [
              // Bank icon chip
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kBlue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.account_balance_rounded,
                    color: _kBlue, size: 20),
              ),
              const SizedBox(width: 12),
              // Bank name + holder
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            account.bankName,
                            style: TextStyle(
                              color: AppTheme.textPrimaryColor(context),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isDefault) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD166).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star_rounded,
                                    color: Color(0xFFFFD166), size: 10),
                                SizedBox(width: 3),
                                Text('DEFAULT',
                                    style: TextStyle(
                                        color: Color(0xFFFFD166),
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(account.accountHolder,
                        style: TextStyle(
                            color: AppTheme.textMutedColor(context), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          Container(height: 1, color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.05)),
          const SizedBox(height: 14),

          // ── Balance + Account Number ───────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('BALANCE',
                      style: TextStyle(
                          color: AppTheme.textMutedColor(context),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(
                    '${fmt.format(account.balance)} EGP',
                    style: TextStyle(
                      color: account.balance >= 0 ? _kBlue : _kRed,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('ACCOUNT',
                      style: TextStyle(
                          color: AppTheme.textMutedColor(context),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(
                    account.accountNumber,
                    style: TextStyle(
                        color: AppTheme.textMutedColor(context),
                        fontSize: 12,
                        letterSpacing: 1.5),
                  ),
                ],
              ),
            ],
          ),

          // ── Admin Actions ──────────────────────────────────────────────
          if (isAdmin) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _ActionChip(
                  icon: isDefault
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  label: isDefault ? 'Default' : 'Set Default',
                  color: const Color(0xFFFFD166),
                  onTap: onSetDefault,
                ),
                const SizedBox(width: 8),
                _ActionChip(
                  icon: Icons.add_circle_outline_rounded,
                  label: '+ fund_bank'.tr(),
                  color: _kGreen,
                  onTap: onFund,
                ),
                const SizedBox(width: 8),
                _ActionChip(
                  icon: Icons.tune_rounded,
                  label: context.locale.languageCode == 'ar' ? 'تصحيح' : 'Fix',
                  color: Colors.orangeAccent,
                  onTap: onCorrect,
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: AppTheme.surfaceColor(context),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                      title: Text('delete_confirm'.tr(),
                          style: TextStyle(color: AppTheme.textPrimaryColor(context))),
                      content: Text('delete_msg'.tr(),
                          style: TextStyle(color: AppTheme.textMutedColor(context))),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('cancel'.tr(),
                              style: TextStyle(color: AppTheme.textMutedColor(context))),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            onDelete();
                          },
                          child: Text('delete'.tr(),
                              style: const TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kRed.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: _kRed, size: 18),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Action Chip ──────────────────────────────────────────────────────────────

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
