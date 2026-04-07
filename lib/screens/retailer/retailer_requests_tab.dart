part of 'retailer_dashboard.dart';

class _RequestsTab extends StatefulWidget {
  final List<RetailerAssignmentRequest> requests;
  final VoidCallback onNewRequest;

  const _RequestsTab({required this.requests, required this.onNewRequest});

  @override
  State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab> {
  String _filter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.requests.where((r) => _filter == 'ALL' || r.status == _filter).toList();
    
    return Column(
      children: [
        // Filter Chips
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _StatusChip(label: 'All', selected: _filter == 'ALL', onTap: () => setState(() => _filter = 'ALL')),
                const SizedBox(width: 8),
                _StatusChip(label: 'Pending', selected: _filter == 'PENDING', onTap: () => setState(() => _filter = 'PENDING')),
                const SizedBox(width: 8),
                _StatusChip(label: 'Live', selected: _filter == 'PROCESSING', onTap: () => setState(() => _filter = 'PROCESSING')),
                const SizedBox(width: 8),
                _StatusChip(label: 'Done', selected: _filter == 'COMPLETED', onTap: () => setState(() => _filter = 'COMPLETED')),
              ],
            ),
          ),
        ),

        // Add Button
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: ElevatedButton.icon(
            onPressed: widget.onNewRequest,
            icon: const Icon(Icons.add_circle_outline, size: 20),
            label: Text('new_assignment_request'.tr(), style: const TextStyle(fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              backgroundColor: AppTheme.accent,
            ),
          ),
        ),

        Expanded(
          child: filtered.isEmpty
              ? Center(child: Text('no_requests_found'.tr()))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final r = filtered[i];
                    return _PremiumRequestCard(request: r);
                  },
                ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StatusChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: AppTheme.surfaceColor(context).withValues(alpha: 0.5),
      selectedColor: AppTheme.accent.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: selected ? AppTheme.accent : AppTheme.textMutedColor(context),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide.none),
      showCheckmark: false,
    );
  }
}

class _PremiumRequestCard extends StatelessWidget {
  final RetailerAssignmentRequest request;
  const _PremiumRequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd().add_Hm();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.lineColor(context).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(status: request.status),
              const Spacer(),
              Text(fmt.format(DateTime.fromMillisecondsSinceEpoch(request.createdAt)), style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('assigned_amount'.tr(), style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 10, fontWeight: FontWeight.bold)),
                  Text(request.requestedAmount.toStringAsFixed(0), style: TextStyle(color: AppTheme.textPrimaryColor(context), fontSize: 20, fontWeight: FontWeight.w900)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Target Phone', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 10, fontWeight: FontWeight.bold)),
                  Text(request.vfPhoneNumber, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
          if (request.notes != null || request.adminNotes != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, thickness: 0.5),
            ),
            if (request.notes != null)
              Text('Note: ${request.notes}', style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 12)),
            if (request.adminNotes != null)
              Text('Admin: ${request.adminNotes}', style: TextStyle(color: AppTheme.accentSoft, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
          if (request.proofImageUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ProofImageThumbnail(imageUrl: request.proofImageUrl!, height: 120),
            ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoCard({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accent, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: AppTheme.textPrimaryColor(context), fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: AppTheme.textMutedColor(context), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
