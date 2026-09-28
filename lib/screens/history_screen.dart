import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:task_boss/theme.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/utils/show_receipt_modal.dart';

double _toDouble(dynamic val) {
  if (val == null) return 0.0;
  if (val is num) return val.toDouble();
  if (val is String) return double.tryParse(val) ?? 0.0;
  return 0.0;
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryState();
}

class _HistoryState extends State<HistoryScreen> {
  bool _loading = true;
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  String _formatTag(String? tag) {
    if (tag == null || tag.isEmpty) return 'Movement';
    const map = {
      'client_payment': 'Client Payment',
      'loan_received': 'Loan Received',
      'other_income': 'Other Income',
      'business_expense': 'Business Expense',
      'personal_partner': 'Personal / Partner',
      'loan_given': 'Loan Given',
      'loan_repayment': 'Loan Repayment',
      'partner_funding': 'Partner Funding',
      'partner_reimbursement': 'Partner Reimbursement',
      'cash_in': 'Cash In',
      'cash_out': 'Cash Out',
      'handover_out': 'Handover Sent',
      'handover_in': 'Handover Received',
    };
    return map[tag] ?? tag.replaceAll('_', ' ').toUpperCase();
  }

  String? _parseNote(dynamic item) {
    if (item == null) return null;
    dynamic raw = item['notes'] ??
        item['note'] ??
        item['description'] ??
        item['metadata']?['note'] ??
        item['metadata']?['notes'];
    if (raw == null) return null;
    final str = raw.toString().trim();
    if (str.isEmpty) return null;

    if (str.startsWith('{') && str.endsWith('}')) {
      try {
        final decoded = jsonDecode(str);
        if (decoded is Map) {
          final inner =
              decoded['note'] ?? decoded['notes'] ?? decoded['description'];
          if (inner != null && inner.toString().trim().isNotEmpty) {
            return inner.toString().trim();
          }
          return null;
        }
      } catch (_) {}
    }
    return str;
  }

  Future<void> _fetch() async {
    final app = context.read<AppState>();
    if (app.user == null) return;
    setState(() => _loading = true);
    try {
      final cId = app.user!.custodianId;
      final cmp = app.user!.companyId;

      final mUri = Uri.parse(
          '${app.apiBaseUrl}/ledger/custodians/$cId/movements?companyId=$cmp');
      final tUri = Uri.parse(
          '${app.apiBaseUrl}/custody/transfers?custodianId=$cId&companyId=$cmp');

      final results = await Future.wait([
        app.authRequest('GET', mUri).catchError((_) => http.Response('{}', 500)),
        app.authRequest('GET', tUri).catchError((_) => http.Response('[]', 500)),
      ]);

      final Map<String, dynamic> mergedMap = {};

      if (results[0].statusCode == 200) {
        final mData = jsonDecode(results[0].body);
        final items = mData['items'] as List? ?? [];
        for (var mc in items) {
          mc['uiType'] = 'movement';
          mc['date'] = DateTime.tryParse(
                  mc['occurredAt'] ?? mc['createdAt'] ?? '') ??
              DateTime.now();
          mergedMap[mc['id']] = mc;
        }
      }

      if (results[1].statusCode == 200) {
        final rawTransfers = jsonDecode(results[1].body);
        List tList = [];
        if (rawTransfers is List) {
          tList = rawTransfers;
        } else if (rawTransfers is Map && rawTransfers['transfers'] is List) {
          tList = rawTransfers['transfers'];
        }
        for (var tc in tList) {
          final status = (tc['status'] ?? '').toString().toLowerCase();
          if (status == 'confirmed') continue;
          tc['uiType'] = 'transfer';
          tc['date'] = DateTime.tryParse(
                  tc['requestedAt'] ?? tc['createdAt'] ?? '') ??
              DateTime.now();
          tc['isOut'] =
              tc['fromCustodianId'] == cId || tc['from_custodian_id'] == cId;
          mergedMap[tc['id']] = tc;
        }
      }

      final sorted = mergedMap.values.toList()
        ..sort((a, b) => b['date'].compareTo(a['date']));
      if (mounted) {
        setState(() {
          _items = sorted;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Transaction History'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primaryText,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: _loading && _items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? const Center(
                    child: Text(
                      'No transaction history found.',
                      style: TextStyle(color: AppTheme.secondaryText),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _items.length,
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, index) {
                      final it = _items[index];
                      return _HistoryTransactionRow(
                        item: it,
                        formatTag: _formatTag,
                        parseNote: _parseNote,
                      );
                    },
                  ),
      ),
    );
  }
}

class _HistoryTransactionRow extends StatefulWidget {
  final dynamic item;
  final String Function(String?) formatTag;
  final String? Function(dynamic) parseNote;

  const _HistoryTransactionRow({
    required this.item,
    required this.formatTag,
    required this.parseNote,
  });

  @override
  State<_HistoryTransactionRow> createState() => _HistoryTransactionRowState();
}

class _HistoryTransactionRowState extends State<_HistoryTransactionRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final isTransfer = it['uiType'] == 'transfer';
    final amt = _toDouble(it['amount']);
    final fee = _toDouble(it['fee'] ?? it['metadata']?['fee']);
    final date = (it['date'] as DateTime).toLocal();
    final dateStr =
        "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";

    final note = widget.parseNote(it);

    bool isOutflow = false;
    bool isHandover = false;
    String title = '';
    String sourceBank = '';
    String paymentMethod = '';
    String fullRef = '';
    String categoryOrRecipient = '';
    String receiptType = '';

