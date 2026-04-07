import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/auth_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../models/bank_account.dart';
import '../../models/financial_transaction.dart';

part 'bank_account_card.dart';
part 'bank_account_dialogs.dart';


// ─── Palette ──────────────────────────────────────────────────────────────────
const _kBlue    = Color(0xFF4CC9F0);
const _kGreen   = Color(0xFF4ADE80);
const _kRed     = Color(0xFFE63946);


class BankAccountsScreen extends StatefulWidget {
  const BankAccountsScreen({Key? key}) : super(key: key);

  @override
  State<BankAccountsScreen> createState() => _BankAccountsScreenState();
}

class _BankAccountsScreenState extends State<BankAccountsScreen> {
  final PageController _pageCtrl = PageController();
  int _selectedIndex = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    final auth = context.watch<AuthProvider>();
    final accounts = dist.bankAccounts;

    // Keep index in bounds
    if (_selectedIndex >= accounts.length && accounts.isNotEmpty) {
      _selectedIndex = accounts.length - 1;
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── Top AppBar ───────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTheme.surfaceColor(context),
            iconTheme: IconThemeData(color: AppTheme.textPrimaryColor(context)),
            title: Text(
              'bank_accounts'.tr(),
              style: TextStyle(
                  color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold, fontSize: 16),
            ),
            centerTitle: true,
            actions: [
              if (auth.isAdmin)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _PremiumButton(
                    icon: Icons.add_rounded,
                    label: 'add_bank_account'.tr(),
                    onTap: () => _showAddDialog(context),
                  ),
                ),
            ],
          ),

          // ── Body ────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: dist.isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 120),
                      child: CircularProgressIndicator(color: _kBlue),
                    ),
                  )
                : accounts.isEmpty
                    ? _buildEmpty(context, auth)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),

                          // ── Total Banner ─────────────────────────────
                          _buildTotalBanner(context, dist.totalBankBalance, accounts.length),

                          const SizedBox(height: 20),

                          // ── Swipeable Bank Cards ─────────────────────
                          _buildPageView(context, dist, auth, accounts),

                          const SizedBox(height: 10),

                          // ── Dot Indicators ───────────────────────────
                          if (accounts.length > 1)
                            _buildDots(context, accounts.length),

                          const SizedBox(height: 28),

                          // ── Activity for selected bank ───────────────
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: _buildActivityHeader(context, accounts.isNotEmpty ? accounts[_selectedIndex] : null, dist),
                          ),
                          const SizedBox(height: 12),

                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                            child: _buildActivityList(context, dist, accounts),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Total Banner
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTotalBanner(BuildContext context, double total, int count) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: AppTheme.isDark(context)
                ? [const Color(0xFF0D2137), const Color(0xFF0A1628)]
                : [const Color(0xFFDCEEF9), const Color(0xFFEBF5FC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _kBlue.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
                color: _kBlue.withOpacity(AppTheme.isDark(context) ? 0.15 : 0.10),
                blurRadius: 20,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kBlue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.account_balance_rounded,
                  color: _kBlue, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'total_bank_balance'.tr(),
                    style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${fmt.format(total)} EGP',
                    style: TextStyle(
                      color: AppTheme.textPrimaryColor(context),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _kGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count ${'bank_accounts'.tr()}',
                style: const TextStyle(
                    color: _kGreen, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  PageView of Bank Cards
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPageView(BuildContext context, DistributionProvider dist,
      AuthProvider auth, List<BankAccount> accounts) {
    return SizedBox(
      height: 240,
      child: PageView.builder(
        controller: _pageCtrl,
        itemCount: accounts.length,
        onPageChanged: (i) => setState(() => _selectedIndex = i),
        itemBuilder: (ctx, i) {
          final b = accounts[i];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _BankSwipeCard(
              account: b,
              isAdmin: auth.isAdmin,
              onFund: () => _showFundDialog(context, b, dist, auth),
              onCorrect: () => _showCorrectBalanceDialog(context, b, dist, auth),
              onDelete: () => dist.deleteBankAccount(b.id),
              onSetDefault: () => dist.setDefaultBuyBank(b.id),
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Dot Indicators
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDots(BuildContext context, int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == _selectedIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: active ? _kBlue : AppTheme.textPrimaryColor(context).withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Activity Section Header
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildActivityHeader(BuildContext context, BankAccount? bank, DistributionProvider dist) {
    // filter count for this bank
    final bankId = bank?.id;
    final count = bankId == null
        ? 0
        : dist.ledger
            .where((tx) =>
                tx.fromId == bankId || tx.toId == bankId)
            .length;

    return Row(
      children: [
        Container(
          width: 3,
          height: 20,
          decoration: BoxDecoration(
            color: _kBlue,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'recent_activity'.tr(),
                style: TextStyle(
                  color: AppTheme.textPrimaryColor(context),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (bank != null)
                Text(
                  bank.bankName,
                  style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _kBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${count > 20 ? "20+" : count}',
            style: const TextStyle(
                color: _kBlue, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Per-bank Filtered Transaction List
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildActivityList(
      BuildContext context, DistributionProvider dist, List<BankAccount> accounts) {
    if (accounts.isEmpty) return const SizedBox.shrink();
    final bank = accounts[_selectedIndex];

    // Filter ledger to transactions involving this bank only
    final txs = dist.ledger
        .where((tx) => tx.fromId == bank.id || tx.toId == bank.id)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final display = txs.take(20).toList();

    if (display.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Column(
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 48, color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.08)),
              const SizedBox(height: 12),
              Text(
                'no_activity'.tr(),
                style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                bank.bankName,
                style: TextStyle(color: AppTheme.textMutedColor(context).withValues(alpha: 0.6), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: display.length,
      itemBuilder: (_, i) => _buildTxRow(context, display[i]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Transaction Row  (logic unchanged)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTxRow(BuildContext context, FinancialTransaction tx) {
    final isOut = tx.type == FlowType.BUY_USDT;
    final color = isOut ? _kRed : _kGreen;
    final icon  = isOut ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;

    String label = tx.type.label.tr();
    if (tx.type == FlowType.FUND_BANK || tx.type == FlowType.DEPOSIT_TO_BANK) {
      if (tx.fromLabel != null && tx.fromLabel!.isNotEmpty) {
        label = '${tx.type.label.tr()} from ${tx.fromLabel} (${tx.toLabel})';
      } else {
        label = '${tx.type.label.tr()} (${tx.toLabel})';
      }
    } else if (tx.type == FlowType.BUY_USDT) {
      label = 'Buy USDT (${tx.fromLabel})';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: AppTheme.textPrimaryColor(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(tx.timestamp),
                    style:
                        TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isOut ? "-" : "+"}${NumberFormat("#,##0.00", "en_US").format(tx.amount)} EGP',
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
                if (tx.usdtQuantity != null && tx.usdtQuantity! > 0)
                  Text(
                    '${tx.usdtQuantity!.toStringAsFixed(2)} USDT',
                    style:
                        TextStyle(color: AppTheme.textMutedColor(context), fontSize: 10),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Empty State
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEmpty(BuildContext context, AuthProvider auth) {
    return Padding(
      padding: const EdgeInsets.only(top: 120),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: _kBlue.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.account_balance_outlined,
                  size: 56, color: _kBlue),
            ),
            const SizedBox(height: 20),
            Text('no_data'.tr(),
                style: TextStyle(
                    color: AppTheme.textMutedColor(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            if (auth.isAdmin)
              TextButton.icon(
                onPressed: () => _showAddDialog(context),
                icon: const Icon(Icons.add, color: _kBlue),
                label: Text('add_bank_account'.tr(),
                    style: const TextStyle(color: _kBlue)),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Dialogs — 100% unchanged logic
  // ─────────────────────────────────────────────────────────────────────────


}



// ─── Top-right Add Button ─────────────────────────────────────────────────────

class _PremiumButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PremiumButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _kRed,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _kRed.withOpacity(0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.textPrimaryColor(context), size: 16),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: AppTheme.textPrimaryColor(context),
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}


