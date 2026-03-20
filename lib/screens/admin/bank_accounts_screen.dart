import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/auth_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../models/bank_account.dart';
import '../../models/financial_transaction.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────
const _kBlue    = Color(0xFF4CC9F0);
const _kGreen   = Color(0xFF4ADE80);
const _kRed     = Color(0xFFE63946);
const _kBg      = Color(0xFF0F0F1A);
const _kSurface = Color(0xFF16162A);
const _kSurface2 = Color(0xFF1E1E3A);

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
      backgroundColor: _kBg,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── Top AppBar ───────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: _kSurface,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              'bank_accounts'.tr(),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
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
                          _buildTotalBanner(dist.totalBankBalance, accounts.length),

                          const SizedBox(height: 20),

                          // ── Swipeable Bank Cards ─────────────────────
                          _buildPageView(context, dist, auth, accounts),

                          const SizedBox(height: 10),

                          // ── Dot Indicators ───────────────────────────
                          if (accounts.length > 1)
                            _buildDots(accounts.length),

                          const SizedBox(height: 28),

                          // ── Activity for selected bank ───────────────
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: _buildActivityHeader(
                                accounts.isNotEmpty ? accounts[_selectedIndex] : null,
                                dist),
                          ),
                          const SizedBox(height: 12),

                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                            child: _buildActivityList(dist, accounts),
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

  Widget _buildTotalBanner(double total, int count) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0D2137), Color(0xFF0A1628)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _kBlue.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
                color: _kBlue.withOpacity(0.15),
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
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${fmt.format(total)} EGP',
                    style: const TextStyle(
                      color: Colors.white,
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

  Widget _buildDots(int count) {
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
            color: active ? _kBlue : Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Activity Section Header
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildActivityHeader(BankAccount? bank, DistributionProvider dist) {
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (bank != null)
                Text(
                  bank.bankName,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
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
      DistributionProvider dist, List<BankAccount> accounts) {
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
                  size: 48, color: Colors.white.withOpacity(0.08)),
              const SizedBox(height: 12),
              Text(
                'no_activity'.tr(),
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                bank.bankName,
                style: const TextStyle(color: Colors.white24, fontSize: 12),
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
      itemBuilder: (_, i) => _buildTxRow(display[i]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Transaction Row  (logic unchanged)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTxRow(FinancialTransaction tx) {
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
        color: _kSurface,
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
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(tx.timestamp),
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11),
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
                        const TextStyle(color: Colors.white38, fontSize: 10),
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
                style: const TextStyle(
                    color: Colors.white60,
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

  void _showAddDialog(BuildContext context) {
    final nameCtrl   = TextEditingController();
    final holderCtrl = TextEditingController();
    final numCtrl    = TextEditingController();
    final balCtrl    = TextEditingController(text: '0');
    showDialog(
      context: context,
      builder: (_) => _FormDialog(
        title: 'add_bank_account'.tr(),
        fields: [
          _tf(nameCtrl,   'bank_name'.tr(),       Icons.business),
          _tf(holderCtrl, 'account_holder'.tr(),  Icons.person),
          _tf(numCtrl,    'account_number'.tr(),  Icons.credit_card),
          _tf(balCtrl,    'opening_balance'.tr(), Icons.monetization_on,
              keyboard: TextInputType.number),
        ],
        onConfirm: () {
          final uid = context.read<AuthProvider>().currentUser?.uid ?? 'system';
          context.read<DistributionProvider>().addBankAccount(
                BankAccount(
                  bankName: nameCtrl.text.trim(),
                  accountHolder: holderCtrl.text.trim(),
                  accountNumber: numCtrl.text.trim(),
                  balance: double.tryParse(balCtrl.text) ?? 0,
                ),
                createdByUid: uid,
              );
        },
      ),
    );
  }

  void _showFundDialog(BuildContext context, BankAccount bank,
      DistributionProvider dist, AuthProvider auth) {
    final amtCtrl   = TextEditingController();
    final notesCtrl = TextEditingController();
    final fmt = NumberFormat('#,##0.00', 'en_US');

    showDialog(
      context: context,
      builder: (_) => _FormDialog(
        title: 'fund_bank_account'.tr(args: [bank.bankName]),
        fields: [
          _tf(amtCtrl,   'amount_egp'.tr(), Icons.monetization_on,
              keyboard: TextInputType.number),
          _tf(notesCtrl, 'notes'.tr(),      Icons.notes),
        ],
        // Step 1 done — now show confirm dialog before touching data
        onConfirm: () {
          final amount = double.tryParse(amtCtrl.text) ?? 0;
          final notes  = notesCtrl.text.isEmpty ? null : notesCtrl.text;
          if (amount <= 0) return; // guard: nothing to confirm

          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF16162A),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: [
                  const Icon(Icons.verified_outlined,
                      color: _kGreen, size: 20),
                  const SizedBox(width: 8),
                  Text('confirm_fund'.tr(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Summary card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _kGreen.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kGreen.withOpacity(0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bank.bankName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        const SizedBox(height: 4),
                        Text(bank.accountNumber,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11)),
                        const Divider(color: Colors.white12, height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Adding',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 13)),
                            Text('+ ${fmt.format(amount)} EGP',
                                style: const TextStyle(
                                    color: _kGreen,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18)),
                          ],
                        ),
                        if (notes != null) ...[
                          const SizedBox(height: 6),
                          Text(notes,
                              style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic)),
                        ],
                        const Divider(color: Colors.white12, height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('New Balance',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                            Text(
                              '${fmt.format(bank.balance + amount)} EGP',
                              style: const TextStyle(
                                  color: _kBlue,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This action will be recorded in the ledger and cannot be reversed.',
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('cancel'.tr(),
                      style: const TextStyle(color: Colors.white38)),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 16),
                  label: Text('confirm'.tr(),
                      style: const TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    Navigator.pop(context); // close confirm dialog
                    // ── The only place fundBankAccount is called ──────────
                    dist.fundBankAccount(
                      bankAccountId: bank.id,
                      amount: amount,
                      createdByUid: auth.currentUser?.uid ?? 'system',
                      notes: notes,
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCorrectBalanceDialog(BuildContext context, BankAccount bank,
      DistributionProvider dist, AuthProvider auth) {
    final balCtrl = TextEditingController(text: bank.balance.toStringAsFixed(2));
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => _FormDialog(
        title: context.locale.languageCode == 'ar' ? 'تصحيح رصيد ${bank.bankName}' : 'Correct ${bank.bankName} Balance',
        fields: [
          _tf(balCtrl, context.locale.languageCode == 'ar' ? 'الرصيد الجديد' : 'New Balance', Icons.account_balance_wallet,
              keyboard: const TextInputType.numberWithOptions(decimal: true)),
          _tf(notesCtrl, 'notes'.tr(), Icons.notes),
        ],
        onConfirm: () {
          final newBal = double.tryParse(balCtrl.text) ?? bank.balance;
          dist.correctBankBalance(
            bankAccountId: bank.id,
            newBalance: newBal,
            createdByUid: auth.currentUser?.uid ?? 'system',
            notes: notesCtrl.text.isEmpty ? 'Manual Balance Correction' : notesCtrl.text,
          );
        },
      ),
    );
  }

  static Widget _tf(TextEditingController c, String label, IconData icon,
          {TextInputType keyboard = TextInputType.text}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white54),
            prefixIcon: Icon(icon, color: Colors.white38, size: 20),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kRed)),
          ),
        ),
      );
}

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
              ? [const Color(0xFF0D2137), const Color(0xFF0A1628)]
              : [_kSurface2, _kSurface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: isDefault
              ? _kBlue.withOpacity(0.45)
              : Colors.white.withOpacity(0.06),
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
                            style: const TextStyle(
                              color: Colors.white,
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
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          Container(height: 1, color: Colors.white.withOpacity(0.05)),
          const SizedBox(height: 14),

          // ── Balance + Account Number ───────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('BALANCE',
                      style: TextStyle(
                          color: Colors.white38,
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
                  const Text('ACCOUNT',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(
                    account.accountNumber,
                    style: const TextStyle(
                        color: Colors.white60,
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
                      backgroundColor: _kSurface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                      title: Text('delete_confirm'.tr(),
                          style: const TextStyle(color: Colors.white)),
                      content: Text('delete_msg'.tr(),
                          style: const TextStyle(color: Colors.white54)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('cancel'.tr(),
                              style: const TextStyle(color: Colors.white38)),
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
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reusable Form Dialog — unchanged from original
// ─────────────────────────────────────────────────────────────────────────────

class _FormDialog extends StatelessWidget {
  final String title;
  final List<Widget> fields;
  final VoidCallback onConfirm;

  const _FormDialog({
    required this.title,
    required this.fields,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const SizedBox(height: 18),
            ...fields,
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('cancel'.tr(),
                      style: const TextStyle(color: Colors.white38)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    onConfirm();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kRed,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('save'.tr(),
                      style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
