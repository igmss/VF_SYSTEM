import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/app_provider.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiKeyCtrl = TextEditingController();
  final _apiSecretCtrl = TextEditingController();

  bool _showSecret = false;
  bool _isSaving = false;
  bool _isSyncing = false;
  DateTime? _selectedDate;

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _apiSecretCtrl.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _saveCredentials() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await context
          .read<AppProvider>()
          .saveApiCredentials(_apiKeyCtrl.text.trim(), _apiSecretCtrl.text.trim());
      _showSnack('creds_saved'.tr(), isError: false);
    } catch (e) {
      _showSnack('error'.tr() + ': $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _clearCredentials() async {
    await context.read<AppProvider>().clearApiCredentials();
    _apiKeyCtrl.clear();
    _apiSecretCtrl.clear();
    _showSnack('creds_cleared'.tr(), isError: false);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(), // Default to today to avoid wrong month confusion
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'sync_orders'.tr(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _runFullSync() async {
    if (_selectedDate == null) {
      _showSnack('pick_start_date'.tr());
      return;
    }
    _showSnack('sync_started'.tr(args: [DateFormat('dd MMM yyyy').format(_selectedDate!)]), isError: false);
    await _doSync(fromDate: _selectedDate);
  }

  Future<void> _runAutoSync() async {
    _showSnack('sync_incremental'.tr(), isError: false);
    await _doSync();
  }

  Future<void> _doSync({DateTime? fromDate}) async {
    setState(() => _isSyncing = true);
    try {
      final result =
          await context.read<AppProvider>().syncOrders(fromDate: fromDate);
      if (mounted) {
        _showSnack(result.toString(), isError: !result.isSuccess);
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
      duration: const Duration(seconds: 4),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final hasCredentials = provider.hasApiCredentials;
    final lastSync = provider.lastSyncTime;
    final syncStatus = provider.syncStatus;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: Text('settings'.tr()),
        backgroundColor: const Color(0xFF16162A),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── API Credentials ────────────────────────────────────────────
            _sectionHeader('bybit_api_creds'.tr()),
            Card(
              color: const Color(0xFF16162A),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Status chip
                      Row(
                        children: [
                          Icon(
                            hasCredentials ? Icons.check_circle : Icons.cancel,
                            color: hasCredentials ? Colors.green : Colors.orange,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            hasCredentials
                                ? 'creds_configured'.tr()
                                : 'no_creds'.tr(),
                            style: TextStyle(
                              color: hasCredentials ? Colors.green : Colors.orange,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _apiKeyCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'api_key'.tr(),
                          prefixIcon: const Icon(Icons.vpn_key),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'required'.tr() : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _apiSecretCtrl,
                        obscureText: !_showSecret,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'api_secret'.tr(),
                          prefixIcon: const Icon(Icons.lock),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                                _showSecret ? Icons.visibility_off : Icons.visibility),
                            onPressed: () =>
                                setState(() => _showSecret = !_showSecret),
                          ),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'required'.tr() : null,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _saveCredentials,
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.save),
                              label: Text('save'.tr()),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE63946),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          if (hasCredentials) ...[
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: _clearCredentials,
                              icon: const Icon(Icons.delete_outline),
                              label: Text('clear_creds'.tr()),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Sync ───────────────────────────────────────────────────────
            _sectionHeader('bybit_sync'.tr()),
            Card(
              color: const Color(0xFF16162A),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Last sync info
                    if (lastSync != null) ...[
                      Row(
                        children: [
                          const Icon(Icons.history, size: 16, color: Colors.grey),
                          const SizedBox(width: 6),
                          Text(
                            'last_sync'.tr(args: [DateFormat('dd MMM yyyy, HH:mm').format(lastSync)]),
                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Live progress
                    if (syncStatus.isNotEmpty) ...[
                      LinearProgressIndicator(
                          color: const Color(0xFFE63946)),
                      const SizedBox(height: 8),
                      Text(syncStatus,
                          style: const TextStyle(fontSize: 13, color: Colors.grey)),
                      const SizedBox(height: 12),
                    ],

                    // ── Auto Sync ──
                    Text(
                      'auto_sync_incremental'.tr(),
                      style:
                          const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'auto_sync_desc'.tr(),
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            (!hasCredentials || _isSyncing) ? null : _runAutoSync,
                        icon: _isSyncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync),
                        label: Text('auto_sync_incremental'.tr()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE63946),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),

                    const Divider(height: 32),

                    // ── Full Sync ──
                    Text(
                      'full_sync_date'.tr(),
                      style:
                          const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'full_sync_desc'.tr(),
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 10),

                    // Date picker row
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.calendar_today),
                            label: Text(
                              _selectedDate == null
                                  ? 'pick_date'.tr()
                                  : DateFormat('dd MMM yyyy')
                                      .format(_selectedDate!),
                            ),
                          ),
                        ),
                        if (_selectedDate != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                setState(() => _selectedDate = null),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (!hasCredentials ||
                                _isSyncing ||
                                _selectedDate == null)
                            ? null
                            : _runFullSync,
                        icon: const Icon(Icons.download_for_offline_outlined),
                        label: Text('start_full_sync'.tr()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    if (!hasCredentials)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '⚠ ' + 'save_creds_first'.tr(),
                          style: const TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Data Management ───────────────────────────────────────────
            _sectionHeader('data_mgmt'.tr()),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'clear_history'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'clear_history_desc'.tr(),
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: provider.isLoading ? null : () => _showDeleteAllConfirmation(context),
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: Text('delete_all_reset'.tr()),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAllConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16162A),
        title: Text('delete_all_data_confirm'.tr(), style: const TextStyle(color: Colors.white)),
        content: Text('delete_all_data_msg'.tr(), style: const TextStyle(color: Colors.white54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AppProvider>().deleteAllTransactions();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE63946)),
            child: Text('delete_everything'.tr(), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFFE63946),
          ),
        ),
      );
}

