import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/auth_provider.dart';
import '../../models/app_user.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  static const List<UserRole> _supportedRoles = [
    UserRole.ADMIN,
    UserRole.FINANCE,
    UserRole.COLLECTOR,
    UserRole.RETAILER,
  ];
  List<AppUser> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    final users = await context.read<AuthProvider>().getAllUsers();
    if (!mounted) return;
    setState(() {
      _users = users;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isEmbedded = auth.isAdmin || auth.isFinance;

    final bodyContent = _loading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: AppTheme.textMutedColor(context).withValues(alpha: 0.18)),
                      const SizedBox(height: 16),
                      Text(
                        'no_users'.tr(),
                        style: TextStyle(color: AppTheme.textMutedColor(context).withValues(alpha: 0.6), fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 24),
                      if (auth.isAdmin)
                        ElevatedButton.icon(
                          onPressed: () => _showCreateUserDialog(context),
                          icon: const Icon(Icons.add),
                          label: Text('create_new_user'.tr()),
                        ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: AppTheme.isDark(context)
                                ? AppTheme.panelGradient(context)
                                : const [Color(0xFFFFFBF4), Color(0xFFF2E5D2)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppTheme.lineColor(context)),
                          boxShadow: AppTheme.softShadow(context),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: _UserSummary(label: 'Users', value: _users.length.toString())),
                            Expanded(child: _UserSummary(label: 'Admins', value: _users.where((u) => u.role == UserRole.ADMIN).length.toString())),
                            if (auth.isAdmin) ...[
                              IconButton(
                                tooltip: 'repair_account'.tr(),
                                icon: Icon(Icons.build_outlined, color: AppTheme.infoColor(context)),
                                onPressed: () => _showSyncDialog(context),
                                style: IconButton.styleFrom(
                                  backgroundColor: AppTheme.surfaceColor(context).withValues(alpha: 0.5),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'create_new_user'.tr(),
                                icon: const Icon(Icons.add, color: AppTheme.accent),
                                onPressed: () => _showCreateUserDialog(context),
                                style: IconButton.styleFrom(
                                  backgroundColor: AppTheme.surfaceColor(context).withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                        itemCount: _users.length,
                        itemBuilder: (context, index) => _UserCard(user: _users[index]),
                      ),
                    ),
                  ],
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
          backgroundColor: AppTheme.surfaceColor(context),
          elevation: 0,
          title: Text(
            'manage_users'.tr(),
            style: TextStyle(
              color: AppTheme.textPrimaryColor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          iconTheme: IconThemeData(color: AppTheme.textPrimaryColor(context)),
          actions: [
            if (auth.isAdmin)
              IconButton(
                tooltip: 'repair_account'.tr(),
                icon: Icon(Icons.build_outlined, color: AppTheme.infoColor(context)),
                onPressed: () => _showSyncDialog(context),
              ),
            if (auth.isAdmin)
              IconButton(
                tooltip: 'create_new_user'.tr(),
                icon: const Icon(Icons.add, color: AppTheme.accent),
                onPressed: () => _showCreateUserDialog(context),
              ),
          ],
        ),
        body: bodyContent,
      );
    }
  }

  Future<void> _showCreateUserDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    UserRole selectedRole = UserRole.COLLECTOR;
    String? selectedRetailerId;

    final retailerMap = <String, String>{};
    try {
      final snap = await FirebaseDatabase.instance.ref('retailers').get();
      if (snap.exists && snap.value is Map) {
        (snap.value as Map).forEach((k, v) {
          if (v is Map) {
            final m = Map<String, dynamic>.from(v);
            final name = m['name']?.toString() ?? k.toString();
            retailerMap[k.toString()] = name;
          }
        });
      }
    } catch (_) {}

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => _ManagementDialog(
          title: 'create_new_user'.tr(),
          fields: [
            _tf(nameCtrl, 'full_name'.tr(), Icons.person),
            _tf(emailCtrl, 'email'.tr(), Icons.email, keyboard: TextInputType.emailAddress),
            _tf(passCtrl, 'password'.tr(), Icons.lock, obscure: true),
            const SizedBox(height: 12),
            DropdownButtonFormField<UserRole>(
              value: selectedRole,
              dropdownColor: AppTheme.surfaceColor(context),
              style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: 'role'.tr(),
                filled: true,
                fillColor: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
              ),
              items: _supportedRoles
                  .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                  .toList(),
              onChanged: (v) => setSt(() {
                selectedRole = v ?? selectedRole;
                if (selectedRole != UserRole.RETAILER) selectedRetailerId = null;
              }),
            ),
            if (selectedRole == UserRole.RETAILER) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedRetailerId,
                isExpanded: true,
                dropdownColor: AppTheme.surfaceColor(context),
                style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: 'link_retailer_profile'.tr(),
                  filled: true,
                  fillColor: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
                ),
                items: retailerMap.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text('${e.value} (${e.key})')))
                    .toList(),
                onChanged: (v) => setSt(() => selectedRetailerId = v),
              ),
            ],
          ],
          onConfirm: () async {
            if (selectedRole == UserRole.RETAILER &&
                (selectedRetailerId == null || selectedRetailerId!.isEmpty)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('select_retailer_profile'.tr()), backgroundColor: Colors.red),
              );
              return false;
            }
            final auth = context.read<AuthProvider>();
            try {
              await auth.createUser(
                email: emailCtrl.text.trim(),
                password: passCtrl.text.trim(),
                name: nameCtrl.text.trim(),
                role: selectedRole,
                retailerId: selectedRole == UserRole.RETAILER ? selectedRetailerId : null,
              );
              if (!ctx.mounted) return false;
              Navigator.pop(ctx);
              _loadUsers();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('user_created_success'.tr())),
              );
              return true;
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
              );
              return false;
            }
          },
        ),
      ),
    );
  }

  Future<void> _showSyncDialog(BuildContext context) async {
    final uidCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    UserRole selectedRole = UserRole.COLLECTOR;
    String? selectedRetailerId;

    final retailerMap = <String, String>{};
    try {
      final snap = await FirebaseDatabase.instance.ref('retailers').get();
      if (snap.exists && snap.value is Map) {
        (snap.value as Map).forEach((k, v) {
          if (v is Map) {
            final m = Map<String, dynamic>.from(v);
            final name = m['name']?.toString() ?? k.toString();
            retailerMap[k.toString()] = name;
          }
        });
      }
    } catch (_) {}

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => _ManagementDialog(
          title: 'repair_desynced_account'.tr(),
          fields: [
            _tf(uidCtrl, 'Firebase UID', Icons.key),
            _tf(nameCtrl, 'full_name'.tr(), Icons.person),
            _tf(emailCtrl, 'email'.tr(), Icons.email),
            const SizedBox(height: 12),
            DropdownButtonFormField<UserRole>(
              value: selectedRole,
              dropdownColor: AppTheme.surfaceColor(context),
              style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: 'role'.tr(),
                filled: true,
                fillColor: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
              ),
              items: _supportedRoles
                  .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                  .toList(),
              onChanged: (v) => setSt(() {
                selectedRole = v ?? selectedRole;
                if (selectedRole != UserRole.RETAILER) selectedRetailerId = null;
              }),
            ),
            if (selectedRole == UserRole.RETAILER) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedRetailerId,
                isExpanded: true,
                dropdownColor: AppTheme.surfaceColor(context),
                style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: 'link_retailer_profile'.tr(),
                  filled: true,
                  fillColor: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
                ),
                items: retailerMap.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text('${e.value} (${e.key})')))
                    .toList(),
                onChanged: (v) => setSt(() => selectedRetailerId = v),
              ),
            ],
          ],
          onConfirm: () async {
            if (selectedRole == UserRole.RETAILER &&
                (selectedRetailerId == null || selectedRetailerId!.isEmpty)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('select_retailer_profile'.tr()), backgroundColor: Colors.red),
              );
              return false;
            }
            final auth = context.read<AuthProvider>();
            try {
              await auth.syncUserRecord(
                uid: uidCtrl.text.trim(),
                email: emailCtrl.text.trim(),
                name: nameCtrl.text.trim(),
                role: selectedRole,
                retailerId: selectedRole == UserRole.RETAILER ? selectedRetailerId : null,
              );
              if (!ctx.mounted) return false;
              Navigator.pop(ctx);
              _loadUsers();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('user_synced_success'.tr())),
              );
              return true;
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
              );
              return false;
            }
          },
        ),
      ),
    );
  }

  Widget _tf(
    TextEditingController c,
    String label,
    IconData icon, {
    TextInputType keyboard = TextInputType.text,
    bool obscure = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          obscureText: obscure,
          style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 20),
            filled: true,
            fillColor: AppTheme.surfaceRaisedColor(context).withValues(alpha: 0.5),
          ),
        ),
      );
}

