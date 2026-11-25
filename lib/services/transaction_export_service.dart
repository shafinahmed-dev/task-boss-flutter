import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;
import 'file_download_helper.dart'
    if (dart.library.html) 'file_download_helper_web.dart';

class TransactionExportService {
  static double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  static String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = (raw is DateTime ? raw : DateTime.parse(raw.toString())).toLocal();
      return DateFormat('yyyy-MM-dd').format(dt);
    } catch (_) {
      final s = raw.toString();
      return s.length >= 10 ? s.substring(0, 10) : s;
    }
  }

  static String _formatTime(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = (raw is DateTime ? raw : DateTime.parse(raw.toString())).toLocal();
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return '';
    }
  }

  static String _cleanFileName(String title, String ext) {
    final sanitized = title
        .replaceAll(RegExp(r'[^ws-]'), '')
        .trim()
        .replaceAll(RegExp(r's+'), '_');
    final dateSuffix = DateFormat('yyyyMMdd').format(DateTime.now());
    return "${sanitized}_$dateSuffix.$ext";
  }
  /// Exports the active [transactions] list to an Excel (.xlsx) file.
  static Future<void> exportToExcel({
    required BuildContext context,
    required List<dynamic> transactions,
    required String title,
    required String filterSummary,
  }) async {
    try {
      final workbook = xls.Workbook();
      final sheet = workbook.worksheets[0];
      sheet.name = 'Transactions';

      // Row 1: Title
      sheet.getRangeByIndex(1, 1).setText(title);
      sheet.getRangeByIndex(1, 1).cellStyle.fontSize = 14;
      sheet.getRangeByIndex(1, 1).cellStyle.bold = true;

      // Row 2: Filter Summary & Generated Time
      final generatedAt = DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.now());
      sheet.getRangeByIndex(2, 1).setText('Filter: $filterSummary  |  Generated: $generatedAt  |  Count: ${transactions.length}');
      sheet.getRangeByIndex(2, 1).cellStyle.fontSize = 10;
      sheet.getRangeByIndex(2, 1).cellStyle.italic = true;

      // Row 4: Headers
      final headers = [
        'Date',
        'Time',
        'Direction',
        'Concern',
        'Ledger',
        'Segment',
        'Amount (BDT)',
        'Payment Method',
        'Recorded By',
        'Note',
        'Receipt Attached',
      ];

      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.getRangeByIndex(4, i + 1);
        cell.setText(headers[i]);
        cell.cellStyle.bold = true;
        cell.cellStyle.backColor = '#0F172A';
        cell.cellStyle.fontColor = '#FFFFFF';
      }

      double totalInflow = 0.0;
      double totalOutflow = 0.0;

      int rowIdx = 5;
      for (final tx in transactions) {
        final rawCreatedAt = tx['createdAt'] ?? tx['date'];
        final dateStr = _formatDate(rawCreatedAt);
        final timeStr = _formatTime(rawCreatedAt);

        final dirRaw = (tx['direction'] ?? '').toString().toLowerCase();
        final typeRaw = (tx['type'] ?? tx['movementType'] ?? '').toString().toLowerCase();
        final isOut = dirRaw == 'out' || typeRaw == 'cash out' || typeRaw == 'expense';
        final direction = isOut ? 'Outflow' : 'Inflow';

        final concern = (tx['companyCode'] ?? tx['companyName'] ?? tx['concernName'] ?? tx['concern'] ?? '').toString();
        final ledger = (tx['ledgerName'] ?? tx['ledger']?['name'] ?? '').toString();
        final segment = (tx['segmentName'] ?? tx['segment']?['name'] ?? tx['segment'] ?? '').toString();
        final amount = _toDouble(tx['amount']).abs();

        if (isOut) {
          totalOutflow += amount;
        } else {
          totalInflow += amount;
        }

        final method = (tx['paymentMethod'] ?? tx['method'] ?? tx['channel'] ?? '').toString();
        final recordedBy = (tx['userName'] ?? tx['actorName'] ?? tx['collector']?['name'] ?? tx['user']?['name'] ?? '').toString();
        final note = (tx['description'] ?? tx['notes'] ?? tx['note'] ?? tx['title'] ?? '').toString();

        final rawReceipt = tx['receiptUrl'] ?? tx['receipt'] ?? tx['receiptImage'];
        final hasReceipt = rawReceipt != null && rawReceipt.toString().isNotEmpty;
        final receiptAttached = hasReceipt ? 'Yes' : 'No';

        sheet.getRangeByIndex(rowIdx, 1).setText(dateStr);
        sheet.getRangeByIndex(rowIdx, 2).setText(timeStr);
        sheet.getRangeByIndex(rowIdx, 3).setText(direction);
        sheet.getRangeByIndex(rowIdx, 4).setText(concern);
        sheet.getRangeByIndex(rowIdx, 5).setText(ledger);
        sheet.getRangeByIndex(rowIdx, 6).setText(segment);
        final amtCell = sheet.getRangeByIndex(rowIdx, 7);
        amtCell.setNumber(amount);
        amtCell.numberFormat = '#,##0.00';
        sheet.getRangeByIndex(rowIdx, 8).setText(method);
        sheet.getRangeByIndex(rowIdx, 9).setText(recordedBy);
        sheet.getRangeByIndex(rowIdx, 10).setText(note);
        sheet.getRangeByIndex(rowIdx, 11).setText(receiptAttached);

        rowIdx++;
      }

      // Summary Footer Rows (2 rows below data)
      final summaryStart = rowIdx + 1;

      sheet.getRangeByIndex(summaryStart, 6).setText('Total Inflow:');
      sheet.getRangeByIndex(summaryStart, 6).cellStyle.bold = true;
      final inflowCell = sheet.getRangeByIndex(summaryStart, 7);
      inflowCell.setNumber(totalInflow);
      inflowCell.numberFormat = '#,##0.00';
      inflowCell.cellStyle.bold = true;

      sheet.getRangeByIndex(summaryStart + 1, 6).setText('Total Outflow:');
      sheet.getRangeByIndex(summaryStart + 1, 6).cellStyle.bold = true;
      final outflowCell = sheet.getRangeByIndex(summaryStart + 1, 7);
      outflowCell.setNumber(totalOutflow);
      outflowCell.numberFormat = '#,##0.00';
      outflowCell.cellStyle.bold = true;

      sheet.getRangeByIndex(summaryStart + 2, 6).setText('Net Balance:');
      sheet.getRangeByIndex(summaryStart + 2, 6).cellStyle.bold = true;
      final netCell = sheet.getRangeByIndex(summaryStart + 2, 7);
      netCell.setNumber(totalInflow - totalOutflow);
      netCell.numberFormat = '#,##0.00';
      netCell.cellStyle.bold = true;

      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final fileName = _cleanFileName(title, 'xlsx');
      await _deliverFile(
        bytes: Uint8List.fromList(bytes),
        fileName: fileName,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        context: context,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel export failed: $e')),
        );
      }
    }
  }
  /// Exports the active [transactions] list to an RFC-4180 CSV (.csv) file.
  static Future<void> exportToCsv({
    required BuildContext context,
    required List<dynamic> transactions,
    required String title,
    required String filterSummary,
  }) async {
    try {
      final buffer = StringBuffer();

      String quoteField(String val) {
        final escaped = val.replaceAll('"', '""');
        if (escaped.contains(',') || escaped.contains('"') || escaped.contains('\n') || escaped.contains('\r')) {


          return '"$escaped"';
        }
        return escaped;
      }

      final headers = [
        'Date',
        'Time',
        'Direction',
        'Concern',
        'Ledger',
        'Segment',
        'Amount',
        'Payment Method',
        'Recorded By',
        'Note',
        'Receipt Attached',
      ];
      buffer.writeln(headers.map(quoteField).join(','));

      for (final tx in transactions) {
        final rawCreatedAt = tx['createdAt'] ?? tx['date'];
        final dateStr = _formatDate(rawCreatedAt);
        final timeStr = _formatTime(rawCreatedAt);

        final dirRaw = (tx['direction'] ?? '').toString().toLowerCase();
        final typeRaw = (tx['type'] ?? tx['movementType'] ?? '').toString().toLowerCase();
        final isOut = dirRaw == 'out' || typeRaw == 'cash out' || typeRaw == 'expense';
        final direction = isOut ? 'Outflow' : 'Inflow';

        final concern = (tx['companyCode'] ?? tx['companyName'] ?? tx['concernName'] ?? tx['concern'] ?? '').toString();
        final ledger = (tx['ledgerName'] ?? tx['ledger']?['name'] ?? '').toString();
        final segment = (tx['segmentName'] ?? tx['segment']?['name'] ?? tx['segment'] ?? '').toString();
        final amount = _toDouble(tx['amount']).abs().toStringAsFixed(2);
        final method = (tx['paymentMethod'] ?? tx['method'] ?? tx['channel'] ?? '').toString();
        final recordedBy = (tx['userName'] ?? tx['actorName'] ?? tx['collector']?['name'] ?? tx['user']?['name'] ?? '').toString();
        final note = (tx['description'] ?? tx['notes'] ?? tx['note'] ?? tx['title'] ?? '').toString();

        final rawReceipt = tx['receiptUrl'] ?? tx['receipt'] ?? tx['receiptImage'];
        final hasReceipt = rawReceipt != null && rawReceipt.toString().isNotEmpty;
        final receiptAttached = hasReceipt ? 'Yes' : 'No';

        final row = [
          dateStr,
          timeStr,
          direction,
          concern,
          ledger,
          segment,
          amount,
          method,
          recordedBy,
          note,
          receiptAttached,
        ];
        buffer.writeln(row.map(quoteField).join(','));
      }

      final csvString = '﻿${buffer.toString()}';
      final bytes = Uint8List.fromList(utf8.encode(csvString));

      final fileName = _cleanFileName(title, 'csv');
      await _deliverFile(
        bytes: bytes,
        fileName: fileName,
        mimeType: 'text/csv;charset=utf-8',
        context: context,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV export failed: $e')),
        );
      }
    }
  }
  /// Cross-platform file delivery helper:
  /// - On Web: browser file download using blob/anchor
  /// - On Mobile/Desktop: writes to temp storage and invokes share_plus share sheet
  static Future<void> _deliverFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required BuildContext context,
  }) async {
    if (kIsWeb) {
      triggerWebDownload(bytes, fileName, mimeType);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$fileName downloaded successfully')),
        );
      }
    } else {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/$fileName';
      final file = XFile.fromData(bytes, name: fileName, mimeType: mimeType);
      await file.saveTo(filePath);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath, mimeType: mimeType, name: fileName)],
          subject: 'Exported transactions statement: $fileName',
        ),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$fileName ready for share/save')),
        );
      }
    }
  }

  /// Sleek modal bottom sheet offering PDF, Excel (.xlsx), and CSV (.csv) exports.
  static void showExportOptionsSheet({
    required BuildContext context,
    required List<dynamic> transactions,
    required String title,
    required String filterSummary,
    required VoidCallback onExportPdf,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Export Transactions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${transactions.length} transactions ($filterSummary)',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                    splashRadius: 20,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildExportOptionTile(
                icon: Icons.picture_as_pdf_rounded,
                iconColor: const Color(0xFFDC2626),
                iconBg: const Color(0xFFFEF2F2),
                title: 'PDF Statement (.pdf)',
                subtitle: 'Formatted executive report with inflow/outflow summary',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onExportPdf();
                },
              ),
              const SizedBox(height: 10),
              _buildExportOptionTile(
                icon: Icons.table_chart_rounded,
                iconColor: const Color(0xFF10B981),
                iconBg: const Color(0xFFECFDF5),
                title: 'Excel Workbook (.xlsx)',
                subtitle: 'Structured spreadsheet with summary totals for accounting',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  exportToExcel(
                    context: context,
                    transactions: transactions,
                    title: title,
                    filterSummary: filterSummary,
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildExportOptionTile(
                icon: Icons.grid_on_rounded,
                iconColor: const Color(0xFF2563EB),
                iconBg: const Color(0xFFEFF6FF),
                title: 'CSV File (.csv)',
                subtitle: 'Universal comma-separated data for Excel & Google Sheets',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  exportToCsv(
                    context: context,
                    transactions: transactions,
                    title: title,
                    filterSummary: filterSummary,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildExportOptionTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
