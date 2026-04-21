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


  void _showModuleSettings() {
    _showReconciliationSettings();
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

  void _showPaymentDialog(Partner partner, double payable) {
    if (payable <= 0) return;

    final amountCtrl = TextEditingController(text: payable.toStringAsFixed(2));
    final notesCtrl = TextEditingController();
    String sourceType = 'bank';
    String? sourceId;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final provider = context.watch<DistributionProvider>();

          return AlertDialog(
            backgroundColor: AppTheme.surfaceColor(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
            title: Text('pay_partner_profit'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w900)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${'partner'.tr()}: ${partner.name}', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13)),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                       labelText: 'amount'.tr(),
                       suffixText: 'EGP',
                       helperText: 'Max Payable: ${Formatters.formatCurrency(payable)}',
                    ),
                  ),
                  const SizedBox(height: 16),
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
                  TextFormField(
                    controller: notesCtrl,
                    style: TextStyle(color: AppTheme.textPrimaryColor(context)),
                    decoration: InputDecoration(
                      labelText: 'notes'.tr(),
                      prefixIcon: const Icon(Icons.notes),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('cancel'.tr())),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: (sourceId == null || provider.isPartnerLoading) ? null : () async {
                  try {
                    final amount = double.tryParse(amountCtrl.text) ?? 0.0;
                    await provider.payPartnerProfit(
                      partnerId: partner.id,
                      amount: amount,
                      paymentSourceType: sourceType,
                      paymentSourceId: sourceId!,
                      createdByUid: context.read<AuthProvider>().currentUser?.uid ?? 'system',
                      notes: notesCtrl.text,
                    );
                    if (mounted) Navigator.pop(context);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                },
                child: Text('pay'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                  GestureDetector(
                    onTap: provider.loadAll,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: AppTheme.heroGradient(context)),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: AppTheme.softShadow(context),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.refresh, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text('Refresh', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: AppTheme.textMutedColor(context)),
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'settings') _showReconciliationSettings();
                      else if (value == 'toggle') setState(() => _showInactive = !_showInactive);
                      else if (value == 'history') {
                         // TODO: Show global payout history
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'settings',
                        child: Row(
                          children: [
                            Icon(Icons.settings_outlined, color: AppTheme.accent, size: 18),
                            const SizedBox(width: 10),
                            Text('Module Settings', style: TextStyle(fontSize: 14, color: AppTheme.textPrimaryColor(context))),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Row(
                          children: [
                            Icon(_showInactive ? Icons.visibility : Icons.visibility_off, color: AppTheme.accent, size: 18),
                            const SizedBox(width: 10),
                            Text(_showInactive ? 'Hide Inactive' : 'Show Inactive', style: TextStyle(fontSize: 14, color: AppTheme.textPrimaryColor(context))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 30),
          InkWell(
            onTap: _showReconciliationSettings,
            borderRadius: BorderRadius.circular(24),
            child: FutureBuilder<Map<String, dynamic>>(
            future: provider.getPartnerPerformance(),
            builder: (context, snapshot) {
              final perf = snapshot.data;
              final assets = perf?['assetsSummary'];
              final totalAssets = assets?['currentTotalAssets']?.toDouble() ?? 0.0;
              final netPool = perf?['partnerPool']?.toDouble() ?? 0.0;
              final totalLoans = assets?['totalOutstandingLoans']?.toDouble() ?? 0.0;

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppTheme.panelGradient(context),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(color: AppTheme.lineColor(context).withValues(alpha: 0.2)),
                ),
                child: snapshot.connectionState == ConnectionState.waiting
                  ? const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'total_business_assets'.tr().toUpperCase(),
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.5),
                          ),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.account_balance_wallet_outlined, color: Colors.white70, size: 13),
                                    const SizedBox(width: 5),
                                    Text(
                                      'OC: ${Formatters.formatCurrency(provider.openingCapital)}',
                                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.edit_outlined, color: Colors.white38, size: 16),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        Formatters.formatCurrency(totalAssets),
                        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _MiniPoolItem(label: 'Net Pool', amount: netPool, color: AppTheme.accent),
                          _MiniPoolItem(label: 'Loans', amount: totalLoans, color: Colors.white70),
                          _MiniPoolItem(label: 'Unpaid', amount: provider.totalPartnerProfitOwed, color: Colors.orange),
                        ],
                      ),
                    ],
                  ),
              );
            }
          ),
          ), // closes InkWell
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
    final isInactive = partner.status != 'active';
    
    return FutureBuilder<Map<String, dynamic>>(
      future: provider.getPartnerPerformance(),
      builder: (context, snapshot) {
        final perf = snapshot.data?['partnerBreakdown']?[partner.id];
        final double earned = perf?['totalEarned']?.toDouble() ?? 0.0;
        final double paid = perf?['totalPaid']?.toDouble() ?? 0.0;
        final double payable = perf?['payableBalance']?.toDouble() ?? 0.0;

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
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(partner.name, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: isInactive ? Colors.grey : AppTheme.textPrimaryColor(context), letterSpacing: -0.5)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('${'share'.tr()}: ${partner.sharePercent}%', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w800, fontSize: 11)),
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
                ),
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMiniStat('lifetime_earned'.tr(), Formatters.formatCurrency(earned), context, Colors.white70),
                      _buildMiniStat('total_paid'.tr(), Formatters.formatCurrency(paid), context, Colors.green),
                      _buildMiniStat('payable'.tr(), Formatters.formatCurrency(payable), context, payable > 0 ? AppTheme.accent : Colors.grey),
                    ],
                  ),
                ),
                
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shadowColor: AppTheme.accent.withValues(alpha: 0.5),
                            elevation: 8,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          onPressed: (payable <= 0 || isInactive) ? null : () => _showPaymentDialog(partner, payable),
                          child: Text('pay_profit'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildMiniStat(String label, String value, BuildContext context, [Color? valueColor]) {
    if (valueColor != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: -0.5)),
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

    final provider = Provider.of<DistributionProvider>(context, listen: false);
    final perf = await provider.getPartnerPerformance();
    final assets = perf['assetsSummary'];
    final totalLoans = assets?['totalOutstandingLoans']?.toDouble() ?? 0.0;

    final vfController = TextEditingController(text: data['vf']);
    final instaController = TextEditingController(text: data['instapay']);
    final capitalController = TextEditingController(text: provider.openingCapital.toStringAsFixed(0));

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final currentCap = double.tryParse(capitalController.text) ?? provider.openingCapital;
          final effectiveCap = currentCap - totalLoans;

          return AlertDialog(
            backgroundColor: AppTheme.surfaceColor(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            title: Row(
              children: [
                Icon(Icons.settings_suggest_outlined, color: AppTheme.accent),
                const SizedBox(width: 12),
                const Text('Module Settings', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
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
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  TextField(
                    controller: capitalController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: AppTheme.textPrimaryColor(context)),
                    decoration: InputDecoration(
                      labelText: 'Partner Opening Capital',
                      hintText: 'e.g. 180000',
                      prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceRaisedColor(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.lineColor(context)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Minus Total Loans:', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12)),
                            Text('- ${Formatters.formatCurrency(totalLoans)}', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Effective Hurdle Base:', style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold, fontSize: 13)),
                            Text(Formatters.formatCurrency(effectiveCap), style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w900, fontSize: 14)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('cancel'.tr())),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
              onPressed: () async {
                final newVf = vfController.text.trim();
                final newInsta = instaController.text.trim();
                final newCap = double.tryParse(capitalController.text.trim()) ?? 180000;

                try {
                  await db.set({
                    'vf': newVf,
                    'instapay': newInsta,
                  });
                  await provider.setOpeningCapital(newCap);
                  
                  if (mounted) Navigator.pop(context);
                  provider.loadAll();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Save Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      }),
    );
  }
}

class _MiniPoolItem extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;

  const _MiniPoolItem({required this.label, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(Formatters.formatCurrency(amount), style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)),
      ],
    );
  }
}
