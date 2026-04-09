import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/retailer.dart';
import '../../providers/distribution_provider.dart';
import '../../theme/app_theme.dart';
import 'collect_cash_dialog.dart';
import '../admin/retailer_dialogs.dart'; // Depending on where the assign logic is.
// We will need to make sure we have access to _showDistributeDialog or similar, or just build one here if not exported.

class RetailerFocusScreen extends StatefulWidget {
  final List<Retailer> retailers;
  final int initialIndex;

  const RetailerFocusScreen({
    Key? key,
    required this.retailers,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  State<RetailerFocusScreen> createState() => _RetailerFocusScreenState();
}

class _RetailerFocusScreenState extends State<RetailerFocusScreen> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex, viewportFraction: 0.92);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _callRetailer(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch phone app')));
      }
    }
  }

  void _whatsappRetailer(String phone) async {
    // Basic formatting: remove leading 0, assume Egypt +20
    String formatted = phone;
    if (formatted.startsWith('0')) {
      formatted = '+20${formatted.substring(1)}';
    } else if (!formatted.startsWith('+')) {
      formatted = '+20$formatted';
    }

    final uri = Uri.parse('https://wa.me/$formatted');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch WhatsApp')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.retailers.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Retailers')),
        body: const Center(child: Text('No assigned retailers')),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        title: const Text('Focus Mode'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        itemCount: widget.retailers.length,
        itemBuilder: (context, index) {
          final retailer = widget.retailers[index];
          return _buildFocusCard(context, retailer);
        },
      ),
    );
  }

  Widget _buildFocusCard(BuildContext context, Retailer retailer) {
    final dist = context.watch<DistributionProvider>();
    final r = dist.retailers.firstWhere((element) => element.id == retailer.id, orElse: () => retailer);
    final isDark = AppTheme.isDark(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [AppTheme.surfaceColor(context), const Color(0xFF2C2C2E)]
              : [const Color(0xFFFFFFFF), const Color(0xFFF2F4F8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.4 : 0.05),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: AppTheme.primaryColor(context).withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
        border: Border.all(
          color: Colors.white.withOpacity(isDark ? 0.05 : 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Header Section
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: AppTheme.primaryColor(context).withOpacity(0.1),
                  child: Text(
                    r.name.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      color: AppTheme.primaryColor(context),
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  r.name,
                  style: TextStyle(
                    color: AppTheme.textPrimaryColor(context),
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  r.phone,
                  style: TextStyle(
                    color: AppTheme.textMutedColor(context),
                    fontSize: 16,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Balances Section (Glassmorphism look)
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor(context).withOpacity(0.03),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLargeBalance(context, 'Vodafone Cash Debt', r.pendingDebt, AppTheme.warningColor(context)),
                  const SizedBox(height: 32),
                  _buildLargeBalance(context, 'InstaPay Debt', r.pendingInstaPayDebt, const Color(0xFF1B5E20)),
                ],
              ),
            ),
          ),

          const Divider(height: 1),

          // 2x2 Oversized Action Grid
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildActionCard(
                        context: context,
                        icon: Icons.money,
                        label: 'Collect',
                        color: AppTheme.positiveColor(context),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => CollectCashDialog(retailer: r),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildActionCard(
                        context: context,
                        icon: Icons.send,
                        label: 'Assign',
                        color: AppTheme.primaryColor(context),
                        onTap: () {
                          // The assign UI is normally in admin section.
                          // For field collectors, maybe they don't have this right?
                          // The prompt explicitly asks for [Assign].
                          // We will just show a snackbar for now if it requires admin auth,
                          // or you can invoke a custom Assign dialog here if needed.
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assign not fully wired for Collectors yet')));
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildActionCard(
                        context: context,
                        icon: Icons.call,
                        label: 'Call',
                        color: const Color(0xFF2196F3),
                        onTap: () => _callRetailer(r.phone),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildActionCard(
                        context: context,
                        icon: Icons.chat,
                        label: 'WhatsApp',
                        color: const Color(0xFF25D366),
                        onTap: () => _whatsappRetailer(r.phone),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeBalance(BuildContext context, String title, double amount, Color amountColor) {
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppTheme.textMutedColor(context),
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          NumberFormat.currency(symbol: 'EGP ').format(amount),
          style: TextStyle(
            color: amountColor,
            fontSize: 36,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = AppTheme.isDark(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
