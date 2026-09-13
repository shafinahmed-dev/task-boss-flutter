import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TransactionReceiptTicket extends StatelessWidget {
  final String receiptNo, type, categoryOrRecipient, wallet, method, note;
  final DateTime date;
  final double amount, fee;

  const TransactionReceiptTicket({
    super.key,
    required this.receiptNo,
    required this.date,
    required this.type,
    required this.categoryOrRecipient,
    required this.wallet,
    required this.method,
    required this.note,
    required this.amount,
    required this.fee,
  });

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('dd MMM yyyy, hh:mm a').format(date);
    final total = amount + fee;

    return Container(
      width: 480,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'TASK DESIGN & CONSULTANCY',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 2),
          const Text(
            'Transaction Receipt',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Receipt No: #${receiptNo.startsWith('#') ? receiptNo.substring(1) : receiptNo}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              Text(
                'Date: $formattedDate',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF334155)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _dashedDivider(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _gridItem('Transaction Type', type)),
              Expanded(child: _gridItem(type.contains('Transfer') || type.contains('Handover') ? 'Recipient / Sender' : 'Category', categoryOrRecipient)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _gridItem('Wallet / Account', wallet)),
              Expanded(child: _gridItem('Method', method)),
            ],
          ),
          const SizedBox(height: 10),
          _gridItem('Note', note.isEmpty ? 'N/A' : note),
          const SizedBox(height: 10),
          _dashedDivider(),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Amount: ৳${amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Fee: ৳${fee.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF1E293B)),
                  ),
                ],
              ),
              _buildCircularStamp(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'TOTAL AMOUNT',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '৳${total.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCircularStamp() {
    return Transform.rotate(
      angle: -12 * (math.pi / 180),
      child: Container(
        width: 86,
        height: 86,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x441D4ED8), width: 2),
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x331D4ED8), width: 1),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'TASK DNC',
                  style: TextStyle(color: Color(0x551D4ED8), fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                ),
                SizedBox(height: 1),
                Text(
                  'VERIFIED',
                  style: TextStyle(color: Color(0x661D4ED8), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                ),
                SizedBox(height: 1),
                Text(
                  'OFFICIAL',
                  style: TextStyle(color: Color(0x551D4ED8), fontSize: 7.5, fontWeight: FontWeight.w800, letterSpacing: 1.0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _gridItem(String l, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 2),
          Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
        ],
      );

  Widget _dashedDivider() => Row(
        children: List.generate(
          20,
          (i) => Expanded(child: Container(color: i % 2 == 0 ? const Color(0xFFCBD5E1) : Colors.transparent, height: 1)),
        ),
      );
}