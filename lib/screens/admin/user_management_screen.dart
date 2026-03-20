import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/auth_provider.dart';
import '../../models/app_user.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({Key? key}) : super(key: key);

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
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
    setState(() {
      _users = users;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16162A),
        title: Text('manage_users'.tr(), style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'repair_account'.tr(),
            icon: const Icon(Icons.build_outlined, color: Colors.blueAccent),
            onPressed: () => _showSyncDialog(context),
          ),
          IconButton(
            tooltip: 'create_new_user'.tr(),
            icon: const Icon(Icons.add, color: Color(0xFFE63946)),
            onPressed: () => _showCreateUserDialog(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? Center(child: Text('no_users'.tr(), style: const TextStyle(color: Colors.white38)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    return _UserCard(user: user);
                  },
                ),
    );
  }

  void _showCreateUserDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    UserRole selectedRole = UserRole.COLLECTOR;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: const Color(0xFF16162A),
          title: Text('create_new_user'.tr(), style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tf(nameCtrl, 'full_name'.tr(), Icons.person),
                _tf(emailCtrl, 'email'.tr(), Icons.email, keyboard: TextInputType.emailAddress),
                _tf(passCtrl, 'password'.tr(), Icons.lock, obscure: true),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  value: selectedRole,
                  dropdownColor: const Color(0xFF1E1E3A),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'role'.tr(),
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: UserRole.values
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(r.name),
                          ))
                      .toList(),
                  onChanged: (v) => setSt(() => selectedRole = v ?? selectedRole),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('cancel'.tr(), style: const TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () async {
                final auth = context.read<AuthProvider>();
                try {
                  await auth.createUser(
                    email: emailCtrl.text.trim(),
                    password: passCtrl.text.trim(),
                    name: nameCtrl.text.trim(),
                    role: selectedRole,
                  );
                  Navigator.pop(ctx);
                  _loadUsers();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('user_created_success'.tr())),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE63946)),
              child: Text('create'.tr(), style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showSyncDialog(BuildContext context) {
    final uidCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    UserRole selectedRole = UserRole.COLLECTOR;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: const Color(0xFF16162A),
          title: Text('repair_desynced_account'.tr(), style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tf(uidCtrl, 'Firebase UID', Icons.key),
                _tf(nameCtrl, 'full_name'.tr(), Icons.person),
                _tf(emailCtrl, 'email'.tr(), Icons.email),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  value: selectedRole,
                  dropdownColor: const Color(0xFF1E1E3A),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'role'.tr(),
                    labelStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: UserRole.values
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(r.name),
                          ))
                      .toList(),
                  onChanged: (v) => setSt(() => selectedRole = v ?? selectedRole),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('cancel'.tr(), style: const TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () async {
                final auth = context.read<AuthProvider>();
                try {
                  await auth.syncUserRecord(
                    uid: uidCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                    name: nameCtrl.text.trim(),
                    role: selectedRole,
                  );
                  Navigator.pop(ctx);
                  _loadUsers();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('user_synced_success'.tr())),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              child: Text('sync'.tr(), style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tf(TextEditingController c, String label, IconData icon,
          {TextInputType keyboard = TextInputType.text, bool obscure = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white54),
            prefixIcon: Icon(icon, color: Colors.white38, size: 20),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
}

class _UserCard extends StatelessWidget {
  final AppUser user;
  const _UserCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final color = _getRoleColor(user.role);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.12),
            child: Text(user.name.substring(0, 1).toUpperCase(),
                style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(user.email, style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              user.role.name.toUpperCase(),
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.ADMIN:
        return const Color(0xFFE63946);
      case UserRole.FINANCE:
        return const Color(0xFF4CC9F0);
      case UserRole.COLLECTOR:
        return const Color(0xFFA78BFA);
      case UserRole.OPERATOR:
        return const Color(0xFF4ADE80);
    }
  }
}
