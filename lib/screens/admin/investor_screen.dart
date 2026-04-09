import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../models/investor.dart';
import '../../providers/distribution_provider.dart';
import '../../utils/theme.dart';

class InvestorScreen extends StatefulWidget {
  const InvestorScreen({Key? key}) : super(key: key);

  @override
  State<InvestorScreen> createState() => _InvestorScreenState();
}

class _InvestorScreenState extends State<InvestorScreen> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _priorityController = TextEditingController();
  final _profitShareController = TextEditingController();

  // Simulation inputs
  final _avgBuyController = TextEditingController();
  final _avgSellController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _priorityController.text = '1';
    _profitShareController.text = '100';
    _avgBuyController.text = '50';
    _avgSellController.text = '52';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _priorityController.dispose();
    _profitShareController.dispose();
    _avgBuyController.dispose();
    _avgSellController.dispose();
    super.dispose();
  }

  void _addInvestor() async {
    final name = _nameController.text.trim();
    final amount = double.tryParse(_amountController.text);
    final priority = int.tryParse(_priorityController.text) ?? 1;
    final profitShare = double.tryParse(_profitShareController.text) ?? 100.0;

    if (name.isEmpty || amount == null || amount <= 0) return;

    final distProv = context.read<DistributionProvider>();

    try {
      await distProv.addInvestor(
        name: name,
        investmentAmount: amount,
        priority: priority,
        profitSharePercentage: profitShare,
      );

      _nameController.clear();
      _amountController.clear();
      _priorityController.text = '1';
      _profitShareController.text = '100';
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Investor added successfully')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showEditDialog(Investor inv) {
    final nameController = TextEditingController(text: inv.name);
    final amountController = TextEditingController(text: inv.investmentAmount.toString());
    final priorityController = TextEditingController(text: inv.priority.toString());
    final shareController = TextEditingController(text: inv.profitSharePercentage.toString());

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Edit Investor'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(labelText: 'Investment Amount'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              TextField(
                controller: priorityController,
                decoration: const InputDecoration(labelText: 'Priority (1 is highest)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: shareController,
                decoration: const InputDecoration(labelText: 'Profit Share % (e.g. 30)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                final distProv = context.read<DistributionProvider>();
                final updated = Investor(
                  id: inv.id,
                  name: nameController.text.trim(),
                  investmentAmount: double.tryParse(amountController.text) ?? inv.investmentAmount,
                  priority: int.tryParse(priorityController.text) ?? inv.priority,
                  profitSharePercentage: double.tryParse(shareController.text) ?? inv.profitSharePercentage,
                  createdByUid: inv.createdByUid,
                  createdAt: inv.createdAt,
                );
                await distProv.updateInvestor(updated);
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final distProv = context.watch<DistributionProvider>();

    double avgBuy = double.tryParse(_avgBuyController.text) ?? 0;
    double avgSell = double.tryParse(_avgSellController.text) ?? 0;

    final waterfall = distProv.calculateWaterfall(distProv.investors, avgBuy, avgSell);
    final double dailyFlow = waterfall['dailyFlow'];
    final double profitPer1000 = waterfall['profitPer1000'];
    final Map<String, double> allocations = waterfall['allocations'];
    final Map<String, double> profits = waterfall['profits'];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side: List of investors + Waterfall results
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Card(
                  color: AppTheme.primaryColor(context).withOpacity(0.05),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text('Simulation Parameters', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _avgBuyController,
                                decoration: const InputDecoration(labelText: 'Avg Buy Price', isDense: true),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: (_) => setState((){}),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _avgSellController,
                                decoration: const InputDecoration(labelText: 'Avg Sell Price', isDense: true),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: (_) => setState((){}),
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Text('Active Daily Flow: ${NumberFormat.currency(symbol: '').format(dailyFlow)}'),
                            Text('Profit/1000: ${NumberFormat.currency(symbol: '').format(profitPer1000)}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Card(
                    child: distProv.investors.isEmpty
                        ? const Center(child: Text('No investors recorded'))
                        : ListView.builder(
                            itemCount: distProv.investors.length,
                            itemBuilder: (context, index) {
                              final inv = distProv.investors[index];
                              final alloc = allocations[inv.id] ?? 0.0;
                              final prof = profits[inv.id] ?? 0.0;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.primaryColor(context).withOpacity(0.1),
                                  child: Text(inv.priority.toString()),
                                ),
                                title: Text('${inv.name} - ${inv.profitSharePercentage}% Share'),
                                subtitle: Text('Invested: ${NumberFormat.currency(symbol: '').format(inv.investmentAmount)} | Allocated Flow: ${NumberFormat.currency(symbol: '').format(alloc)}\nCalculated Profit: ${NumberFormat.currency(symbol: 'EGP ').format(prof)}'),
                                isThreeLine: true,
                                trailing: IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _showEditDialog(inv),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Right side: Add Investor form
          Expanded(
            flex: 1,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Add Investor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Investor Name', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _amountController,
                        decoration: const InputDecoration(labelText: 'Investment Amount (EGP)', border: OutlineInputBorder()),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _priorityController,
                        decoration: const InputDecoration(labelText: 'Priority Level (1=Highest)', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _profitShareController,
                        decoration: const InputDecoration(labelText: 'Profit Share Percentage (e.g. 30)', border: OutlineInputBorder()),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _addInvestor,
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        child: const Text('Add Investor'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
