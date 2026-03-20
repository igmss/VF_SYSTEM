import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/distribution_provider.dart';
import '../../providers/app_provider.dart';
import '../../models/retailer.dart';
import '../../models/models.dart';

class CreditReturnDialog extends StatefulWidget {
  final Retailer retailer;

  const CreditReturnDialog({Key? key, required this.retailer}) : super(key: key);

  @override
  State<CreditReturnDialog> createState() => _CreditReturnDialogState();
}

class _CreditReturnDialogState extends State<CreditReturnDialog> {
  final _amountController = TextEditingController();
  final _feesController = TextEditingController();
  final _notesController = TextEditingController();
  final _feeRateController = TextEditingController(text: '7.0');
  
  String? _selectedVfNumberId;
  double _feeRate = 7.0; // Default: 7 EGP per 1000 EGP

  @override
  void initState() {
    super.initState();
    // Pre-calculate fees if amount changes
    _amountController.addListener(_updateFees);
  }

  void _updateFees() {
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    final calculatedFees = (amount / 1000.0) * _feeRate;
    _feesController.text = calculatedFees.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountController.removeListener(_updateFees);
    _amountController.dispose();
    _feesController.dispose();
    _notesController.dispose();
    _feeRateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dist = context.read<DistributionProvider>();
    final app = context.watch<AppProvider>();
    final vfNumbers = app.mobileNumbers;

    if (_selectedVfNumberId == null && vfNumbers.isNotEmpty) {
      // Try to find default number first
      final defaultNum = vfNumbers.any((n) => n.isDefault) 
          ? vfNumbers.firstWhere((n) => n.isDefault) 
          : vfNumbers.first;
      _selectedVfNumberId = defaultNum.id;
    }

    return Dialog(
      backgroundColor: const Color(0xFF16162A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE63946).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.keyboard_return, color: Color(0xFFE63946), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Credit Return',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        Text(
                          'Settling debt for ${widget.retailer.name}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // VF Number Selection
              const Text('Target VF Number', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedVfNumberId,
                dropdownColor: const Color(0xFF1E1E3A),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.phone_android, color: Colors.white38, size: 20),
                ),
                items: vfNumbers.map((n) => DropdownMenuItem(
                  value: n.id,
                  child: Text(n.phoneNumber),
                )).toList(),
                onChanged: (v) => setState(() => _selectedVfNumberId = v),
              ),
              const SizedBox(height: 16),

              // Amount
              _field(
                controller: _amountController,
                label: 'Debt Amount to Deduct',
                icon: Icons.money_off,
                keyboard: TextInputType.number,
                hint: 'e.g. 5000',
              ),
              
              // Fee Rate & Fee Amount
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Fee Rate (per 1K)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _feeRateController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.04),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onChanged: (val) {
                            setState(() {
                              _feeRate = double.tryParse(val) ?? 0.0;
                              _updateFees();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _field(
                      controller: _feesController,
                      label: 'Calculated Fee',
                      icon: Icons.add_chart,
                      keyboard: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Summary Box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF4ADE80).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF4ADE80).withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    _summaryRow('Retailer Pays Total:', _totalAmount, isBold: true),
                    const Divider(color: Colors.white10, height: 20),
                    _summaryRow('Debt Deduction:', _amountOnly),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              _field(
                controller: _notesController,
                label: 'Notes (Optional)',
                icon: Icons.notes,
                hint: 'Transaction details...',
              ),

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE63946),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Confirm Return', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _totalAmount {
    final amt = double.tryParse(_amountController.text) ?? 0.0;
    final fees = double.tryParse(_feesController.text) ?? 0.0;
    return '${(amt + fees).toStringAsFixed(2)} EGP';
  }

  String get _amountOnly {
    final amt = double.tryParse(_amountController.text) ?? 0.0;
    return '${amt.toStringAsFixed(2)} EGP';
  }

  Widget _summaryRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        Text(value, style: TextStyle(color: isBold ? const Color(0xFF4ADE80) : Colors.white70, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: keyboard,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
              prefixIcon: Icon(icon, color: Colors.white38, size: 18),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    final fees = double.tryParse(_feesController.text) ?? 0.0;
    
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_selectedVfNumberId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a target VF number'), backgroundColor: Colors.red),
      );
      return;
    }

    final app = context.read<AppProvider>();
    final vfNum = app.mobileNumbers.firstWhere((n) => n.id == _selectedVfNumberId);

    context.read<DistributionProvider>().creditReturn(
      retailerId: widget.retailer.id,
      vfNumberId: vfNum.id,
      vfPhone: vfNum.phoneNumber,
      amount: amount,
      fees: fees,
      createdByUid: 'admin', 
      notes: _notesController.text.trim(),
    );

    Navigator.pop(context);
  }
}
