import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';

class SuiteTransactionsScreen extends StatefulWidget {
  const SuiteTransactionsScreen({super.key});

  @override
  State<SuiteTransactionsScreen> createState() => _SuiteTransactionsScreenState();
}

class _SuiteTransactionsScreenState extends State<SuiteTransactionsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
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
    _searchCtrl.dispose();
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
          final concernCode = (tx['companyCode'] ?? tx['company']?['code'] ?? 'CONCERN').toString().toUpperCase();
          final segment = (tx['segmentName'] ?? tx['category']?['name'] ?? 'General').toString();
          final titleText = '$concernCode • $segment';

          final isOut = tx['direction'] == 'out' || tx['type'] == 'Cash Out' || tx['type'] == 'EXPENSE';
          final amt = double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0;
          final formattedAmt = isOut ? '-৳ ${amt.toStringAsFixed(2)}' : '+৳ ${amt.toStringAsFixed(2)}';
          final color = isOut ? const Color(0xFFEF4444) : const Color(0xFF10B981);
          final iconBg = isOut ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4);
          final icon = isOut ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;

          final createdAt = tx['createdAt'];
          final actorName = tx['actorName'] ?? tx['user']?['name'] ?? 'System';

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
                    color: iconBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    color: color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleText,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(createdAt),
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formattedAmt,
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      actorName,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
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
    final rawList = context.watch<AppState>().suiteTransactions;
    final query = _searchQuery.trim().toLowerCase();

    final transactions = rawList.where((tx) {
      if (query.isEmpty) return true;
      final code = (tx['companyCode'] ?? tx['company']?['code'] ?? '').toString().toLowerCase();
      final company = (tx['companyName'] ?? tx['company']?['name'] ?? '').toString().toLowerCase();
      final segment = (tx['segmentName'] ?? tx['category']?['name'] ?? '').toString().toLowerCase();
      final actor = (tx['actorName'] ?? tx['user']?['name'] ?? '').toString().toLowerCase();
      final note = (tx['note'] ?? '').toString().toLowerCase();
      final amt = (tx['amount'] ?? '').toString();

      return code.contains(query) ||
          company.contains(query) ||
          segment.contains(query) ||
          actor.contains(query) ||
          note.contains(query) ||
          amt.contains(query);
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
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search transactions...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1E2638)),
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
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

