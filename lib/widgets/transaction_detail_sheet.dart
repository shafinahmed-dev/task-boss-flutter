import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/app_state.dart';


class TransactionDetailSheet extends StatelessWidget {
  final Map<String, dynamic> transaction;

  const TransactionDetailSheet({super.key, required this.transaction});

  String _resolveReceiptUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('data:image') ||
        trimmed.startsWith('http://') ||
        trimmed.startsWith('https://')) {
      return trimmed;
    }
    // Extract scheme + host + port (e.g., http://localhost:3000) without '/api'
    final apiUri = Uri.parse(AppState.defaultApiUrl);
    final origin =
        '${apiUri.scheme}://${apiUri.host}${apiUri.hasPort ? ':${apiUri.port}' : ''}';
    final normalizedPath = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return '$origin$normalizedPath';
  }

  Uint8List? _parseReceiptBytes(String url) {
    if (url.startsWith('data:image')) {
      try {
        final commaIdx = url.indexOf(',');
        if (commaIdx != -1) {
          final base64Str = url.substring(commaIdx + 1);
          return base64Decode(base64Str);
        }
      } catch (_) {}
    }
    return null;
  }

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
    final rawDate = transaction['createdAt']?.toString() ?? transaction['date']?.toString() ?? '';
    final parsedDate = DateTime.tryParse(rawDate);
    final dateTime = parsedDate != null
        ? DateFormat('MMM d, yyyy • h:mm a').format(parsedDate.toLocal())
        : rawDate;
    final note = transaction['notes']?.toString() ?? transaction['note']?.toString() ?? transaction['description']?.toString() ?? '';
    final rawReceiptUrl = transaction['receiptUrl']?.toString() ??
        transaction['photoUrl']?.toString() ??
        transaction['metadata']?['receiptUrl']?.toString() ??
        transaction['metadata']?['photoUrl']?.toString() ??
        '';
    final receiptUrl = _resolveReceiptUrl(rawReceiptUrl);

    final receiptBytes = _parseReceiptBytes(receiptUrl);

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
            const SizedBox(height: 20),
            const Divider(color: Color(0xFFE2E8F0), height: 1),
            const SizedBox(height: 16),
            _buildDetailRow(Icons.business_rounded, 'Concern', concern),
            _buildDetailRow(Icons.account_balance_wallet_rounded, 'Ledger', ledger),
            _buildDetailRow(Icons.folder_open_rounded, 'Segment', segment),
            _buildDetailRow(Icons.person_rounded, 'Recorded By', member),
            _buildDetailRow(Icons.payment_rounded, 'Payment Method', paymentMethod),
            _buildDetailRow(Icons.calendar_today_rounded, 'Date & Time', dateTime),
            if (note.isNotEmpty) _buildDetailRow(Icons.note_rounded, 'Note', note),
            const SizedBox(height: 20),
            const Text(
              'Receipt / Cash Memo',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            receiptUrl.isNotEmpty
                ? InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => Dialog(
                          backgroundColor: Colors.black,
                          insetPadding: EdgeInsets.zero,
                          child: Stack(
                            children: [
                              Center(
                                child: InteractiveViewer(
                                  minScale: 0.5,
                                  maxScale: 4.0,
                                  child: receiptBytes != null
                                      ? Image.memory(receiptBytes)
                                      : Image.network(
                                          receiptUrl,
                                          errorBuilder: (context, error, stackTrace) => const Center(
                                            child: Text('Failed to load receipt image', style: TextStyle(color: Colors.white, fontSize: 13)),
                                          ),
                                        ),
                                ),
                              ),
                              Positioned(
                                top: 40,
                                right: 20,
                                child: IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                                  onPressed: () => Navigator.pop(ctx),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 160,
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF1F5F9),
                        ),
                        child: receiptBytes != null
                            ? Image.memory(receiptBytes, fit: BoxFit.cover)
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
