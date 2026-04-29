part of 'collector_dashboard.dart';

enum _DepositDestination { bank, vf }

class _DepositTab extends StatefulWidget {
  final Collector? collector;
  final List<BankAccount> bankAccounts;

  const _DepositTab({required this.collector, required this.bankAccounts});

  @override
  State<_DepositTab> createState() => _DepositTabState();
}

class _DepositTabState extends State<_DepositTab> {
  BankAccount? _selectedBank;
  final _amountCtrl = TextEditingController();
  _DepositDestination _destination = _DepositDestination.bank;
  bool _isFetchingVf = false;

  @override
  void initState() {
    super.initState();
    // Auto-fetch the latest default VF number when the deposit tab opens
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchVfNumber());
  }

  Future<void> _fetchVfNumber() async {
    if (!mounted) return;
    setState(() => _isFetchingVf = true);
    try {
      await context.read<AppProvider>().fetchLatestDefaultVfNumber();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('error_with_msg'.tr(args: [e.toString()])),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isFetchingVf = false);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collector = widget.collector;
    final cashOnHand = collector?.cashOnHand ?? 0;
    final dist = context.watch<DistributionProvider>();
    final app = context.watch<AppProvider>();
    final isDepositing = dist.isDepositing;
    final isLight = !AppTheme.isDark(context);
    final defaultVfNumber = app.defaultNumber;
    final publicVfPhone = app.publicDefaultNumberPhone;
    final hasDefaultVf = defaultVfNumber != null || publicVfPhone != null;
    final feeRate = app.collectorVfDepositFeePer1000;
    final amount = double.tryParse(_amountCtrl.text) ?? 0.0;
    final vfFee = _calculateVfFee(amount, feeRate);
    final vfTransferTotal = amount + vfFee;
    final isBankDestination = _destination == _DepositDestination.bank;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isLight
                    ? const [Color(0xFFF7FBFF), Color(0xFFE4EEF8)]
                    : AppTheme.panelGradient(context),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.positiveColor(context).withValues(alpha: 0.2)),
              boxShadow: AppTheme.softShadow(context),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.positiveColor(context).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.account_balance_wallet, color: AppTheme.positiveColor(context), size: 28),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('cash_on_hand'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${cashOnHand.toStringAsFixed(0)} ${'currency'.tr()}',
                      style: TextStyle(color: AppTheme.positiveColor(context), fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('deposit_destination'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DestinationOption(
                  label: 'bank_account'.tr(),
                  subtitle: 'bank_account_desc'.tr(),
                  icon: Icons.account_balance,
                  selected: isBankDestination,
                  color: AppTheme.infoColor(context),
                  onTap: () => setState(() => _destination = _DepositDestination.bank),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DestinationOption(
                  label: 'default_vf_number'.tr(),
                  subtitle: _isFetchingVf
                      ? 'loading'.tr()
                      : defaultVfNumber?.phoneNumber ?? publicVfPhone ?? 'no_default_vf_set'.tr(),
                  icon: Icons.phone_android,
                  selected: !isBankDestination,
                  color: AppTheme.positiveColor(context),
                  onTap: () => setState(() => _destination = _DepositDestination.vf),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (isBankDestination) ...[
            Text('select_bank'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (widget.bankAccounts.isEmpty)
              Text('no_bank_accounts'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context)))
            else
              ...widget.bankAccounts.map((b) => _BankOption(
                    bank: b,
                    selected: _selectedBank?.id == b.id,
                    onTap: () => setState(() => _selectedBank = b),
                  )),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.lineColor(context)),
              ),
              child: !hasDefaultVf
                  ? _buildNoVfNumberCard(context)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                defaultVfNumber?.phoneNumber ?? publicVfPhone ?? '',
                                style: TextStyle(
                                  color: AppTheme.textPrimaryColor(context),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            // Refresh button to fetch latest number from Firebase
                            _isFetchingVf
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : IconButton(
                                    tooltip: 'fetch_current_vf_number'.tr(),
                                    icon: const Icon(Icons.refresh_rounded),
                                    color: AppTheme.positiveColor(context),
                                    onPressed: _fetchVfNumber,
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                  ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'vf_fee_rate_notice'.tr(args: [feeRate.toStringAsFixed(2)]),
                          style: TextStyle(
                            color: AppTheme.textMutedColor(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (amount > 0) ...[
                          const SizedBox(height: 14),
                          _summaryRow(
                            context,
                            'cash_deducted_from_you'.tr(),
                            '${amount.toStringAsFixed(2)} ${'currency'.tr()}',
                            AppTheme.warningColor(context),
                          ),
                          const SizedBox(height: 6),
                          _summaryRow(
                            context,
                            'vf_retail_profit'.tr(),
                            '+${vfFee.toStringAsFixed(2)} ${'currency'.tr()}',
                            AppTheme.positiveColor(context),
                          ),
                          const SizedBox(height: 6),
                          _summaryRow(
                            context,
                            'total_transferred_to_vf'.tr(),
                            '${vfTransferTotal.toStringAsFixed(2)} ${'currency'.tr()}',
                            AppTheme.infoColor(context),
                          ),
                        ],
                      ],
                    ),
            ),
          ],

          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              labelText: 'deposit_amount'.tr(),
            suffixText: 'currency'.tr(),
              filled: true,
              fillColor: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: AsyncButton.icon(
              icon: const Icon(Icons.upload_rounded),
              label: Text(
                isBankDestination
                        ? 'deposit_to_bank'.tr()
                        : 'deposit_to_default_vf'.tr(),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isBankDestination
                    ? AppTheme.infoColor(context)
                    : AppTheme.positiveColor(context),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              isDisabled: collector == null || isDepositing,
              onPressed: () async => _doDeposit(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _doDeposit() async {
    final collector = widget.collector!;
    final dist = Provider.of<DistributionProvider>(context, listen: false);
    final app = Provider.of<AppProvider>(context, listen: false);
    final bank = _selectedBank;
    final defaultVfNumber = app.defaultNumber;
    final publicVfPhone = app.publicDefaultNumberPhone;
    final hasDefaultVf = defaultVfNumber != null || publicVfPhone != null;
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    final feeRate = app.collectorVfDepositFeePer1000;
    final vfFee = _calculateVfFee(amount, feeRate);
    final vfTransferTotal = amount + vfFee;

    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('invalid_amount'.tr()), backgroundColor: Colors.red));
      return;
    }
    if (amount > collector.cashOnHand) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('deposit_exceeds_cash'.tr(args: [collector.cashOnHand.toStringAsFixed(0)])), backgroundColor: Colors.orange));
      return;
    }
    if (_destination == _DepositDestination.bank && bank == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('select_bank_first'.tr())));
      return;
    }
    if (_destination == _DepositDestination.vf && !hasDefaultVf) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('no_default_vf_set'.tr()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text('confirm_action'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold)),
        content: Text(
          _destination == _DepositDestination.bank
              ? 'deposit_bank_confirm_msg'.tr(args: [amount.toStringAsFixed(0), bank!.bankName])
              : 'deposit_vf_confirm_msg'.tr(args: [
                  amount.toStringAsFixed(2),
                  defaultVfNumber?.phoneNumber ?? publicVfPhone ?? 'default_vf_number'.tr(),
                  amount.toStringAsFixed(2),
                  vfTransferTotal.toStringAsFixed(2),
                  vfFee.toStringAsFixed(2)
                ]),
          style: TextStyle(color: AppTheme.textMutedColor(context)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _destination == _DepositDestination.bank
                  ? AppTheme.infoColor(context)
                  : AppTheme.positiveColor(context),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text('confirm'.tr(), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (_destination == _DepositDestination.bank) {
        await dist.depositToBank(
          collectorId: collector.id,
          bankAccountId: bank!.id,
          amount: amount,
          createdByUid:
              Provider.of<AuthProvider>(context, listen: false).currentUser?.uid ??
                  '',
        );
      } else {
        await dist.depositToDefaultVf(
          collectorId: collector.id,
          amount: amount,
          createdByUid:
              Provider.of<AuthProvider>(context, listen: false).currentUser?.uid ??
                  '',
        );
      }
      if (!mounted) return;
      _amountCtrl.clear();
      setState(() => _selectedBank = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _destination == _DepositDestination.bank
                ? 'deposit_success'.tr()
                : 'vf_deposit_success'.tr(),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('error_with_msg'.tr(args: [e.toString()])), backgroundColor: Colors.red));
    }
  }

  double _calculateVfFee(double amount, double feeRatePer1000) {
    if (amount <= 0 || feeRatePer1000 <= 0) return 0.0;
    return double.parse(((amount / 1000.0) * feeRatePer1000).toStringAsFixed(2));
  }

  /// Shown when no default VF number is cached — gives the collector a clear
  /// action to fetch the current number set by the admin.
  Widget _buildNoVfNumberCard(BuildContext context) {
    final warningColor = AppTheme.warningColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: warningColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'no_default_vf_hint'.tr(),
                style: TextStyle(
                  color: warningColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: _isFetchingVf
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: Text(
              _isFetchingVf
                  ? 'loading'.tr()
                  : 'fetch_current_vf_number'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: warningColor,
              side: BorderSide(color: warningColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: _isFetchingVf ? null : _fetchVfNumber,
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppTheme.textMutedColor(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _DestinationOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _DestinationOption({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.10)
              : AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? color : AppTheme.lineColor(context),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? color : AppTheme.textMutedColor(context)),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : AppTheme.textPrimaryColor(context),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textMutedColor(context),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BankOption extends StatelessWidget {
  final BankAccount bank;
  final bool selected;
  final VoidCallback onTap;

  const _BankOption({required this.bank, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final infoColor = AppTheme.infoColor(context);
    final isDark = AppTheme.isDark(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? infoColor.withValues(alpha: 0.1) : AppTheme.surfaceRaisedColor(context).withValues(alpha: isDark ? 0.8 : 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? infoColor : AppTheme.lineColor(context), width: selected ? 1.5 : 1.0),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: selected ? infoColor.withValues(alpha: 0.1) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.account_balance, color: selected ? infoColor : AppTheme.textMutedColor(context), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(bank.bankName, style: TextStyle(color: selected ? infoColor : AppTheme.textPrimaryColor(context), fontSize: 15, fontWeight: selected ? FontWeight.w800 : FontWeight.w600))),
            if (selected) ...[const SizedBox(width: 8), Icon(Icons.check_circle, color: infoColor, size: 20)],
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accent;
    final isDark = AppTheme.isDark(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : AppTheme.surfaceRaisedColor(context).withValues(alpha: isDark ? 0.6 : 1.0),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: selected ? accent : AppTheme.lineColor(context), width: selected ? 1.5 : 1.0),
          boxShadow: selected ? [BoxShadow(color: accent.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4))] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: selected ? accent : AppTheme.textMutedColor(context)),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: selected ? accent : AppTheme.textMutedColor(context), fontWeight: selected ? FontWeight.w800 : FontWeight.w600, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
