import 'package:flutter/material.dart';
import 'package:task_boss/widgets/transaction_receipt_ticket.dart';
import 'package:task_boss/utils/receipt_exporter.dart';

void showReceiptModal(
  BuildContext context, {
  required String receiptNo,
  required DateTime date,
  required String type,
  required String categoryOrRecipient,
  required String wallet,
  required String method,
  required String note,
  required double amount,
  required double fee,
}) {
  final GlobalKey boundaryKey = GlobalKey();

  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              key: boundaryKey,
              child: TransactionReceiptTicket(
                receiptNo: receiptNo,
                date: date,
                type: type,
                categoryOrRecipient: categoryOrRecipient,
                wallet: wallet,
                method: method,
                note: note,
                amount: amount,
                fee: fee,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    final cleanId = receiptNo.replaceAll('#', '').replaceAll(' ', '_');
                    await exportReceiptImage(boundaryKey, 'Voucher_$cleanId');
                  },
                  icon: const Icon(Icons.download_rounded, color: Colors.white, size: 18),
                  label: const Text('Download PNG', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}