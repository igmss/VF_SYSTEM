import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../models/retailer_assignment_request.dart';
import '../../providers/auth_provider.dart';
import '../../services/retailer_portal_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/proof_image_viewer.dart';

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
      setState(() {
        _loading = false;
        _loadError = 'retailer_profile_missing'.tr();
      });
      return;
    }

    _reqSub?.cancel();
    _reqSub = _portal.streamRequestsForUser(uid).listen((list) {
      if (mounted) setState(() => _requests = list);
    });

    await _refreshPortal();
  }

  Future<void> _refreshPortal() async {
    final range = _todayLocalRange();
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final data = await _portal.getPortalData(startMs: range.$1, endMs: range.$2);
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

  /// Local calendar day [start, end] in ms.
  (int, int) _todayLocalRange() {
    final n = DateTime.now();
    final start = DateTime(n.year, n.month, n.day);
    final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    return (start.millisecondsSinceEpoch, end.millisecondsSinceEpoch);
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
                  filled: true,
                  fillColor: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
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
                  filled: true,
                  fillColor: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                style: TextStyle(color: AppTheme.textPrimaryColor(context)),
                decoration: InputDecoration(
                  labelText: 'notes'.tr(),
                  filled: true,
                  fillColor: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr())),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('welcome_user'.tr(args: [name]), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('retailer_portal_subtitle'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh, color: AppTheme.textMutedColor(context)),
                      onPressed: _refreshPortal,
                    ),
                    IconButton(
                      icon: Icon(Icons.logout, color: AppTheme.textMutedColor(context)),
                      onPressed: () => context.read<AuthProvider>().signOut(),
                    ),
                  ],
                ),
              ),
              _buildTabs(context),
              Expanded(
                child: _loadError != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_loadError!, textAlign: TextAlign.center)))
                    : _tab == 0
                        ? _OverviewTab(portalData: _portalData, loading: _loading, onRefresh: _refreshPortal)
                        : _tab == 1
                            ? _ActivityTab(portalData: _portalData, loading: _loading)
                            : _RequestsTab(requests: _requests, onNewRequest: _openNewRequestDialog),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabs(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _TabChip(label: 'tab_overview'.tr(), selected: _tab == 0, onTap: () => setState(() => _tab = 0)),
          const SizedBox(width: 8),
          _TabChip(label: 'tab_activity'.tr(), selected: _tab == 1, onTap: () => setState(() => _tab = 1)),
          const SizedBox(width: 8),
          _TabChip(label: 'tab_requests'.tr(), selected: _tab == 2, onTap: () => setState(() => _tab = 2)),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? AppTheme.accent.withValues(alpha: 0.2) : AppTheme.surfaceColor(context).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? AppTheme.accent : AppTheme.textMutedColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
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
    if (r is! Map) {
      return Center(child: Text('no_data'.tr()));
    }
    final m = Map<String, dynamic>.from(r);
    double d(dynamic v) => v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;

    final assigned = d(m['totalAssigned']);
    final collected = d(m['totalCollected']);
    final credit = d(m['credit']);
    final pending = (assigned - collected);
    final debt = pending > 0 ? pending : 0.0;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('business_snapshot'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 16),
                _RowMetric(label: 'assigned'.tr(), value: assigned),
                _RowMetric(label: 'collected'.tr(), value: collected),
                _RowMetric(label: 'debt'.tr(), value: debt),
                _RowMetric(label: 'credit'.tr(), value: credit),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'retailer_daily_hint'.tr(),
            style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12),
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
      return Center(child: Text('no_activity_period'.tr()));
    }
    final fmt = DateFormat.yMMMd().add_Hm();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: raw.length,
      itemBuilder: (context, i) {
        final item = raw[i];
        if (item is! Map) return const SizedBox.shrink();
        final map = Map<String, dynamic>.from(item);
        final ts = map['timestamp'];
        final t = ts is int ? DateTime.fromMillisecondsSinceEpoch(ts) : DateTime.tryParse(ts?.toString() ?? '') ?? DateTime.now();
        final type = map['type']?.toString() ?? '';
        final amount = map['amount'];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type, style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 4),
                Text('${'amount'.tr()}: $amount EGP', style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(fmt.format(t), style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RequestsTab extends StatelessWidget {
  final List<RetailerAssignmentRequest> requests;
  final VoidCallback onNewRequest;

  const _RequestsTab({required this.requests, required this.onNewRequest});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd().add_Hm();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onNewRequest,
              icon: const Icon(Icons.add),
              label: Text('new_assignment_request'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ),
        Expanded(
          child: requests.isEmpty
              ? Center(child: Text('no_requests_yet'.tr()))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: requests.length,
                  itemBuilder: (context, i) {
                    final r = requests[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _StatusPill(status: r.status),
                                const Spacer(),
                                Text(fmt.format(DateTime.fromMillisecondsSinceEpoch(r.createdAt)), style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('${'requested_amount_egp'.tr()}: ${r.requestedAmount}', style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w700)),
                            Text('${'vf_number_for_assignment'.tr()}: ${r.vfPhoneNumber}', style: TextStyle(color: AppTheme.textPrimaryColor(context))),
                            if (r.notes != null && r.notes!.isNotEmpty) Text(r.notes!, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13)),
                            if (r.assignedAmount != null)
                              Text('${'assigned_amount'.tr()}: ${r.assignedAmount}', style: TextStyle(color: AppTheme.positiveColor(context), fontWeight: FontWeight.w600)),
                            if (r.adminNotes != null && r.adminNotes!.isNotEmpty)
                              Text('${'admin_notes'.tr()}: ${r.adminNotes}', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12)),
                            if (r.proofImageUrl != null && r.proofImageUrl!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              ProofImageThumbnail(
                                imageUrl: r.proofImageUrl!,
                                height: 160,
                              ),
                            ],
                            if (r.rejectedReason != null && r.rejectedReason!.isNotEmpty)
                              Text('${'rejected_reason'.tr()}: ${r.rejectedReason}', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    Color c = AppTheme.textMutedColor(context);
    if (status == 'PENDING') c = Colors.orange;
    if (status == 'COMPLETED') c = AppTheme.positiveColor(context);
    if (status == 'REJECTED') c = Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(status, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.lineColor(context)),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: child,
    );
  }
}

class _RowMetric extends StatelessWidget {
  final String label;
  final double value;

  const _RowMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textMutedColor(context))),
          Text('${value.toStringAsFixed(0)} EGP', style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
