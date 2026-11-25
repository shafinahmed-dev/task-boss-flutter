import 'dart:ui';
import 'dart:convert';
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../services/app_state.dart';
import '../../services/transaction_export_service.dart';
import '../../widgets/transaction_detail_sheet.dart';
import 'suite_transaction_filter_modal.dart';

String formatBdt(num value) {
  final formatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '৳ ',
    decimalDigits: 2,
  );
  return formatter.format(value);
}

// Converts raw ISO timestamp (e.g. 2026-10-24T06:10:19Z) to clean "24 Oct 2026, 06:10 AM/PM"
String _formatPdfDateTime(String? raw) {
  if (raw == null || raw.isEmpty) return '-';
  try {
    final dt = DateTime.parse(raw).toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day.toString().padLeft(2, '0')}${months[dt.month - 1]} ${dt.year}\n${hour.toString().padLeft(2, '0')}:$min$ampm';
  } catch (_) {
    return raw.length > 10 ? raw.substring(0, 10) : raw;
  }
}

// Formats number into South Asian comma-separated BDT: 195000.00 -> "BDT 1,95,000.00"
String _formatPdfCurrency(num? amount, {bool showSign = false, bool isInflow = true}) {
  if (amount == null) return 'BDT 0.00';
  final val = amount.abs().toDouble();
  final fixed = val.toStringAsFixed(2);
  final parts = fixed.split('.');
  String integer = parts[0];
  final decimal = parts[1];

  if (integer.length > 3) {
    final last3 = integer.substring(integer.length - 3);
    String rest = integer.substring(0, integer.length - 3);
    rest = rest.replaceAllMapped(RegExp(r'(\d)(?=(\d{2})+(?!\d))'), (Match m) => '${m[1]},');
    integer = '$rest,$last3';
  }

  final prefix = showSign ? (isInflow ? '+ ' : '- ') : '';
  return '${prefix}BDT $integer.$decimal';
}

void downloadPdfWeb(Uint8List bytes, String fileName) {
  if (kIsWeb) {
    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..style.display = 'none';
    
    html.document.body?.children.add(anchor);
    anchor.click();
    
    html.document.body?.children.remove(anchor);
    html.Url.revokeObjectUrl(url);
  } else {
    debugPrint('PDF download saved: $fileName');
  }
}

class SuiteTransactionsScreen extends StatefulWidget {
  const SuiteTransactionsScreen({super.key});

  @override
  State<SuiteTransactionsScreen> createState() =>
      _SuiteTransactionsScreenState();
}

class _SuiteTransactionsScreenState extends State<SuiteTransactionsScreen> {
  final TextEditingController _searchController = TextEditingController();
  SuiteFilterState _filterState = SuiteFilterState();

  List<Map<String, dynamic>> get _availableConcerns {
    final app = context.read<AppState>();
    final map = <String, String>{};
    for (final t in app.suiteTransactions) {
      final id = t['companyId']?.toString() ?? t['concernId']?.toString();
      final name = t['companyCode']?.toString() ?? t['companyName']?.toString() ?? t['concernName']?.toString();
      if (id != null && id.isNotEmpty && name != null && name.isNotEmpty) {
        map[id] = name;
      }
    }
    return map.entries.map((e) => {'id': e.key, 'name': e.value}).toList();
  }

  List<String> get _availableSegments {
    final app = context.read<AppState>();
    final set = <String>{};
    for (final t in app.suiteTransactions) {
      final seg = t['segmentName']?.toString();
      if (seg != null && seg.isNotEmpty) set.add(seg);
    }
    return set.toList()..sort();
  }

  List<String> get _availableMembers {
    final app = context.read<AppState>();
    final set = <String>{};
    for (final t in app.suiteTransactions) {
      final mem = t['userName']?.toString();
      if (mem != null && mem.isNotEmpty) set.add(mem);
    }
    return set.toList()..sort();
  }

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
    await context.read<AppState>().fetchSuiteTransactions();
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

