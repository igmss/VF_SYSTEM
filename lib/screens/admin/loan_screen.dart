import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../models/loan.dart';
import '../../providers/distribution_provider.dart';
import '../../utils/theme.dart';

class LoanScreen extends StatefulWidget {
  const LoanScreen({Key? key}) : super(key: key);

  @override
  State<LoanScreen> createState() => _LoanScreenState();
}

class _LoanScreenState extends State<LoanScreen> {
  final _amountController = TextEditingController();
  final _borrowerController = TextEditingController();
  final _notesController = TextEditingController();

  String? _selectedBankId;

  @override
  void dispose() {
    _amountController.dispose();
    _borrowerController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _issueLoan() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) return;
    if (_borrowerController.text.trim().isEmpty) return;
    if (_selectedBankId == null) return;

    final distProv = context.read<DistributionProvider>();

    try {
      await distProv.issueLoan(
        borrowerName: _borrowerController.text.trim(),
        principal: amount,
        sourceBankId: _selectedBankId!,
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      );

      _amountController.clear();
      _borrowerController.clear();
      _notesController.clear();
      setState(() {
        _selectedBankId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Loan issued successfully')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showRepayDialog(Loan loan) {
    final repayController = TextEditingController();
    String? selectedRepayBankId;

    showDialog(
      context: context,
      builder: (ctx) {
        final distProv = context.read<DistributionProvider>();
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Repay Loan: ${loan.borrowerName}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Remaining: ${NumberFormat.currency(symbol: 'EGP ').format(loan.remainingAmount)}'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: repayController,
                    decoration: const InputDecoration(labelText: 'Repayment Amount (EGP)', border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedRepayBankId,
                    decoration: const InputDecoration(labelText: 'Destination Bank', border: OutlineInputBorder()),
                    items: distProv.bankAccounts.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                    onChanged: (val) => setState(() => selectedRepayBankId = val),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final amt = double.tryParse(repayController.text);
                    if (amt == null || amt <= 0 || selectedRepayBankId == null) return;
                    if (amt > loan.remainingAmount) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Amount exceeds remaining balance')));
                      return;
                    }
                    try {
                      await distProv.repayLoan(
                        loanId: loan.id,
                        amount: amt,
                        destBankId: selectedRepayBankId!,
                      );
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Repayment successful')));
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  child: const Text('Confirm'),
                ),
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final distProv = context.watch<DistributionProvider>();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side: List of loans
          Expanded(
            flex: 2,
            child: Card(
              child: distProv.loans.isEmpty
                  ? const Center(child: Text('No loans issued'))
                  : ListView.builder(
                      itemCount: distProv.loans.length,
                      itemBuilder: (context, index) {
                        final loan = distProv.loans[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: loan.isPaidOff ? AppTheme.positiveColor(context).withOpacity(0.1) : AppTheme.warningColor(context).withOpacity(0.1),
                            child: Icon(loan.isPaidOff ? Icons.check_circle : Icons.hourglass_empty,
                                        color: loan.isPaidOff ? AppTheme.positiveColor(context) : AppTheme.warningColor(context)),
                          ),
                          title: Text(loan.borrowerName),
                          subtitle: Text('Principal: ${NumberFormat.currency(symbol: '').format(loan.principal)} | Repaid: ${NumberFormat.currency(symbol: '').format(loan.repaidAmount)}\nStatus: ${loan.status.label} - ${DateFormat('MMM d, yyyy HH:mm').format(loan.issuedAt)}'),
                          isThreeLine: true,
                          trailing: loan.isPaidOff ? null : ElevatedButton(
                            onPressed: () => _showRepayDialog(loan),
                            child: const Text('Repay'),
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(width: 16),
          // Right side: Issue Loan form
          Expanded(
            flex: 1,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Issue New Loan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _borrowerController,
                      decoration: const InputDecoration(labelText: 'Borrower Name', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountController,
                      decoration: const InputDecoration(labelText: 'Principal Amount (EGP)', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedBankId,
                      decoration: const InputDecoration(labelText: 'Source Bank', border: OutlineInputBorder()),
                      items: distProv.bankAccounts.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                      onChanged: (val) => setState(() => _selectedBankId = val),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      decoration: const InputDecoration(labelText: 'Notes (Optional)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _issueLoan,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: const Text('Issue Loan'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
