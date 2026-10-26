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

  Future<void> _exportPdf(
      List<Map<String, dynamic>> items, double inflow, double outflow) async {
    try {
      final labels = {
        'all_time': 'All Time',
        'today': 'Today',
        'this_week': 'This Week',
        'this_month': 'This Month',
      };
      final periodStr = labels[_selectedPeriod] ?? 'All Time';
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
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildFloatingSummaryDeck(
              inflow: liveInflow,
              outflow: liveOutflow,
              onExport: () => _exportPdf(filteredTransactions, liveInflow, liveOutflow),
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
