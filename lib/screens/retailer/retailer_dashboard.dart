import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';

import '../../models/retailer_assignment_request.dart';
import '../../providers/auth_provider.dart';
import '../../services/retailer_portal_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/proof_image_viewer.dart';
import 'retailer_components.dart';

part 'retailer_requests_tab.dart';

class RetailerDashboard extends StatefulWidget {
  const RetailerDashboard({super.key});

  @override
  State<RetailerDashboard> createState() => _RetailerDashboardState();
}

class _RetailerDashboardState extends State<RetailerDashboard> {
  final RetailerPortalService _portal = RetailerPortalService();
  int _tab = 0;

  Map<String, dynamic>? _portalData;
  String? _loadError;
  bool _loading = true;

  StreamSubscription<List<RetailerAssignmentRequest>>? _reqSub;
  List<RetailerAssignmentRequest> _requests = [];
  
  // Date Filtering
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    end: DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    final uid = auth.currentUser?.uid;
    final rid = auth.currentUser?.retailerId;
    if (uid == null || rid == null || rid.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'retailer_profile_missing'.tr();
        });
      }
      return;
    }

    _reqSub?.cancel();
    _reqSub = _portal.streamRequestsForUser(uid).listen((list) {
      if (mounted) setState(() => _requests = list);
    });

    await _refreshPortal();
  }

  Future<void> _refreshPortal() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final data = await _portal.getPortalData(
        startMs: _dateRange.start.millisecondsSinceEpoch,
        endMs: _dateRange.end.millisecondsSinceEpoch,
      );
      if (!mounted) return;
      setState(() {
        _portalData = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _dateRange,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppTheme.accent,
              onPrimary: Colors.white,
              surface: AppTheme.surfaceColor(context),
              onSurface: AppTheme.textPrimaryColor(context),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _dateRange) {
      setState(() => _dateRange = picked);
      _refreshPortal();
    }
  }

  @override
  void dispose() {
    _reqSub?.cancel();
    super.dispose();
  }

  Future<void> _openNewRequestDialog() async {
    final auth = context.read<AuthProvider>();
    final uid = auth.currentUser!.uid;
    final retailerId = auth.currentUser!.retailerId!;

    final amountCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text('new_assignment_request'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: 'requested_amount_egp'.tr(),
                  prefixIcon: const Icon(Icons.monetization_on_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: 'vf_number_for_assignment'.tr(),
                  hintText: '01xxxxxxxxx',
                  prefixIcon: const Icon(Icons.phone_android_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                style: TextStyle(color: AppTheme.textPrimaryColor(context)),
                decoration: InputDecoration(
                  labelText: 'notes'.tr(),
                  prefixIcon: const Icon(Icons.note_alt_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr())),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('submit_request'.tr()),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final amount = double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
    final phone = phoneCtrl.text.trim();
    if (amount <= 0 || phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('invalid_request_fields'.tr())));
      return;
    }

    try {
      await _portal.createRequest(
        retailerUserUid: uid,
        retailerId: retailerId,
        createdByUid: uid,
        requestedAmount: amount,
        vfPhoneNumber: phone,
        notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('request_submitted'.tr())));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = auth.currentUser?.name ?? 'Retailer';
    final rid = auth.currentUser?.retailerId ?? '';

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: AppTheme.backgroundGradient(context),
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Premium Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'welcome_user'.tr(args: [name]), 
                            style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)
                          ),
                          const SizedBox(height: 2),
                          Text('Retailer Code: $rid', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.logout, color: AppTheme.textMutedColor(context), size: 20),
                      ),
                      onPressed: () => context.read<AuthProvider>().signOut(),
                    ),
                  ],
                ),
              ),

              // Date Range Picker Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: InkWell(
                  onTap: _selectDateRange,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor(context).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.lineColor(context).withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 16, color: AppTheme.accent),
                        const SizedBox(width: 12),
                        Text(
                          '${DateFormat.yMMMd().format(_dateRange.start)} - ${DateFormat.yMMMd().format(_dateRange.end)}',
                          style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        const Spacer(),
                        Icon(Icons.arrow_drop_down, color: AppTheme.textMutedColor(context)),
                      ],
                    ),
                  ),
                ),
              ),

              _buildTabs(context),
              
              Expanded(
                child: _loadError != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_loadError!, textAlign: TextAlign.center)))
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _tab == 0
                            ? _OverviewTab(portalData: _portalData, loading: _loading, onRefresh: _refreshPortal)
                            : _tab == 1
                                ? _ActivityTab(portalData: _portalData, loading: _loading)
                                : _RequestsTab(requests: _requests, onNewRequest: _openNewRequestDialog),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabs(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            _TabItem(label: 'Dashboard', selected: _tab == 0, onTap: () => setState(() => _tab = 0)),
            _TabItem(label: 'Finance', selected: _tab == 1, onTap: () => setState(() => _tab = 1)),
            _TabItem(label: 'Requests', selected: _tab == 2, onTap: () => setState(() => _tab = 2)),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabItem({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.textMutedColor(context),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final Map<String, dynamic>? portalData;
  final bool loading;
  final Future<void> Function() onRefresh;

  const _OverviewTab({required this.portalData, required this.loading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (loading && portalData == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final r = portalData?['retailer'];
    if (r is! Map) return Center(child: Text('no_data'.tr()));
    
    final m = Map<String, dynamic>.from(r);
    double d(dynamic v) => v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;

    final assigned = d(m['totalAssigned']);
    final collected = d(m['totalCollected']);
    final credit = d(m['credit']);
    final debt = (assigned - collected).clamp(0, double.infinity);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        children: [
          ReconciliationSummary(assigned: assigned, collected: collected, debt: debt.toDouble()),
          const SizedBox(height: 24),
          
          Text(
            'operational_stats'.tr(), 
            style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w800, fontSize: 16)
          ),
          const SizedBox(height: 16),
          
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.3,
            children: [
              StatTile(label: 'Assigned', value: assigned, icon: Icons.assignment_outlined, color: Colors.blueAccent),
              StatTile(label: 'Collected', value: collected, icon: Icons.payments_outlined, color: AppTheme.positiveColor(context)),
              StatTile(label: 'Available Owed', value: debt.toDouble(), icon: Icons.account_balance_wallet_outlined, color: Colors.orangeAccent),
              StatTile(label: 'Your Credit', value: credit, icon: Icons.stars_rounded, color: Colors.purpleAccent),
            ],
          ),
          
          const SizedBox(height: 24),
          _InfoCard(
            icon: Icons.lightbulb_outline,
            title: 'daily_reconciliation_tip'.tr(),
            subtitle: 'retailer_daily_hint'.tr(),
          ),
        ],
      ),
    );
  }
}

class _ActivityTab extends StatelessWidget {
  final Map<String, dynamic>? portalData;
  final bool loading;

  const _ActivityTab({required this.portalData, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading && portalData == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final raw = portalData?['activity'];
    if (raw is! List || raw.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off, size: 64, color: AppTheme.textMutedColor(context).withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('no_activity_period'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context))),
        ],
      ));
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: raw.length,
      itemBuilder: (context, i) {
        final item = raw[i];
        if (item is! Map) return const SizedBox.shrink();
        final map = Map<String, dynamic>.from(item);
        final ts = map['timestamp'];
        final t = ts is int ? DateTime.fromMillisecondsSinceEpoch(ts) : DateTime.tryParse(ts?.toString() ?? '') ?? DateTime.now();
        final type = map['type']?.toString() ?? '';
        final amount = (map['amount'] is num) ? (map['amount'] as num).toDouble() : 0.0;
        
        return TransactionRow(
          type: type,
          amount: amount,
          timestamp: t,
        );
      },
    );
  }
}