  Future<void> _exportPdf(
      List<Map<String, dynamic>> items, double inflow, double outflow) async {
    try {
      String periodStr = 'All Time';
      if (_filterState.datePreset == 'today') periodStr = 'Today';
      else if (_filterState.datePreset == 'yesterday') periodStr = 'Yesterday';
      else if (_filterState.datePreset == 'this_week') periodStr = 'This Week';
      else if (_filterState.datePreset == 'this_month') periodStr = 'This Month';
      else if (_filterState.datePreset == 'custom' && _filterState.customRange != null) {
        periodStr = '${DateFormat('dd MMM yyyy').format(_filterState.customRange!.start)} - ${DateFormat('dd MMM yyyy').format(_filterState.customRange!.end)}';
      }
      if (_filterState.direction != null && _filterState.direction != 'all') {
        periodStr += ' (${_filterState.direction == 'in' ? 'Inflow' : 'Outflow'})';
      }
      if (_filterState.concernId != null && _filterState.concernId != 'all') {
        final c = _availableConcerns.firstWhere((x) => x['id'] == _filterState.concernId, orElse: () => {'name': ''});
        if (c['name'] != null && (c['name'] as String).isNotEmpty) {
          periodStr += ' [Concern: ${c['name']}]';
        }
      }
      if (_filterState.ledgerName != null && _filterState.ledgerName != 'all') {
        periodStr += ' [Ledger: ${_filterState.ledgerName}]';
      }
      final net = inflow - outflow;
      final pdf = pw.Document();

      final tableRows = items.asMap().entries.map((entry) {
        final index = entry.key;
        final tx = entry.value;
        final dateStr = _formatPdfDateTime(tx['createdAt']?.toString() ?? tx['date']?.toString());
        final title = tx['ledgerName']?.toString() ?? tx['title']?.toString() ?? 'Transaction';
        final actor = tx['userName']?.toString() ?? '';
        final concern = tx['segmentName']?.toString() ?? '';
        final note = tx['description']?.toString() ?? tx['notes']?.toString() ?? '';
        final isIn = tx['direction']?.toString() == 'in';
        final amt = (tx['amount'] as num? ?? 0.0).abs().toDouble();

        return pw.TableRow(
          decoration: pw.BoxDecoration(color: index % 2 == 1 ? const PdfColor.fromInt(0xFFF8FAFC) : PdfColors.white),
          children: [
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: pw.Text(dateStr, style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF475569)))),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(title, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F172A))),
              if (note.isNotEmpty) pw.Text(note, style: const pw.TextStyle(fontSize: 7.5, color: PdfColor.fromInt(0xFF64748B))),
            ])),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: pw.Text([if(actor.isNotEmpty) actor, if(concern.isNotEmpty) '[$concern]'].join(' '), style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF334155)))),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(isIn ? _formatPdfCurrency(amt, showSign: true, isInflow: true) : '-', style: pw.TextStyle(fontSize: 8.5, fontWeight: isIn ? pw.FontWeight.bold : pw.FontWeight.normal, color: isIn ? const PdfColor.fromInt(0xFF059669) : const PdfColor.fromInt(0xFF94A3B8))))),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text(!isIn ? _formatPdfCurrency(amt, showSign: true, isInflow: false) : '-', style: pw.TextStyle(fontSize: 8.5, fontWeight: !isIn ? pw.FontWeight.bold : pw.FontWeight.normal, color: !isIn ? const PdfColor.fromInt(0xFFDC2626) : const PdfColor.fromInt(0xFF94A3B8))))),
          ],
        );
      }).toList();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (pw.Context ctx) => [
            // Corporate Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('TASK GROUP', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F172A))),
                    pw.SizedBox(height: 2),
                    pw.Text('Executive Financial Statement', style: const pw.TextStyle(fontSize: 11, color: PdfColor.fromInt(0xFF64748B))),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Filter: $periodStr', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F172A))),
                    pw.SizedBox(height: 2),
                    pw.Text('Generated: ${_formatPdfDateTime(DateTime.now().toIso8601String()).replaceAll('\n', ' ')}', style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF64748B))),
                    pw.Text('Total Transactions: ${items.length}', style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF64748B))),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Divider(thickness: 1, color: const PdfColor.fromInt(0xFFE2E8F0)),
            pw.SizedBox(height: 12),

            // 3-Card KPI Summary Bar
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: const PdfColor.fromInt(0xFFECFDF5),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      border: pw.Border.all(color: const PdfColor.fromInt(0xFFA7F3D0)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('TOTAL INFLOW', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF059669))),
                        pw.SizedBox(height: 3),
                        pw.Text(_formatPdfCurrency(inflow), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF065F46))),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: const PdfColor.fromInt(0xFFFFF1F2),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      border: pw.Border.all(color: const PdfColor.fromInt(0xFFFECDD3)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('TOTAL OUTFLOW', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFFE11D48))),
                        pw.SizedBox(height: 3),
                        pw.Text(_formatPdfCurrency(outflow), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF9F1239))),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: const PdfColor.fromInt(0xFFF8FAFC),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      border: pw.Border.all(color: const PdfColor.fromInt(0xFFCBD5E1)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('NET POSITION', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF475569))),
                        pw.SizedBox(height: 3),
                        pw.Text(_formatPdfCurrency(net), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F172A))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 18),

            // Structured Itemized Table with FIXED column widths
            pw.Table(
              columnWidths: const {
                0: pw.FixedColumnWidth(85),  // Date
                1: pw.FlexColumnWidth(3.0),  // Transaction Details
                2: pw.FlexColumnWidth(1.5),  // User / Concern
                3: pw.FixedColumnWidth(95),  // Inflow (no wrapping)
                4: pw.FixedColumnWidth(95),  // Outflow (no wrapping)
              },
              border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
              children: [
                // Header Row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0F172A)),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      child: pw.Text('DATE & TIME', style: pw.TextStyle(color: PdfColors.white, fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      child: pw.Text('DESCRIPTION', style: pw.TextStyle(color: PdfColors.white, fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      child: pw.Text('USER / CONCERN', style: pw.TextStyle(color: PdfColors.white, fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text('INFLOW', style: pw.TextStyle(color: PdfColors.white, fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text('OUTFLOW', style: pw.TextStyle(color: PdfColors.white, fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
                ...tableRows,
              ],
            ),
          ],
        ),
      );

      final Uint8List pdfBytes = await pdf.save();
      downloadPdfWeb(pdfBytes, 'TASK_Group_Statement_${DateTime.now().millisecondsSinceEpoch}.pdf');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Statement PDF downloaded successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF Export failed: $e')),
        );
      }
    }
  }

  Widget _buildActiveFilterChipsBar() {
    if (!_filterState.hasActiveFilters) return const SizedBox.shrink();

    final List<Widget> chips = [];

    // Direction chip
    if (_filterState.direction != null && _filterState.direction != 'all') {
      final label = _filterState.direction == 'in' ? 'Inflow Only' : 'Outflow Only';
      chips.add(_buildFilterChip(label, () {
        setState(() => _filterState.direction = 'all');
      }));
    }

    // Concern chip
    if (_filterState.concernId != null && _filterState.concernId != 'all') {
      final concern = _availableConcerns.firstWhere(
        (c) => c['id']?.toString() == _filterState.concernId,
        orElse: () => {'name': _filterState.concernId!},
      );
      chips.add(_buildFilterChip('Concern: ${concern['name'] ?? concern['companyName']}', () {
        setState(() => _filterState.concernId = 'all');
      }));
    }

    // Ledger chip
    if (_filterState.ledgerName != null && _filterState.ledgerName != 'all') {
      chips.add(_buildFilterChip('Ledger: ${_filterState.ledgerName!}', () {
        setState(() => _filterState.ledgerName = 'all');
      }));
    }

    // Segment chip
    if (_filterState.segmentName != null && _filterState.segmentName != 'all') {
      chips.add(_buildFilterChip('Segment: ${_filterState.segmentName}', () {
        setState(() => _filterState.segmentName = 'all');
      }));
    }

    // Member chip
    if (_filterState.memberName != null && _filterState.memberName != 'all') {
      chips.add(_buildFilterChip('Member: ${_filterState.memberName}', () {
        setState(() => _filterState.memberName = 'all');
      }));
    }

    // Payment Method chip
    if (_filterState.paymentMethod != null && _filterState.paymentMethod != 'all') {
      chips.add(_buildFilterChip('Method: ${_filterState.paymentMethod}', () {
        setState(() => _filterState.paymentMethod = 'all');
      }));
    }

    // Date Preset / Custom chip
    if (_filterState.datePreset != 'all_time') {
      String dateLabel = 'Date: All Time';
      if (_filterState.datePreset == 'today') dateLabel = 'Today';
      else if (_filterState.datePreset == 'yesterday') dateLabel = 'Yesterday';
      else if (_filterState.datePreset == 'this_week') dateLabel = 'This Week';
      else if (_filterState.datePreset == 'this_month') dateLabel = 'This Month';
      else if (_filterState.datePreset == 'custom' && _filterState.customRange != null) {
        dateLabel = '${DateFormat('dd MMM').format(_filterState.customRange!.start)} - ${DateFormat('dd MMM yyyy').format(_filterState.customRange!.end)}';
      }
      chips.add(_buildFilterChip(dateLabel, () {
        setState(() {
          _filterState.datePreset = 'all_time';
          _filterState.customRange = null;
        });
      }));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ...chips,
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _filterState.reset();
                  _searchController.clear();
                });
              },
              icon: const Icon(Icons.refresh_rounded, size: 14, color: Color(0xFFEF4444)),
              label: const Text(
                'Reset All',
                style: TextStyle(fontSize: 12, color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onDeleted) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF0F172A), fontWeight: FontWeight.w500)),
        backgroundColor: const Color(0xFFF1F5F9),
        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF64748B)),
        onDeleted: onDeleted,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
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

    final filteredTransactions = rawList.where((t) {
      // 1. Search Query
      final q = _filterState.searchQuery.toLowerCase();
      if (q.isNotEmpty) {
        final l = (t['ledgerName'] ?? t['title'] ?? '').toString().toLowerCase();
        final s = (t['segmentName'] ?? '').toString().toLowerCase();
        final u = (t['userName'] ?? '').toString().toLowerCase();
        final v = (t['voucherNumber'] ?? '').toString().toLowerCase();
        final n = (t['notes'] ?? t['description'] ?? '').toString().toLowerCase();
        final c = (t['companyCode'] ?? t['companyName'] ?? '').toString().toLowerCase();
        final match = l.contains(q) || s.contains(q) || u.contains(q) || v.contains(q) || n.contains(q) || c.contains(q);
        if (!match) return false;
      }

      // 2. Direction
      if (_filterState.direction != null && _filterState.direction != 'all') {
        if (t['direction'] != _filterState.direction) return false;
      }

      // 3. Concern ID
      if (_filterState.concernId != null && _filterState.concernId != 'all') {
        final tConcernId = (t['companyId'] ?? t['concernId']?.toString());
        if (tConcernId != _filterState.concernId) return false;
      }

      // Ledger matching
      if (_filterState.ledgerName != null && _filterState.ledgerName != 'all') {
        final lName = (t['ledgerName'] ?? t['ledger']?['name'] ?? '').toString().trim();
        if (lName != _filterState.ledgerName) return false;
      }

      // 4. Segment
      if (_filterState.segmentName != null && _filterState.segmentName != 'all') {
        final tSeg = (t['segmentName'] ?? '').toString();
        if (tSeg != _filterState.segmentName) return false;
      }

      // 5. Member
      if (_filterState.memberName != null && _filterState.memberName != 'all') {
        final tMem = (t['userName'] ?? '').toString();
        if (tMem != _filterState.memberName) return false;
      }

      // 6. Payment Method
      if (_filterState.paymentMethod != null && _filterState.paymentMethod != 'all') {
        final tMethod = (t['paymentMethod'] ?? t['method'] ?? '').toString().toUpperCase();
        if (!tMethod.contains(_filterState.paymentMethod!.toUpperCase())) return false;
      }

      // 7. Date Preset / Range
      final dateStr = t['createdAt']?.toString() ?? t['date']?.toString();
      if (dateStr != null && dateStr.isNotEmpty) {
        try {
          final dt = DateTime.parse(dateStr);
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);

          if (_filterState.datePreset == 'today') {
            final tDay = DateTime(dt.year, dt.month, dt.day);
            if (tDay != today) return false;
          } else if (_filterState.datePreset == 'yesterday') {
            final yesterday = today.subtract(const Duration(days: 1));
            final tDay = DateTime(dt.year, dt.month, dt.day);
            if (tDay != yesterday) return false;
          } else if (_filterState.datePreset == 'this_week') {
            final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
            if (dt.isBefore(startOfWeek)) return false;
          } else if (_filterState.datePreset == 'this_month') {
            if (dt.year != now.year || dt.month != now.month) return false;
          } else if (_filterState.datePreset == 'custom' && _filterState.customRange != null) {
            final localTx = dt.toLocal();
            final start = DateTime(
              _filterState.customRange!.start.year,
              _filterState.customRange!.start.month,
              _filterState.customRange!.start.day,
              0, 0, 0,
            );
            final end = DateTime(
              _filterState.customRange!.end.year,
              _filterState.customRange!.end.month,
              _filterState.customRange!.end.day,
              23, 59, 59, 999,
            );
            if (localTx.isBefore(start) || localTx.isAfter(end)) return false;
          }
        } catch (_) {}
      }

      return true;
    }).toList();

    final liveInflow = filteredTransactions
        .where((t) => t['direction'] == 'in')
        .fold<double>(
            0.0, (sum, t) => sum + (t['amount'] as num).toDouble());
    final liveOutflow = filteredTransactions
        .where((t) => t['direction'] == 'out')
        .fold<double>(
            0.0, (sum, t) => sum + (t['amount'] as num).toDouble());

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
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  filteredTransactions.length == 1 ? '1 Transaction' : '${filteredTransactions.length} Transactions',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
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
                            setState(() => _filterState.searchQuery = val),
                        decoration: InputDecoration(
                          hintText:
                              'Search transactions by ledger, segment, user, note, or voucher...',
                          hintStyle: const TextStyle(
                              fontSize: 13, color: Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded,
                              size: 20, color: Color(0xFF64748B)),
                          suffixIcon: _filterState.searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded,
                                      size: 18, color: Color(0xFF94A3B8)),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _filterState.searchQuery = '');
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
                    InkWell(
                      onTap: () {
                        final allLedgers = rawList
                            .map((t) => (t['ledgerName'] ?? t['ledger']?['name'] ?? '').toString().trim())
                            .where((l) => l.isNotEmpty)
                            .toSet()
                            .toList();

                        final concerns = app.suiteConcerns.isNotEmpty
                            ? app.suiteConcerns
                            : rawList
                                .where((t) => t['company'] != null || t['companyName'] != null || t['companyId'] != null)
                                .map((t) => {
                                      'id': (t['companyId'] ?? t['company']?['id'] ?? '').toString(),
                                      'name': (t['companyName'] ?? t['company']?['name'] ?? 'Concern').toString(),
                                    })
                                .toSet()
                                .toList();

                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => SuiteAdvanceFilterModal(
                            initialFilter: _filterState,
                            concerns: concerns,
                            ledgers: allLedgers,
                            rawTransactions: rawList,
                            members: _availableMembers,
                            onApply: (newFilter) {
                              setState(() {
                                _filterState = newFilter;
                              });
                            },
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: _filterState.hasActiveFilters ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _filterState.hasActiveFilters ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 18,
                              color: _filterState.hasActiveFilters ? Colors.white : const Color(0xFF0F172A),
                            ),
                            if (_filterState.activeFilterCount > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${_filterState.activeFilterCount}',
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
              ),
              _buildActiveFilterChipsBar(),
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
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                "$ledgerName • $segmentName",
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: Color(0xFF0F172A),
                                                ),
                                              ),
                                            ),
                                            if (hasReceipt) ...[
                                              const SizedBox(width: 6),
                                              const Icon(Icons.receipt_long_rounded, size: 14, color: Color(0xFF64748B)),
                                            ],
                                          ],
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
                            ),
                          );
                          },
                        ),
                      ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildFloatingSummaryDeck(
              inflow: liveInflow,
              outflow: liveOutflow,
              onExport: () {
                String filterSummary = "All Time";
                if (_filterState.datePreset == "today") filterSummary = "Today";
                else if (_filterState.datePreset == "yesterday") filterSummary = "Yesterday";
                else if (_filterState.datePreset == "this_week") filterSummary = "This Week";
                else if (_filterState.datePreset == "this_month") filterSummary = "This Month";
                else if (_filterState.datePreset == "custom" && _filterState.customRange != null) {
                  filterSummary = "${DateFormat("dd MMM").format(_filterState.customRange!.start)} - ${DateFormat("dd MMM yyyy").format(_filterState.customRange!.end)}";
                }
                TransactionExportService.showExportOptionsSheet(
                  context: context,
                  transactions: filteredTransactions,
                  title: "Suite Transactions Statement",
                  filterSummary: filterSummary,
                  onExportPdf: () => _exportPdf(filteredTransactions, liveInflow, liveOutflow),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingSummaryDeck({
    required double inflow,
    required double outflow,
    required VoidCallback onExport,
  }) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF0F172A).withValues(alpha: 0.88),
                    const Color(0xFF020617).withValues(alpha: 0.92),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1.0,
                ),
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
                        '+৳ ${formatBdt(inflow)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onExport,
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
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
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
                        '-৳ ${formatBdt(outflow)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: Color(0xFFF43F5E),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
