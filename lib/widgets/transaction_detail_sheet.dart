import 'package:flutter/material.dart';

class TransactionDetailSheet extends StatelessWidget {
  final Map<String, dynamic> transaction;

  const TransactionDetailSheet({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse((transaction['amount'] ?? 0).toString()) ?? 0.0;
    final direction = (transaction['direction'] ?? '').toString().toLowerCase();
    final isInflow = direction == 'in' || direction == 'inflow';
    final title = transaction['title']?.toString() ?? transaction['ledgerName']?.toString() ?? 'Transaction';
    final concern = transaction['companyName']?.toString() ?? transaction['concernName']?.toString() ?? transaction['concern']?.toString() ?? '';
    final ledger = transaction['ledgerName']?.toString() ?? transaction['ledger']?['name']?.toString() ?? 'General';
    final segment = transaction['segmentName']?.toString() ?? transaction['segment']?['name']?.toString() ?? transaction['category']?['name']?.toString() ?? 'General';
    final member = transaction['userName']?.toString() ?? transaction['actorName']?.toString() ?? 'Staff';
    final paymentMethod = transaction['paymentMethod']?.toString() ?? transaction['walletName']?.toString() ?? 'Cash';
    final dateTime = transaction['createdAt']?.toString() ?? transaction['date']?.toString() ?? '';
    final note = transaction['notes']?.toString() ?? transaction['note']?.toString() ?? transaction['description']?.toString() ?? '';
    final receiptUrl = transaction['receiptUrl']?.toString() ?? transaction['photoUrl']?.toString() ?? transaction['metadata']?['receiptUrl']?.toString() ?? '';

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20,
        right: 20,
        top: 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '৳ ${amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isInflow ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
            const SizedBox(height: 20),
            const Divider(color: Color(0xFFE2E8F0)),
            const SizedBox(height: 12),
            _buildDetailRow(Icons.business_rounded, 'Concern', concern.isNotEmpty ? concern : 'Workspace Concern'),
            _buildDetailRow(Icons.account_balance_rounded, 'Ledger', ledger),
            _buildDetailRow(Icons.category_rounded, 'Segment', segment),
            _buildDetailRow(Icons.person_rounded, 'Member / Actor', member),
            _buildDetailRow(Icons.payment_rounded, 'Payment Method', paymentMethod),
            _buildDetailRow(Icons.calendar_today_rounded, 'Date & Time', dateTime),
            if (note.isNotEmpty) _buildDetailRow(Icons.note_rounded, 'Note', note),
            const SizedBox(height: 16),
            const Text(
              'Receipt / Cash Memo',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            receiptUrl.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => Dialog(
                          backgroundColor: Colors.black.withValues(alpha: 0.9),
                          insetPadding: EdgeInsets.zero,
                          child: Stack(
                            children: [
                              Center(
                                child: InteractiveViewer(
                                  maxScale: 5.0,
                                  child: receiptUrl.startsWith('data:')
                                      ? Image.memory(Uri.parse(receiptUrl).data!.contentBytes)
                                      : Image.network(receiptUrl),
                                ),
                              ),
                              Positioned(
                                top: 40,
                                right: 20,
                                child: IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 160,
                        width: double.infinity,
                        color: const Color(0xFFF1F5F9),
                        child: receiptUrl.startsWith('data:')
                            ? Image.memory(
                                Uri.parse(receiptUrl).data!.contentBytes,
                                fit: BoxFit.cover,
                              )
                            : Image.network(
                                receiptUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => const Center(
                                  child: Text('Failed to load receipt image', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                                ),
                              ),
                      ),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Center(
                      child: Text(
                        'No receipt or cash memo attached',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      ),
                    ),
                  ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF64748B)),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isInflow ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isInflow ? 'INFLOW' : 'OUTFLOW',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isInflow ? const Color(0xFF059669) : const Color(0xFFDC2626),
                    ),
                  ),
                ),
              ],
            ),
