const fs = require('fs');

const p1 = `import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';

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

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  String _formatAmount(dynamic val) => _toDouble(val).toStringAsFixed(2);

  String _formatDateTime(dynamic iso) {
    if (iso == null || iso.toString().isEmpty) return 'Recent';
    final d = DateTime.tryParse(iso.toString())?.toLocal();
    if (d == null) return iso.toString();
    final year = d.year;
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hour = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final minute = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return \`\${year}-\${month}-\${day} • \${hour}:\${minute} \${ampm}\`;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final List<Map<String, dynamic>> rawList = app.managerTransactions;
    final query = _searchQuery.trim().toLowerCase();

    final filtered = rawList.where((tx) {
      if (query.isEmpty) return true;
      final seg = (tx['segmentName'] ?? tx['category']?['name'] ?? '').toString().toLowerCase();
      final note = (tx['note'] ?? tx['movementType'] ?? '').toString().toLowerCase();
      final actor = (tx['actorName'] ?? tx['user']?['name'] ?? '').toString().toLowerCase();
      return seg.contains(query) || note.contains(query) || actor.contains(query);
    }).toList();

    final isSegmentMatch = query.isNotEmpty && rawList.any((tx) {
      final seg = (tx['segmentName'] ?? tx['category']?['name'] ?? '').toString().toLowerCase();
      return seg == query;
    });

    double segmentInflow = 0.0;
    double segmentOutflow = 0.0;
    String matchedSegmentTitle = '';

    if (isSegmentMatch) {
      for (final tx in rawList) {
        final seg = (tx['segmentName'] ?? tx['category']?['name'] ?? '').toString().toLowerCase();
        if (seg == query) {
          matchedSegmentTitle = tx['segmentName'] ?? tx['category']?['name'] ?? query;
          final amt = _toDouble(tx['amount']);
          final isOut = tx['direction'] == 'out' || tx['type'] == 'Cash Out' || tx['type'] == 'EXPENSE';
          if (isOut) {
            segmentOutflow += amt;
          } else {
            segmentInflow += amt;
          }
        }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('All Transactions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          if (isSegmentMatch) _buildSegmentLedgerCard(matchedSegmentTitle, segmentInflow, segmentOutflow),
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) => _buildTransactionCard(filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: TextField(
        controller: _searchCtl,
        onChanged: (val) => setState(() => _searchQuery = val),
        decoration: InputDecoration(
          hintText: 'Search by segment, note, or actor...',
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF94A3B8)),
                  onPressed: () {
                    _searchCtl.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFFF1F5F9),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildSegmentLedgerCard(String title, double inflow, double outflow) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF334155), borderRadius: BorderRadius.circular(6)),
                child: const Text('Segment Book', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Inflow', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(\`+৳ \${_formatAmount(inflow)}\`, style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Outflow', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(\`-৳ \${_formatAmount(outflow)}\`, style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Net Balance', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(\`৳ \${_formatAmount(inflow - outflow)}\`, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
   
