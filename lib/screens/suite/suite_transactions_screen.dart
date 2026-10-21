import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';

class SuiteTransactionsScreen extends StatefulWidget {
  const SuiteTransactionsScreen({super.key});

  @override
  State<SuiteTransactionsScreen> createState() =>
      _SuiteTransactionsScreenState();
}

class _SuiteTransactionsScreenState extends State<SuiteTransactionsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedPeriod = 'all_time';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchTransactions();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTransactions() async {
    await context.read<AppState>().fetchSuiteTransactions(
          range: _selectedPeriod == 'all_time' ? null : _selectedPeriod,
        );
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final hour = dt.hour == 0
          ? 12
          : dt.hour > 12
              ? dt.hour - 12
              : dt.hour;
      final amPm = dt.hour < 12 ? 'AM' : 'PM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return "${months[dt.month - 1]} ${dt.day}, ${dt.year} • $hour:$minute $amPm";
    } catch (_) {
      return dateStr;
    }
  }

  Widget _pdfRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF64748B))),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? const Color(0xFF0F172A))),
        ],
      ),
    );
  }

  void _exportPdf(
      List<Map<String, dynamic>> items, double inflow, double outflow) {
    final labels = {
      'all_time': 'All Time',
      'today': 'Today',
      'this_week': 'This Week',
      'this_month': 'This Month',
    };
    final net = inflow - outflow;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.picture_as_pdf_rounded,
              color: Color(0xFF0F172A), size: 22),
          SizedBox(width: 8),
          Text('Export PDF Statement',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _pdfRow('Period', labels[_selectedPeriod] ?? 'All Time'),
              _pdfRow('Total Transactions', "${items.length}"),
              const Divider(height: 20),
              _pdfRow('Total Inflow',
                  "+৳ ${inflow.toStringAsFixed(2)}",
                  valueColor: const Color(0xFF10B981)),
              _pdfRow('Total Outflow',
                  "-৳ ${outflow.toStringAsFixed(2)}",
                  valueColor: const Color(0xFFEF4444)),
              _pdfRow(
                  'Net Balance',
                  '${net >= 0 ? '+' : ''}৳ ${net.toStringAsFixed(2)}',
                  valueColor: net >= 0
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444)),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Sample Entries:',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF64748B))),
                const SizedBox(height: 6),
                ...items.take(3).map((t) {
                  final isIn = t['direction'] == 'in';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Icon(
                          isIn
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          size: 12,
                          color: isIn
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444)),
                      const SizedBox(width: 4),
                      Expanded(
                          child: Text(
                              "${t['ledgerName']} • ${t['segmentName']}",
                              style: const TextStyle(fontSize: 10),
                              overflow: TextOverflow.ellipsis)),
                      Text(
                          "৳ ${(t['amount'] as num).toStringAsFixed(2)}",
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ]),
                  );
                }),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close')),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content:
                      Text('PDF statement successfully exported.')));
            },
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Download / Print'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (app.isSuiteLoading && app.suiteTransactions.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(
            child: CircularProgressIndicator(color: Color(0xFF1E2638))),
      );
    }

    final rawList = app.suiteTransactions;
    final q = _searchQuery.toLowerCase();

    final filteredTransactions = rawList.where((t) {
      if (q.isEmpty) return true;
      final l = (t['ledgerName'] ?? '').toString().toLowerCase();
      final s = (t['segmentName'] ?? '').toString().toLowerCase();
      final u = (t['userName'] ?? '').toString().toLowerCase();
      final v = (t['voucherNumber'] ?? '').toString().toLowerCase();
      final n = (t['notes'] ?? '').toString().toLowerCase();
      final c = (t['companyCode'] ?? '').toString().toLowerCase();
      return l.contains(q) ||
          s.contains(q) ||
          u.contains(q) ||
          v.contains(q) ||
          n.contains(q) ||
          c.contains(q);
    }).toList();

    final liveInflow = filteredTransactions
        .where((t) => t['direction'] == 'in')
        .fold<double>(
            0.0, (sum, t) => sum + (t['amount'] as num).toDouble());
    final liveOutflow = filteredTransactions
        .where((t) => t['direction'] == 'out')
        .fold<double>(
            0.0, (sum, t) => sum + (t['amount'] as num).toDouble());

    final periodLabels = {
      'all_time': 'All Time',
      'today': 'Today',
      'this_week': 'This Week',
      'this_month': 'This Month',
    };
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Suite Transactions',
          style: TextStyle(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${filteredTransactions.length} txns',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                color: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) =>
                            setState(() => _searchQuery = val.trim()),
                        decoration: InputDecoration(
                          hintText:
                              'Search transactions by ledger, segment, user, note, or voucher...',
                          hintStyle: const TextStyle(
                              fontSize: 13, color: Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded,
                              size: 20, color: Color(0xFF64748B)),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded,
                                      size: 18, color: Color(0xFF94A3B8)),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: PopupMenuButton<String>(
                        initialValue: _selectedPeriod,
                        tooltip: 'Filter by date',
                        icon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today_rounded,
                                size: 16, color: Color(0xFF0F172A)),
                            const SizedBox(width: 4),
                            Text(
                              periodLabels[_selectedPeriod] ?? 'All Time',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F172A)),
                            ),
                            const SizedBox(width: 2),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 0),
                        onSelected: (val) {
                          setState(() => _selectedPeriod = val);
                          _fetchTransactions();
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                              value: 'all_time', child: Text('All Time')),
                          const PopupMenuItem(
                              value: 'today', child: Text('Today')),
                          const PopupMenuItem(
                              value: 'this_week', child: Text('This Week')),
                          const PopupMenuItem(
                              value: 'this_month', child: Text('This Month')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filteredTransactions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.receipt_long_rounded,
                                size: 48, color: Color(0xFF94A3B8)),
                            const SizedBox(height: 12),
                            Text(
                              rawList.isEmpty
                                  ? 'No transactions recorded yet.'
                                  : 'No matching transactions found.',
                              style: const TextStyle(
                                  color: Color(0xFF64748B), fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchTransactions,
                        color: const Color(0xFF0F172A),
                        child: ListView.builder(
                          padding: const EdgeInsets.only(
                              top: 8, bottom: 96, left: 0, right: 0),
                          itemCount: filteredTransactions.length,
                          itemBuilder: (context, index) {
                            final tx = filteredTransactions[index];
                            final isInflow = tx['direction'] == 'in';
                            final amount =
                                (tx['amount'] as num?)?.toDouble() ?? 0.0;
                            final ledgerName =
                                (tx['ledgerName'] ?? 'General Operations')
                                    .toString();
                            final segmentName =
                                (tx['segmentName'] ?? 'General').toString();
                            final userName =
                                (tx['userName'] ?? 'Staff').toString();
                            final companyCode =
                                (tx['companyCode'] ?? '').toString();
                            final isHandover =
                                tx['isHandover'] == true;
                            final senderName =
                                (tx['senderName'] ?? '').toString();
                            final senderCode =
                                (tx['senderCode'] ?? '').toString();
                            final recipientName =
                                (tx['recipientName'] ?? '').toString();
                            final recipientCode =
                                (tx['recipientCode'] ?? '').toString();
                            final formattedDateTime =
                                _formatDateTime(tx['createdAt']?.toString());

                            return Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    isInflow
                                        ? Icons.arrow_downward_rounded
                                        : Icons.arrow_upward_rounded,
                                    color: isInflow
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFFEF4444),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          "$ledgerName • $segmentName",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          formattedDateTime,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        "৳ ${amount.toStringAsFixed(2)}",
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        isHandover
                                            ? "$senderName [$senderCode] → $recipientName [$recipientCode]"
                                            : "$userName [$companyCode]",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Inflow',
                          style: TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 10)),
                      Text(
                        "+৳ ${liveInflow.toStringAsFixed(2)}",
                        style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _exportPdf(
                        filteredTransactions, liveInflow, liveOutflow),
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                    label: const Text('Export PDF',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0F172A),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Outflow',
                          style: TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 10)),
                      Text(
                        "-৳ ${liveOutflow.toStringAsFixed(2)}",
                        style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
