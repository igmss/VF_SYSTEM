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

part 'collector_retailers_tab.dart';
part 'collector_deposit_tab.dart';
part 'collector_history_tab.dart';

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

