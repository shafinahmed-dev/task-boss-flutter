import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/utils/show_receipt_modal.dart';

class ManagerTransactionsScreen extends StatefulWidget {
  const ManagerTransactionsScreen({super.key});

  @override
  State<ManagerTransactionsScreen> createState() => _ManagerTransactionsScreenState();
}

class _ManagerTransactionsScreenState extends State<ManagerTransactionsScreen> {
  final TextEditingController _searchCtl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().fetchManagerTransactions();
    });
  }

  String _formatAmount(dynamic val) {
    if (val == null) return '0.00';
    final n = (val is num) ? val.toDouble() : (double.tryParse(val.toString()) ?? 0.0);
    return n.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final txList = app.managerTransactionsList.where((tx) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final w = tx['wallet']?['name']?.toString().toLowerCase() ?? '';
      final c = tx['collector']?['name']?.toString().toLowerCase() ?? '';
      final a = tx['amount']?.toString() ?? '';
      final s = tx['segmentName']?.toString().toLowerCase() ?? tx['category']?['name']?.toString().toLowerCase() ?? '';
      final n = tx['note']?.toString().toLowerCase() ?? '';
      return w.contains(q) || c.contains(q) || a.contains(q) || s.contains(q) || n.contains(q);
    }).toList();
    final matchedSegment = _searchQuery.isNotEmpty 
      ? app.concernCategories.firstWhere((c) => c['name']?.toString().toLowerCase() == _searchQuery.toLowerCase(), orElse: () => {})
      : {};
    
    double segmentInflow = 0;
    double segmentOutflow = 0;
    if (matchedSegment.isNotEmpty) {
      for (final tx in app.managerTransactionsList) {
        if (tx['category']?['id'] == matchedSegment['id']) {
          final amt = (tx['amount'] is num) ? (tx['amount'] as num).toDouble() : (double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0);
          if (tx['direction'] == 'in') segmentInflow += amt;
          else segmentOutflow += amt;
        }
      }
    }
    final segmentNet = segmentInflow - segmentOutflow;



    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('All Transactions', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E2638),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchCtl,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          if (matchedSegment.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📁 ${matchedSegment['name']}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('In: +৳ ${_formatAmount(segmentInflow)}', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                      Text('Out: -৳ ${_formatAmount(segmentOutflow)}', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                      Text('Net: ৳ ${_formatAmount(segmentNet)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  )
                ],
              ),
            )
          ],
              controller: _searchCtl,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => app.fetchManagerTransactions(),
              color: const Color(0xFF1E2638),
              child: txList.isEmpty
                  ? const Center(child: Text('No transactions found.', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: txList.length,
                      itemBuilder: (context, index) {
                        final tx = txList[index];
                        final amount = _formatAmount(tx['amount']);
                        final isIn = (tx['direction'] ?? 'IN').toString().toUpperCase() == 'IN';
                        final walletName = tx['wallet']?['name'] ?? 'Wallet';
                        final employeeName = tx['collector']?['name'] ?? tx['custodian']?['name'] ?? 'Employee';
                        final dateStr = tx['createdAt'] != null ? tx['createdAt'].toString().substring(0, 10) : '';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(12),
                            leading: CircleAvatar(
                              backgroundColor: isIn ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                              child: Icon(isIn ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, color: isIn ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
                            ),
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(walletName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A))),
                                Text('${isIn ? '+' : '-'}৳ $amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isIn ? const Color(0xFF16A34A) : const Color(0xFFDC2626))),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(tx['segmentName'] ?? tx['category']?['name'] ?? 'General', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                                  const SizedBox(height: 2),
                                  Text('By: ${tx['actorName'] ?? employeeName} (${tx['actorRole'] ?? 'Staff'})', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                  const SizedBox(height: 2),
                                  Text(dateStr, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                                ],
                              ),
                            ),
                            onTap: () {
                              final receiptNo = tx['receiptNo'] ?? tx['_id']?.toString().substring(0, 8).toUpperCase() ?? 'REC';
                              final date = tx['createdAt'] != null ? DateTime.tryParse(tx['createdAt'].toString()) ?? DateTime.now() : DateTime.now();
                              final type = tx['direction'] ?? 'IN';
                              final categoryOrRecipient = tx['collector']?['name'] ?? tx['custodian']?['name'] ?? 'Employee';
                              final wallet = tx['wallet']?['name'] ?? 'Wallet';
                              final method = tx['method'] ?? 'Transfer';
                              final note = tx['note'] ?? 'Manager Transaction';
                              final amount = (tx['amount'] is num) ? (tx['amount'] as num).toDouble() : (double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0);
                              final fee = (tx['fee'] is num) ? (tx['fee'] as num).toDouble() : (double.tryParse(tx['fee']?.toString() ?? '0') ?? 0.0);

                              showReceiptModal(
                                context,
                                receiptNo: receiptNo,
                                date: date,
                                type: type,
                                categoryOrRecipient: categoryOrRecipient,
                                wallet: wallet,
                                method: method,
                                note: note,
                                amount: amount,
                                fee: fee,
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
