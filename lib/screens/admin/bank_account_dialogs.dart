part of 'bank_accounts_screen.dart';

import '../../widgets/async_button.dart';

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
        _tf(context, nameCtrl,   'bank_name'.tr(),       Icons.business),
        _tf(context, holderCtrl, 'account_holder'.tr(),  Icons.person),
        _tf(context, numCtrl,    'account_number'.tr(),  Icons.credit_card),
        _tf(context, balCtrl,    'opening_balance'.tr(), Icons.monetization_on,
            keyboard: TextInputType.number),
      ],
      onConfirm: () async {
        final uid = context.read<AuthProvider>().currentUser?.uid ?? 'system';
        await context.read<DistributionProvider>().addBankAccount(
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
        _tf(context, amtCtrl,   'amount_egp'.tr(), Icons.monetization_on,
            keyboard: TextInputType.number),
        _tf(context, notesCtrl, 'notes'.tr(),      Icons.notes),
      ],
      // Step 1 done — now show confirm dialog before touching data
      onConfirm: () async {
        final amount = double.tryParse(amtCtrl.text) ?? 0;
        final notes  = notesCtrl.text.isEmpty ? null : notesCtrl.text;
        if (amount <= 0) return; // guard: nothing to confirm

        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppTheme.surfaceColor(context),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(Icons.verified_outlined,
                    color: _kGreen, size: 20),
                const SizedBox(width: 8),
                Text('confirm_fund'.tr(),
                    style: TextStyle(
                        color: AppTheme.textPrimaryColor(context),
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
                          style: TextStyle(
                              color: AppTheme.textPrimaryColor(context),
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(bank.accountNumber,
                          style: TextStyle(
                              color: AppTheme.textMutedColor(context), fontSize: 11)),
                      Divider(color: AppTheme.lineColor(context), height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Adding',
                              style: TextStyle(
                                  color: AppTheme.textMutedColor(context), fontSize: 13)),
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
                            style: TextStyle(
                                color: AppTheme.textMutedColor(context),
                                fontSize: 11,
                                fontStyle: FontStyle.italic)),
                      ],
                      Divider(color: AppTheme.lineColor(context), height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('New Balance',
                              style: TextStyle(
                                  color: AppTheme.textMutedColor(context), fontSize: 12)),
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
                Text(
                  'This action will be recorded in the ledger and cannot be reversed.',
                  style: TextStyle(
                      color: AppTheme.textMutedColor(context),
                      fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('cancel'.tr(),
                    style: TextStyle(color: AppTheme.textMutedColor(context))),
              ),
              AsyncButton.icon(
                icon: Icon(Icons.check_rounded,
                    color: AppTheme.textPrimaryColor(context), size: 16),
                label: Text('confirm'.tr(),
                    style: TextStyle(color: AppTheme.textPrimaryColor(context))),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  // ── The only place fundBankAccount is called ──────────
                  await dist.fundBankAccount(
                    bankAccountId: bank.id,
                    amount: amount,
                    createdByUid: auth.currentUser?.uid ?? 'system',
                    notes: notes,
                  );
                  if (context.mounted) {
                    Navigator.pop(context); // close confirm dialog
                  }
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
        _tf(context, balCtrl, context.locale.languageCode == 'ar' ? 'الرصيد الجديد' : 'New Balance', Icons.account_balance_wallet,
            keyboard: const TextInputType.numberWithOptions(decimal: true)),
        _tf(context, notesCtrl, 'notes'.tr(), Icons.notes),
      ],
      onConfirm: () async {
        final newBal = double.tryParse(balCtrl.text) ?? bank.balance;
        await dist.correctBankBalance(
          bankAccountId: bank.id,
          newBalance: newBal,
          createdByUid: auth.currentUser?.uid ?? 'system',
          notes: notesCtrl.text.isEmpty ? 'Manual Balance Correction' : notesCtrl.text,
        );
      },
    ),
  );
}

Widget _tf(BuildContext context, TextEditingController c, String label, IconData icon,
        {TextInputType keyboard = TextInputType.text}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        style: TextStyle(color: AppTheme.textPrimaryColor(context)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: AppTheme.textMutedColor(context)),
          prefixIcon: Icon(icon, color: AppTheme.textMutedColor(context), size: 20),
          filled: true,
          fillColor: AppTheme.textPrimaryColor(context).withValues(alpha: 0.06),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.1))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.1))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kRed)),
        ),
      ),
    );

// ─────────────────────────────────────────────────────────────────────────────
//  Reusable Form Dialog — unchanged from original
// ─────────────────────────────────────────────────────────────────────────────

class _FormDialog extends StatelessWidget {
  final String title;
  final List<Widget> fields;
  final Future<void> Function() onConfirm;

  const _FormDialog({
    required this.title,
    required this.fields,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceColor(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    color: AppTheme.textPrimaryColor(context),
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
                      style: TextStyle(color: AppTheme.textMutedColor(context))),
                ),
                const SizedBox(width: 8),
                AsyncButton(
                  onPressed: () async {
                    await onConfirm();
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kRed,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('save'.tr(),
                      style: TextStyle(color: AppTheme.textPrimaryColor(context))),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
