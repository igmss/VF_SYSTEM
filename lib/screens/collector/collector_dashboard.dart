import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/app_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../models/retailer.dart';
import '../../models/collector.dart';
import '../../models/bank_account.dart';
import '../../models/financial_transaction.dart';
import '../admin/retailer_details_screen.dart';
import '../../theme/app_theme.dart';
import 'package:intl/intl.dart';

enum _DepositDestination { bank, vf }

class CollectorDashboard extends StatefulWidget {
  const CollectorDashboard({super.key});

  @override
  State<CollectorDashboard> createState() => _CollectorDashboardState();
}

class _CollectorDashboardState extends State<CollectorDashboard> {
  int _tab = 0;

  static Color _collectorAccent(BuildContext context) =>
      AppTheme.isDark(context) ? const Color(0xFFB8925A) : const Color(0xFF8C6239);

  static List<Color> _headerGradient(BuildContext context) => AppTheme.isDark(context)
      ? AppTheme.panelGradient(context)
      : const [Color(0xFFFFFBF3), Color(0xFFF3E3C2)];

  static List<Color> _heroCardGradient(BuildContext context) => AppTheme.isDark(context)
      ? [const Color(0xFF2E261A), const Color(0xFF1B1A18)]
      : const [Color(0xFFFFF4DA), Color(0xFFF5E2B8)];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DistributionProvider>().loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final dist = context.watch<DistributionProvider>();
    final uid = auth.currentUser?.uid ?? '';
    final collector = dist.getMyCollector(uid);
    final myRetailers = dist.getMyRetailers(uid);

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: AppTheme.backgroundGradient(context),
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context, auth, collector),
              _buildTabs(),
              Expanded(
                child: _tab == 0
                    ? _RetailersTab(
                        retailers: myRetailers,
                        collector: collector,
                        bankAccounts: dist.bankAccounts,
                      )
                    : _tab == 1
                        ? _DepositTab(
                            collector: collector,
                            bankAccounts: dist.bankAccounts,
                          )
                        : _HistoryTab(collector: collector),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, AuthProvider auth, Collector? collector) {
    final textPrimary = AppTheme.textPrimaryColor(context);
    final textMuted = AppTheme.textMutedColor(context);
    final accent = _collectorAccent(context);
    final cashOnHand = collector?.cashOnHand ?? 0;
    final cashLimit = collector?.cashLimit ?? 50000;
    final progress = cashLimit > 0 ? (cashOnHand / cashLimit).clamp(0.0, 1.0) : 0.0;
    
    final Color progressColor;
    if (progress > 0.85) {
      progressColor = const Color(0xFFE63946);
    } else if (progress > 0.6) {
      progressColor = AppTheme.warningColor(context);
    } else {
      progressColor = AppTheme.positiveColor(context);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _headerGradient(context),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        border: Border(bottom: BorderSide(color: AppTheme.lineColor(context))),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: accent.withValues(alpha: 0.14),
                child: Icon(Icons.person, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.currentUser?.name ?? 'collector'.tr(),
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      'collector_dashboard'.tr(),
                      style: TextStyle(color: textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  final isAr = context.locale.languageCode == 'ar';
                  context.setLocale(isAr ? const Locale('en') : const Locale('ar'));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.lineColor(context)),
                  ),
                  child: Text(
                    context.locale.languageCode == 'ar' ? 'EN' : 'ع',
                    style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.logout, color: textMuted),
                onPressed: () => context.read<AuthProvider>().signOut(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _heroCardGradient(context),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('cash_on_hand'.tr(),
                        style: TextStyle(
                            color: textMuted, fontSize: 13)),
                    Text(
                      '${cashOnHand.toStringAsFixed(0)} / ${cashLimit.toStringAsFixed(0)} ${'currency'.tr()}',
                      style: TextStyle(
                          color: progressColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppTheme.isDark(context) ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
                    valueColor: AlwaysStoppedAnimation(progressColor),
                    minHeight: 10,
                  ),
                ),
                if (progress > 0.85) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 14),
                      const SizedBox(width: 6),
                      Text('near_cash_limit'.tr(),
                          style: const TextStyle(
                              color: Colors.orange, fontSize: 11)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _TabChip(
              label: 'my_retailers'.tr(),
              icon: Icons.store,
              selected: _tab == 0,
              onTap: () => setState(() => _tab = 0)),
          const SizedBox(width: 10),
          _TabChip(
              label: 'deposit'.tr(),
              icon: Icons.account_balance,
              selected: _tab == 1,
              onTap: () => setState(() => _tab = 1)),
          const SizedBox(width: 10),
          _TabChip(
              label: 'history'.tr(),
              icon: Icons.history,
              selected: _tab == 2,
              onTap: () => setState(() => _tab = 2)),
        ],
      ),
    );
  }
}

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
            child: ElevatedButton.icon(
              icon: isDepositing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.upload_rounded),
              label: Text(
                isDepositing
                    ? 'processing'.tr()
                    : isBankDestination
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
              onPressed: collector == null || isDepositing ? null : _doDeposit,
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
