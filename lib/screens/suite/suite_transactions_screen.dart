import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';

class SuiteTransactionsScreen extends StatefulWidget {
  const SuiteTransactionsScreen({super.key});

  @override
  State<SuiteTransactionsScreen> createState() => _SuiteTransactionsScreenState();
}

class _SuiteTransactionsScreenState extends State<SuiteTransactionsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() => _searchQuery = _searchController.text.trim().toLowerCase()));
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await context.read<AppState>().fetchSuiteTransactions();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading transactions: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatAmount(dynamic val) {
    if (val == null) return '0.00';
    return ((val is num) ? val.toDouble() : (double.tryParse(val.toString()) ?? 0.0)).toStringAsFixed(2);
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(dateStr);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} • ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  Widget _buildTransactionList(List<Map<String, dynamic>> transactions) {
    if (_isLoading && context.read<AppState>().suiteTransactions.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1E2638)));
    }
    if (transactions.isEmpty) {
      return const Center(
        child: Text('No transactions recorded yet.', style: TextStyle(color: Color(0xFF64748B), fontSize: 14, fontWeight: FontWeight.w500)),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF1E2638),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: transactions.length,
        itemBuilder: (context, index) {
          final tx = transactions[index];
          final type = (tx['type'] ?? 'INFLOW').toString().toUpperCase();
          final isInflow = type == 'INFLOW' || type == 'IN';
          final amount = tx['amount'] ?? 0.0;
          final description = tx['description'] ?? 'Transaction';
          final concernCode = (tx['concernCode'] ?? '').toString().toUpperCase();
          final createdAt = tx['createdAt'];
          final actorName = tx['actorName'] ?? 'System';

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isInflow ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    isInflow ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                    color: isInflow ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(description, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (concernCode.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(4)),
                              child: Text(concernCode, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(_formatDate(createdAt), style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${isInflow ? '+' : '-'}৳ ${_formatAmount(amount)}', style: TextStyle(color: isInflow ? const Color(0xFF10B981) : const Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(actorName, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transactions = context.watch<AppState>().suiteTransactions.where((tx) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery;
      return (tx['description'] ?? '').toString().toLowerCase().contains(q) ||
          (tx['concernName'] ?? '').toString().toLowerCase().contains(q) ||
          (tx['concernCode'] ?? '').toString().toLowerCase().contains(q) ||
          (tx['amount'] ?? '').toString().toLowerCase().contains(q) ||
          (tx['actorName'] ?? '').toString().toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2638),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Suite Transactions', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Search transactions...',
                        hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    InkWell(
                      onTap: () => _searchController.clear(),
                      child: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 18),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _buildTransactionList(transactions),
          ),
        ],
      ),
    );
  }
}

