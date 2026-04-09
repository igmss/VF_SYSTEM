import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/auth_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../providers/app_provider.dart';
import '../../models/financial_transaction.dart';
import '../../theme/app_theme.dart';

/// Available expense categories (value → localization key).
const _kCategories = [
  ('rent', 'category_rent'),
  ('salaries', 'category_salaries'),
  ('transport', 'category_transport'),
  ('utilities', 'category_utilities'),
  ('other', 'category_other'),
];

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dist = context.watch<DistributionProvider>();
    final auth = context.watch<AuthProvider>();
    final expenses = dist.expenseLedger;
    final fmt = NumberFormat('#,##0.00', 'en_US');
    final dateFmt = DateFormat('dd MMM yyyy, HH:mm');

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      body: Column(
        children: [
          // ── Summary card ────────────────────────────────────────────────
          _SummaryCard(total: dist.totalExpenses, count: expenses.length),

          // ── Expense list ────────────────────────────────────────────────
          Expanded(
            child: expenses.isEmpty
                ? _empty(context)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                    physics: const BouncingScrollPhysics(),
                    itemCount: expenses.length,
                    itemBuilder: (ctx, i) =>
                        _ExpenseTile(tx: expenses[i], fmt: fmt, dateFmt: dateFmt),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRecordExpenseSheet(context, dist, auth),
        backgroundColor: const Color(0xFFE63946),
        icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
        label: Text('record_expense'.tr(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.money_off_outlined,
                size: 64,
                color: AppTheme.textMutedColor(context).withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('no_data'.tr(),
                style: TextStyle(
                    color: AppTheme.textMutedColor(context), fontSize: 16)),
          ],
        ),
      );
}

// ── Summary Card ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final double total;
  final int count;
  const _SummaryCard({required this.total, required this.count});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'en_US');
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.isDark(context)
              ? const [Color(0xFF2D1515), Color(0xFF1A0A0A)]
              : const [Color(0xFFFFEEEE), Color(0xFFFFD6D6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border:
            Border.all(color: const Color(0xFFE63946).withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE63946).withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE63946).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.money_off, color: Color(0xFFE63946), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('total_expenses'.tr(),
                    style: TextStyle(
                        color: AppTheme.textMutedColor(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${fmt.format(total)} EGP',
                    style: const TextStyle(
                        color: Color(0xFFE63946),
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE63946).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('$count entries',
                style: const TextStyle(
                    color: Color(0xFFE63946),
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

// ── Individual Expense Tile ───────────────────────────────────────────────────

class _ExpenseTile extends StatelessWidget {
  final FinancialTransaction tx;
  final NumberFormat fmt;
  final DateFormat dateFmt;

  const _ExpenseTile(
      {required this.tx, required this.fmt, required this.dateFmt});

  @override
  Widget build(BuildContext context) {
    final icon = _iconFor(tx.type);
    const color = Color(0xFFE63946);

    String categoryLabel = '';
    if (tx.category != null && tx.category!.isNotEmpty) {
      final match = _kCategories
          .where((c) => c.$1 == tx.category)
          .map((c) => c.$2.tr())
          .firstOrNull;
      categoryLabel = match ?? tx.category!;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.panelGradient(context),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.12)),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  categoryLabel.isNotEmpty ? categoryLabel : tx.type.label.tr(),
                  style: TextStyle(
                      color: AppTheme.textPrimaryColor(context),
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
                if (tx.fromLabel != null && tx.fromLabel!.isNotEmpty)
                  Text('← ${tx.fromLabel}',
                      style: TextStyle(
                          color: AppTheme.textMutedColor(context),
                          fontSize: 11)),
                if (tx.notes != null && tx.notes!.isNotEmpty)
                  Text(tx.notes!,
                      style: TextStyle(
                          color: AppTheme.textMutedColor(context),
                          fontSize: 10,
                          fontStyle: FontStyle.italic),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(dateFmt.format(tx.timestamp),
                    style: TextStyle(
                        color: AppTheme.textMutedColor(context), fontSize: 10)),
              ],
            ),
          ),
          Text('−${fmt.format(tx.amount)} EGP',
              style: const TextStyle(
                  color: Color(0xFFE63946),
                  fontWeight: FontWeight.w900,
                  fontSize: 14)),
        ],
      ),
    );
  }

  IconData _iconFor(FlowType t) {
    switch (t) {
      case FlowType.EXPENSE_BANK:
        return Icons.account_balance;
      case FlowType.EXPENSE_VFNUMBER:
        return Icons.phone_disabled;
      case FlowType.EXPENSE_COLLECTOR:
        return Icons.person_off;
      default:
        return Icons.money_off;
    }
  }
}

// ── Record Expense Bottom Sheet ───────────────────────────────────────────────

void _showRecordExpenseSheet(
    BuildContext context, DistributionProvider dist, AuthProvider auth) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _RecordExpenseSheet(dist: dist, auth: auth),
  );
}

class _RecordExpenseSheet extends StatefulWidget {
  final DistributionProvider dist;
  final AuthProvider auth;
  const _RecordExpenseSheet({required this.dist, required this.auth});

  @override
  State<_RecordExpenseSheet> createState() => _RecordExpenseSheetState();
}

