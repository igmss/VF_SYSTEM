part of 'loans_screen.dart';

void _showIssueLoanDialog(BuildContext context, DistributionProvider dist, AuthProvider auth) {
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final amtCtrl = TextEditingController();
  final notesCtrl = TextEditingController();

  final banks = dist.bankAccounts;
  final collectors = dist.collectors;

  if (banks.isEmpty && collectors.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No funding sources available.')));
    return;
  }

  String? selectedSourceId;
  LoanSourceType selectedType = banks.isNotEmpty ? LoanSourceType.bank : LoanSourceType.collector;
  if (banks.isNotEmpty) selectedSourceId = banks.first.id;
  else if (collectors.isNotEmpty) selectedSourceId = collectors.first.id;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context2, setSt) {
        return _LoanBaseDialog(
          title: 'issue_loan'.tr(),
          onConfirm: () async {
            final name = nameCtrl.text.trim();
            final amt = double.tryParse(amtCtrl.text) ?? 0;
            if (name.isEmpty || amt <= 0 || selectedSourceId == null) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('invalid_request_fields'.tr()), backgroundColor: Colors.red));
              return false;
            }

            await dist.issueLoan(
              sourceType: selectedType,
              sourceId: selectedSourceId!,
              borrowerName: name,
              borrowerPhone: phoneCtrl.text.trim(),
              amount: amt,
              notes: notesCtrl.text.trim(),
              createdByUid: auth.currentUser?.uid ?? 'system',
            );
            return true;
          },
          children: [
            _LoanTextField(controller: nameCtrl, label: 'borrower_name'.tr(), icon: Icons.person_outline),
            _LoanTextField(controller: phoneCtrl, label: 'borrower_phone'.tr(), icon: Icons.phone_outlined, keyboard: TextInputType.phone),
            _LoanTextField(controller: amtCtrl, label: 'amount_egp'.tr(), icon: Icons.payments_outlined, keyboard: TextInputType.number),
            const SizedBox(height: 12),
            Text('Funding Source', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.lineColor(context)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedSourceId,
                  isExpanded: true,
                  dropdownColor: AppTheme.surfaceColor(context),
                  items: [
                    ...banks.map((b) => DropdownMenuItem(
                          value: b.id,
                          onTap: () => selectedType = LoanSourceType.bank,
                          child: Text('Bank: ${b.bankName}', style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 14)),
                        )),
                    ...collectors.map((c) => DropdownMenuItem(
                          value: c.id,
                          onTap: () => selectedType = LoanSourceType.collector,
                          child: Text('Collector: ${c.name}', style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 14)),
                        )),
                  ],
                  onChanged: (v) => setSt(() => selectedSourceId = v),
                ),
              ),
            ),
            _LoanTextField(controller: notesCtrl, label: 'notes'.tr(), icon: Icons.note_outlined, maxLines: 2),
          ],
        );
      },
    ),
  );
}

void _showRepaymentDialog(BuildContext context, Loan loan, DistributionProvider dist, AuthProvider auth) {
  final amtCtrl = TextEditingController(text: loan.outstandingBalance.toStringAsFixed(0));
  
  showDialog(
    context: context,
    builder: (ctx) => _LoanBaseDialog(
      title: 'record_repayment'.tr(),
      onConfirm: () async {
        final amt = double.tryParse(amtCtrl.text) ?? 0;
        if (amt <= 0 || amt > loan.outstandingBalance + 0.01) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('invalid_amount'.tr()), backgroundColor: Colors.red));
          return false;
        }
        await dist.recordLoanRepayment(
          loanId: loan.id,
          amount: amt,
          createdByUid: auth.currentUser?.uid ?? 'system',
        );
        return true;
      },
      children: [
        Text(loan.borrowerName, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Remaining: ${NumberFormat('#,##0.00', 'en_US').format(loan.outstandingBalance)} EGP',
            style: TextStyle(color: AppTheme.warningColor(context), fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _LoanTextField(controller: amtCtrl, label: 'amount_egp'.tr(), icon: Icons.account_balance_wallet_outlined, keyboard: TextInputType.number),
      ],
    ),
  );
}

class _LoanBaseDialog extends StatefulWidget {
  final String title;
  final List<Widget> children;
  final Future<bool> Function() onConfirm;

  const _LoanBaseDialog({required this.title, required this.children, required this.onConfirm});

  @override
  State<_LoanBaseDialog> createState() => _LoanBaseDialogState();
}

class _LoanBaseDialogState extends State<_LoanBaseDialog> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceColor(context),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(widget.title, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w900, fontSize: 20)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widget.children,
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text('cancel'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context), fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _loading ? null : () async {
            setState(() => _loading = true);
            try {
              final ok = await widget.onConfirm();
              if (ok && mounted) Navigator.pop(context);
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
            } finally {
              if (mounted) setState(() => _loading = false);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accent,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _loading 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text('confirm'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ],
    );
  }
}

class _LoanTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboard;
  final int maxLines;

  const _LoanTextField({required this.controller, required this.label, required this.icon, this.keyboard = TextInputType.text, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13),
          prefixIcon: Icon(icon, color: AppTheme.textMutedColor(context), size: 20),
          filled: true,
          fillColor: AppTheme.textPrimaryColor(context).withValues(alpha: 0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}
