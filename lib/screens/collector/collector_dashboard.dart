import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/auth_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../models/retailer.dart';
import '../../models/collector.dart';
import '../../models/bank_account.dart';
import '../../models/financial_transaction.dart';
import '../admin/retailer_details_screen.dart';

class CollectorDashboard extends StatefulWidget {
  const CollectorDashboard({Key? key}) : super(key: key);

  @override
  State<CollectorDashboard> createState() => _CollectorDashboardState();
}

class _CollectorDashboardState extends State<CollectorDashboard> {
  int _tab = 0;

  static const _bg = Color(0xFF0F0F1A);
  static const _card = Color(0xFF16162A);
  static const _accent = Color(0xFFE63946);
  static const _purple = Color(0xFFA78BFA);

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
      backgroundColor: _bg,
      body: SafeArea(
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
                  : _DepositTab(
                      collector: collector,
                      bankAccounts: dist.bankAccounts,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, AuthProvider auth, Collector? collector) {
    final cashOnHand = collector?.cashOnHand ?? 0;
    final cashLimit = collector?.cashLimit ?? 50000;
    final progress = cashLimit > 0 ? (cashOnHand / cashLimit).clamp(0.0, 1.0) : 0.0;
    final progressColor = progress > 0.85
        ? Colors.redAccent
        : progress > 0.6
            ? Colors.orange
            : const Color(0xFF4ADE80);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF16162A),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: _purple.withOpacity(0.15),
                child: const Icon(Icons.person, color: _purple),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.currentUser?.name ?? 'Collector',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 17),
                    ),
                    Text(
                      'collector_dashboard'.tr(),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Language toggle
              GestureDetector(
                onTap: () {
                  final isAr = context.locale.languageCode == 'ar';
                  context.setLocale(
                      isAr ? const Locale('en') : const Locale('ar'));
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                        fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white54),
                onPressed: () => context.read<AuthProvider>().signOut(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Cash on hand card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_purple.withOpacity(0.25), _purple.withOpacity(0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _purple.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('cash_on_hand'.tr(),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                    Text(
                      '${cashOnHand.toStringAsFixed(0)} / ${cashLimit.toStringAsFixed(0)} EGP',
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
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(progressColor),
                    minHeight: 8,
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
        ],
      ),
    );
  }
}

// ─── Retailers Tab ────────────────────────────────────────────────────────────

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
            const Icon(Icons.store_outlined, color: Colors.white24, size: 56),
            const SizedBox(height: 14),
            Text('no_assigned_retailers'.tr(),
                style: const TextStyle(color: Colors.white38, fontSize: 15)),
            const SizedBox(height: 8),
            Text('contact_admin_to_assign'.tr(),
                style: const TextStyle(color: Colors.white24, fontSize: 12)),
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
    final debt = retailer.pendingDebt;
    final debtColor = debt > 0 ? const Color(0xFFFBBF24) : const Color(0xFF4ADE80);

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RetailerDetailsScreen(retailer: retailer),
        ),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF16162A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: debtColor.withOpacity(0.2)),
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
                    color: debtColor.withOpacity(0.1),
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
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      Text(retailer.area.isEmpty ? retailer.phone : '${retailer.area} • ${retailer.phone}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatColumn('total_assigned'.tr(), retailer.totalAssigned, Colors.white70),
                  Container(width: 1, height: 30, color: Colors.white12),
                  _buildStatColumn('collected'.tr(), retailer.totalCollected, const Color(0xFF4ADE80)),
                  Container(width: 1, height: 30, color: Colors.white12),
                  _buildStatColumn('pending'.tr(), debt, debtColor),
                ],
              ),
            ),
            if (debt > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.payments_outlined, size: 16),
                  label: Text('collect_from'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA78BFA),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () =>
                      _showCollectDialog(context, retailer, collector),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF4ADE80), size: 16),
                    const SizedBox(width: 6),
                    Text('fully_collected'.tr(),
                        style: const TextStyle(
                            color: Color(0xFF4ADE80), fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),);
  }

  Widget _buildStatColumn(String label, double amount, Color color) {
    return Column(
      children: [
        Text(
          '${amount.toStringAsFixed(0)} EGP',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
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
        SnackBar(
            content: Text('no_collector_record'.tr()),
            backgroundColor: Colors.red),
      );
      return;
    }
    final ctrl = TextEditingController(
        text: retailer.pendingDebt.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16162A),
        title: Text(
          '${'collect_from'.tr()} ${retailer.name}',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${'pending_debt'.tr()}: ${retailer.pendingDebt.toStringAsFixed(0)} EGP',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'amount'.tr(),
                labelStyle: const TextStyle(color: Colors.white54),
                suffixText: 'EGP',
                suffixStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('cancel'.tr(),
                style: const TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(ctrl.text) ?? 0;
              if (amount <= 0 || amount > (retailer.pendingDebt + 0.5).ceilToDouble()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('invalid_amount'.tr()),
                      backgroundColor: Colors.red),
                );
                return;
              }
              // Confirmation Dialog
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF16162A),
                  title: const Text('Confirm Action', style: TextStyle(color: Colors.white)),
                  content: Text(
                    'Are you sure you collected ${amount.toStringAsFixed(0)} EGP from ${retailer.name}?',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA78BFA)),
                      child: const Text('Confirm', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );

              if (confirm != true) return;

              final auth = context.read<AuthProvider>();
              try {
                await context.read<DistributionProvider>().collectFromRetailer(
                      collectorId: collector.id,
                      retailerId: retailer.id,
                      amount: amount,
                      createdByUid: auth.currentUser?.uid ?? '',
                    );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('collect_success'.tr())),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA78BFA)),
            child: Text('collect'.tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ─── Deposit Tab ──────────────────────────────────────────────────────────────

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

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collector = widget.collector;
    final cashOnHand = collector?.cashOnHand ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cash available
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF16162A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF4ADE80).withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet,
                    color: Color(0xFF4ADE80)),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('cash_on_hand'.tr(),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                    Text(
                      '${cashOnHand.toStringAsFixed(0)} EGP',
                      style: const TextStyle(
                          color: Color(0xFF4ADE80),
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('select_bank'.tr(),
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (widget.bankAccounts.isEmpty)
            Text('no_bank_accounts'.tr(),
                style: const TextStyle(color: Colors.white38))
          else
            ...widget.bankAccounts.map((b) => _BankOption(
                  bank: b,
                  selected: _selectedBank?.id == b.id,
                  onTap: () => setState(() => _selectedBank = b),
                )),
          const SizedBox(height: 20),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'deposit_amount'.tr(),
              labelStyle: const TextStyle(color: Colors.white54),
              suffixText: 'EGP',
              suffixStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.upload_rounded),
              label: Text('deposit_to_bank'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CC9F0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: collector == null ? null : _doDeposit,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _doDeposit() async {
    final collector = widget.collector!;
    final bank = _selectedBank;
    final amount = double.tryParse(_amountCtrl.text) ?? 0;

    if (bank == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('select_bank_first'.tr())),
      );
      return;
    }
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('invalid_amount'.tr()),
            backgroundColor: Colors.red),
      );
      return;
    }
    if (amount > collector.cashOnHand) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('deposit_exceeds_cash'.tr(
              args: [collector.cashOnHand.toStringAsFixed(0)]
            )),
            backgroundColor: Colors.orange),
      );
      return;
    }

    // Confirmation Dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16162A),
        title: const Text('Confirm Action', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to deposit ${amount.toStringAsFixed(0)} EGP to ${bank.bankName}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CC9F0)),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final auth = context.read<AuthProvider>();
      await context.read<DistributionProvider>().depositToBank(
            collectorId: collector.id,
            bankAccountId: bank.id,
            amount: amount,
            createdByUid: auth.currentUser?.uid ?? '',
          );
      _amountCtrl.clear();
      setState(() => _selectedBank = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('deposit_success'.tr())),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

class _BankOption extends StatelessWidget {
  final BankAccount bank;
  final bool selected;
  final VoidCallback onTap;

  const _BankOption(
      {required this.bank, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF4CC9F0).withOpacity(0.1)
              : const Color(0xFF16162A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? const Color(0xFF4CC9F0)
                : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.account_balance,
                color: selected
                    ? const Color(0xFF4CC9F0)
                    : Colors.white54,
                size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(bank.bankName,
                  style: TextStyle(
                      color: selected ? const Color(0xFF4CC9F0) : Colors.white70,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal)),
            ),
            // Bank balance intentionally hidden from collectors
            if (selected) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle,
                  color: Color(0xFF4CC9F0), size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Tab chip ────────────────────────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFA78BFA);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.15) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: selected ? accent : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? accent : Colors.white54),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(
                    color: selected ? accent : Colors.white54,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
