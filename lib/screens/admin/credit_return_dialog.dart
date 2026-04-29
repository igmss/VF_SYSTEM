import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../theme/app_theme.dart';
import '../../providers/distribution_provider.dart';
import '../../providers/app_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/retailer.dart';
import '../../widgets/async_button.dart';

class CreditReturnDialog extends StatefulWidget {
  final Retailer retailer;

  const CreditReturnDialog({super.key, required this.retailer});

  @override
  State<CreditReturnDialog> createState() => _CreditReturnDialogState();
}

class _CreditReturnDialogState extends State<CreditReturnDialog> {
  final _amountController = TextEditingController();
  final _feesController = TextEditingController();
  final _notesController = TextEditingController();
  final _feeRateController = TextEditingController(text: '7.0');

  String? _selectedVfNumberId;
  double _feeRate = 7.0;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.retailer.pendingDebt.toStringAsFixed(0);
    _amountController.addListener(_updateFees);
    _updateFees();
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
    final dist = context.watch<DistributionProvider>();
    final app = context.watch<AppProvider>();
    final vfNumbers = app.mobileNumbers;
    final isSubmitting = dist.isCreditReturning;
    final retailer = dist.retailers.firstWhere(
      (item) => item.id == widget.retailer.id,
      orElse: () => widget.retailer,
    );
    final remainingDebt = retailer.pendingDebt;

    if (_selectedVfNumberId == null && vfNumbers.isNotEmpty) {
      final defaultNum = vfNumbers.any((n) => n.isDefault)
          ? vfNumbers.firstWhere((n) => n.isDefault)
          : vfNumbers.first;
      _selectedVfNumberId = defaultNum.id;
    }

    return Dialog(
      backgroundColor: AppTheme.surfaceColor(context),
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
                      color: const Color(0xFFE63946).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.keyboard_return, color: Color(0xFFE63946), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'credit_return'.tr(),
                          style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        Text(
                          'settling_debt_for'.tr(args: [retailer.name]),
                          style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor(context).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.warningColor(context).withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppTheme.warningColor(context), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'remaining_debt_with_amount'.tr(args: [remainingDebt.toStringAsFixed(2)]),
                        style: TextStyle(color: AppTheme.warningColor(context), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('target_vf_number'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.7), fontSize: 13)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedVfNumberId,
                dropdownColor: AppTheme.surfaceColor(context),
                style: TextStyle(color: AppTheme.textPrimaryColor(context)),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppTheme.textPrimaryColor(context).withValues(alpha: 0.06),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.phone_android, color: AppTheme.textMutedColor(context), size: 20),
                ),
                items: vfNumbers.map((n) => DropdownMenuItem(
                  value: n.id,
                  child: Text(n.phoneNumber),
                )).toList(),
                onChanged: isSubmitting ? null : (v) => setState(() => _selectedVfNumberId = v),
              ),
              const SizedBox(height: 16),
              _field(
                controller: _amountController,
                label: 'return_amount'.tr(),
                icon: Icons.money_off,
                keyboard: TextInputType.number,
                hint: 'e.g. 5000',
                enabled: !isSubmitting,
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('fee_rate_per_1k'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.7), fontSize: 12)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _feeRateController,
                          enabled: !isSubmitting,
                          style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 14),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: AppTheme.textPrimaryColor(context).withValues(alpha: 0.04),
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
                      label: 'calculated_fee'.tr(),
                      icon: Icons.add_chart,
                      keyboard: TextInputType.number,
                      enabled: !isSubmitting,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF4ADE80).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF4ADE80).withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    _summaryRow('retailer_pays_total'.tr(), _totalAmount, isBold: true),
                    Divider(color: AppTheme.lineColor(context), height: 20),
                    _summaryRow('debt_deduction'.tr(), _amountOnly),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _field(
                controller: _notesController,
                label: '${'notes'.tr()} (${'optional'.tr()})',
                icon: Icons.notes,
                hint: '...',
                enabled: !isSubmitting,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: isSubmitting ? null : () => Navigator.pop(context),
                    child: Text('cancel'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context))),
                  ),
                  const SizedBox(width: 12),
                  AsyncButton(
                    onPressed: () => _submit(retailer),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE63946),
                      foregroundColor: AppTheme.textPrimaryColor(context),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text('confirm_return'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
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
    return '${(amt + fees).toStringAsFixed(2)} ${'currency'.tr()}';
  }

  String get _amountOnly {
    final amt = double.tryParse(_amountController.text) ?? 0.0;
    return '${amt.toStringAsFixed(2)} ${'currency'.tr()}';
  }

  Widget _summaryRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.7), fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        Text(value, style: TextStyle(color: isBold ? const Color(0xFF4ADE80) : AppTheme.textPrimaryColor(context).withValues(alpha: 0.7), fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    String? hint,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textPrimaryColor(context).withValues(alpha: 0.7), fontSize: 12)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: keyboard,
            enabled: enabled,
            style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: AppTheme.textMutedColor(context).withValues(alpha: 0.6), fontSize: 13),
              prefixIcon: Icon(icon, color: AppTheme.textMutedColor(context), size: 18),
              filled: true,
              fillColor: AppTheme.textPrimaryColor(context).withValues(alpha: 0.06),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(Retailer retailer) async {
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    final fees = double.tryParse(_feesController.text) ?? 0.0;
    final remainingDebt = retailer.pendingDebt;

    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('enter_valid_amount'.tr()), backgroundColor: Colors.red),
      );
      return;
    }

    if ((amount - remainingDebt) > 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('return_exceeds_debt'.tr(args: [remainingDebt.toStringAsFixed(2)])),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedVfNumberId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('select_target_vf'.tr()), backgroundColor: Colors.red),
      );
      return;
    }

    final app = context.read<AppProvider>();
    final auth = context.read<AuthProvider>();
    final vfNum = app.mobileNumbers.firstWhere((n) => n.id == _selectedVfNumberId);

    try {
      await context.read<DistributionProvider>().creditReturn(
        retailerId: retailer.id,
        vfNumberId: vfNum.id,
        vfPhone: vfNum.phoneNumber,
        amount: amount,
        fees: fees,
        createdByUid: auth.currentUser?.uid ?? 'admin',
        notes: _notesController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('credit_return_success'.tr()), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('error_with_msg'.tr(args: [e.toString()])), backgroundColor: Colors.red),
      );
    }
  }
}