    if (isTransfer) {
      isHandover = true;
      isOutflow = it['isOut'] == true;
      final cp = isOutflow
          ? (it['toCustodian'] ?? it['to_custodian'])
          : (it['fromCustodian'] ?? it['from_custodian']);
      final cpName = cp?['name'] ?? 'Custodian Account';

      title = isOutflow ? 'Handover: $cpName' : 'Handover: $cpName';
      categoryOrRecipient = cpName;
      receiptType = isOutflow ? 'Handover Sent' : 'Handover Received';

      sourceBank =
          it['walletName'] ?? it['metadata']?['walletName'] ?? 'Main Wallet';
      paymentMethod = (it['channel'] ?? it['metadata']?['channel'] ?? 'TRANSFER')
          .toString()
          .toUpperCase();

      fullRef = it['receiptNo'] ??
          'HND-${(it['id'] ?? '').toString().length >= 8 ? (it['id'] ?? '').toString().substring(0, 8).toUpperCase() : (it['id'] ?? '')}';
    } else {
      final dir = (it['direction'] ?? '').toString().toLowerCase();
      final tag = (it['entryTag'] ?? '').toString().toLowerCase();
      isOutflow = dir == 'out';
      isHandover = tag == 'handover_out' || tag == 'handover_in';

      final meta = it['metadata'] is Map ? it['metadata'] : {};
      final category = meta['category'] ?? it['category'] ?? meta['rawTag'];
      final tagLabel = widget.formatTag(tag);

      final senderName = meta['senderName'] ?? '';
      final recipientName = meta['recipientName'] ?? '';

      if (tag == 'handover_out') {
        title = recipientName.isNotEmpty
            ? 'Handover: $recipientName'
            : 'Handover Sent';
        categoryOrRecipient = recipientName.isNotEmpty ? recipientName : 'Handover';
      } else if (tag == 'handover_in') {
        title = senderName.isNotEmpty
            ? 'Handover: $senderName'
            : 'Handover Received';
        categoryOrRecipient = senderName.isNotEmpty ? senderName : 'Handover';
      } else {
        title = (category != null && category.toString().trim().isNotEmpty)
            ? category.toString().trim()
            : tagLabel;
        categoryOrRecipient = (category != null && category.toString().trim().isNotEmpty)
            ? category.toString().trim()
            : (senderName.isNotEmpty
                ? senderName
                : (recipientName.isNotEmpty ? recipientName : tagLabel));
      }

      sourceBank = meta['walletName'] ?? it['walletName'] ?? 'Main Wallet';
      paymentMethod = (meta['paymentMethod'] ??
              it['paymentMethod'] ??
              it['channel'] ??
              'CASH')
          .toString()
          .toUpperCase();

      fullRef = it['receiptNo'] ??
          meta['voucherNumber'] ??
          'TRX-${(it['id'] ?? '').toString().length >= 8 ? (it['id'] ?? '').toString().substring(0, 8).toUpperCase() : (it['id'] ?? '')}';

      receiptType = isHandover
          ? (isOutflow ? 'Handover Sent' : 'Handover Received')
          : (!isOutflow
              ? 'Cash In'
              : (tagLabel.toLowerCase().contains('expense')
                  ? 'Expense'
                  : 'Cash Out'));
    }

    final Color avatarBg;
    final Color avatarIconColor;
    final IconData avatarIcon;

    if (isHandover) {
      avatarBg = const Color(0xFFEFF6FF);
      avatarIconColor = const Color(0xFF2563EB);
      avatarIcon = Icons.swap_horiz_rounded;
    } else if (isOutflow) {
      avatarBg = const Color(0xFFFEF2F2);
      avatarIconColor = const Color(0xFFDC2626);
      avatarIcon = Icons.arrow_upward_rounded;
    } else {
      avatarBg = const Color(0xFFF0FDF4);
      avatarIconColor = const Color(0xFF16A34A);
      avatarIcon = Icons.arrow_downward_rounded;
    }

    String shortRef = fullRef;
    if (shortRef.startsWith('TRX-') && shortRef.length > 10) {
      shortRef = shortRef.substring(4);
    } else if (shortRef.startsWith('HND-') && shortRef.length > 10) {
      shortRef = shortRef.substring(4);
    }
    if (shortRef.length > 8) {
      shortRef = shortRef.substring(0, 8);
    }

    final metaSubtitle = '$sourceBank • $paymentMethod • $dateStr';

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: avatarBg,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(avatarIcon, color: avatarIconColor, size: 22),
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
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          metaSubtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
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
                        '${isOutflow ? '-' : '+'}৳${amt.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isOutflow
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF16A34A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        fee > 0
                            ? 'Fee: ৳${fee.toStringAsFixed(2)}'
                            : 'Ref: $shortRef',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontStyle:
                              fee > 0 ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Full Ref: ',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryText,
                            ),
                          ),
                          Expanded(
                            child: SelectableText(
                              fullRef,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (fee > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Text(
                              'Fee Charged: ',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryText,
                              ),
                            ),
                            Text(
                              '৳${fee.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (note != null && note.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Text(
                            'Notes: $note',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            side: BorderSide(color: Colors.grey.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () {
                            showReceiptModal(
                              context,
                              receiptNo: fullRef,
                              date: date,
                              type: receiptType,
                              categoryOrRecipient: categoryOrRecipient,
                              wallet: sourceBank,
                              method: paymentMethod,
                              note: note ?? '',
                              amount: amt,
                              fee: fee,
                            );
                          },
                          icon: const Icon(
                            Icons.receipt_long_rounded,
                            size: 18,
                            color: AppTheme.primaryText,
                          ),
                          label: const Text(
                            'View & Download Digital Receipt',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryText,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }
}
