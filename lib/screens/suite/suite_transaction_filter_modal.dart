import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SuiteFilterState {
  String? ledgerName;
  String? concernId;
  String? segmentName;
  String? memberName;
  String? paymentMethod; // 'CASH' | 'BANK' | 'MFS'
  String? direction;     // 'in' | 'out' | 'all'
  String datePreset;     // 'all_time' | 'today' | 'yesterday' | 'this_week' | 'this_month' | 'custom'
  DateTimeRange? customRange;
  String searchQuery;

  SuiteFilterState({
    this.ledgerName,
    this.concernId,
    this.segmentName,
    this.memberName,
    this.paymentMethod,
    this.direction,
    this.datePreset = 'all_time',
    this.customRange,
    this.searchQuery = '',
  });

  bool get hasActiveFilters =>
      (ledgerName != null && ledgerName != 'all') ||
      (concernId != null && concernId != 'all') ||
      (segmentName != null && segmentName != 'all') ||
      (memberName != null && memberName != 'all') ||
      (paymentMethod != null && paymentMethod != 'all') ||
      (direction != null && direction != 'all') ||
      datePreset != 'all_time' ||
      searchQuery.trim().isNotEmpty;

  int get activeFilterCount {
    int count = 0;
    if (ledgerName != null && ledgerName != 'all') count++;
    if (concernId != null && concernId != 'all') count++;
    if (segmentName != null && segmentName != 'all') count++;
    if (memberName != null && memberName != 'all') count++;
    if (paymentMethod != null && paymentMethod != 'all') count++;
    if (direction != null && direction != 'all') count++;
    if (datePreset != 'all_time') count++;
    if (searchQuery.trim().isNotEmpty) count++;
    return count;
  }

  void reset() {
    ledgerName = null;
    concernId = null;
    segmentName = null;
    memberName = null;
    paymentMethod = null;
    direction = null;
    datePreset = 'all_time';
    customRange = null;
    searchQuery = '';
  }

  SuiteFilterState copy() {
    return SuiteFilterState(
      ledgerName: ledgerName,
      concernId: concernId,
      segmentName: segmentName,
      memberName: memberName,
      paymentMethod: paymentMethod,
      direction: direction,
      datePreset: datePreset,
      customRange: customRange,
      searchQuery: searchQuery,
    );
  }
}

class SuiteAdvanceFilterModal extends StatefulWidget {
  final SuiteFilterState initialFilter;
  final List<Map<String, dynamic>> concerns;
  final List<String> ledgers;
  final List<Map<String, dynamic>> rawTransactions;
  final List<String> members;
  final Function(SuiteFilterState) onApply;

  const SuiteAdvanceFilterModal({
    super.key,
    required this.initialFilter,
    required this.concerns,
    required this.ledgers,
    required this.rawTransactions,
    required this.members,
    required this.onApply,
  });

  @override
  State<SuiteAdvanceFilterModal> createState() => _SuiteAdvanceFilterModalState();
}

