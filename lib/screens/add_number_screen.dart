import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/app_provider.dart';

class AddNumberScreen extends StatefulWidget {
  const AddNumberScreen({Key? key}) : super(key: key);

  @override
  State<AddNumberScreen> createState() => _AddNumberScreenState();
}

class _AddNumberScreenState extends State<AddNumberScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _phoneController;
  late TextEditingController _initialBalanceController;
  late TextEditingController _inDailyLimitController;
  late TextEditingController _inMonthlyLimitController;
  late TextEditingController _outDailyLimitController;
  late TextEditingController _outMonthlyLimitController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    _initialBalanceController = TextEditingController(text: '0');
    _inDailyLimitController = TextEditingController(text: '50000');
    _inMonthlyLimitController = TextEditingController(text: '1000000');
    _outDailyLimitController = TextEditingController(text: '60000');
    _outMonthlyLimitController = TextEditingController(text: '1000000');
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _initialBalanceController.dispose();
    _inDailyLimitController.dispose();
    _inMonthlyLimitController.dispose();
    _outDailyLimitController.dispose();
    _outMonthlyLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('add_number'.tr()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('basic_info'.tr()),
              _buildLabel('phone_number'.tr()),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: _buildInputDecoration(
                  hint: '+20 123 456 7890',
                  icon: Icons.phone,
                ),
                validator: (val) =>
                    val?.isEmpty ?? true ? 'required'.tr() : null,
              ),
              const SizedBox(height: 16),
              _buildLabel('opening_balance'.tr()),
              TextFormField(
                controller: _initialBalanceController,
                keyboardType: TextInputType.number,
                decoration: _buildInputDecoration(
                  hint: '0.00',
                  icon: Icons.account_balance_wallet,
                ),
                validator: _validateNumber,
              ),
              const Divider(height: 48),
              _buildSectionTitle('incoming_limits'.tr()),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('daily_limit'.tr()),
                        TextFormField(
                          controller: _inDailyLimitController,
                          keyboardType: TextInputType.number,
                          decoration: _buildInputDecoration(hint: '50000'),
                          validator: _validateNumber,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('monthly_limit'.tr()),
                        TextFormField(
                          controller: _inMonthlyLimitController,
                          keyboardType: TextInputType.number,
                          decoration: _buildInputDecoration(hint: '1000000'),
                          validator: _validateNumber,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 48),
              _buildSectionTitle('outgoing_limits'.tr()),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('daily_limit'.tr()),
                        TextFormField(
                          controller: _outDailyLimitController,
                          keyboardType: TextInputType.number,
                          decoration: _buildInputDecoration(hint: '60000'),
                          validator: _validateNumber,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('monthly_limit'.tr()),
                        TextFormField(
                          controller: _outMonthlyLimitController,
                          keyboardType: TextInputType.number,
                          decoration: _buildInputDecoration(hint: '1000000'),
                          validator: _validateNumber,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isLoading ? null : _handleAddNumber,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text('save'.tr(),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }

  InputDecoration _buildInputDecoration({required String hint, IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  String? _validateNumber(String? val) {
    if (val?.isEmpty ?? true) return 'required'.tr();
    if (double.tryParse(val!) == null) return 'invalid_number'.tr();
    return null;
  }

  Future<void> _handleAddNumber() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await context.read<AppProvider>().addMobileNumber(
            phoneNumber: _phoneController.text,
            initialBalance: double.parse(_initialBalanceController.text),
            inDailyLimit: double.parse(_inDailyLimitController.text),
            inMonthlyLimit: double.parse(_inMonthlyLimitController.text),
            outDailyLimit: double.parse(_outDailyLimitController.text),
            outMonthlyLimit: double.parse(_outMonthlyLimitController.text),
          );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('add_success'.tr())),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
