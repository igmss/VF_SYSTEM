import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';
import 'add_number_screen.dart';
import 'number_details_screen.dart';

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
      await p.loadMobileNumbers();
      await p.loadAllTransactions();
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

    // Keep selected index in bounds
    if (_selectedIndex >= numbers.length && numbers.isNotEmpty) {
      _selectedIndex = numbers.length - 1;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Top App Bar ──────────────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              backgroundColor: const Color(0xFF16162A),
              elevation: 0,
              title: widget.embedded
                  ? null
                  : Text(
                      'vf_numbers'.tr(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
              centerTitle: true,
              actions: [
                _buildSyncIndicator(provider),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                  onPressed: _reload,
                ),
              ],
            ),

            // ── Content ──────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: provider.isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.only(top: 80),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : numbers.isEmpty
                      ? _buildEmptyState(context)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Swipeable Number Cards ────────────────────
                            _buildSwipeableCards(context, provider, numbers),
                            const SizedBox(height: 8),

                            // ── Dot Indicators ────────────────────────────
                            if (numbers.length > 1)
                              _buildDotIndicators(numbers.length),

                            const SizedBox(height: 28),

                            // ── Recent Transactions for Selected Number ───
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: _sectionHeader(
                                  'recent_activity'.tr()),
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                              child: _buildFilteredTransactions(
                                  context, provider, numbers),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddNumberScreen()),
        ),
        label: Text('add_number'.tr()),
        icon: const Icon(Icons.add),
        backgroundColor: const Color(0xFFE63946),
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
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: isDefault
                ? [const Color(0xFFE63946), const Color(0xFF9B1D25)]
                : [const Color(0xFF1E1E3A), const Color(0xFF16162A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: (isDefault
                      ? const Color(0xFFE63946)
                      : Colors.black)
                  .withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(
            color: isDefault
                ? Colors.white.withOpacity(0.15)
                : Colors.white.withOpacity(0.05),
            width: 1.5,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDefault ? Icons.star : Icons.phone_android,
                        color: isDefault ? Colors.amber : Colors.white70,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isDefault
                            ? 'primary_account'.tr()
                            : 'secondary_account'.tr(),
                        style: const TextStyle(
                          color: Colors.white70,
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
                            ? Colors.greenAccent
                            : const Color(0xFFFF6B6B),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'balance'.tr(),
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Phone Number ─────────────────────────────────────────────
            Text(
              number.phoneNumber,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),

            const SizedBox(height: 4),

            // ── Monthly Net ──────────────────────────────────────────────
            Text(
              '${net >= 0 ? "+" : ""}${net.toStringAsFixed(0)} EGP  ${'monthly_net_flow'.tr()}',
              style: TextStyle(
                color: net >= 0 ? Colors.greenAccent.withOpacity(0.8) : Colors.redAccent.withOpacity(0.8),
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
                    'intake_today'.tr(),
                    number.inDailyUsed,
                    number.inDailyLimit,
                    inPct,
                    Colors.greenAccent,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMiniProgress(
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
      String label, double used, double limit, double pct, Color color) {
    final remaining = (limit - used).clamp(0, double.infinity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.white54)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: pct.clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: Colors.white.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${remaining.toInt()} ${'left'.tr()}',
          style:
              TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
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
                ? const Color(0xFFE63946)
                : Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Section Header
  // ─────────────────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.white,
        letterSpacing: 0.5,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Filtered Transactions for Selected Number
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFilteredTransactions(
      BuildContext context, AppProvider provider, List<MobileNumber> numbers) {
    if (provider.transactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Text(
            'no_activity'.tr(),
            style: const TextStyle(color: Colors.white38),
          ),
        ),
      );
    }

    final selectedNumber =
        numbers.isNotEmpty ? numbers[_selectedIndex] : null;

    // Filter transactions: only VF AND for this number
    final filtered = provider.transactions.where((tx) {
      final pm = tx.paymentMethod.toLowerCase();
      final isVf = pm.contains('vodafone') || pm.contains('voda');
      if (!isVf) return false;
      if (selectedNumber == null) return true;
      return tx.phoneNumber == selectedNumber.phoneNumber;
    }).take(20).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Column(
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 48, color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 12),
              Text(
                'no_activity'.tr(),
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
              if (selectedNumber != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    selectedNumber.phoneNumber,
                    style: const TextStyle(color: Colors.white24, fontSize: 12),
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
        final color = isIncoming ? Colors.greenAccent : const Color(0xFFE63946);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF16162A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
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
                style: const TextStyle(fontSize: 11, color: Colors.white38),
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
                    color: tx.phoneNumber == null
                        ? Colors.orange
                        : Colors.white38,
                    fontWeight: tx.phoneNumber == null
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${tx.timestamp.day}/${tx.timestamp.month} '
                  '${tx.timestamp.hour}:${tx.timestamp.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 10, color: Colors.white24),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Sync Indicator (unchanged logic)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSyncIndicator(AppProvider provider) {
    return Row(
      children: [
        if (provider.isLiveSyncEnabled)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Icon(Icons.circle, color: Colors.greenAccent, size: 8),
          ),
        Text(
          provider.isLiveSyncEnabled ? 'LIVE' : 'AUTO',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: provider.isLiveSyncEnabled
                ? Colors.greenAccent
                : Colors.white54,
          ),
        ),
        Switch(
          value: provider.isLiveSyncEnabled,
          onChanged: (val) {
            if (provider.syncPassword != null && provider.syncPassword!.isNotEmpty) {
              _showPasswordDialog(context, provider, val);
            } else {
              provider.toggleLiveSync(val);
            }
          },
          activeColor: Colors.greenAccent,
          activeTrackColor: Colors.greenAccent.withOpacity(0.3),
        ),
      ],
    );
  }

  void _showPasswordDialog(BuildContext context, AppProvider provider, bool newValue) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16162A),
        title: Text(newValue ? 'Enable Live Sync?' : 'Disable Live Sync?',
            style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter protection password to continue:',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text == provider.syncPassword) {
                Navigator.pop(ctx);
                provider.toggleLiveSync(newValue);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Incorrect password'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE63946)),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Empty State
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 80),
          Icon(Icons.phone_android,
              size: 80, color: Colors.white.withOpacity(0.05)),
          const SizedBox(height: 16),
          Text('no_numbers'.tr(),
              style: const TextStyle(color: Colors.white70, fontSize: 18)),
          const SizedBox(height: 8),
          Text('add_to_start'.tr(),
              style: const TextStyle(color: Colors.white38, fontSize: 14)),
        ],
      ),
    );
  }
}
