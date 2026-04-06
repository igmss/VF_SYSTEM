import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'add_number_screen.dart';
import 'number_details_screen.dart';
import 'admin/vf_transfer_dialog.dart';

class HomeScreen extends StatefulWidget {
  final bool embedded;
  const HomeScreen({Key? key, this.embedded = false}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _reloading = false;
  final PageController _pageController = PageController();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload(silent: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload(silent: true);
  }

  Future<void> _reload({bool silent = false}) async {
    if (_reloading) return;
    setState(() => _reloading = true);
    try {
      final p = context.read<AppProvider>();
      await p.recalculateAllUsage();
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('success'.tr()),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final numbers = provider.mobileNumbers;
    final isDark = AppTheme.isDark(context);
    final textPrimary = AppTheme.textPrimaryColor(context);
    final textMuted = AppTheme.textMutedColor(context);

    // Keep selected index in bounds
    if (_selectedIndex >= numbers.length && numbers.isNotEmpty) {
      _selectedIndex = numbers.length - 1;
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
        child: Stack(
          children: [
            Positioned(
              top: -120,
              right: -80,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.glowColor(context),
                ),
              ),
            ),
            Positioned(
              top: 120,
              left: -80,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.secondaryGlowColor(context),
                ),
              ),
            ),
            RefreshIndicator(
              onRefresh: _reload,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    backgroundColor: AppTheme.scaffoldBg(context).withValues(alpha: isDark ? 0.78 : 0.92),
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    title: widget.embedded
                        ? null
                        : Text(
                            'vf_numbers'.tr(),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                    centerTitle: true,
                    actions: [
                      _buildSyncIndicator(provider),
                      IconButton(
                        icon: Icon(Icons.refresh, color: textMuted),
                        onPressed: _reloading ? null : _reload,
                      ),
                    ],
                  ),
                  SliverToBoxAdapter(
                    child: provider.isLoading
                        ? const Padding(
                            padding: EdgeInsets.only(top: 80),
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : numbers.isEmpty
                            ? _buildEmptyState(context)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                                    child: _buildHeroHeader(numbers.length),
                                  ),
                                  _buildSwipeableCards(context, provider, numbers),
                                  const SizedBox(height: 8),
                                  if (numbers.length > 1)
                                    _buildDotIndicators(numbers.length),
                                  const SizedBox(height: 28),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    child: _sectionHeader(context, 'recent_activity'.tr()),
                                  ),
                                  const SizedBox(height: 12),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                                    child: _buildFilteredTransactions(context, provider, numbers),
                                  ),
                                ],
                              ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'transfer_btn',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const VfTransferDialog(),
            ),
            label: Text('transfer_vf_balance'.tr()),
            icon: const Icon(Icons.sync_alt_rounded),
            backgroundColor: AppTheme.positiveColor(context),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'add_btn',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddNumberScreen()),
            ),
            label: Text('add_number'.tr()),
            icon: const Icon(Icons.add),
            backgroundColor: AppTheme.accent,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Swipeable Number Cards (PageView)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSwipeableCards(
      BuildContext context, AppProvider provider, List<MobileNumber> numbers) {
    return SizedBox(
      height: 260,
      child: PageView.builder(
        controller: _pageController,
        itemCount: numbers.length,
        onPageChanged: (index) {
          setState(() => _selectedIndex = index);
        },
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _buildNumberCard(context, provider, numbers[index]),
          );
        },
      ),
    );
  }

  Widget _buildNumberCard(
      BuildContext context, AppProvider provider, MobileNumber number) {
    final isDark = AppTheme.isDark(context);
    final textPrimary = AppTheme.textPrimaryColor(context);
    final textMuted = AppTheme.textMutedColor(context);
    final surface = AppTheme.surfaceColor(context);
    final raised = AppTheme.surfaceRaisedColor(context);
    final line = AppTheme.lineColor(context);
    final isDefault = number.isDefault;
    final net = number.inMonthlyUsed - number.outMonthlyUsed;
    final inPct = provider.getInDailyUsagePercentage(number);
    final outPct = provider.getOutDailyUsagePercentage(number);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NumberDetailsScreen(number: number)),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            colors: isDefault
                ? AppTheme.heroGradient(context)
                : [raised, surface],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: (isDefault ? AppTheme.accent : Colors.black)
                  .withValues(alpha: 0.26),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
          border: Border.all(
            color: isDefault
                ? Colors.white.withValues(alpha: 0.16)
                : line,
            width: 1.2,
          ),
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header Row ───────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Chip: primary / secondary
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : AppTheme.accent).withValues(alpha: isDark ? 0.10 : 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDefault ? Icons.star : Icons.phone_android,
                        color: isDefault ? AppTheme.gold : textMuted,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isDefault
                            ? 'primary_account'.tr()
                            : 'secondary_account'.tr(),
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Balance
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${number.currentBalance.toStringAsFixed(0)} EGP',
                      style: TextStyle(
                        color: number.currentBalance >= 0
                            ? AppTheme.positiveColor(context)
                            : const Color(0xFFFF8A80),
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    Text(
                      'balance'.tr(),
                      style: TextStyle(color: textMuted, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Phone Number ─────────────────────────────────────────────
            Text(
              number.phoneNumber,
              style: TextStyle(
                color: textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),

            const SizedBox(height: 4),

            // ── Monthly Net ──────────────────────────────────────────────
            Text(
              '${net >= 0 ? "+" : ""}${net.toStringAsFixed(0)} EGP  ${'monthly_net_flow'.tr()}',
              style: TextStyle(
                color: net >= 0
                    ? AppTheme.positiveColor(context).withValues(alpha: 0.90)
                    : Colors.redAccent.withValues(alpha: 0.84),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),

            const Spacer(),

            // ── Progress Bars ────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _buildMiniProgress(
                    context,
                    'intake_today'.tr(),
                    number.inDailyUsed,
                    number.inDailyLimit,
                    inPct,
                    AppTheme.positiveColor(context),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMiniProgress(
                    context,
                    'outtake_today'.tr(),
                    number.outDailyUsed,
                    number.outDailyLimit,
                    outPct,
                    const Color(0xFFE63946),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniProgress(
      BuildContext context, String label, double used, double limit, double pct, Color color) {
    final textMuted = AppTheme.textMutedColor(context);
    final remaining = (limit - used).clamp(0, double.infinity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: textMuted)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: pct.clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: AppTheme.lineColor(context).withValues(alpha: 0.4),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${remaining.toInt()} ${'left'.tr()}',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Dot Indicators
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDotIndicators(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == _selectedIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 20 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: active
                ? AppTheme.accent
                : AppTheme.lineColor(context).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Section Header
  // ─────────────────────────────────────────────────────────────────────────

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppTheme.textPrimaryColor(context),
        letterSpacing: 0.5,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Filtered Transactions for Selected Number
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFilteredTransactions(
      BuildContext context, AppProvider provider, List<MobileNumber> numbers) {
    final isDark = AppTheme.isDark(context);
    final textMuted = AppTheme.textMutedColor(context);
    final raised = AppTheme.surfaceRaisedColor(context);
    final line = AppTheme.lineColor(context);

    if (provider.transactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Text(
            'no_activity'.tr(),
            style: TextStyle(color: textMuted.withValues(alpha: 0.72)),
          ),
        ),
      );
    }

    final selectedNumber = numbers.isNotEmpty ? numbers[_selectedIndex] : null;

    final filtered = provider.transactions
        .where((tx) {
          final pm = tx.paymentMethod.toLowerCase();
          final isVf = pm.contains('vodafone') ||
              pm.contains('voda') ||
              pm.startsWith('vf') ||
              pm.contains(' vf');
          if (!isVf) return false;
          if (selectedNumber == null) return true;
          return tx.phoneNumber == selectedNumber.phoneNumber;
        })
        .take(20)
        .toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Column(
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 48, color: AppTheme.textMutedColor(context).withValues(alpha: 0.25)),
              const SizedBox(height: 12),
              Text(
                'no_activity'.tr(),
                style: TextStyle(color: textMuted.withValues(alpha: 0.72), fontSize: 14),
              ),
              if (selectedNumber != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    selectedNumber.phoneNumber,
                    style: TextStyle(color: textMuted.withValues(alpha: 0.55), fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final tx = filtered[index];
        final isIncoming = tx.side == 1;
        final color = isIncoming ? AppTheme.positiveColor(context) : const Color(0xFFE63946);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: raised.withValues(alpha: isDark ? 0.94 : 0.98),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: line),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
                color: color,
                size: 18,
              ),
            ),
            title: Text(
              '${isIncoming ? "+" : "-"}${tx.amount.toStringAsFixed(2)} ${tx.currency}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: color,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${tx.paymentMethod}  •  ${tx.bybitOrderId.length > 8 ? tx.bybitOrderId.substring(0, 8) : tx.bybitOrderId}...',
                style: TextStyle(fontSize: 11, color: textMuted.withValues(alpha: 0.72)),
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  tx.phoneNumber ?? 'unassigned'.tr(),
                  style: TextStyle(
                    fontSize: 11,
                    color: tx.phoneNumber == null ? Colors.orange : textMuted.withValues(alpha: 0.72),
                    fontWeight: tx.phoneNumber == null ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${tx.timestamp.day}/${tx.timestamp.month} '
                  '${tx.timestamp.hour}:${tx.timestamp.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 10, color: textMuted.withValues(alpha: 0.55)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Sync Indicator
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSyncIndicator(AppProvider provider) {
    final textMuted = AppTheme.textMutedColor(context);
    return Row(
      children: [
        if (provider.isLiveSyncEnabled)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(Icons.circle, color: AppTheme.positiveColor(context), size: 8),
          ),
        Text(
          provider.isLiveSyncEnabled ? 'LIVE' : 'AUTO',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: provider.isLiveSyncEnabled ? AppTheme.positiveColor(context) : textMuted,
          ),
        ),
        Switch(
          value: provider.isLiveSyncEnabled,
          onChanged: (val) => provider.toggleLiveSync(val),
          activeColor: AppTheme.positiveColor(context),
          activeTrackColor: AppTheme.positiveColor(context).withValues(alpha: 0.3),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Empty State
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    final textPrimary = AppTheme.textPrimaryColor(context);
    final textMuted = AppTheme.textMutedColor(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 80),
          Icon(Icons.phone_android,
              size: 80, color: AppTheme.textMutedColor(context).withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          Text('no_numbers'.tr(),
              style: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('add_to_start'.tr(), style: TextStyle(color: textMuted, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(int count) {
    final isDark = AppTheme.isDark(context);
    final surface = AppTheme.surfaceColor(context);
    final line = AppTheme.lineColor(context);
    final textPrimary = AppTheme.textPrimaryColor(context);
    final textMuted = AppTheme.textMutedColor(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface.withValues(alpha: isDark ? 0.82 : 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'vf_numbers'.tr(),
            style: TextStyle(
              color: textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$count active lines tracked with a clean live balance view.',
            style: TextStyle(
              color: textMuted,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
