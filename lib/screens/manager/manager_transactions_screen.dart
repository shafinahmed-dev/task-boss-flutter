import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../services/app_state.dart';
import '../../services/transaction_export_service.dart';
import '../../utils/platform_file_helper.dart';
import '../suite/suite_transaction_filter_modal.dart';
import '../../widgets/transaction_detail_sheet.dart';

class ManagerTransactionsScreen extends StatefulWidget {
  final String? companyId;
  final String? companyName;
  const ManagerTransactionsScreen({super.key, this.companyId, this.companyName});

  @override
  State<ManagerTransactionsScreen> createState() => _ManagerTransactionsScreenState();
}

class _ManagerTransactionsScreenState extends State<ManagerTransactionsScreen> {
  final TextEditingController _searchCtl = TextEditingController();
  SuiteFilterState _filter = SuiteFilterState();
  final RegExp _uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      final cid = widget.companyId ?? app.effectiveCompanyId;
      app.fetchManagerTransactions(companyId: cid, search: _filter.searchQuery);
    });
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _onSearchChanged(String query) async {
    setState(() => _filter.searchQuery = query);
    final app = context.read<AppState>();
    final cid = widget.companyId ?? app.effectiveCompanyId;
    await app.fetchManagerTransactions(companyId: cid, search: query);
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> rawList) {
    final now = DateTime.now();

    return rawList.where((tx) {
      // 1. Text Query (Search across segment, note/description, ledger, user/actor, voucher)
      final q = _filter.searchQuery.trim().toLowerCase();
      if (q.isNotEmpty) {
        final title = (tx['title'] ?? '').toString().toLowerCase();
        final notes = (tx['notes'] ?? tx['note'] ?? tx['description'] ?? '').toString().toLowerCase();
        final segment = (tx['segmentName'] ?? tx['segment']?['name'] ?? tx['segment'] ?? '').toString().toLowerCase();
        final ledger = (tx['ledgerName'] ?? tx['ledger']?['name'] ?? '').toString().toLowerCase();
        final actor = (tx['userName'] ?? tx['actorName'] ?? tx['collector']?['name'] ?? tx['user']?['name'] ?? '').toString().toLowerCase();
        final voucher = (tx['voucherNumber'] ?? tx['reference'] ?? '').toString().toLowerCase();

        final match = title.contains(q) ||
            notes.contains(q) ||
            segment.contains(q) ||
            ledger.contains(q) ||
            actor.contains(q) ||
            voucher.contains(q);

        if (!match) return false;
      }

      // 2. Flow Direction (in / out)
      if (_filter.direction != null && _filter.direction != 'all') {
        final dir = (tx['direction'] ?? '').toString().toLowerCase();
        if (dir != _filter.direction!.toLowerCase()) return false;
      }

      // 3. Ledger (Only ledgers in this concern)
      if (_filter.ledgerName != null && _filter.ledgerName != 'all') {
        final lName = (tx['ledgerName'] ?? tx['ledger']?['name'] ?? '').toString().trim();
        if (lName != _filter.ledgerName) return false;
      }

      // 4. Segment
      if (_filter.segmentName != null && _filter.segmentName != 'all') {
        final seg = (tx['segmentName'] ?? tx['segment']?['name'] ?? tx['segment'] ?? '').toString().trim();
        if (seg != _filter.segmentName) return false;
      }

      // 5. Member / Actor
      if (_filter.memberName != null && _filter.memberName != 'all') {
        final actor = (tx['userName'] ?? tx['actorName'] ?? tx['collector']?['name'] ?? tx['user']?['name'] ?? '').toString().trim();
        if (actor != _filter.memberName) return false;
      }

      // 6. Payment Method
      if (_filter.paymentMethod != null && _filter.paymentMethod != 'all') {
        final method = (tx['paymentMethod'] ?? tx['wallet']?['type'] ?? '').toString().toUpperCase();
        if (!method.contains(_filter.paymentMethod!.toUpperCase())) return false;
      }

      // 7. Date / Duration Presets
      if (tx['createdAt'] != null) {
        final txDate = DateTime.tryParse(tx['createdAt'].toString());
        if (txDate != null) {
          if (_filter.datePreset == 'today') {
            if (txDate.year != now.year || txDate.month != now.month || txDate.day != now.day) return false;
          } else if (_filter.datePreset == 'yesterday') {
            final yesterday = now.subtract(const Duration(days: 1));
            if (txDate.year != yesterday.year || txDate.month != yesterday.month || txDate.day != yesterday.day) return false;
          } else if (_filter.datePreset == 'this_week') {
            if (now.difference(txDate).inDays > 7) return false;
          } else if (_filter.datePreset == 'this_month') {
            if (txDate.year != now.year || txDate.month != now.month) return false;
          } else if (_filter.datePreset == 'custom' && _filter.customRange != null) {
            final localTx = txDate.toLocal();
            final start = DateTime(
              _filter.customRange!.start.year,
              _filter.customRange!.start.month,
              _filter.customRange!.start.day,
              0, 0, 0,
            );
            final end = DateTime(
              _filter.customRange!.end.year,
              _filter.customRange!.end.month,
              _filter.customRange!.end.day,
              23, 59, 59, 999,
            );
            if (localTx.isBefore(start) || localTx.isAfter(end)) return false;
          }
        }
      }

      return true;
    }).toList();
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

    final filtered = _applyFilters(rawList);

    final query = _filter.searchQuery.trim().toLowerCase();
    final effectiveSegmentMatch = (_filter.segmentName != null && _filter.segmentName != 'all')
        ? _filter.segmentName!
        : (query.isNotEmpty && rawList.any((tx) {
            final seg = (tx['segmentName'] ?? tx['segment']?['name'] ?? tx['category']?['name'] ?? '').toString().trim();
            return seg.toLowerCase() == query;
          }) ? query : '');

    final isSegmentMatch = effectiveSegmentMatch.isNotEmpty;
    double segmentInflow = 0.0;
    double segmentOutflow = 0.0;
    String matchedSegmentTitle = effectiveSegmentMatch;

    if (isSegmentMatch) {
      for (final tx in rawList) {
        final seg = (tx['segmentName'] ?? tx['segment']?['name'] ?? tx['category']?['name'] ?? '').toString().trim();
        if (seg.toLowerCase() == matchedSegmentTitle.toLowerCase()) {
          matchedSegmentTitle = seg;
          final amt = _toDouble(tx['amount']);
          final isOut = tx['direction'] == 'out' ||
              tx['type'] == 'Cash Out' ||
              tx['movementType'] == 'Cash Out' ||
              tx['type'] == 'EXPENSE';
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  filtered.length == 1 ? '1 Transaction' : '${filtered.length} Transactions',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
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
              _buildSearchBar(),
              if (_filter.hasActiveFilters) _buildActiveFilterChipsBar(),
              if (isSegmentMatch) _buildSegmentLedgerCard(matchedSegmentTitle, segmentInflow, segmentOutflow),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: () async {
                          final app = context.read<AppState>();
                          final cid = widget.companyId ?? app.effectiveCompanyId;
                          await app.fetchManagerTransactions(companyId: cid, search: _filter.searchQuery);
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) => _buildTransactionCard(filtered[i]),
                        ),
                      ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildFloatingDock(filtered),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtl,
              onChanged: (val) => _onSearchChanged(val),
              decoration: InputDecoration(
                hintText: 'Search by segment, note, or actor...',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF64748B)),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () {
              final app = context.read<AppState>();
              List<Map<String, dynamic>> rawList = app.managerTransactions;
              if (rawList.isEmpty && app.managerOverviewData['recentTransactions'] is List) {
                final recent = app.managerOverviewData['recentTransactions'] as List;
                rawList = recent.map((item) => Map<String, dynamic>.from(item as Map)).toList();
              }

              final uniqueLedgers = rawList
                  .map((t) => (t['ledgerName'] ?? t['ledger']?['name'] ?? '').toString().trim())
                  .where((l) => l.isNotEmpty)
                  .toSet()
                  .toList();

              final uniqueMembers = rawList
                  .map((t) => (t['userName'] ?? t['actorName'] ?? t['collector']?['name'] ?? t['user']?['name'] ?? '').toString().trim())
                  .where((m) => m.isNotEmpty)
                  .toSet()
                  .toList();

              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => SuiteAdvanceFilterModal(
                  initialFilter: _filter,
                  concerns: const [], // Empty list hides concern selector; screen is already scoped to this concern
                  ledgers: uniqueLedgers,
                  rawTransactions: rawList,
                  members: uniqueMembers,
                  onApply: (newFilter) {
                    setState(() => _filter = newFilter);
                  },
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: _filter.hasActiveFilters ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _filter.hasActiveFilters ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: _filter.hasActiveFilters ? Colors.white : const Color(0xFF334155),
                  ),
                  if (_filter.activeFilterCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${_filter.activeFilterCount}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildActiveFilterChipsBar() {
    final chips = <Widget>[];

    if (_filter.direction != null && _filter.direction != 'all') {
      chips.add(_buildChipTag('Flow: ${_filter.direction}', () => setState(() => _filter.direction = 'all')));
    }
    if (_filter.ledgerName != null && _filter.ledgerName != 'all') {
      chips.add(_buildChipTag('Ledger: ${_filter.ledgerName}', () => setState(() => _filter.ledgerName = 'all')));
    }
    if (_filter.segmentName != null && _filter.segmentName != 'all') {
      chips.add(_buildChipTag('Segment: ${_filter.segmentName}', () => setState(() => _filter.segmentName = 'all')));
    }
    if (_filter.memberName != null && _filter.memberName != 'all') {
      chips.add(_buildChipTag('Member: ${_filter.memberName}', () => setState(() => _filter.memberName = 'all')));
    }
    if (_filter.paymentMethod != null && _filter.paymentMethod != 'all') {
      chips.add(_buildChipTag('Method: ${_filter.paymentMethod}', () => setState(() => _filter.paymentMethod = 'all')));
    }
    if (_filter.datePreset != 'all_time' && _filter.datePreset != 'all') {
      final dateLabel = (_filter.datePreset == 'custom' && _filter.customRange != null)
          ? '${DateFormat('dd MMM').format(_filter.customRange!.start)} - ${DateFormat('dd MMM yyyy').format(_filter.customRange!.end)}'
          : _filter.datePreset.toUpperCase().replaceAll('_', ' ');
      chips.add(_buildChipTag(dateLabel, () => setState(() {
        _filter.datePreset = 'all_time';
        _filter.customRange = null;
      })));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Active Filters:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
              GestureDetector(
                onTap: () => setState(() => _filter.reset()),
                child: const Text('Clear All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: chips.map((c) => Padding(padding: const EdgeInsets.only(right: 6), child: c)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChipTag(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded, size: 14, color: Colors.white70),
          ),
        ],
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
            _filter.searchQuery.isNotEmpty ? 'No matching transactions found.' : 'No transactions recorded yet.',
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
    final hasReceipt = (tx['receiptUrl'] ?? tx['photoUrl'] ?? tx['receiptNo'] ?? tx['digitalReceipt'] ?? '').toString().isNotEmpty;

    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => TransactionDetailSheet(transaction: tx),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
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
                      if (hasReceipt) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.receipt_long_rounded, size: 14, color: Color(0xFF64748B)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  Future<void> _exportPdf(List<dynamic> filtered, double inflow, double outflow) async {
    final pdf = pw.Document();
    String periodStr = 'All Time';
    if (_filter.datePreset == 'today') periodStr = 'Today';
    else if (_filter.datePreset == 'yesterday') periodStr = 'Yesterday';
    else if (_filter.datePreset == 'this_week') periodStr = 'This Week';
    else if (_filter.datePreset == 'this_month') periodStr = 'This Month';
    else if (_filter.datePreset == 'custom' && _filter.customRange != null) {
      periodStr = '${DateFormat('dd MMM yyyy').format(_filter.customRange!.start)} - ${DateFormat('dd MMM yyyy').format(_filter.customRange!.end)}';
    }
    if (_filter.direction != null && _filter.direction != 'all') {
      periodStr += ' (${_filter.direction == 'in' ? 'Inflow' : 'Outflow'})';
    }
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Company: ${widget.companyName ?? 'Manager Transactions'}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text('Transactions Statement', style: pw.TextStyle(fontSize: 14)),
              pw.SizedBox(height: 4),
              pw.Text('Filter: $periodStr', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total Inflow: ৳ ${inflow.toStringAsFixed(2)}', style: pw.TextStyle(color: PdfColors.green700, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Total Outflow: ৳ ${outflow.toStringAsFixed(2)}', style: pw.TextStyle(color: PdfColors.red700, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Table.fromTextArray(
                headers: ['Date', 'Type', 'Ledger', 'Segment', 'Amount', 'Note'],
                data: filtered.map((tx) {
                  final dt = _formatDateTime(tx['createdAt']);
                  final dir = (tx['direction'] ?? '').toString().toUpperCase();
                  final ledger = (tx['ledgerName'] ?? tx['ledger']?['name'] ?? '').toString();
                  final segmentName = (tx['segmentName'] ?? tx['segment']?['name'] ?? '').toString();
                  final amt = _toDouble(tx['amount']).toStringAsFixed(2);
                  final note = (tx['title'] ?? tx['note'] ?? tx['notes'] ?? '').toString();
                  return [dt, dir, ledger, segmentName, amt, note];
                }).toList(),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();

    await deliverFile(
      bytes: bytes,
      fileName: 'manager_transactions_statement.pdf',
      mimeType: 'application/pdf',
      context: mounted ? context : null,
    );
  }

  Widget _buildFloatingDock(List<dynamic> filtered) {
    double inflow = 0.0;
    double outflow = 0.0;
    for (final tx in filtered) {
      final amt = _toDouble(tx['amount']);
      final isOut = tx['direction'] == 'out' ||
          tx['type'] == 'Cash Out' ||
          tx['movementType'] == 'Cash Out' ||
          tx['type'] == 'EXPENSE';
      if (isOut) {
        outflow += amt;
      } else {
        inflow += amt;
      }
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'INFLOW',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '+৳ ${_formatAmount(inflow)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      String filterSummary = "All Time";
                      if (_filter.datePreset == "today") filterSummary = "Today";
                      else if (_filter.datePreset == "yesterday") filterSummary = "Yesterday";
                      else if (_filter.datePreset == "this_week") filterSummary = "This Week";
                      else if (_filter.datePreset == "this_month") filterSummary = "This Month";
                      else if (_filter.datePreset == "custom" && _filter.customRange != null) {
                        filterSummary = "${DateFormat("dd MMM").format(_filter.customRange!.start)} - ${DateFormat("dd MMM yyyy").format(_filter.customRange!.end)}";
                      }
                      final companyTitle = widget.companyName ?? "Manager Transactions";
                      TransactionExportService.showExportOptionsSheet(
                        context: context,
                        transactions: filtered,
                        title: "$companyTitle Statement",
                        filterSummary: filterSummary,
                        onExportPdf: () => _exportPdf(filtered, inflow, outflow),
                      );
                    },
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                          width: 1.0,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.download_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'OUTFLOW',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '-৳ ${_formatAmount(outflow)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