class _UserCard extends StatelessWidget {
  final AppUser user;
  const _UserCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final color = _getRoleColor(context, user.role);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.isDark(context)
              ? AppTheme.panelGradient(context)
              : const [Color(0xFFFFFEFB), Color(0xFFF6EFE2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Text(
                user.name.substring(0, 1).toUpperCase(),
                style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(user.email, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12, fontWeight: FontWeight.w500)),
                  if (user.role == UserRole.RETAILER && user.retailerId != null && user.retailerId!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${'retailer_id'.tr()}: ${user.retailerId}',
                        style: TextStyle(color: AppTheme.infoColor(context), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Text(
                user.role.name.toUpperCase(),
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getRoleColor(BuildContext context, UserRole role) {
    switch (role) {
      case UserRole.ADMIN:
        return AppTheme.accent;
      case UserRole.FINANCE:
        return AppTheme.infoColor(context);
      case UserRole.COLLECTOR:
        return const Color(0xFF8C6239);
      case UserRole.OPERATOR:
        return AppTheme.positiveColor(context);
      case UserRole.RETAILER:
        return const Color(0xFF6B4FA3);
    }
  }
}

class _UserSummary extends StatelessWidget {
  final String label;
  final String value;

  const _UserSummary({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 15, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _ManagementDialog extends StatelessWidget {
  final String title;
  final List<Widget> fields;
  final Future<bool> Function() onConfirm;

  const _ManagementDialog({required this.title, required this.fields, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceColor(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(title, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w800, fontSize: 18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: fields,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('cancel'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context), fontWeight: FontWeight.bold)),
        ),
        ElevatedButton(
          onPressed: () async {
            await onConfirm();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text('save'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