class _RecordExpenseSheetState extends State<_RecordExpenseSheet> {
  String _sourceType = 'bank'; // 'bank' | 'vfnumber' | 'collector'
  String? _sourceId;
  String? _category;
  final _amtCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _updateSourceId();
  }

  void _updateSourceId() {
    if (_sourceType == 'bank' && widget.dist.bankAccounts.isNotEmpty) {
      _sourceId = widget.dist.bankAccounts.first.id;
    } else if (_sourceType == 'vfnumber') {
      final vfs = context.read<AppProvider>().mobileNumbers;
      _sourceId = vfs.isNotEmpty ? vfs.first.id : null;
    } else if (_sourceType == 'collector' &&
        widget.dist.collectors.isNotEmpty) {
      _sourceId = widget.dist.collectors.first.id;
    } else {
      _sourceId = null;
    }
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amtCtrl.text) ?? 0;
    if (_sourceId == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('invalid_amount'.tr()), backgroundColor: Colors.red));
      return;
    }
    setState(() => _loading = true);
    try {
      await widget.dist.recordExpense(
        sourceType: _sourceType,
        sourceId: _sourceId!,
        amount: amount,
        category: _category,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        createdByUid: widget.auth.currentUser?.uid ?? 'system',
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('success'.tr()),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('error_with_msg'.tr(args: ['$e'])),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final dist = widget.dist;
    final fmt = NumberFormat('#,##0.00', 'en_US');

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 32),
          children: [
            // Handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppTheme.lineColor(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('record_expense'.tr(),
                style: TextStyle(
                    color: AppTheme.textPrimaryColor(context),
                    fontSize: 22,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 20),

            // ── Source type chips ────────────────────────────────────────
            Text('Funding Source',
                style: TextStyle(
                    color: AppTheme.textMutedColor(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final entry in [
                  ('bank', 'banks'.tr(), Icons.account_balance),
                  ('vfnumber', 'vf_cash'.tr(), Icons.phone_android),
                  ('collector', 'collector'.tr(), Icons.delivery_dining),
                ])
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _sourceType = entry.$1;
                        _updateSourceId();
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          color: _sourceType == entry.$1
                              ? const Color(0xFFE63946)
                              : AppTheme.textPrimaryColor(context)
                                  .withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _sourceType == entry.$1
                                ? const Color(0xFFE63946)
                                : AppTheme.lineColor(context),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(entry.$3,
                                size: 18,
                                color: _sourceType == entry.$1
                                    ? Colors.white
                                    : AppTheme.textMutedColor(context)),
                            const SizedBox(height: 4),
                            Text(entry.$2,
                                style: TextStyle(
                                    color: _sourceType == entry.$1
                                        ? Colors.white
                                        : AppTheme.textMutedColor(context),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Source entity dropdown ───────────────────────────────────
            _buildSourceDropdown(context, app, dist, fmt),
            const SizedBox(height: 14),

            // ── Amount field ────────────────────────────────────────────
            _field(context, _amtCtrl, 'amount_egp'.tr(),
                Icons.payments_outlined, TextInputType.number),
            const SizedBox(height: 14),

            // ── Category dropdown ───────────────────────────────────────
            _buildCategoryDropdown(context),
            const SizedBox(height: 14),

            // ── Notes field ─────────────────────────────────────────────
            _field(context, _notesCtrl, 'notes'.tr(), Icons.note_outlined,
                TextInputType.text,
                maxLines: 2),
            const SizedBox(height: 24),

            // ── Confirm button ──────────────────────────────────────────
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE63946),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text('confirm'.tr(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceDropdown(BuildContext context, AppProvider app,
      DistributionProvider dist, NumberFormat fmt) {
    final List<DropdownMenuItem<String>> items = [];

    if (_sourceType == 'bank') {
      items.addAll(dist.bankAccounts.map((b) => DropdownMenuItem(
            value: b.id,
            child: Text('${b.bankName}  (${fmt.format(b.balance)} EGP)',
                style: TextStyle(color: AppTheme.textPrimaryColor(context))),
          )));
    } else if (_sourceType == 'vfnumber') {
      items.addAll(app.mobileNumbers.map((n) => DropdownMenuItem(
            value: n.id,
            child: Text(
                '${n.phoneNumber}  (${fmt.format(n.currentBalance)} EGP)',
                style: TextStyle(color: AppTheme.textPrimaryColor(context))),
          )));
    } else if (_sourceType == 'collector') {
      items.addAll(dist.collectors.map((c) => DropdownMenuItem(
            value: c.id,
            child: Text('${c.name}  (${fmt.format(c.cashOnHand)} EGP)',
                style: TextStyle(color: AppTheme.textPrimaryColor(context))),
          )));
    }

    if (items.isEmpty) {
      return Text('No sources available.',
          style: TextStyle(color: AppTheme.textMutedColor(context)));
    }

    return _styledDropdown<String>(
      context: context,
      value: _sourceId,
      hint: 'select_bank'.tr(),
      items: items,
      onChanged: (v) => setState(() => _sourceId = v),
    );
  }

  Widget _buildCategoryDropdown(BuildContext context) {
    return _styledDropdown<String>(
      context: context,
      value: _category,
      hint: 'expense_category'.tr(),
      items: _kCategories
          .map((c) => DropdownMenuItem(
                value: c.$1,
                child: Text(c.$2.tr(),
                    style: TextStyle(color: AppTheme.textPrimaryColor(context))),
              ))
          .toList(),
      onChanged: (v) => setState(() => _category = v),
    );
  }

  Widget _styledDropdown<T>({
    required BuildContext context,
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.lineColor(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: Text(hint,
              style: TextStyle(
                  color: AppTheme.textMutedColor(context), fontSize: 13)),
          dropdownColor: AppTheme.surfaceColor(context),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _field(
    BuildContext context,
    TextEditingController ctrl,
    String label,
    IconData icon,
    TextInputType keyboard, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      maxLines: maxLines,
      style:
          TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13),
        prefixIcon:
            Icon(icon, color: AppTheme.textMutedColor(context), size: 20),
        filled: true,
        fillColor:
            AppTheme.textPrimaryColor(context).withValues(alpha: 0.05),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}
