import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/distribution_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/financial_transaction.dart';
import '../../models/partner.dart';
import '../../models/partner_profit_snapshot.dart';
import '../../utils/formatters.dart';
import '../../utils/utils.dart';
import '../../theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';

class PartnersScreen extends StatefulWidget {
  const PartnersScreen({super.key});

  @override
  State<PartnersScreen> createState() => _PartnersScreenState();
}

class _PartnersScreenState extends State<PartnersScreen> {
  final _workingDaysController = TextEditingController(text: '1');
  final _dateController = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
  bool _showInactive = false;

  @override
  void dispose() {
    _workingDaysController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  void _showRebuildSnapshotsDialog() {
    final startCtrl = TextEditingController(text: '2026-03-18');
    final endCtrl = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    bool resetPaid = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surfaceColor(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Row(
            children: [
              Icon(Icons.refresh, color: Colors.orange),
              const SizedBox(width: 12),
              Text('Rebuild Snapshots', style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Rebuild all system, investor, and partner snapshots for a date range.',
                style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13)),
              const SizedBox(height: 20),
              TextField(
                controller: startCtrl,
                decoration: InputDecoration(
                  labelText: 'Start Date',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: endCtrl,
                decoration: InputDecoration(
                  labelText: 'End Date',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                title: Text('Reset paid flags', style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 14)),
                subtitle: Text('Mark all as unpaid', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12)),
                value: resetPaid,
                onChanged: (v) => setDialogState(() => resetPaid = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('cancel'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () async {
                final dist = context.read<DistributionProvider>();
                try {
                  final res = await dist.rebuildProfitSnapshots(
                    startDate: startCtrl.text,
                    endDate: endCtrl.text,
                    resetPaidFlags: resetPaid,
                  );
                  if (context.mounted) {
                    final count = res['count'] ?? 0;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Rebuilt $count days successfully'),
                      backgroundColor: AppTheme.positiveColor(context),
                    ));
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(e.toString()),
                      backgroundColor: AppTheme.errorColor(context),
                    ));
                  }
                }
              },
              child: const Text('Rebuild', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showCalculateProfitDialog() {
    final dist = context.read<DistributionProvider>();

    // The VF module start date — used when nothing has been paid yet (first ever run).
    final DateTime moduleStartDate = DateTime(2026, 3, 18);

    // If profits have been paid for some days, the NEW period starts the day AFTER
    // the latest paid snapshot. This prevents old paid days from diluting the
    // allocationRatio for the new period (their profit was already extracted from the bank).
    // If nothing is paid yet, we start from the module start date (full history).
    DateTime startDate = moduleStartDate;
    final allSnaps = dist.partnerSnapshots.values.expand((e) => e).toList();
    final paidSnaps = allSnaps.where((s) => s.isPaid).toList();
    if (paidSnaps.isNotEmpty) {
      paidSnaps.sort((a, b) => b.date.compareTo(a.date));
      try {
        final latestPaidDate = DateFormat('yyyy-MM-dd').parse(paidSnaps.first.date);
        startDate = latestPaidDate.add(const Duration(days: 1));
      } catch (_) {}
    }

    DateTime latestLedgerDate = DateTime.now();
    final distTxs = dist.ledger.where((tx) => tx.type == FlowType.DISTRIBUTE_VFCASH || tx.type == FlowType.DISTRIBUTE_INSTAPAY).toList();
    if (distTxs.isNotEmpty) {
      distTxs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      latestLedgerDate = distTxs.first.timestamp;
    }

    _dateController.text = DateFormat('yyyy-MM-dd').format(latestLedgerDate);

    // +1 to include both the start date and end date in the range
    final diff = latestLedgerDate.difference(startDate).inDays + 1;
    _workingDaysController.text = (diff > 1 ? diff : 1).toString();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surfaceColor(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Row(
            children: [
              Icon(Icons.calculate_outlined, color: AppTheme.accent),
              const SizedBox(width: 12),
              Text('calculate_profit'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w900, fontSize: 20)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                paidSnaps.isNotEmpty
                  ? 'New period starts: ${DateFormat('MMM dd, yyyy').format(startDate)} (day after last paid profit)'
                  : 'First run — full history from: ${DateFormat('MMM dd, yyyy').format(startDate)}',
                style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.1)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: AppTheme.accent),
                        const SizedBox(width: 8),
                        Text('Professional Reconciliation', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This will calculate profit based on Lifetime Collections vs Liquid Assets since the start (VF: Mar 18 | Insta: Apr 9).',
                      style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Date Selection
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: startDate,
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    builder: (context, child) => Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: ColorScheme.dark(
                          primary: AppTheme.accent,
                          onPrimary: Colors.white,
                          surface: AppTheme.surfaceColor(context),
                          onSurface: AppTheme.textPrimaryColor(context),
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    setDialogState(() {
                      _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
                      final newDiff = picked.difference(startDate).inDays + 1;
                      _workingDaysController.text = (newDiff > 1 ? newDiff : 1).toString();
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceRaisedColor(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.lineColor(context)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, size: 18, color: AppTheme.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('calculation_date'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11)),
                            Text(_dateController.text, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_drop_down, color: AppTheme.textMutedColor(context)),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Information Row
              Row(
                children: [
                  Expanded(
                    child: _buildMiniStat('VF Start', 'Mar 18', context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMiniStat('Insta Start', 'Apr 9', context),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: Text('cancel'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context)))
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () async {
                try {
                  await dist.calculatePartnerDailyProfit(
                    date: _dateController.text,
                    workingDays: int.tryParse(_workingDaysController.text) ?? 1,
                  ).then((res) {
                    if (context.mounted) {
                      final rawNet = res['businessNetProfitAfterInvestors'] ?? res['businessNetProfit'];
                      final double net = (rawNet is num) ? rawNet.toDouble() : 0.0;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Success: Net Profit ${Formatters.formatCurrency(net)}'),
                        backgroundColor: AppTheme.positiveColor(context),
                      ));
                    }
                  });
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(e.toString()),
                      backgroundColor: AppTheme.errorColor(context),
                    ));
                  }
                }
              },
              child: Text('calculate'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPartnerDialog([Partner? partner]) {
    final nameController = TextEditingController(text: partner?.name ?? '');
    final shareController = TextEditingController(text: partner?.sharePercent.toString() ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(partner == null ? 'add_partner'.tr() : 'edit_partner'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'name'.tr(),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: shareController,
              decoration: InputDecoration(
                labelText: 'share_percent'.tr(),
                suffixText: '%',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('cancel'.tr())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (nameController.text.isEmpty || shareController.text.isEmpty) return;
              
              final provider = context.read<DistributionProvider>();
              final double share = double.tryParse(shareController.text) ?? 0;
              
              final newPartner = Partner(
                id: partner?.id,
                name: nameController.text,
                sharePercent: share,
                totalProfitPaid: partner?.totalProfitPaid ?? 0,
                createdAt: partner?.createdAt,
                status: partner?.status ?? 'active',
              );

              try {
                await provider.savePartner(newPartner);
                if (mounted) Navigator.pop(context);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: Text('save'.tr()),
          ),
        ],
      ),
    );
  }

  void _showPaymentDialog(Partner partner, List<PartnerProfitSnapshot> unpaidSnapshots) {
    if (unpaidSnapshots.isEmpty) return;

    final selectedDates = <String>{unpaidSnapshots.first.date};
    String sourceType = 'bank';
    String? sourceId;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final provider = context.watch<DistributionProvider>();
          final totalAmount = unpaidSnapshots
            .where((s) => selectedDates.contains(s.date))
            .fold(0.0, (sum, s) => sum + s.partnerProfit);

          return AlertDialog(
            backgroundColor: AppTheme.surfaceColor(context),
            title: Text('pay_partner_profit'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context))),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${'partner'.tr()}: ${partner.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Text('select_dates'.tr()),
                  ...unpaidSnapshots.map((s) => CheckboxListTile(
                    title: Text(s.date, style: TextStyle(color: AppTheme.textPrimaryColor(context))),
                    subtitle: Text(Formatters.formatCurrency(s.partnerProfit), style: const TextStyle(color: Colors.green)),
                    value: selectedDates.contains(s.date),
                    onChanged: (val) {
                      setDialogState(() {
                        if (val == true) selectedDates.add(s.date);
                        else selectedDates.remove(s.date);
                      });
                    },
                  )),
                  const Divider(),
                  DropdownButtonFormField<String>(
                    dropdownColor: AppTheme.surfaceColor(context),
                    value: sourceType,
                    decoration: InputDecoration(labelText: 'source_type'.tr()),
                    items: [
                      DropdownMenuItem(value: 'bank', child: Text('bank'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context)))),
                      DropdownMenuItem(value: 'vf', child: Text('vf_number'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context)))),
                    ],
                    onChanged: (val) {
                      setDialogState(() {
                        sourceType = val!;
                        sourceId = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  if (sourceType == 'bank')
                    DropdownButtonFormField<String>(
                      dropdownColor: AppTheme.surfaceColor(context),
                      value: sourceId,
                      decoration: InputDecoration(labelText: 'bank_account'.tr()),
                      items: provider.bankAccounts.map((b) => DropdownMenuItem(
                        value: b.id,
                        child: Text('${b.bankName} (${CurrencyUtils.formatCompactNumber(b.balance)})', style: TextStyle(color: AppTheme.textPrimaryColor(context))),
                      )).toList(),
                      onChanged: (val) => setDialogState(() => sourceId = val),
                    ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Total: ${Formatters.formatCurrency(totalAmount)}', 
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('cancel'.tr())),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
                onPressed: (selectedDates.isEmpty || sourceId == null) ? null : () async {
                  try {
                    await provider.payPartnerProfit(
                      partnerId: partner.id,
                      dates: selectedDates.toList(),
                      paymentSourceType: sourceType,
                      paymentSourceId: sourceId!,
                      createdByUid: context.read<AuthProvider>().currentUser?.uid ?? 'system',
                    );
                    if (mounted) Navigator.pop(context);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                },
                child: Text('pay'.tr(), style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DistributionProvider>();
    final isAdmin = context.watch<AuthProvider>().currentUser?.isAdmin ?? false;

    final filteredPartners = provider.partners.where((p) => _showInactive || p.status == 'active').toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: AppTheme.backgroundGradient(context), begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context, provider),
              Expanded(
                child: provider.isPartnerLoading
                    ? const Center(child: CircularProgressIndicator())
                    : provider.partners.isEmpty
                        ? _buildEmptyState(context, isAdmin, provider)
                        : RefreshIndicator(
                            onRefresh: provider.loadAll,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              itemCount: filteredPartners.length,
                              itemBuilder: (ctx, idx) => _buildPartnerCard(context, filteredPartners[idx], provider, isAdmin),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: isAdmin ? FloatingActionButton.extended(
        backgroundColor: AppTheme.accent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('add_partner'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () => _showPartnerDialog(),
      ) : null,
    );
  }

  Widget _buildHeader(BuildContext context, DistributionProvider provider) {
    final totalOwed = provider.totalPartnerProfitOwed;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('partners'.tr(), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.textPrimaryColor(context), letterSpacing: -1)),
                  Text('management_panel'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context), fontWeight: FontWeight.w500)),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.orange),
                    onPressed: _showRebuildSnapshotsDialog,
                    tooltip: 'Rebuild Snapshots',
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, color: AppTheme.accent),
                    onPressed: _showReconciliationSettings,
                    tooltip: 'Module Settings',
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(_showInactive ? Icons.visibility : Icons.visibility_off, color: AppTheme.accent),
                    onPressed: () => setState(() => _showInactive = !_showInactive),
                    tooltip: 'toggle_inactive'.tr(),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _showCalculateProfitDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: AppTheme.heroGradient(context)),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: AppTheme.softShadow(context),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calculate, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text('calculate'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: AppTheme.panelGradient(context), begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppTheme.lineColor(context).withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('total_unpaid_profit'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context), fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(Formatters.formatCurrency(totalOwed), style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppTheme.accent, letterSpacing: -0.5)),
                  ],
                ),
                Icon(Icons.account_balance_wallet, color: AppTheme.accent.withValues(alpha: 0.2), size: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isAdmin, DistributionProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: AppTheme.textMutedColor(context).withValues(alpha: 0.3)),
          const SizedBox(height: 20),
          Text('no_partners_found'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 18, fontWeight: FontWeight.w500)),
          if (isAdmin) ...[
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () => provider.seedPartners(),
              icon: const Icon(Icons.auto_fix_high),
              label: Text('seed_initial_partners'.tr()),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPartnerCard(BuildContext context, Partner partner, DistributionProvider provider, bool isAdmin) {
    final currentSnapshots = (provider.partnerSnapshots[partner.id] ?? [])
        .where((s) => s.isCurrentVersion)
        .toList();
    final unpaidSnapshots = currentSnapshots.where((s) => !s.isPaid).toList();
    final latestSnapshot = currentSnapshots.isNotEmpty ? currentSnapshots.first : null;
    final totalUnpaid = provider.partnerUnpaidTotalFor(partner.id);
    final isInactive = partner.status != 'active';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(30),
        boxShadow: AppTheme.softShadow(context),
        border: Border.all(color: isInactive ? Colors.grey.withValues(alpha: 0.3) : AppTheme.lineColor(context)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            backgroundColor: isInactive ? Colors.black.withValues(alpha: 0.05) : null,
            collapsedBackgroundColor: isInactive ? Colors.black.withValues(alpha: 0.05) : null,
            tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            title: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(partner.name, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: isInactive ? Colors.grey : AppTheme.textPrimaryColor(context), letterSpacing: -0.5)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${'share'.tr()}: ${partner.sharePercent}%', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                if (isAdmin) PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: AppTheme.textMutedColor(context)),
                  onSelected: (value) {
                    if (value == 'edit') _showPartnerDialog(partner);
                    else if (value == 'toggle') {
                      provider.setPartnerStatus(partner.id, isInactive ? 'active' : 'inactive');
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(value: 'edit', child: Row(children: [const Icon(Icons.edit, size: 18), const SizedBox(width: 8), Text('edit'.tr())])),
                    PopupMenuItem(
                      value: 'toggle', 
                      child: Row(children: [
                        Icon(isInactive ? Icons.check_circle_outline : Icons.block, size: 18, color: isInactive ? Colors.green : Colors.red), 
                        const SizedBox(width: 8), 
                        Text(isInactive ? 'activate'.tr() : 'inactivate'.tr(), style: TextStyle(color: isInactive ? Colors.green : Colors.red))
                      ])),
                  ],
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (latestSnapshot != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Dist=${latestSnapshot.vfDailyFlow.toStringAsFixed(0)} | Margin=${latestSnapshot.systemVfProfitPer1000.toStringAsFixed(2)} | Partner=${latestSnapshot.partnerProfit.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildMiniStat('paid'.tr(), Formatters.formatCurrency(partner.totalProfitPaid), context, Colors.green),
                    const SizedBox(width: 16),
                    _buildMiniStat('unpaid'.tr(), Formatters.formatCurrency(totalUnpaid), context, totalUnpaid > 0 ? Colors.orange : AppTheme.textMutedColor(context)),
                  ],
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 32),
                    if (latestSnapshot != null) ...[
                      Text('latest_performance'.tr(), style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textPrimaryColor(context), fontSize: 15)),
                      const SizedBox(height: 16),
                      _buildPerformanceRow('VF Distributed', Formatters.formatCurrency(latestSnapshot.totalDistVf), context),
                      if (latestSnapshot.outstandingRetailerVfDebt > 0)
                        _buildPerformanceRow('Outstanding (retailers)', '- ${Formatters.formatCurrency(latestSnapshot.outstandingRetailerVfDebt)}', context, isNegative: true),
                      _buildPerformanceRow('Effective VF Dist', Formatters.formatCurrency(latestSnapshot.effectiveVfDist), context),
                      const SizedBox(height: 4),
                      _buildPerformanceRow('Gross Profit', Formatters.formatCurrency(latestSnapshot.businessGrossProfit), context),
                      if (latestSnapshot.totalFees > 0)
                        _buildPerformanceRow('Fees & Expenses', '- ${Formatters.formatCurrency(latestSnapshot.totalFees)}', context, isNegative: true),
                      _buildPerformanceRow('business_net_profit'.tr(), Formatters.formatCurrency(latestSnapshot.businessNetProfitAfterInvestors), context),
                      if (latestSnapshot.totalInvestorProfitDeducted > 0)
                        _buildPerformanceRow('Investor Deduction', '- ${Formatters.formatCurrency(latestSnapshot.totalInvestorProfitDeducted)}', context, isNegative: true),
                      _buildPerformanceRow('partner_share'.tr(), Formatters.formatCurrency(latestSnapshot.partnerProfit), context, isHighlighted: true),
                      const SizedBox(height: 20),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                            onPressed: (unpaidSnapshots.isEmpty || isInactive) ? null : () => _showPaymentDialog(partner, unpaidSnapshots),
                            child: Text('pay_profit'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                    if (currentSnapshots.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text('recent_history'.tr(), style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textPrimaryColor(context), fontSize: 14)),
                      const SizedBox(height: 10),
                      ...currentSnapshots.take(3).map((s) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(color: AppTheme.lineColor(context).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(s.date, style: TextStyle(color: AppTheme.textMutedColor(context), fontWeight: FontWeight.bold, fontSize: 13)),
                            Text(Formatters.formatCurrency(s.partnerProfit), style: TextStyle(color: s.isPaid ? Colors.green : Colors.orange, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      )),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, BuildContext context, [Color? valueColor]) {
    if (valueColor != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.w800, fontSize: 14)),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaisedColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lineColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w900, fontSize: 13)),
        ],
      ),
    );
  }

  void _showReconciliationSettings() async {
    final db = FirebaseDatabase.instance.ref('system_config/module_start_dates');
    final snap = await db.get();
    final data = snap.exists ? Map<String, dynamic>.from(snap.value as Map) : {
      'vf': '2026-03-18',
      'instapay': '2026-04-09'
    };

    final vfController = TextEditingController(text: data['vf']);
    final instaController = TextEditingController(text: data['instapay']);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Row(
          children: [
            Icon(Icons.settings_suggest_outlined, color: AppTheme.accent),
            const SizedBox(width: 12),
            const Text('Module Settings', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Set the official start dates for each module. These are used to calculate accurate daily flow.',
              style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: vfController,
              style: TextStyle(color: AppTheme.textPrimaryColor(context)),
              decoration: InputDecoration(
                labelText: 'VF Cash Start Date',
                hintText: 'YYYY-MM-DD',
                prefixIcon: const Icon(Icons.date_range),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: instaController,
              style: TextStyle(color: AppTheme.textPrimaryColor(context)),
              decoration: InputDecoration(
                labelText: 'InstaPay Start Date',
                hintText: 'YYYY-MM-DD',
                prefixIcon: const Icon(Icons.date_range),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('cancel'.tr())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () async {
              await db.set({
                'vf': vfController.text,
                'instapay': instaController.text,
              });
              if (mounted) Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved. Refreshing logic...')));
              }
            },
            child: const Text('Save Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceRow(String label, String value, BuildContext context, {bool isHighlighted = false, bool isNegative = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textMutedColor(context), fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(
            color: isHighlighted
                ? AppTheme.accent
                : isNegative
                    ? AppTheme.errorColor(context)
                    : AppTheme.textPrimaryColor(context),
            fontWeight: isHighlighted ? FontWeight.w900 : FontWeight.w700,
            fontSize: isHighlighted ? 16 : 14,
          )),
        ],
      ),
    );
  }
}
