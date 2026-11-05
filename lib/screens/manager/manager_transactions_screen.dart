import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';

class ManagerTransactionsScreen extends StatefulWidget {
  final String? companyId;
  final String? companyName;
  const ManagerTransactionsScreen({super.key, this.companyId, this.companyName});

  @override
  State<ManagerTransactionsScreen> createState() => _ManagerTransactionsScreenState();
}

class _ManagerTransactionsScreenState extends State<ManagerTransactionsScreen> {
  final TextEditingController _searchCtl = TextEditingController();
  String _searchQuery = '';
  final RegExp _uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      final cid = widget.companyId ?? app.effectiveCompanyId;
      app.fetchManagerTransactions(companyId: cid, search: _searchQuery);
    });
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _onSearchChanged(String query) async {
    setState(() => _searchQuery = query);
    final app = context.read<AppState>();
    final cid = widget.companyId ?? app.effectiveCompanyId;
    await app.fetchManagerTransactions(companyId: cid, search: query);
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
    return '$year-$month-$day • $hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    
    List<Map<String, dynamic>> rawList = app.managerTransactions;
    if (rawList.isEmpty && app.managerOverviewData['recentTransactions'] is List) {
      final recent = app.managerOverviewData['recentTransactions'] as List;
      rawList = recent.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    }
    
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
        title: Text(
          widget.companyName != null ? '${widget.companyName} — Transactions' : 'All Transactions',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          if (isSegmentMatch) _buildSegmentLedgerCard(matchedSegmentTitle, segmentInflow, segmentOutflow),
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: () async {
                      final app = context.read<AppState>();
                      final cid = widget.companyId ?? app.effectiveCompanyId;
                      await app.fetchManagerTransactions(companyId: cid, search: _searchQuery);
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) => _buildTransactionCard(filtered[i]),
                    ),
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
        onChanged: (val) => _onSearchChanged(val),
        decoration: InputDecoration(
          hintText: 'Search by segment, note, or actor...',
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF94A3B8)),
                  onPressed: () {
                    _searchCtl.clear();
                    _onSearchChanged('');
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
                  Text('+৳ ${_formatAmount(inflow)}', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Outflow', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                  const SizedBox(height: 2),
                  Text('-৳ ${_formatAmount(outflow)}', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Net Balance', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                  const SizedBox(height: 2),
                  Text('৳ ${_formatAmount(inflow - outflow)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty ? 'No matching transactions found.' : 'No transactions recorded yet.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final amt = _toDouble(tx['amount']);
    final isOut = tx['direction'] == 'out' ||
        tx['type'] == 'Cash Out' ||
        tx['movementType'] == 'Cash Out' ||
        tx['type'] == 'EXPENSE';

    // Segment Pill Resolution
    String segment = 'General';
    final rawSegment = tx['segmentName'] ?? tx['segment']?['name'] ?? tx['category']?['name'];
    if (rawSegment != null) {
      final s = rawSegment.toString().trim();
      if (s.isNotEmpty && !_uuidRegex.hasMatch(s)) {
        segment = s;
      }
    }

    // Title Resolution
    String displayTitle = segment;
    final rawNote = (tx['title'] ?? tx['note'] ?? tx['notes'] ?? '').toString().trim();
    if (rawNote.isNotEmpty && !_uuidRegex.hasMatch(rawNote)) {
      displayTitle = rawNote;
    } else if (displayTitle == 'General' && tx['movementType'] != null) {
      final mType = tx['movementType'].toString().trim();
      if (mType.isNotEmpty && !_uuidRegex.hasMatch(mType)) {
        displayTitle = mType;
      }
    }

    // Actor and Role Resolution
    final actor = tx['actorName'] ?? tx['userName'] ?? tx['collector']?['name'] ?? tx['user']?['name'] ?? 'Staff';
    final role = tx['actorRole'] ?? tx['userRole'] ?? tx['collector']?['role'] ?? tx['user']?['role'] ?? 'Staff';
    final formattedDate = _formatDateTime(tx['createdAt']);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isOut ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isOut ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              color: isOut ? const Color(0xFFEF4444) : const Color(0xFF10B981),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        displayTitle,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      isOut ? '-৳ ${_formatAmount(amt)}' : '+৳ ${_formatAmount(amt)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isOut ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        segment.toString(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$formattedDate  •  By: $actor ($role)',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

