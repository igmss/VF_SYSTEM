import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../providers/auth_provider.dart';
import '../../providers/app_provider.dart';
import '../../providers/distribution_provider.dart';
import '../../services/retailer_portal_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/proof_image_viewer.dart';
import '../../services/retailer_assignment_ussd_runner.dart';
import '../../services/retailer_ussd_auto_queue_service.dart';
import '../../services/ussd_service.dart';
import 'package:permission_handler/permission_handler.dart';

class RetailerAssignmentRequestsScreen extends StatefulWidget {
  const RetailerAssignmentRequestsScreen({super.key});

  @override
  State<RetailerAssignmentRequestsScreen> createState() => _RetailerAssignmentRequestsScreenState();
}

class _RetailerAssignmentRequestsScreenState extends State<RetailerAssignmentRequestsScreen> {
  final RetailerPortalService _portal = RetailerPortalService();

  Future<void> _processWithUssd({
    required RetailerPortalRequestRow row,
    required String selectedNumId,
    required double amount,
    required double fees,
    required bool isExternalWallet,
    required bool applyCredit,
    required String adminNotes,
    required BuildContext sheetContext,
  }) async {
    final auth = context.read<AuthProvider>();
    final adminUid = auth.currentUser?.uid ?? 'system';

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Starting USSD Automation...')));

    try {
      final result = await RetailerAssignmentUssdRunner.run(
        row: row,
        adminUid: adminUid,
        selectedNumId: selectedNumId,
        amount: amount,
        formFees: fees,
        isExternalWallet: isExternalWallet,
        applyCredit: applyCredit,
        adminNotes: adminNotes,
        distribution: context.read<DistributionProvider>(),
        app: context.read<AppProvider>(),
        portal: _portal,
        onSuccessUi: () {
          if (!mounted) return;
          if (Navigator.canPop(sheetContext)) {
            Navigator.of(sheetContext).pop();
          }
        },
      );

      if (!mounted) return;
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('transaction_completed'.tr()), backgroundColor: Colors.green),
        );
      } else if (result.message.isNotEmpty) {
        final isTimeout = result.message.contains('timed out');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: isTimeout ? Colors.orange : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _showPinSetup() async {
    final cur = await UssdService.getPin();
    final ctrl = TextEditingController(text: cur);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(context),
        title: Text('setup_ussd_pin'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ussd_pin_hint'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: 'Enter 6-digit PIN',
                filled: true,
                fillColor: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('cancel'.tr())),
          ElevatedButton(
            onPressed: () async {
              await UssdService.savePin(ctrl.text.trim());
              if (mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white),
            child: Text('save'.tr()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'retailer_requests_admin'.tr(),
          style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.security, color: Colors.orange),
            onPressed: _showPinSetup,
            tooltip: 'setup_ussd_pin'.tr(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<RetailerPortalRequestRow>>(
        stream: _portal.streamAllRequests(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('${snap.error}', style: const TextStyle(color: Colors.red)));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          final pending = rows.where((r) => r.request.status == 'PENDING').toList();
          final done = rows.where((r) => r.request.status != 'PENDING').toList();
          final autoQ = context.watch<RetailerUssdAutoQueueService>();

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              if (autoQ.isAutoQueueEnabled)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Material(
                      color: AppTheme.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.bolt, color: AppTheme.accent, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'retailer_auto_ussd_banner'.tr(),
                                    style: TextStyle(
                                      color: AppTheme.textPrimaryColor(context),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (autoQ.isProcessing) ...[
                              const SizedBox(height: 8),
                              Text(
                                autoQ.statusLine ?? 'retailer_auto_ussd_processing'.tr(),
                                style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12),
                              ),
                            ],
                            if (autoQ.lastError != null && autoQ.lastError!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                autoQ.lastError!,
                                style: const TextStyle(color: Colors.orange, fontSize: 11),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'retailer_requests_admin_hint'.tr(),
                    style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13),
                  ),
                ),
              ),
              if (pending.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Text('pending'.tr(), style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w800)),
                  ),
                ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _RequestTile(
                    row: pending[i],
                    onAction: () => _showProcessSheet(pending[i]),
                  ),
                  childCount: pending.length,
                ),
              ),
              if (done.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Text('history'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context), fontWeight: FontWeight.w800)),
                  ),
                ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _RequestTile(row: done[i], onAction: null),
                  childCount: done.length,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showProcessSheet(RetailerPortalRequestRow row) async {
    final assignedCtrl = TextEditingController(text: row.request.requestedAmount.toStringAsFixed(0));
    final notesCtrl = TextEditingController();
    final feesCtrl = TextEditingController();

    final appProvider = context.read<AppProvider>();
    final distProvider = context.read<DistributionProvider>();
    final numbers = appProvider.mobileNumbers;
    
    if (numbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('no_data'.tr())));
      return;
    }

    String selectedId = numbers.first.id;
    bool isExternalWallet = false;
    bool applyCredit = false;

    // Find retailer to know their credit
    final matchedRetailers = distProvider.retailers.where((r) => r.id == row.request.retailerId);
    final retailer = matchedRetailers.isNotEmpty ? matchedRetailers.first : null;

    if (row.request.status == 'PROCESSING') {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request is currently being processed by another admin.')));
       return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceColor(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      // Consumer must wrap StatefulBuilder: context.watch inside StatefulBuilder breaks Provider.
      builder: (sheetCtx) => Consumer2<DistributionProvider, RetailerUssdAutoQueueService>(
        builder: (context, dist, autoQ, _) {
          final isSubmitting = dist.isDistributing || autoQ.isProcessing;
          return StatefulBuilder(
            builder: (ctx, setSt) {
          final selectedNum = numbers.firstWhere((n) => n.id == selectedId, orElse: () => numbers.first);
          final availableBalance = selectedNum.currentBalance;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('process_request'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('${'retailer_id'.tr()}: ${row.request.retailerId}', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12)),
                  const SizedBox(height: 16),
                  
                  DropdownButtonFormField<String>(
                    value: selectedId,
                    dropdownColor: AppTheme.surfaceColor(context),
                    style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: 'from'.tr(),
                      filled: true,
                      fillColor: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
                    ),
                    items: numbers.map((n) => DropdownMenuItem(
                      value: n.id,
                      child: Text('${n.phoneNumber}  (${n.currentBalance.toStringAsFixed(0)} EGP)'),
                    )).toList(),
                    onChanged: (v) => setSt(() => selectedId = v ?? selectedId),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: availableBalance <= 0
                          ? Colors.red.withValues(alpha: 0.08)
                          : AppTheme.positiveColor(context).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: availableBalance <= 0
                            ? Colors.red.withValues(alpha: 0.3)
                            : AppTheme.positiveColor(context).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          availableBalance <= 0 ? Icons.warning_amber : Icons.account_balance_wallet,
                          size: 16,
                          color: availableBalance <= 0 ? Colors.orange : AppTheme.positiveColor(context),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'available: ${availableBalance.toStringAsFixed(0)} EGP',
                          style: TextStyle(
                            color: availableBalance <= 0 ? Colors.orange : AppTheme.positiveColor(context),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: assignedCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'assigned_amount'.tr(),
                      prefixIcon: const Icon(Icons.monetization_on, size: 20),
                      filled: true,
                      fillColor: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
                    ),
                    style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),

                  CheckboxListTile(
                    title: Text('External Wallet (Charge Fees)', style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 13, fontWeight: FontWeight.w600)),
                    value: isExternalWallet,
                    activeColor: AppTheme.accent,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (val) {
                      setSt(() {
                        isExternalWallet = val ?? false;
                        if (isExternalWallet) {
                          final amt = double.tryParse(assignedCtrl.text) ?? 0.0;
                          double calcFee = amt * 0.005;
                          if (calcFee > 15.0) calcFee = 15.0;
                          feesCtrl.text = calcFee.toStringAsFixed(2);
                        } else {
                          feesCtrl.text = '';
                        }
                      });
                    },
                  ),

                  TextField(
                    controller: feesCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Vodafone Fees (Optional)'.tr(),
                      prefixIcon: const Icon(Icons.money_off, size: 20),
                      filled: true,
                      fillColor: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
                    ),
                    style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w600),
                  ),

                  if (retailer != null && retailer.credit > 0)
                    CheckboxListTile(
                      title: Text('Use Retailer Credit (${retailer.credit.toStringAsFixed(0)} EGP)', style: TextStyle(color: AppTheme.positiveColor(context), fontSize: 13, fontWeight: FontWeight.bold)),
                      value: applyCredit,
                      activeColor: AppTheme.positiveColor(context),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (val) => setSt(() => applyCredit = val ?? false),
                    ),

                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'admin_notes'.tr(),
                      filled: true,
                      fillColor: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
                    ),
                    style: TextStyle(color: AppTheme.textPrimaryColor(context)),
                  ),
                  const SizedBox(height: 24),
                  
                  if (isSubmitting)
                    const Center(child: CircularProgressIndicator())
                  else
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: isSubmitting
                                    ? null
                                    : () => _processWithUssd(
                                          row: row,
                                          selectedNumId: selectedId,
                                          amount: double.tryParse(assignedCtrl.text) ?? 0,
                                          fees: double.tryParse(feesCtrl.text) ?? 0,
                                          isExternalWallet: isExternalWallet,
                                          applyCredit: applyCredit,
                                          adminNotes: notesCtrl.text.trim(),
                                          sheetContext: ctx,
                                        ),
                                icon: const Icon(Icons.bolt, color: Colors.orange),
                                label: const Text('Auto-Process USSD', style: TextStyle(color: Colors.orange)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.orange),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: isSubmitting
                                    ? null
                                    : () => _completeWithImage(
                                          sheetCtx,
                                          row,
                                          assignedCtrl.text,
                                          notesCtrl.text.trim(),
                                          selectedId,
                                          feesCtrl.text,
                                          isExternalWallet,
                                          applyCredit,
                                        ),
                                icon: const Icon(Icons.cloud_upload),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                label: Text('complete_with_proof'.tr()),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: isSubmitting
                              ? null
                              : () => _reject(sheetCtx, row, notesCtrl.text.trim()),
                          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                          icon: const Icon(Icons.close),
                          label: Text('reject_request'.tr()),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
            },
          );
        },
      ),
    );
  }

  Future<void> _reject(BuildContext sheetCtx, RetailerPortalRequestRow row, String reason) async {
    if (!mounted) return;
    try {
      await context.read<DistributionProvider>().processRetailerRequest(
        portalUserUid: row.portalUserUid,
        requestId: row.request.id,
        status: 'REJECTED',
        adminNotes: reason.isEmpty ? 'rejected' : reason,
      );
      if (mounted) {
        Navigator.of(sheetCtx).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request Rejected.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _completeWithImage(
    BuildContext sheetCtx,
    RetailerPortalRequestRow row,
    String assignedText,
    String notes,
    String fromVfNumberId,
    String feesText,
    bool isExternalWallet,
    bool applyCredit,
  ) async {
    final assigned = double.tryParse(assignedText.replaceAll(',', '')) ?? 0;
    if (assigned <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('invalid_amount'.tr())));
      return;
    }

    final fees = double.tryParse(feesText.replaceAll(',', '')) ?? 0;
    final numbers = context.read<AppProvider>().mobileNumbers;
    final numObj = numbers.firstWhere((n) => n.id == fromVfNumberId);
    if (numObj.phoneNumber.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${'invalid_request_fields'.tr()} (VF phone)')),
      );
      return;
    }

    try {
      await Permission.photos.request();
      await Permission.camera.request();

      final picker = ImagePicker();
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surfaceColor(context),
          title: Text('pick_proof'.tr(), style: TextStyle(color: AppTheme.textPrimaryColor(context))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, ImageSource.camera), child: Text('camera'.tr())),
            TextButton(onPressed: () => Navigator.pop(ctx, ImageSource.gallery), child: Text('gallery'.tr())),
          ],
        ),
      );
      if (source == null || !mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('cancel'.tr())));
        return;
      }

      final xfile = await picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (xfile == null || !mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('no_image_selected'.tr())));
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploading image and processing...')));

      final path = 'assignment_proofs/${row.request.retailerId}/${row.request.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref(path);
      
      final bytes = await xfile.readAsBytes();
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();

      if (!mounted) return;
      await context.read<DistributionProvider>().processRetailerRequest(
        portalUserUid: row.portalUserUid,
        requestId: row.request.id,
        status: 'COMPLETED',
        proofImageUrl: url,
        adminNotes: notes,
        retailerId: row.request.retailerId,
        fromVfNumberId: fromVfNumberId,
        fromVfPhone: numObj.phoneNumber,
        amount: assigned,
        fees: fees,
        chargeFeesToRetailer: isExternalWallet,
        applyCredit: applyCredit,
      );

      if (mounted) {
        Navigator.of(sheetCtx).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('request_completed'.tr()), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'error'.tr()}: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _RequestTile extends StatelessWidget {
  final RetailerPortalRequestRow row;
  final VoidCallback? onAction;

  const _RequestTile({required this.row, this.onAction});

  @override
  Widget build(BuildContext context) {
    final r = row.request;
    final fmt = DateFormat.yMMMd().add_Hm();
    final isProcessing = r.status == 'PROCESSING';
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: AppTheme.surfaceColor(context).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: isProcessing ? null : onAction,
          borderRadius: BorderRadius.circular(18),
          child: Opacity(
            opacity: isProcessing ? 0.6 : 1.0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: r.status == 'PENDING' 
                              ? Colors.orange.withValues(alpha: 0.2) 
                              : isProcessing 
                                  ? Colors.blue.withValues(alpha: 0.2)
                                  : AppTheme.textMutedColor(context).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isProcessing ? 'PROCESSING...' : r.status, 
                          style: TextStyle(
                            fontSize: 11, 
                            fontWeight: FontWeight.w800,
                            color: isProcessing ? Colors.blue : null,
                          )
                        ),
                      ),
                      const Spacer(),
                      Text(fmt.format(DateTime.fromMillisecondsSinceEpoch(r.createdAt)), style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('${'requested_amount_egp'.tr()}: ${r.requestedAmount}', style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w700)),
                  Text('VF: ${r.vfPhoneNumber}', style: TextStyle(color: AppTheme.textPrimaryColor(context))),
                  if (r.notes != null && r.notes!.isNotEmpty) Text(r.notes!, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 13)),
                  if (r.assignedAmount != null)
                    Text('${'assigned_amount'.tr()}: ${r.assignedAmount}', style: TextStyle(color: AppTheme.positiveColor(context))),
                  if (r.processingBy != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Being handled by: ${r.processingBy}', style: const TextStyle(fontSize: 10, color: Colors.blue, fontStyle: FontStyle.italic)),
                    ),
                  if (r.proofImageUrl != null && r.proofImageUrl!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ProofImageThumbnail(
                        imageUrl: r.proofImageUrl!,
                        height: 120,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
