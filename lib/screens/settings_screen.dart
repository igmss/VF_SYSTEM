import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import '../providers/app_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

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

  Future<void> _saveCredentials() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await context
          .read<AppProvider>()
          .saveApiCredentials(_apiKeyCtrl.text.trim(), _apiSecretCtrl.text.trim());
      _showSnack('creds_saved'.tr(), isError: false);
    } catch (e) {
      _showSnack('${'error'.tr()}: $e');
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
      initialDate: DateTime.now(),
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
    _showSnack(
      'sync_started'.tr(args: [DateFormat('dd MMM yyyy').format(_selectedDate!)]),
      isError: false,
    );
    await _doSync(fromDate: _selectedDate);
  }

  Future<void> _runAutoSync() async {
    _showSnack('sync_incremental'.tr(), isError: false);
    await _doSync();
  }

  Future<void> _doSync({DateTime? fromDate}) async {
    setState(() => _isSyncing = true);
    try {
      final result = await context.read<AppProvider>().syncOrders(fromDate: fromDate);
      if (mounted) {
        _showSnack(result.toString(), isError: !result.isSuccess);
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final hasCredentials = provider.hasApiCredentials;
    final lastSync = provider.lastSyncTime;
    final syncStatus = provider.syncStatus;
    final isDark = AppTheme.isDark(context);
    final surface = AppTheme.surfaceColor(context);
    final raised = AppTheme.surfaceRaisedColor(context);
    final textPrimary = AppTheme.textPrimaryColor(context);
    final auth = context.watch<AuthProvider>();
    final isEmbedded = auth.isAdmin || auth.isFinance;
    final textMuted = AppTheme.textMutedColor(context);

    final bodyContent = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? AppTheme.panelGradient(context)
                      : const [Color(0xFFFFFBF4), Color(0xFFF2E5D2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.lineColor(context)),
                boxShadow: AppTheme.softShadow(context),
              ),
              child: Text(
                'Control theme, credentials, and data operations from one cleaner settings workspace.',
                style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600, height: 1.35),
              ),
            ),
            _sectionHeader('Appearance'),
            _panel(
              context,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Theme mode',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose a system, light, or dark look for the app shell.',
                      style: TextStyle(fontSize: 12, color: textMuted),
                    ),
                    const SizedBox(height: 14),
                    SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto_outlined),
                          label: Text('System'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined),
                          label: Text('Light'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {themeProvider.themeMode},
                      onSelectionChanged: (selection) {
                        themeProvider.setThemeMode(selection.first);
                      },
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: raised,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppTheme.lineColor(context)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isDark
                                ? Icons.nightlight_round
                                : Icons.wb_sunny_outlined,
                            color: AppTheme.accent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isDark
                                  ? 'Dark mode is active now.'
                                  : 'Light mode is active now.',
                              style: TextStyle(
                                color: textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _sectionHeader('bybit_api_creds'.tr()),
            _panel(
              context,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            hasCredentials ? Icons.check_circle : Icons.cancel,
                            color: hasCredentials ? Colors.green : Colors.orange,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            hasCredentials ? 'creds_configured'.tr() : 'no_creds'.tr(),
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
                        style: TextStyle(color: textPrimary),
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
                        style: TextStyle(color: textPrimary),
                        decoration: InputDecoration(
                          labelText: 'api_secret'.tr(),
                          prefixIcon: const Icon(Icons.lock),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _showSecret ? Icons.visibility_off : Icons.visibility,
                            ),
                            onPressed: () => setState(() => _showSecret = !_showSecret),
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
                                foregroundColor: Colors.red,
                              ),
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
            _sectionHeader('bybit_sync'.tr()),
            _panel(
              context,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.cloud_done, color: Colors.green),
                      title: Text(
                        'Server-Side Sync',
                        style: TextStyle(color: textPrimary),
                      ),
                      subtitle: Text(
                        'Bybit sync now runs only in the cloud. API credentials are no longer stored on this device.',
                        style: TextStyle(color: textMuted, fontSize: 12),
                      ),
                    ),
                    const Divider(height: 12),
                    Text(
                      'Sync control is now role-based. The app no longer exposes a shared sync password to clients.',
                      style: TextStyle(color: textMuted, fontSize: 12),
                    ),
                    const Divider(height: 24),
                    if (lastSync != null) ...[
                      Row(
                        children: [
                          const Icon(Icons.history, size: 16, color: Colors.grey),
                          const SizedBox(width: 6),
                          Text(
                            'last_sync'.tr(args: [DateFormat('dd MMM yyyy, HH:mm').format(lastSync)]),
                            style: TextStyle(color: textMuted, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (syncStatus.isNotEmpty) ...[
                      const LinearProgressIndicator(color: Color(0xFFE63946)),
                      const SizedBox(height: 8),
                      Text(
                        syncStatus,
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      'auto_sync_incremental'.tr(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: textPrimary,
                        ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'auto_sync_desc'.tr(),
                      style: TextStyle(fontSize: 12, color: textMuted),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (!hasCredentials || _isSyncing) ? null : _runAutoSync,
                        icon: _isSyncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync),
                        label: Text('auto_sync_incremental'.tr()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const Divider(height: 32),
                    Text(
                      'full_sync_date'.tr(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'full_sync_desc'.tr(),
                      style: TextStyle(fontSize: 12, color: textMuted),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.calendar_today),
                            label: Text(
                              _selectedDate == null
                                  ? 'pick_date'.tr()
                                  : DateFormat('dd MMM yyyy').format(_selectedDate!),
                            ),
                          ),
                        ),
                        if (_selectedDate != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _selectedDate = null),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (!hasCredentials || _isSyncing || _selectedDate == null)
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
                          'save_creds_first'.tr(),
                          style: const TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _sectionHeader('data_mgmt'.tr()),
            _panel(
              context,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'clear_history'.tr(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'clear_history_desc'.tr(),
                      style: TextStyle(fontSize: 12, color: textMuted),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: provider.isLoading
                            ? null
                            : () => _showDeleteAllConfirmation(context),
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
      );
    if (isEmbedded) {
      return Scaffold(
        backgroundColor: AppTheme.scaffoldBg(context),
        body: bodyContent,
      );
    } else {
      return Scaffold(
        backgroundColor: AppTheme.scaffoldBg(context),
        appBar: AppBar(
          title: Text('settings'.tr(), style: const TextStyle(fontWeight: FontWeight.w800)),
          backgroundColor: surface,
          foregroundColor: textPrimary,
          elevation: 0,
        ),
        body: bodyContent,
      );
    }
  }

  Widget _panel(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.isDark(context)
              ? AppTheme.panelGradient(context)
              : const [Color(0xFFFFFEFB), Color(0xFFF6EFE2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.lineColor(context)),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: child,
    );
  }

  void _showDeleteAllConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(context),
        title: Text(
          'delete_all_data_confirm'.tr(),
          style: TextStyle(color: AppTheme.textPrimaryColor(context)),
        ),
        content: Text(
          'delete_all_data_msg'.tr(),
          style: TextStyle(color: AppTheme.textMutedColor(context)),
        ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE63946),
            ),
            child: Text(
              'delete_everything'.tr(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimaryColor(context),
          ),
        ),
      );
}