class _SuiteAdvanceFilterModalState extends State<SuiteAdvanceFilterModal> {
  late SuiteFilterState _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialFilter.copy();
  }

  List<String> _getAvailableSegments() {
    var txs = widget.rawTransactions;

    if (_current.concernId != null && _current.concernId != 'all') {
      txs = txs.where((t) {
        final compId = (t['companyId'] ?? t['company']?['id'] ?? t['wallet']?['companyId'] ?? '').toString();
        return compId == _current.concernId;
      }).toList();
    }

    if (_current.ledgerName != null && _current.ledgerName != 'all') {
      txs = txs.where((t) {
        final lName = (t['ledgerName'] ?? t['ledger']?['name'] ?? '').toString().trim();
        return lName == _current.ledgerName;
      }).toList();
    }

    return txs
        .map((t) => (t['segmentName'] ?? t['segment']?['name'] ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }

  List<String> get availableSegments => _getAvailableSegments();

  @override
  Widget build(BuildContext context) {
    const navyColor = Color(0xFF0F172A);
    const slateBlue = Color(0xFF1E293B);

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, color: navyColor, size: 22),
                    const SizedBox(width: 8),
                    const Text('Advance Filters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: navyColor)),
                    if (_current.activeFilterCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: navyColor, borderRadius: BorderRadius.circular(12)),
                        child: Text('${_current.activeFilterCount}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                TextButton(
                  onPressed: () => setState(() => _current.reset()),
                  child: const Text('Reset All', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                _buildSectionHeader('Duration & Date Range'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildChip('All Time', _current.datePreset == 'all_time', () => setState(() => _current.datePreset = 'all_time')),
                    _buildChip('Today', _current.datePreset == 'today', () => setState(() => _current.datePreset = 'today')),
                    _buildChip('Yesterday', _current.datePreset == 'yesterday', () => setState(() => _current.datePreset = 'yesterday')),
                    _buildChip('This Week', _current.datePreset == 'this_week', () => setState(() => _current.datePreset = 'this_week')),
                    _buildChip('This Month', _current.datePreset == 'this_month', () => setState(() => _current.datePreset = 'this_month')),
                  ],
                ),
                const SizedBox(height: 20),
                _buildSectionHeader('Transaction Flow (Direction)'),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildChip('All', _current.direction == null || _current.direction == 'all', () => setState(() => _current.direction = 'all')),
                    _buildChip('↓ Inflow (+)', _current.direction == 'in', () => setState(() => _current.direction = 'in'), activeColor: const Color(0xFF059669)),
                    _buildChip('↑ Outflow (-)', _current.direction == 'out', () => setState(() => _current.direction = 'out'), activeColor: const Color(0xFFDC2626)),
                  ],
                ),
                const SizedBox(height: 20),
                if (widget.concerns.isNotEmpty) ...[
                  _buildSectionHeader('Business Concern'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChip('All Concerns', _current.concernId == null || _current.concernId == 'all', () {
                        setState(() {
                          _current.concernId = 'all';
                          final validSegments = _getAvailableSegments();
                          if (_current.segmentName != null && !validSegments.contains(_current.segmentName)) {
                            _current.segmentName = null;
                          }
                        });
                      }),
                      ...widget.concerns.map((c) {
                        final id = c['id']?.toString() ?? '';
                        final name = c['name']?.toString() ?? 'Concern';
                        return _buildChip(name, _current.concernId == id, () {
                          setState(() {
                            _current.concernId = id;
                            final validSegments = _getAvailableSegments();
                            if (_current.segmentName != null && !validSegments.contains(_current.segmentName)) {
                              _current.segmentName = null;
                            }
                          });
                        });
                      }),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],

                if (widget.ledgers.isNotEmpty) ...[
                  _buildSectionHeader('Ledger'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChip('All Ledgers', _current.ledgerName == null || _current.ledgerName == 'all', () {
                        setState(() {
                          _current.ledgerName = 'all';
                          final validSegments = _getAvailableSegments();
                          if (_current.segmentName != null && !validSegments.contains(_current.segmentName)) {
                            _current.segmentName = null;
                          }
                        });
                      }),
                      ...widget.ledgers.map((lName) => _buildChip(
                            lName,
                            _current.ledgerName == lName,
                            () {
                              setState(() {
                                _current.ledgerName = (_current.ledgerName == lName) ? 'all' : lName;
                                final validSegments = _getAvailableSegments();
                                if (_current.segmentName != null && !validSegments.contains(_current.segmentName)) {
                                  _current.segmentName = null;
                                }
                              });
                            },
                          )),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                if (availableSegments.isNotEmpty || (_current.segmentName != null && _current.segmentName != 'all')) ...[
                  _buildSectionHeader('Segment'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChip('All Segments', _current.segmentName == null || _current.segmentName == 'all', () => setState(() => _current.segmentName = 'all')),
                      ...availableSegments.map((seg) => _buildChip(seg, _current.segmentName == seg, () => setState(() => _current.segmentName = seg))),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                if (widget.members.isNotEmpty) ...[
                  _buildSectionHeader('Recorded By (Team Member)'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChip('All Members', _current.memberName == null || _current.memberName == 'all', () => setState(() => _current.memberName = 'all')),
                      ...widget.members.map((mem) => _buildChip(mem, _current.memberName == mem, () => setState(() => _current.memberName = mem))),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                _buildSectionHeader('Payment Method'),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildChip('All Methods', _current.paymentMethod == null || _current.paymentMethod == 'all', () => setState(() => _current.paymentMethod = 'all')),
                    _buildChip('Cash', _current.paymentMethod == 'CASH', () => setState(() => _current.paymentMethod = 'CASH')),
                    _buildChip('Bank Account', _current.paymentMethod == 'BANK', () => setState(() => _current.paymentMethod = 'BANK')),
                    _buildChip('MFS (bKash/Nagad)', _current.paymentMethod == 'MFS', () => setState(() => _current.paymentMethod = 'MFS')),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: slateBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      widget.onApply(_current);
                      Navigator.pop(context);
                    },
                    child: Text(
                      _current.hasActiveFilters ? 'Apply Filters (${_current.activeFilterCount})' : 'Show All Transactions',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildChip(String label, bool isSelected, VoidCallback onTap, {Color? activeColor}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? (activeColor ?? const Color(0xFF0F172A)) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : const Color(0xFFCBD5E1),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF334155),
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
