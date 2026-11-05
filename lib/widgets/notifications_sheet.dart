import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';

class NotificationsSheet extends StatefulWidget {
  const NotificationsSheet({super.key});

  static void show(BuildContext context) {
    final app = context.read<AppState>();
    app.fetchPendingTransfers();
    final isManager = app.userRole == 'MANAGER' ||
        app.userRole == 'SUITE_ADMIN' ||
        app.userRole == 'ADMIN';
    if (isManager) {
      app.fetchPendingMovements();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NotificationsSheet(),
    ).whenComplete(() {
      // Clear badge when dismissed/closed
      if (context.mounted) {
        // Removed
      }
    });
  }

  @override
  State<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<NotificationsSheet> {
  String? _processingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      final isManager = app.userRole == 'MANAGER' ||
          app.userRole == 'SUITE_ADMIN' ||
          app.userRole == 'ADMIN';
      if (isManager) {
        app.fetchPendingMovements();
      }
    });
  }

  String _formatAmount(dynamic val) {
    final d = double.tryParse(val?.toString() ?? '0') ?? 0.0;
    return d.toStringAsFixed(2);
  }

  String _timeAgo(dynamic dateStr) {
    if (dateStr == null) return 'Recently';
    final date = DateTime.tryParse(dateStr.toString())?.toLocal();
    if (date == null) return 'Recently';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildPendingMovementCard(BuildContext context, Map<String, dynamic> m) {
    final movementId = m['id']?.toString() ?? '';
    final isOut = (m['direction'] ?? '').toString().toLowerCase() == 'out';
    final amt = _formatAmount(m['amount']);
    final segmentName = m['segment']?['name']?.toString() ??
        m['category']?['name']?.toString() ??
        m['entryTag']?.toString() ??
        'Transaction';
    final collectorName = m['collector']?['name']?.toString() ??
        m['collector']?['handle']?.toString() ??
        'Staff';
    final ledgerName = m['ledger']?['name']?.toString() ??
        m['ledger']?['code']?.toString() ??
        'General Operations';

    final notes = (m['notes'] ??
            m['metadata']?['notes'] ??
            m['metadata']?['note'] ??
            '')
        .toString()
        .trim();
    final receiptNo = (m['receiptNo'] ??
            m['voucherNumber'] ??
            m['metadata']?['voucherNumber'] ??
            '')
        .toString()
        .trim();

    final captionParts = <String>[];
    if (receiptNo.isNotEmpty) captionParts.add('Receipt: #$receiptNo');
    if (notes.isNotEmpty) captionParts.add(notes);
    final captionText = captionParts.join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFDE68A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  segmentName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${isOut ? '-' : '+'}৳ $amt',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isOut ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Submitted by $collectorName • $ledgerName',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (captionText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              captionText,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _buildMovementActionButtons(movementId),
        ],
      ),
    );
  }

  Widget _buildMovementActionButtons(String movementId) {
    final app = context.read<AppState>();
    if (_processingId == movementId) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFEF4444),
            side: const BorderSide(color: Color(0xFFEF4444)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: () async {
            setState(() => _processingId = movementId);
            final messenger = ScaffoldMessenger.of(context);
            final success = await app.rejectMovement(movementId, 'Declined by manager');
            if (mounted) {
              setState(() => _processingId = null);
              if (success) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Transaction declined'),
                    backgroundColor: Color(0xFFEF4444),
                  ),
                );
                app.fetchDashboardData();
              } else {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Failed to decline transaction')),
                );
              }
            }
          },
          child: const Text(
            'Decline',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F172A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: () async {
            setState(() => _processingId = movementId);
            final messenger = ScaffoldMessenger.of(context);
            final success = await app.approveMovement(movementId);
            if (mounted) {
              setState(() => _processingId = null);
              if (success) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Transaction approved'),
                    backgroundColor: Color(0xFF10B981),
                  ),
                );
                app.fetchDashboardData();
              } else {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Failed to approve transaction')),
                );
              }
            }
          },
          child: const Text(
            'Approve',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingTransferItem(BuildContext context, Map<String, dynamic> t) {
    final isIncoming = t['isIncoming'] == true;
    final amt = _formatAmount(t['amount']);
    final sender = t['senderName'] ?? 'Manager';
    final receiver = t['receiverName'] ?? 'Staff';
    final voucher = t['voucherNumber'] ?? 'Transfer';
    final transferId = t['id'].toString();
    final channel = t['channel']?.toString() ?? 'Physical Cash';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isIncoming ? const Color(0xFFF0FDF4) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isIncoming ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: isIncoming ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                child: Icon(
                  isIncoming ? Icons.arrow_downward_rounded : Icons.sync_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isIncoming ? 'Incoming Handover: +৳ $amt' : 'Outgoing Handover: ৳ $amt',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isIncoming ? const Color(0xFF166534) : const Color(0xFF92400E),
                      ),
                    ),
                    Text(
                      isIncoming ? 'From $sender • $voucher' : 'Sent to $receiver • $voucher',
                      style: TextStyle(
                        fontSize: 12,
                        color: isIncoming ? const Color(0xFF15803D) : const Color(0xFFB45309),
                      ),
                    ),
                    if (isIncoming) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0E7FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              channel,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4338CA)),
                            ),
                          ),
                        ],
                      ),
                    ],

                  ],
                ),
              ),
              if (!isIncoming)
                OutlinedButton.icon(
                  onPressed: _processingId == transferId
                      ? null
                      : () async {
                          setState(() => _processingId = transferId);
                          final success = await context.read<AppState>().cancelHandover(transferId);
                          if (mounted) setState(() => _processingId = null);
                          if (success && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Handover cancelled successfully.'),
                                backgroundColor: Color(0xFF64748B),
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.close_rounded, size: 14),
                  label: Text(
                    _processingId == transferId ? '...' : 'Cancel',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(0, 30),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
            ],
          ),
          if (isIncoming) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                // Decline Button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _processingId == transferId
                        ? null
                        : () async {
                            setState(() => _processingId = transferId);
                            final success = await context.read<AppState>().declineHandover(transferId);
                            if (mounted) setState(() => _processingId = null);
                            if (success && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Handover declined.'),
                                  backgroundColor: Color(0xFFEF4444),
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: Text(
                      _processingId == transferId ? '...' : 'Decline',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Accept Button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _processingId == transferId
                        ? null
                        : () async {
                            final app = context.read<AppState>();
                            setState(() => _processingId = transferId);
                            try {
                              await app.acceptHandover(transferId);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Handover accepted successfully!'),
                                    backgroundColor: Color(0xFF059669),
                                  ),
                                );
                                // Refresh notifications & user balances
                                Navigator.of(context).pop();
                              }
                            } catch (e) {
                              debugPrint('Handover Accept Error: $e');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to accept: $e'),
                                    backgroundColor: const Color(0xFFDC2626),
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _processingId = null);
                            }
                          },
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: Text(
                      _processingId == transferId ? '...' : 'Accept',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pending = app.pendingTransfers;
    final resolved = app.resolvedTransfers;
    final managerRecent = (app.managerOverviewData['recentTransactions'] as List?);
    final regularRecent = (managerRecent != null && managerRecent.isNotEmpty)
        ? managerRecent
        : app.employeeTransactions;

    // Combine audit items (declined/cancelled) with ledger movements
    final combinedActivity = <Map<String, dynamic>>[];
    final seenVouchers = <String>{};

    // Add audit events first
    for (final item in resolved) {
      final v = item['voucherNumber']?.toString() ?? '';
      if (v.isNotEmpty) seenVouchers.add(v);
      combinedActivity.add(Map<String, dynamic>.from(item));
    }

    // Add ledger movements (skipping if already represented by an audit event)
    for (final raw in regularRecent) {
      final item = Map<String, dynamic>.from(raw as Map);
      final v = item['voucherNumber']?.toString() ?? item['metadata']?['voucherNumber']?.toString() ?? '';
      if (v.isNotEmpty && seenVouchers.contains(v)) continue;
      combinedActivity.add(item);
    }

    // Add reviewed (approved/rejected) audit entries from manager review trail
    for (final m in app.reviewedMovements) {
      final item = Map<String, dynamic>.from(m);
      item['_isReviewedAudit'] = true;
      // Avoid duplicates by receipt or ID
      final v = item['receiptNo']?.toString() ?? item['id']?.toString() ?? '';
      if (v.isNotEmpty && seenVouchers.contains(v)) continue;
      if (v.isNotEmpty) seenVouchers.add(v);
      combinedActivity.add(item);
    }

    // Sort newest first
    combinedActivity.sort((a, b) {
      final da = DateTime.tryParse(a['approvedAt']?.toString() ?? a['createdAt']?.toString() ?? '') ?? DateTime(1970);
      final db = DateTime.tryParse(b['approvedAt']?.toString() ?? b['createdAt']?.toString() ?? '') ?? DateTime(1970);
      return db.compareTo(da);
    });

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.notifications_active_rounded, color: Color(0xFF0F172A), size: 22),
                    const SizedBox(width: 8),
                    const Text(
                      'Notifications & Activity',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (app.notificationCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${app.notificationCount}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                TextButton(
                  onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                  child: const Text('Close', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          // Content List
          Expanded(
            child: (app.pendingMovements.isEmpty && pending.isEmpty && combinedActivity.isEmpty)
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications_off_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text(
                          "You're all caught up!",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF334155)),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Handover transfers and ledger updates will appear here.",
                          style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Pending Movements Section
                      if (app.pendingMovements.isNotEmpty) ...[
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${app.pendingMovements.length} PENDING APPROVAL',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...app.pendingMovements.map((m) => _buildPendingMovementCard(context, m)),
                        const SizedBox(height: 16),
                      ],
                      // Pending Handovers Section
                      if (pending.isNotEmpty) ...[
                        const Text(
                          'PENDING HANDOVERS',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 8),
                        ...pending.map((t) => _buildPendingTransferItem(context, t)),
                        const SizedBox(height: 16),
                      ],
                      // Recent Activity Section
                      if (combinedActivity.isNotEmpty) ...[
                        const Text(
                          'RECENT ACTIVITY',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 8),
                        ...combinedActivity.map((item) {
                          final status = item['status']?.toString();
                          final isDeclined = status == 'declined';
                          final isCancelled = status == 'cancelled';
                          final amt = _formatAmount(item['amount']);
                          final time = _timeAgo(item['createdAt']);
                          final voucher = item['voucherNumber'] ?? item['metadata']?['voucherNumber'] ?? '';

                          if (isDeclined) {
                            final declinedBy = item['declinedBy'] ?? 'Recipient';
                            final voucher = item['voucherNumber'] ?? 'HND-TRANSFER';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFFECACA)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.close_rounded, color: Color(0xFFEF4444), size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Handover Declined: ৳ $amt',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF991B1B)),
                                        ),
                                        Text(
                                          'Declined by $declinedBy • $time • $voucher',
                                          style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('Declined', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                          }
                          if (isCancelled) {
                            final cancelledBy = item['cancelledBy'] ?? 'Sender';
                            final voucher = item['voucherNumber'] ?? 'HND-TRANSFER';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE2E8F0),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.block_rounded, color: Color(0xFF64748B), size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Handover Cancelled: ৳ $amt',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155)),
                                        ),
                                        Text(
                                          'Cancelled by $cancelledBy • $time • $voucher',
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF94A3B8),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('Cancelled', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                          }


                          // 2b. REVIEWED AUDIT ENTRY (Approved/Rejected by manager)
                          final isReviewedAudit = item['_isReviewedAudit'] == true ||
                              (item['approvalStatus'] != null && item['approvalStatus'] != 'pending' && item['approvedById'] != null);
                          if (isReviewedAudit) {
                            final isApproved = item['approvalStatus'] == 'approved';
                            final auditTitle = item['segment']?['name']?.toString() ??
                                item['category']?['name']?.toString() ??
                                item['note']?.toString() ??
                                'Transaction';
                            final employee = item['collector']?['name']?.toString() ?? item['actorName']?.toString() ?? 'Staff';
                            final approver = item['approver']?['name']?.toString() ?? 'Manager';
                            final ledgerName = item['ledger']?['name']?.toString() ?? '';
                            final auditTime = _timeAgo(item['approvedAt']?.toString() ?? item['createdAt']?.toString());
                            final ref = item['receiptNo'] != null ? 'Ref: #${item['receiptNo']}' : '';
                            final isAuditOut = item['direction'] == 'out' || item['type'] == 'CASH_OUT';
                            final rejectionReason = item['rejectionReason']?.toString() ?? '';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isApproved ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      isApproved ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                      color: isApproved ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${isApproved ? "Transaction Approved" : "Transaction Rejected"}: ${isAuditOut ? '-' : '+'}৳ $amt',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: isApproved ? const Color(0xFF166534) : const Color(0xFF991B1B),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$auditTitle • By $employee • ${isApproved ? "Approved" : "Rejected"} by $approver${ledgerName.isNotEmpty ? " • $ledgerName" : ""} • $auditTime',
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                        ),
                                        if (ref.isNotEmpty || (!isApproved && rejectionReason.isNotEmpty)) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            [
                                              if (ref.isNotEmpty) ref,
                                              if (!isApproved && rejectionReason.isNotEmpty) 'Reason: $rejectionReason',
                                            ].join(' • '),
                                            style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isApproved ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isApproved ? 'Approved' : 'Rejected',
                                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          // 3. REGULAR LEDGER MOVEMENT (INFLOW / OUTFLOW)
                          final isOut = item['direction'] == 'out' || item['type'] == 'CASH_OUT';
                          final rawTitle = (item['note'] ?? item['movementType'] ?? '').toString().trim();
                          final title = rawTitle.isNotEmpty ? rawTitle : (isOut ? 'Outflow' : 'Inflow');

                          // Subtitle resolution
                          final meta = item['metadata'] is Map ? item['metadata'] as Map : {};
                          final sender = item['senderName'] ?? meta['senderName'];
                          final recipient = item['recipientName'] ?? meta['recipientName'];
                          final actor = item['actorName'] ?? item['userName'];
                          final channel = item['channel'] ?? meta['channel'] ?? '';

                          String subtitle;
                          if (!isOut && sender != null && sender.toString().isNotEmpty) {
                            subtitle = 'From $sender';
                          } else if (isOut && recipient != null && recipient.toString().isNotEmpty) {
                            subtitle = 'To $recipient';
                          } else if (actor != null && actor.toString().isNotEmpty && actor.toString().toLowerCase() != 'system') {
                            subtitle = 'By $actor';
                          } else {
                            subtitle = isOut ? 'Outflow' : 'Inflow';
                          }

                          if (channel.toString().isNotEmpty) {
                            subtitle += ' • $channel';
                          }
                          subtitle += ' • $time';
                          if (voucher.toString().isNotEmpty) {
                            subtitle += ' • $voucher';
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isOut ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    isOut ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                                    color: isOut ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        subtitle,
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  isOut ? '-৳ $amt' : '+৳ $amt',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isOut ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
