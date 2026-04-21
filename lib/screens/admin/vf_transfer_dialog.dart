import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/app_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

class VfTransferDialog extends StatefulWidget {
  const VfTransferDialog({Key? key}) : super(key: key);

  @override
  State<VfTransferDialog> createState() => _VfTransferDialogState();
}

class _VfTransferDialogState extends State<VfTransferDialog> {
  final _amountCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  
  MobileNumber? _sourceVf;
  MobileNumber? _destVf;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  void _submit() async {
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    final fee = double.tryParse(_feeCtrl.text) ?? 0;

    if (_sourceVf == null || _destVf == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('select_vf_number_first'.tr())),
      );
      return;
    }
    if (_sourceVf!.id == _destVf!.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('same_number_error'.tr())),
      );
      return;
    }
    if (amount <= 0 || fee < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('invalid_amount'.tr())),
      );
      return;
    }

    final totalDeduct = amount + fee;
    // Source should have enough
    if (_sourceVf!.currentBalance < totalDeduct) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('insufficient_balance'.tr())),
      );
      return;
    }

    final dist = context.read<DistributionProvider>();
    try {
      await dist.transferInternalVfCash(
        fromVfId: _sourceVf!.id,
        toVfId: _destVf!.id,
        amount: amount,
        fees: fee,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('transfer_success'.tr()),
            backgroundColor: AppTheme.positiveColor(context),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final dist = context.watch<DistributionProvider>();
    final isDark = AppTheme.isDark(context);
    final numbers = app.mobileNumbers;
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    final fee = double.tryParse(_feeCtrl.text) ?? 0;
    
    final positive = AppTheme.positiveColor(context);
    
    return Dialog(
      backgroundColor: AppTheme.surfaceColor(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: positive.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.sync_alt_rounded, color: positive),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'internal_vf_transfer'.tr(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimaryColor(context),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: AppTheme.textMutedColor(context)),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Source Dropdown
              Text(
                'source_number'.tr(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMutedColor(context),
                ),
              ),
              const SizedBox(height: 8),
              _buildNumberDropdown(
                selected: _sourceVf,
                items: numbers,
                onChanged: (val) => setState(() => _sourceVf = val),
              ),
              
              const SizedBox(height: 16),

              // Destination Dropdown
              Text(
                'destination_number'.tr(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMutedColor(context),
                ),
              ),
              const SizedBox(height: 8),
              _buildNumberDropdown(
                selected: _destVf,
                items: numbers,
                onChanged: (val) => setState(() => _destVf = val),
              ),

              const SizedBox(height: 20),

              // Amount & Fee
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'amount'.tr(),
                        prefixIcon: const Icon(Icons.attach_money),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _feeCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'transfer_fee'.tr(),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Summary Preview
              if (_sourceVf != null || _destVf != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceRaisedColor(context).withValues(alpha: isDark ? 0.8 : 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.lineColor(context)),
                  ),
                  child: Column(
                    children: [
                      if (_sourceVf != null)
                        _buildPreviewRow(
                          context,
                          '${_sourceVf!.name?.isNotEmpty == true ? _sourceVf!.name : _sourceVf!.phoneNumber} (${'balance'.tr()})',
                          _sourceVf!.currentBalance,
                          amount + fee,
                          true,
                        ),
                      if (_sourceVf != null && _destVf != null)
                        const Divider(height: 20, thickness: 1),
                      if (_destVf != null)
                        _buildPreviewRow(
                          context,
                          '${_destVf!.name?.isNotEmpty == true ? _destVf!.name : _destVf!.phoneNumber} (${'balance'.tr()})',
                          _destVf!.currentBalance,
                          amount,
                          false,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Actions
              SizedBox(
                width: double.infinity,
                height: 52,
                child: dist.isInternalTransferring
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: positive,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _submit,
                        child: Text(
                          'confirm_transfer_label'.tr(),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumberDropdown({
    required MobileNumber? selected,
    required List<MobileNumber> items,
    required ValueChanged<MobileNumber?> onChanged,
  }) {
    final isDark = AppTheme.isDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaisedColor(context).withValues(alpha: isDark ? 0.8 : 0.5),
        border: Border.all(color: AppTheme.lineColor(context)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MobileNumber>(
          value: selected,
          hint: Text('select_vf_number'.tr()),
          isExpanded: true,
          dropdownColor: AppTheme.surfaceRaisedColor(context),
          borderRadius: BorderRadius.circular(16),
          items: items.map((num) {
            return DropdownMenuItem<MobileNumber>(
              value: num,
              child: Row(
                children: [
                  Text(
                    num.phoneNumber,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimaryColor(context),
                    ),
                  ),
                  if (num.name?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Text(
                        num.name!,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMutedColor(context),
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    '${num.currentBalance.toStringAsFixed(0)} EGP',
                    style: TextStyle(
                      color: AppTheme.textMutedColor(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildPreviewRow(BuildContext context, String label, double currentBal, double amountDelta, bool isDeduct) {
    final newBal = isDeduct ? (currentBal - amountDelta) : (currentBal + amountDelta);
    final isZeroDelta = amountDelta == 0;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textMutedColor(context),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${currentBal.toStringAsFixed(2)} EGP',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textMutedColor(context),
                decoration: isZeroDelta ? null : TextDecoration.lineThrough,
              ),
            ),
            if (!isZeroDelta)
              Text(
                '${newBal.toStringAsFixed(2)} EGP',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDeduct ? Colors.red : AppTheme.positiveColor(context),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
