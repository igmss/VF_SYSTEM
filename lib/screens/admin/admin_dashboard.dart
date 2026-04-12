import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../providers/app_provider.dart';
import '../../services/retailer_ussd_auto_queue_service.dart';
import '../../models/app_user.dart';
import '../../theme/app_theme.dart';
import '../home_screen.dart';
import '../settings_screen.dart';
import 'bank_accounts_screen.dart';
import 'retailers_screen.dart';
import 'collectors_screen.dart';
import 'ledger_screen.dart';
import 'user_management_screen.dart';
import 'usd_exchange_screen.dart';
import 'exchange_rate_screen.dart';
import 'retailer_assignment_requests_screen.dart';
import 'loans_screen.dart';
import 'expenses_screen.dart';
import 'investors_screen.dart';
import 'partners_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _idx = 0;
  int? _moreIdx;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DistributionProvider>().loadAll();
      context.read<AppProvider>().loadMobileNumbers();
      context.read<RetailerUssdAutoQueueService>().attach(
            auth: context.read<AuthProvider>(),
            app: context.read<AppProvider>(),
            dist: context.read<DistributionProvider>(),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final dist = context.watch<DistributionProvider>();
    final app = context.watch<AppProvider>();
    final role = auth.currentUser?.role ?? UserRole.OPERATOR;
    final canViewUsdExchange = role == UserRole.ADMIN || role == UserRole.FINANCE;

    final allTabs = <_TabItem>[
      _TabItem(
        label: 'overview'.tr(),
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        widget: _Overview(
          totalAssets: _calcTotalAssets(dist, app, includeUsdExchange: canViewUsdExchange),
          bankBalance: dist.totalBankBalance,
          vfCash: _calcTotalVfCash(app),
          vfDepositProfit: dist.totalVfDepositProfit,
          creditReturnProfit: dist.totalCreditReturnProfit,
          instaPayProfit: dist.totalInstaPayProfit,
          retailerDebt: dist.totalRetailerDebt,
          collectorCash: dist.totalCollectorCash,
          usdtBalance: dist.usdtBalance,
          transferFees: dist.totalTransferFees,
          outstandingLoans: dist.totalOutstandingLoans,
          totalExpenses: dist.totalExpenses,
          totalInvestorCapital: dist.totalInvestorCapital,
          totalInvestorProfitOwed: dist.totalInvestorProfitOwed,
          totalPartnerProfitOwed: dist.totalPartnerProfitOwed,
          userName: auth.currentUser?.name ?? 'Admin',
          canViewUsdExchange: canViewUsdExchange,
        ),
        roles: [UserRole.ADMIN, UserRole.FINANCE, UserRole.COLLECTOR, UserRole.OPERATOR],
      ),
      _TabItem(
        label: 'vf_numbers'.tr(),
        icon: Icons.phone_android_outlined,
        selectedIcon: Icons.phone_android,
        widget: const HomeScreen(embedded: true),
        roles: [UserRole.ADMIN, UserRole.FINANCE],
      ),
      _TabItem(
        label: 'banks'.tr(),
        icon: Icons.account_balance_outlined,
        selectedIcon: Icons.account_balance,
        widget: const BankAccountsScreen(),
        roles: [UserRole.ADMIN, UserRole.FINANCE],
      ),
      _TabItem(
        label: 'USD Exchange',
        icon: Icons.currency_exchange_outlined,
        selectedIcon: Icons.currency_exchange,
        widget: const UsdExchangeScreen(),
        roles: [UserRole.ADMIN, UserRole.FINANCE],
      ),
      _TabItem(
        label: 'EGP/USDT Rate',
        icon: Icons.show_chart_outlined,
        selectedIcon: Icons.show_chart,
        widget: const ExchangeRateScreen(),
        roles: [UserRole.ADMIN, UserRole.FINANCE],
      ),
      _TabItem(
        label: 'retailers'.tr(),
        icon: Icons.store_outlined,
        selectedIcon: Icons.store,
        widget: const RetailersScreen(),
        roles: [UserRole.ADMIN, UserRole.FINANCE, UserRole.COLLECTOR],
      ),
      _TabItem(
        label: 'retailer_requests'.tr(),
        icon: Icons.assignment_outlined,
        selectedIcon: Icons.assignment,
        widget: const RetailerAssignmentRequestsScreen(),
        roles: [UserRole.ADMIN, UserRole.FINANCE],
      ),
      _TabItem(
        label: 'collectors'.tr(),
        icon: Icons.delivery_dining_outlined,
        selectedIcon: Icons.delivery_dining,
        widget: const CollectorsScreen(),
        roles: [UserRole.ADMIN, UserRole.FINANCE, UserRole.COLLECTOR],
      ),
      _TabItem(
        label: 'ledger'.tr(),
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        widget: const LedgerScreen(),
        roles: [UserRole.ADMIN, UserRole.FINANCE],
      ),
      _TabItem(
        label: 'loans'.tr(),
        icon: Icons.volunteer_activism_outlined,
        selectedIcon: Icons.volunteer_activism,
        widget: const LoansScreen(),
        roles: [UserRole.ADMIN, UserRole.FINANCE],
      ),
      _TabItem(
        label: 'expenses'.tr(),
        icon: Icons.money_off_outlined,
        selectedIcon: Icons.money_off,
        widget: const ExpensesScreen(),
        roles: [UserRole.ADMIN, UserRole.FINANCE],
      ),
      _TabItem(
        label: 'investors'.tr(),
        icon: Icons.group_work_outlined,
        selectedIcon: Icons.group_work,
        widget: const InvestorsScreen(),
        roles: [UserRole.ADMIN, UserRole.FINANCE],
      ),
      _TabItem(
        label: 'partners'.tr(),
        icon: Icons.people_outline,
        selectedIcon: Icons.people,
        widget: const PartnersScreen(),
        roles: [UserRole.ADMIN],
      ),
      _TabItem(
        label: 'users'.tr(),
        icon: Icons.people_outline,
        selectedIcon: Icons.people,
        widget: const UserManagementScreen(),
        roles: [UserRole.ADMIN],
      ),
      _TabItem(
        label: 'settings'.tr(),
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        widget: const SettingsScreen(),
        roles: [UserRole.ADMIN, UserRole.FINANCE, UserRole.COLLECTOR],
      ),
    ];

    final availableTabs = allTabs.where((t) => t.roles.contains(role)).toList();
    if (_idx >= availableTabs.length) _idx = 0;

    if (availableTabs.isEmpty) {
      return Scaffold(
        backgroundColor: AppTheme.scaffoldBg(context),
        body: Center(child: Text('No access for this role.', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 16))),
      );
    }

    final bool useMore = availableTabs.length > 4;

    Widget body;
    if (useMore && _idx == 3) {
      if (_moreIdx == null) {
        body = _MoreMenu(
          tabs: availableTabs.sublist(3),
          onSelect: (subIdx) => setState(() => _moreIdx = subIdx),
        );
      } else {
        final actualIdx = 3 + _moreIdx!;
        body = Column(
          children: [
            _buildMoreHeader(availableTabs[actualIdx].label),
            Expanded(child: availableTabs[actualIdx].widget),
          ],
        );
      }
    } else {
      body = availableTabs[_idx].widget;
    }

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
        child: body,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor(context).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppTheme.lineColor(context).withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: (AppTheme.isDark(context) ? Colors.black : const Color(0xFF8A6A3C)).withValues(alpha: 0.12),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: NavigationBar(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              indicatorColor: AppTheme.accent.withValues(alpha: 0.16),
              selectedIndex: _idx >= 3 ? 3 : _idx,
              onDestinationSelected: (i) {
                setState(() {
                  _idx = i;
                  if (i != 3) _moreIdx = null;
                });
              },
              labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: [
                ...availableTabs.take(useMore ? 3 : availableTabs.length).map(
                      (t) => NavigationDestination(
                        icon: Icon(t.icon),
                        selectedIcon: Icon(t.selectedIcon, color: AppTheme.accent),
                        label: t.label,
                      ),
                    ),
                if (useMore)
                  const NavigationDestination(
                    icon: Icon(Icons.grid_view_rounded),
                    selectedIcon: Icon(Icons.grid_view_rounded, color: AppTheme.accent),
                    label: 'More',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMoreHeader(String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 44, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.panelGradient(context),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(bottom: BorderSide(color: AppTheme.lineColor(context))),
      ),
      child: Row(
        children: [
          IconButton(icon: Icon(Icons.arrow_back, color: AppTheme.textMutedColor(context)), onPressed: () => setState(() => _moreIdx = null)),
          Text(title, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  double _calcTotalVfCash(AppProvider app) => app.mobileNumbers.fold<double>(0, (sum, n) => sum + n.currentBalance);
  double _calcTotalAssets(DistributionProvider dist, AppProvider app, {required bool includeUsdExchange}) =>
    dist.totalBankBalance +
    _calcTotalVfCash(app) +
    dist.totalRetailerDebt +
    dist.totalCollectorCash +
    (includeUsdExchange ? dist.totalUsdExchangeBalance : 0.0);
}

class _TabItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget widget;
  final List<UserRole> roles;
  _TabItem({required this.label, required this.icon, required this.selectedIcon, required this.widget, required this.roles});
}

class _Overview extends StatelessWidget {
  final double totalAssets;
  final double bankBalance;
  final double vfCash;
  final double vfDepositProfit;
  final double creditReturnProfit;
  final double instaPayProfit;
  final double retailerDebt;
  final double collectorCash;
  final double usdtBalance;
  final double transferFees;
  final double outstandingLoans;
  final double totalExpenses;
  final double totalInvestorCapital;
  final double totalInvestorProfitOwed;
  final double totalPartnerProfitOwed;
  final String userName;
  final bool canViewUsdExchange;

  const _Overview({
    required this.totalAssets,
    required this.bankBalance,
    required this.vfCash,
    required this.vfDepositProfit,
    required this.creditReturnProfit,
    required this.instaPayProfit,
    required this.retailerDebt,
    required this.collectorCash,
    required this.usdtBalance,
    required this.transferFees,
    required this.outstandingLoans,
    required this.totalExpenses,
    required this.totalInvestorCapital,
    required this.totalInvestorProfitOwed,
    required this.totalPartnerProfitOwed,
    required this.userName,
    required this.canViewUsdExchange,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.transparent,
            expandedHeight: 154,
            pinned: true,
            actions: [
              GestureDetector(
                onTap: () {
                  final isAr = context.locale.languageCode == 'ar';
                  context.setLocale(isAr ? const Locale('en') : const Locale('ar'));
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8, top: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.lineColor(context)),
                  ),
                  child: Text(
                    context.locale.languageCode == 'ar' ? 'EN' : 'Ø¹',
                    style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              IconButton(icon: Icon(Icons.logout, color: AppTheme.textMutedColor(context)), onPressed: () => context.read<AuthProvider>().signOut())
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(start: 20, bottom: 8),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('welcome_user'.tr(args: [userName]), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  const SizedBox(height: 2),
                  Text('business_overview'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: AppTheme.heroGradient(context),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(36),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accent.withValues(alpha: 0.3),
                        blurRadius: 32,
                        offset: const Offset(0, 16),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('total_capital'.tr(), style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                          GestureDetector(
                            onTap: () async {
                              final ctrl = TextEditingController();
                              final val = await showDialog<String>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: AppTheme.surfaceColor(context),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                                  title: Text('set_opening_capital'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('Enter the initial capital amount to begin profit calculation tracking.', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13)),
                                      const SizedBox(height: 20),
                                      TextField(
                                        controller: ctrl,
                                        keyboardType: TextInputType.number,
                                        style: TextStyle(color: AppTheme.textPrimaryColor(context)),
                                        decoration: InputDecoration(
                                          labelText: 'amount'.tr(),
                                          prefixText: 'EGP ',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text('cancel'.tr())),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
                                      onPressed: () => Navigator.pop(ctx, ctrl.text), 
                                      child: Text('confirm'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                                    ),
                                  ],
                                )
                              );
                              if (val != null && double.tryParse(val) != null) {
                                context.read<DistributionProvider>().setOpeningCapital(double.parse(val));
                              }
                            },
                            child: const Icon(Icons.edit, color: Colors.white54, size: 16),
                          )
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('${_f(totalAssets)} EGP', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                      const SizedBox(height: 12),
                      const Text('Premium snapshot of the operating loop across bank accounts, field operations, and inventory.', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Text('asset_breakdown'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 16),

                // ── Section 1: Capital Assets ─────────────────────────────────────
                const _SectionHeader(label: 'Capital Assets', icon: Icons.pie_chart_outline),
                const SizedBox(height: 12),
                _AssetCard(icon: Icons.account_balance, label: 'bank_accounts'.tr(), amount: bankBalance, color: AppTheme.infoColor(context)),
                _AssetCard(icon: Icons.phone_android, label: 'vf_cash'.tr(), amount: vfCash, color: AppTheme.positiveColor(context)),
                if (canViewUsdExchange)
                  _AssetCard(icon: Icons.currency_exchange, label: 'USD Exchange', amount: usdtBalance, color: AppTheme.warningColor(context), unit: 'USDT'),
                _AssetCard(icon: Icons.store, label: 'owed_by_retailers'.tr(), amount: retailerDebt, color: const Color(0xFFD9CB41)),
                _AssetCard(icon: Icons.delivery_dining, label: 'held_by_collectors'.tr(), amount: collectorCash, color: const Color(0xFF8E9BBA)),

                // ── Section 2: Non-Capital Profits ────────────────────────────────
                const SizedBox(height: 8),
                const _SectionHeader(label: 'Additional Profits (not in capital)', icon: Icons.trending_up, muted: true),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'These profits are already embedded in VF balances and excluded from the capital total to avoid double-counting.',
                    style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11, height: 1.5),
                  ),
                ),
                if (vfDepositProfit > 0)
                  _AssetCard(icon: Icons.phone_android, label: 'VF Deposit Profit', amount: vfDepositProfit, color: const Color(0xFF2A9D8F), muted: true),
                if (creditReturnProfit > 0)
                  _AssetCard(icon: Icons.keyboard_return, label: 'Retailer Return Profit', amount: creditReturnProfit, color: const Color(0xFF27AE60), muted: true),
                if (instaPayProfit > 0)
                  _AssetCard(icon: Icons.payment, label: 'InstaPay Dist Profit', amount: instaPayProfit, color: const Color(0xFF1B5E20), muted: true),
                
                // ── Section 3: Outside Loop Assets ────────────────────────────────
                if (outstandingLoans > 0) ...[
                  const SizedBox(height: 12),
                  const _SectionHeader(label: 'Pending / Outside Loop', icon: Icons.hourglass_bottom, muted: true),
                  const SizedBox(height: 8),
                  _AssetCard(icon: Icons.volunteer_activism_outlined, label: 'outstanding_loans'.tr(), amount: outstandingLoans, color: const Color(0xFFF4A261), muted: true),
                ],

                // ── Section 4: Liabilities & Funding ──────────────────────────────
                if (totalInvestorCapital > 0 || totalInvestorProfitOwed > 0) ...[
                  const SizedBox(height: 12),
                  const _SectionHeader(label: 'Liabilities & External Funding', icon: Icons.group_work_outlined, muted: true),
                  const SizedBox(height: 8),
                  if (totalInvestorCapital > 0)
                    _AssetCard(icon: Icons.account_balance_wallet, label: 'investor_capital'.tr(), amount: totalInvestorCapital, color: const Color(0xFFC8A96E), muted: true),
                  if (totalInvestorProfitOwed > 0)
                    _AssetCard(icon: Icons.money_off, label: 'investor_profit_owed'.tr(), amount: totalInvestorProfitOwed, color: const Color(0xFFE63946), muted: true),
                  if (totalPartnerProfitOwed > 0)
                    _AssetCard(icon: Icons.people_outline, label: 'partner_profit_owed'.tr(), amount: totalPartnerProfitOwed, color: const Color(0xFFE63946), muted: true),
                ],

                // ── Section 5: Expenses ───────────────────────────────────────────
                if (transferFees > 0 || totalExpenses > 0) ...[
                  const SizedBox(height: 12),
                  const _SectionHeader(label: 'Expenses', icon: Icons.money_off_outlined, muted: true),
                  const SizedBox(height: 8),
                  if (transferFees > 0)
                    _AssetCard(icon: Icons.money_off, label: 'VF Fees Paid', amount: transferFees, color: AppTheme.accent, muted: true),
                  if (totalExpenses > 0)
                    _AssetCard(icon: Icons.receipt_long, label: 'total_expenses'.tr(), amount: totalExpenses, color: const Color(0xFFE63946), muted: true),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  String _f(double v) => NumberFormat('#,##0.00', 'en_US').format(v);
}

class _AssetCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final double amount;
  final Color color;
  final String unit;
  final bool muted;

  const _AssetCard({required this.icon, required this.label, required this.amount, required this.color, this.unit = 'EGP', this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: muted ? 0.70 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: AppTheme.panelGradient(context),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: muted ? 0.10 : 0.15)),
          boxShadow: muted ? [] : AppTheme.softShadow(context),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13, fontWeight: FontWeight.w700))),
            Text('${_f(amount)} $unit', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  String _f(double v) => NumberFormat('#,##0.00', 'en_US').format(v);
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool muted;

  const _SectionHeader({required this.label, required this.icon, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final color = muted ? AppTheme.textMutedColor(context) : AppTheme.textPrimaryColor(context);
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: AppTheme.lineColor(context), thickness: 1)),
      ],
    );
  }
}

class _MoreMenu extends StatelessWidget {
  final List<_TabItem> tabs;
  final Function(int) onSelect;

  const _MoreMenu({required this.tabs, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('More Settings & Tools', style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 6),
                Text('A cleaner control room for finance and field operations.', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: tabs.length,
              itemBuilder: (context, i) {
                final t = tabs[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: AppTheme.panelGradient(context), begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.lineColor(context).withValues(alpha: 0.5)),
                    boxShadow: AppTheme.softShadow(context),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Icon(t.icon, color: AppTheme.accent, size: 22),
                    ),
                    title: Text(t.label, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w700, fontSize: 15)),
                    trailing: Icon(Icons.chevron_right, color: AppTheme.textMutedColor(context), size: 18),
                    onTap: () => onSelect(i),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
