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
import 'package:task_boss/services/app_state.dart';

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

class LedgerDetailsScreen extends StatefulWidget {
  final String ledgerId;
  final String initialName;

  const LedgerDetailsScreen({
    Key? key,
    required this.ledgerId,
    required this.initialName,
  }) : super(key: key);

  @override
  State<LedgerDetailsScreen> createState() => _LedgerDetailsScreenState();
}

class _LedgerDetailsScreenState extends State<LedgerDetailsScreen> {
  Map<String, dynamic>? _ledger;
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    final app = context.read<AppState>();
    if (app.managers.isEmpty) {
      await app.fetchManagers();
    }
    final data = await app.fetchLedgerDetails(widget.ledgerId);
    if (mounted) {
      setState(() {
        _ledger = data;
        _isLoading = false;
      });
    }
  }

  void _showSegmentTransactionsSheet(BuildContext context, Map<String, dynamic> seg) {
    final name = seg['name']?.toString() ?? 'Segment';
    final inf = double.tryParse(seg['totalInflow']?.toString() ?? '0') ?? 0.0;
    final out = double.tryParse(seg['totalOutflow']?.toString() ?? '0') ?? 0.0;
    final net = double.tryParse(seg['netBalance']?.toString() ?? '0') ?? (inf - out);
    final txns = (seg['transactions'] as List?) ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                        const SizedBox(height: 4),
                        Text('In: +৳${inf.toStringAsFixed(2)}  •  Out: -৳${out.toStringAsFixed(2)}  •  Net: ৳${net.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(ctx).pop()),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Expanded(
              child: txns.isEmpty
                ? const Center(child: Text('No transactions under this segment.', style: TextStyle(color: Color(0xFF64748B))))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: txns.length,
                    itemBuilder: (_, i) {
                      final t = txns[i];
                      final isDirIn = (t['direction']?.toString() ?? '').toLowerCase() == 'in';
                      final amt = double.tryParse(t['amount']?.toString() ?? '0') ?? 0.0;
                      final notes = t['notes']?.toString() ?? '';
                      final voucher = t['voucherNumber']?.toString() ?? '';
                      final collector = t['collectorName']?.toString() ?? 'Staff';
                      final code = t['companyCode']?.toString() ?? '';
                      final dateStr = t['createdAt']?.toString() ?? '';

                      String dtDisplay = dateStr;
                      try {
                        final dt = DateTime.parse(dateStr).toLocal();
                        final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
                        final p = dt.hour >= 12 ? 'PM' : 'AM';
                        dtDisplay = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $h:${dt.minute.toString().padLeft(2, '0')} $p';
                      } catch (_) {}

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                        child: Row(
                          children: [
                            Icon(isDirIn ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, color: isDirIn ? const Color(0xFF10B981) : const Color(0xFFEF4444), size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('$collector${code.isNotEmpty ? ' [$code]' : ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                                      Text('${isDirIn ? '+' : '-'}৳ ${amt.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: isDirIn ? const Color(0xFF10B981) : const Color(0xFFEF4444))),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(dtDisplay, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                                  if (notes.isNotEmpty || voucher.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text([if (voucher.isNotEmpty) 'Voucher: $voucher', if (notes.isNotEmpty) notes].join(' • '), style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }


  void _openEditModal() {
    if (_ledger == null) return;
    final ledger = _ledger!;
    final nameCtrl = TextEditingController(text: ledger['name']?.toString() ?? '');
    final descCtrl = TextEditingController(text: ledger['description']?.toString() ?? '');
    String status = ledger['status']?.toString() ?? 'ACTIVE';
    bool isPerpetual = ledger['isPerpetual'] ?? true;
    final isDefault = ledger['code'] == 'GEN-OPS';
    
    final managersRaw = ledger['managers'] as List? ?? [];
    Set<String> selectedManagerIds = managersRaw.map((m) => m['id'].toString()).toSet();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final app = context.read<AppState>();
            final allManagers = app.managers;

            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                top: 16,
                left: 20,
                right: 20,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit & Manage Ledger',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    const Divider(color: Color(0xFFE2E8F0)),
                    const SizedBox(height: 10),

                    const Text('Ledger Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text('Description', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: status == 'FROZEN' ? 'FROZEN' : 'ACTIVE',
                      items: const [
                        DropdownMenuItem(value: 'ACTIVE', child: Text('ACTIVE (Operational)')),
                        DropdownMenuItem(value: 'FROZEN', child: Text('FROZEN (Read-only lock)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setSheetState(() => status = val);
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                    ),
                    const SizedBox(height: 14),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Perpetual Ledger', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                        Switch(
                          value: isPerpetual,
                          activeThumbColor: const Color(0xFF0F172A),
                          onChanged: (val) => setSheetState(() => isPerpetual = val),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Assigned Managers', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                    const SizedBox(height: 8),
                    if (allManagers.isEmpty)
                      const Text('No managers registered in system.', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))
                    else
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: allManagers.length,
                          itemBuilder: (context, idx) {
                            final m = allManagers[idx];
                            final mId = m['id'].toString();
                            final mName = m['name']?.toString() ?? 'Manager';
                            final isSelected = selectedManagerIds.contains(mId);

                            return Material(
                              color: Colors.transparent,
                              child: CheckboxListTile(
                                value: isSelected,
                                title: Text(mName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                subtitle: Text(m['handle']?.toString() ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                activeColor: const Color(0xFF0F172A),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                onChanged: (val) {
                                  setSheetState(() {
                                    if (val == true) {
                                      selectedManagerIds.add(mId);
                                    } else {
                                      selectedManagerIds.remove(mId);
                                    }
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),

                    const SizedBox(height: 24),
                    Row(
                      children: [
                        if (!isDefault) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: ctx,
                                  builder: (dialogCtx) => AlertDialog(
                                    title: const Text('Delete Ledger'),
                                    content: const Text('Are you sure you want to delete this ledger? If movements exist, it will be archived.'),
                                    actions: [
          Consumer<AppState>(
            builder: (context, app, _) {
              final role = app.user?.role?.toUpperCase() ?? '';
              if (role == 'SUITE_ADMIN' || role == 'SUITE') {
                return IconButton(
                  icon: const Icon(Icons.tune_rounded, color: Color(0xFF0F172A)),
                  onPressed: _openEditModal,
                  tooltip: 'Edit Ledger',
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ]
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E2638)))
          : Stack(
              children: [
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Search segments by name...',
                          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B)),
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                    ),

                    Expanded(
                      child: filteredSegments.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.folder_open_rounded, size: 48, color: Color(0xFF94A3B8)),
                                    SizedBox(height: 12),
                                    Text(
                                      'No segments created by managers yet.',
                                      style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                              itemCount: filteredSegments.length,
                              itemBuilder: (context, index) {
                                final seg = filteredSegments[index];
                                final segName = seg['name']?.toString() ?? 'Unnamed Segment';
                                final txCount = seg['transactionCount'] ?? 0;
                                final inflow = double.tryParse(seg['totalInflow']?.toString() ?? '0') ?? 0.0;
                                final outflow = double.tryParse(seg['totalOutflow']?.toString() ?? '0') ?? 0.0;
                                final net = double.tryParse(seg['netBalance']?.toString() ?? '0') ?? (inflow - outflow);

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.02),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                    child: InkWell(
                                      onTap: () => _showSegmentTransactionsSheet(
                                        context,
                                        Map<String, dynamic>.from(seg as Map),
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    segName,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '$txCount transactions • Net: ৳ ${net.toStringAsFixed(2)}',
                                                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                             _buildSegmentAmountColumn(inflow, outflow),


                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildFloatingSummaryDeck(
                    inflow: filteredInflow,
                    outflow: filteredOutflow,
                    onExport: () => _exportLedgerPdf(filteredSegments, filteredInflow, filteredOutflow),
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

