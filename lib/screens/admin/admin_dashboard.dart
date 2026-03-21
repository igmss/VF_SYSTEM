import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/auth_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../providers/app_provider.dart';
import '../../models/app_user.dart';
import '../home_screen.dart';
import '../settings_screen.dart';
import 'bank_accounts_screen.dart';
import 'retailers_screen.dart';
import 'collectors_screen.dart';
import 'ledger_screen.dart';
import 'user_management_screen.dart';
import 'usd_exchange_screen.dart';
import 'exchange_rate_screen.dart';


class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _idx = 0;
  int? _moreIdx; // Index for sub-tabs within the "More" menu

  static const _darkBg = Color(0xFF0F0F1A);
  static const _accent = Color(0xFFE63946);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DistributionProvider>().loadAll();
      context.read<AppProvider>().loadMobileNumbers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final dist = context.watch<DistributionProvider>();
    final app  = context.watch<AppProvider>();
    final role = auth.currentUser?.role ?? UserRole.OPERATOR;

    // --- Tab Configuration ---
    final allTabs = <_TabItem>[
      _TabItem(
        label: 'overview'.tr(),
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        widget: _Overview(
          totalAssets: _calcTotalAssets(dist, app),
          bankBalance: dist.totalBankBalance,
          vfCash: _calcTotalVfCash(app),
          retailerDebt: dist.totalRetailerDebt,
          collectorCash: dist.totalCollectorCash,
          usdtBalance: dist.usdtBalance,
          transferFees: dist.totalTransferFees,
          userName: auth.currentUser?.name ?? 'Admin',
        ),
        roles: [UserRole.ADMIN, UserRole.FINANCE, UserRole.COLLECTOR],
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

    // Guard: no tabs are configured for this role
    if (availableTabs.isEmpty) {
      return Scaffold(
        backgroundColor: _darkBg,
        body: Center(
          child: Text(
            'No access for this role.',
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ),
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
      backgroundColor: _darkBg,
      body: body,
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF16162A),
        indicatorColor: _accent.withOpacity(0.2),
        selectedIndex: _idx >= 3 ? 3 : _idx,
        onDestinationSelected: (i) {
          setState(() {
            _idx = i;
            if (i != 3) _moreIdx = null;
          });
        },
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: [
          ...availableTabs.take(useMore ? 3 : availableTabs.length).map((t) => NavigationDestination(
                icon: Icon(t.icon),
                selectedIcon: Icon(t.selectedIcon, color: _accent),
                label: t.label,
              )),
          if (useMore)
            const NavigationDestination(
              icon: Icon(Icons.more_horiz_outlined),
              selectedIcon: Icon(Icons.more_horiz, color: _accent),
              label: 'More',
            ),
        ],
      ),
    );
  }

  Widget _buildMoreHeader(String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 40, 16, 8),
      color: const Color(0xFF16162A),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            onPressed: () => setState(() => _moreIdx = null),
          ),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  double _calcTotalVfCash(AppProvider app) => app.mobileNumbers.fold<double>(0, (sum, n) => sum + n.currentBalance);
  double _calcTotalAssets(DistributionProvider dist, AppProvider app) => 
    dist.totalBankBalance + _calcTotalVfCash(app) + dist.totalRetailerDebt + dist.totalCollectorCash + dist.totalUsdExchangeBalance + dist.totalTransferFees;
}

class _TabItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget widget;
  final List<UserRole> roles;
  _TabItem({required this.label, required this.icon, required this.selectedIcon, required this.widget, required this.roles});
}

// ─── Overview Tab ──────────────────────────────────────────────────────────

class _Overview extends StatelessWidget {
  final double totalAssets;
  final double bankBalance;
  final double vfCash;
  final double retailerDebt;
  final double collectorCash;
  final double usdtBalance;
  final double transferFees;
  final String userName;

  const _Overview({
    required this.totalAssets,
    required this.bankBalance,
    required this.vfCash,
    required this.retailerDebt,
    required this.collectorCash,
    required this.usdtBalance,
    required this.transferFees,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: const Color(0xFF0F0F1A),
            expandedHeight: 130,
            pinned: true,
            actions: [
              // Language toggle
              GestureDetector(
                onTap: () {
                  final isAr = context.locale.languageCode == 'ar';
                  context.setLocale(isAr ? const Locale('en') : const Locale('ar'));
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    context.locale.languageCode == 'ar' ? 'EN' : 'ع',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white70),
                onPressed: () => context.read<AuthProvider>().signOut(),
              )
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(start: 20, bottom: 14),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('welcome_user'.tr(args: [userName]),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  Text('business_overview'.tr(),
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Total Assets Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE63946), Color(0xFFFF6B6B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE63946).withOpacity(0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('total_capital'.tr(),
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 6),
                      Text(
                        '${_fmt(totalAssets)} EGP',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('asset_breakdown'.tr(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _AssetCard(
                  icon: Icons.account_balance,
                  label: 'bank_accounts'.tr(),
                  amount: bankBalance,
                  color: const Color(0xFF4CC9F0),
                ),
                _AssetCard(
                  icon: Icons.phone_android,
                  label: 'vf_cash'.tr(),
                  amount: vfCash,
                  color: const Color(0xFF4ADE80),
                ),
                _AssetCard(
                  icon: Icons.currency_exchange,
                  label: 'USD Exchange',
                  amount: usdtBalance,
                  color: const Color(0xFFF59E0B),
                  unit: 'USDT',
                ),
                _AssetCard(
                  icon: Icons.store,
                  label: 'owed_by_retailers'.tr(),
                  amount: retailerDebt,
                  color: const Color(0xFFFBBF24),
                ),
                _AssetCard(
                  icon: Icons.delivery_dining,
                  label: 'held_by_collectors'.tr(),
                  amount: collectorCash,
                  color: const Color(0xFFA78BFA),
                ),
                if (transferFees > 0)
                  _AssetCard(
                    icon: Icons.money_off,
                    label: 'Vodafone Fees Paid',
                    amount: transferFees,
                    color: const Color(0xFFFF9800),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    return NumberFormat('#,##0.00', 'en_US').format(v);
  }
}

class _AssetCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final double amount;
  final Color color;
  final String unit;

  const _AssetCard({
    required this.icon,
    required this.label,
    required this.amount,
    required this.color,
    this.unit = 'EGP',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ),
          Text(
            '${_f(amount)} EGP',
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
    );
  }

  String _f(double v) {
    return NumberFormat('#,##0.00', 'en_US').format(v);
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
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Text(
              'More Settings & Tools',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: tabs.length,
              itemBuilder: (context, i) {
                final t = tabs[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16162A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(t.icon, color: Colors.white70, size: 20),
                    ),
                    title: Text(t.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white24),
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
