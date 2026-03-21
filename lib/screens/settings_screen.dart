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
  final _syncPassCtrl = TextEditingController();

  bool _showSecret = false;
  bool _isSaving = false;
  bool _isSyncing = false;
  bool _isSavingSyncPass = false;
  DateTime? _selectedDate;
  bool _isUnlocked = false;
  final _promptCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<AppProvider>();
    _syncPassCtrl.text = provider.syncPassword ?? '';
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _apiSecretCtrl.dispose();
    _syncPassCtrl.dispose();
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
    final syncPass = provider.syncPassword;

    // Check if locked
    if (syncPass != null && syncPass.isNotEmpty && !_isUnlocked) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0F1A),
        appBar: AppBar(
          title: Text('settings'.tr()),
          backgroundColor: const Color(0xFF16162A),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16162A),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_person_outlined, size: 48, color: Color(0xFFE63946)),
                ),
                const SizedBox(height: 24),
                Text(
                  'settings_locked'.tr(),
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'enter_pass_to_access'.tr(),
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: TextField(
                    controller: _promptCtrl,
                    obscureText: true,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Password',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.password, color: Colors.white54),
                    ),
                    onSubmitted: (val) {
                      if (val == syncPass) {
                        setState(() => _isUnlocked = true);
                      } else {
                        _showSnack('Incorrect password');
                        _promptCtrl.clear();
                      }
                    },
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    if (_promptCtrl.text == syncPass) {
                      setState(() => _isUnlocked = true);
                    } else {
                      _showSnack('Incorrect password');
                      _promptCtrl.clear();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE63946),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('unlock'.tr()),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
                    SwitchListTile(
                      title: const Text('Server-Side Sync', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Sync orders automatically in the cloud', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      value: provider.useServerSync,
                      activeColor: const Color(0xFFE63946),
                      onChanged: (val) => provider.toggleServerSync(val),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(height: 12),
                    TextFormField(
                      controller: _syncPassCtrl,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Sync Protection Password',
                        labelStyle: const TextStyle(color: Colors.white54),
                        hintText: 'Enter password to lock toggle',
                        hintStyle: const TextStyle(color: Colors.white24),
                        prefixIcon: const Icon(Icons.security, color: Colors.white54),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSavingSyncPass ? null : () async {
                          setState(() => _isSavingSyncPass = true);
                          try {
                            final pass = _syncPassCtrl.text.trim();
                            await context.read<AppProvider>().setSyncPassword(pass.isEmpty ? null : pass);
                            _showSnack('Sync password updated!', isError: false);
                          } finally {
                            if (mounted) setState(() => _isSavingSyncPass = false);
                          }
                        },
                        icon: _isSavingSyncPass 
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.lock_outline),
                        label: const Text('Save Sync Password'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const Divider(height: 24),

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

