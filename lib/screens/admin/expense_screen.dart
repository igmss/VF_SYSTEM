import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../models/expense.dart';
import '../../providers/distribution_provider.dart';
import '../../providers/app_provider.dart';
import '../../utils/theme.dart';

class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({Key? key}) : super(key: key);

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController();
  final _notesController = TextEditingController();

  ExpenseSource _selectedSource = ExpenseSource.BANK;
  String? _selectedSourceId;

  @override
  void dispose() {
    _amountController.dispose();
    _categoryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submitExpense() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) return;
    if (_categoryController.text.trim().isEmpty) return;
    if (_selectedSourceId == null) return;

    String sourceLabel = '';
    final distProv = context.read<DistributionProvider>();
    if (_selectedSource == ExpenseSource.BANK) {
      final bank = distProv.bankAccounts.firstWhere((b) => b.id == _selectedSourceId);
      sourceLabel = bank.name;
    } else if (_selectedSource == ExpenseSource.VF_CASH) {
      final appProv = context.read<AppProvider>();
      final vf = appProv.mobileNumbers.firstWhere((m) => m.id == _selectedSourceId);
      sourceLabel = vf.number;
    } else if (_selectedSource == ExpenseSource.COLLECTOR_CASH) {
      final collector = distProv.collectors.firstWhere((c) => c.id == _selectedSourceId);
      sourceLabel = collector.name;
    }

    try {
      await distProv.addExpense(
        amount: amount,
        category: _categoryController.text.trim(),
        source: _selectedSource,
        sourceId: _selectedSourceId!,
        sourceLabel: sourceLabel,
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      );

      _amountController.clear();
      _categoryController.clear();
      _notesController.clear();
      setState(() {
        _selectedSourceId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense added successfully')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final distProv = context.watch<DistributionProvider>();
    final appProv = context.watch<AppProvider>();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side: List of expenses
          Expanded(
            flex: 2,
            child: Card(
              child: distProv.expenses.isEmpty
                  ? const Center(child: Text('No expenses recorded'))
                  : ListView.builder(
                      itemCount: distProv.expenses.length,
                      itemBuilder: (context, index) {
                        final e = distProv.expenses[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.accent.withOpacity(0.1),
                            child: const Icon(Icons.money_off, color: AppTheme.accent),
                          ),
                          title: Text('${e.category} - ${NumberFormat.currency(symbol: 'EGP ').format(e.amount)}'),
                          subtitle: Text('${e.source.label}: ${e.sourceLabel}\n${DateFormat('MMM d, yyyy HH:mm').format(e.timestamp)}'),
                          isThreeLine: true,
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(width: 16),
          // Right side: Add Expense form
          Expanded(
            flex: 1,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Add Expense', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _amountController,
                      decoration: const InputDecoration(labelText: 'Amount (EGP)', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _categoryController,
                      decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ExpenseSource>(
                      value: _selectedSource,
                      decoration: const InputDecoration(labelText: 'Source', border: OutlineInputBorder()),
                      items: ExpenseSource.values.map((s) => DropdownMenuItem(value: s, child: Text(s.label))).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedSource = val;
                            _selectedSourceId = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_selectedSource == ExpenseSource.BANK)
                      DropdownButtonFormField<String>(
                        value: _selectedSourceId,
                        decoration: const InputDecoration(labelText: 'Select Bank', border: OutlineInputBorder()),
                        items: distProv.bankAccounts.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                        onChanged: (val) => setState(() => _selectedSourceId = val),
                      ),
                    if (_selectedSource == ExpenseSource.VF_CASH)
                      DropdownButtonFormField<String>(
                        value: _selectedSourceId,
                        decoration: const InputDecoration(labelText: 'Select VF Number', border: OutlineInputBorder()),
                        items: appProv.mobileNumbers.map((m) => DropdownMenuItem(value: m.id, child: Text(m.number))).toList(),
                        onChanged: (val) => setState(() => _selectedSourceId = val),
                      ),
                    if (_selectedSource == ExpenseSource.COLLECTOR_CASH)
                      DropdownButtonFormField<String>(
                        value: _selectedSourceId,
                        decoration: const InputDecoration(labelText: 'Select Collector', border: OutlineInputBorder()),
                        items: distProv.collectors.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                        onChanged: (val) => setState(() => _selectedSourceId = val),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      decoration: const InputDecoration(labelText: 'Notes (Optional)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _submitExpense,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: const Text('Add Expense'),
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
