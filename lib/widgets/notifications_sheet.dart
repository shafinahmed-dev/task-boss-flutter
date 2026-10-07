import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';

class NotificationsSheet extends StatefulWidget {
  const NotificationsSheet({super.key});

  static void show(BuildContext context) {
    // Clear badge upon opening
    // Removed
    context.read<AppState>().fetchPendingTransfers();

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
      // Removed
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

  Widget _buildPendingTransferItem(BuildContext context, Map<String, dynamic> t) {
    final isIncoming = t['isIncoming'] == true;
    final amt = _formatAmount(t['amount']);
    final sender = t['senderName'] ?? 'Manager';
    final receiver = t['receiverName'] ?? 'Staff';
    final voucher = t['voucherNumber'] ?? 'Transfer';
    final transferId = t['id'].toString();

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
                          if (success && mounted) {
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
                            if (success && mounted) {
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
                            setState(() => _processingId = transferId);
                            final success = await context.read<AppState>().acceptHandover(transferId);
                            if (mounted) setState(() => _processingId = null);
                            if (success && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Received ৳ $amt successfully!'),
                                  backgroundColor: const Color(0xFF10B981),
                                ),
                              );
                              Navigator.of(context, rootNavigator: true).pop();
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

    // Combine regular transactions and resolved handover events
    final combinedActivity = <Map<String, dynamic>>[
      ...resolved,
      ...regularRecent.map((e) => Map<String, dynamic>.from(e as Map)),
    ];

    // Sort combined activity by createdAt descending
    combinedActivity.sort((a, b) {
      final da = DateTime.tryParse(a['createdAt']?.toString() ?? '') ?? DateTime(1970);
      final db = DateTime.tryParse(b['createdAt']?.toString() ?? '') ?? DateTime(1970);
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
            child: (pending.isEmpty && combinedActivity.isEmpty)
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


                          final title = item['note'] ?? item['movementType'] ?? 'Transaction';
                          // Resolve actor/sender label dynamically
                          final rawActor = (item['actorName'] ?? item['senderName'] ?? '').toString().trim();
                          final isOut = item['direction'] == 'out' || item['type'] == 'Cash Out';

                          String subtitleLabel;
                          if (isOut) {
                            subtitleLabel = (rawActor.isNotEmpty && rawActor.toLowerCase() != 'system')
                                ? 'By $rawActor'
                                : 'Outflow';
                          } else {
                            subtitleLabel = (rawActor.isNotEmpty && rawActor.toLowerCase() != 'system')
                                ? 'From $rawActor'
                                : 'From Sender';

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
                                        title.toString(),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                      ),
                                      Text(
                                        '$subtitleLabel • $time',
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
