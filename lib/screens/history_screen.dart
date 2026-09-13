import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:task_boss/theme.dart';
import 'package:task_boss/services/app_state.dart';

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
    if (tag == null || tag.isEmpty) return 'Money Movement';
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
  dynamic raw = item['notes'] ?? item['note'] ?? item['description'] ?? item['metadata']?['note'] ?? item['metadata']?['notes'];
  if (raw == null) return null;
  final str = raw.toString().trim();
  if (str.isEmpty) return null;
  
  if (str.startsWith('{') && str.endsWith('}')) {
    try {
      final decoded = jsonDecode(str);
      if (decoded is Map) {
        final inner = decoded['note'] ?? decoded['notes'] ?? decoded['description'];
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
      final headers = {'Authorization': 'Bearer ${app.token}', 'x-company-id': cmp};

      final mUri = Uri.parse('${app.apiBaseUrl}/ledger/custodians/$cId/movements?companyId=$cmp');
      final tUri = Uri.parse('${app.apiBaseUrl}/custody/transfers?custodianId=$cId&companyId=$cmp');

      final results = await Future.wait([
        http.get(mUri, headers: headers).catchError((_) => http.Response('{}', 500)),
        http.get(tUri, headers: headers).catchError((_) => http.Response('[]', 500)),
      ]);

      final Map<String, dynamic> mergedMap = {};

      if (results[0].statusCode == 200) {
        final mData = jsonDecode(results[0].body);
        final items = mData['items'] as List? ?? [];
        for (var mc in items) {
          mc['uiType'] = 'movement';
          mc['date'] = DateTime.tryParse(mc['occurredAt'] ?? mc['createdAt'] ?? '') ?? DateTime.now();
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
          tc['date'] = DateTime.tryParse(tc['requestedAt'] ?? tc['createdAt'] ?? '') ?? DateTime.now();
          tc['isOut'] = tc['fromCustodianId'] == cId || tc['from_custodian_id'] == cId;
          mergedMap[tc['id']] = tc;
        }
      }

      final sorted = mergedMap.values.toList()..sort((a, b) => b['date'].compareTo(a['date']));
      if (mounted) {
        setState(() { _items = sorted; });
        debugPrint('History Movements Count: ${_items.length}');
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: _loading && _items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? const Center(child: Text('No transaction history found.', style: TextStyle(color: AppTheme.secondaryText)))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    itemBuilder: (c, i) {
                      final it = _items[i];
                      if (it['uiType'] == 'transfer') return _buildTransfer(it);
                      return _buildMovement(it);
                    },
                  ),
      ),
    );
  }

  Widget _buildMovement(dynamic it) {
    final dir = (it['direction'] ?? '').toString().toLowerCase();
    final tag = (it['entryTag'] ?? '').toString().toLowerCase();
    final dirTab = (it['metadata']?['directionTab'] ?? '').toString().toLowerCase();
    final movementType = (it['metadata']?['movementType'] ?? '').toString().toLowerCase();
    final category = it['metadata']?['category'] ?? it['category'] ?? it['metadata']?['rawTag'];
    final categoryStr = (category ?? '').toString();
    final amt = _toDouble(it['amount']);
    final fee = _toDouble(it['fee'] ?? it['metadata']?['fee']);
    final channel = (it['channel'] ?? it['metadata']?['channel'] ?? '').toString().toUpperCase();
    final note = _parseNote(it);
    final date = (it['date'] as DateTime).toLocal();
    final dateStr = "${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')} ${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}";

    final tagLabel = _formatTag(tag);

    final bool isHandoverOut = tag == 'handover_out';
    final meta = it['metadata'] is Map ? it['metadata'] : {};
    final refNo = meta['voucherNumber'] ?? it['receiptNo'] ?? '';
    final senderName = meta['senderName'] ?? '';
    final recipientName = meta['recipientName'] ?? '';
    final paymentMethod = (meta['paymentMethod'] ?? it['paymentMethod'] ?? it['channel'] ?? '').toString().toUpperCase();

    if (isHandoverOut) {
      final title = recipientName.isNotEmpty ? recipientName : 'Handover Sent';
      final badgeText = 'CASH OUT • ${paymentMethod.isNotEmpty ? paymentMethod : "CASH"}';
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppTheme.cardBorder)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                    ),
                  ),
                  if (refNo.isNotEmpty)
                    Text('Ref: $refNo', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.secondaryText)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryText),
                        ),
                        const SizedBox(height: 2),
                        Text(dateStr, style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '-৳${amt.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFB45309)),
                      ),
                      if (fee > 0)
                        Text(
                          'Fee: ৳${fee.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.expenseText, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ],
              ),
              if (note != null && note.toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppTheme.inputBg, borderRadius: BorderRadius.circular(6)),
                  child: Text('Note: ${note.toString()}', style: const TextStyle(fontSize: 12, color: AppTheme.primaryText)),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final bool isHandoverIn = tag == 'handover_in';
    if (isHandoverIn) {
      final title = senderName.isNotEmpty ? senderName : 'Handover Received';
      final badgeText = 'CASH IN • ${paymentMethod.isNotEmpty ? paymentMethod : "CASH"}';
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppTheme.cardBorder)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.inflowBg,
                      border: Border.all(color: AppTheme.inflowBorder),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.inflowText),
                    ),
                  ),
                  if (refNo.isNotEmpty)
                    Text('Ref: $refNo', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.secondaryText)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryText),
                        ),
                        const SizedBox(height: 2),
                        Text(dateStr, style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
                      ],
                    ),
                  ),
                  Text(
                    '+৳${amt.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.inflowText),
                  ),
                ],
              ),
              if (note != null && note.toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppTheme.inputBg, borderRadius: BorderRadius.circular(6)),
                  child: Text('Note: ${note.toString()}', style: const TextStyle(fontSize: 12, color: AppTheme.primaryText)),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final bool isExpense = dirTab == 'expense' ||
                           movementType == 'expense' ||
                           (tag == 'business_expense' && dirTab != 'out' && movementType != 'cash out');

    final bool isCashOut = (dir == 'out' && !isExpense) ||
                           dirTab == 'out' ||
                           movementType == 'cash out' ||
                           tag == 'outflow';

    final bool isCashIn = dir == 'in' || dirTab == 'in' || movementType == 'cash in';

    String badgeLabel = isCashIn ? 'CASH IN' : (isCashOut ? 'CASH OUT' : 'EXPENSE');
    final walletName = (it['wallet']?['name'] ?? it['metadata']?['walletName'] ?? '').toString();
    String railInfo = '';
    if (walletName.isNotEmpty && paymentMethod.isNotEmpty) {
      railInfo = '$walletName • $paymentMethod';
    } else if (walletName.isNotEmpty) {
      railInfo = walletName;
    } else if (paymentMethod.isNotEmpty) {
      railInfo = paymentMethod;
    } else if (channel.isNotEmpty) {
      railInfo = channel;
    }
    if (railInfo.isNotEmpty) badgeLabel += ' • $railInfo';

    Color badgeBg;
    Color badgeBorder;
    Color badgeText;
    Color amtColor;

    if (isCashIn) {
      badgeBg = AppTheme.inflowBg;
      badgeBorder = AppTheme.inflowBorder;
      badgeText = AppTheme.inflowText;
      amtColor = AppTheme.inflowText;
    } else if (isCashOut) {
      badgeBg = const Color(0xFFFEF3C7);
      badgeBorder = const Color(0xFFFDE68A);
      badgeText = const Color(0xFFB45309);
      amtColor = const Color(0xFFB45309);
    } else {
      badgeBg = const Color(0xFFFEE2E2);
      badgeBorder = const Color(0xFFFCA5A5);
      badgeText = const Color(0xFFB91C1C);
      amtColor = const Color(0xFFB91C1C);
    }

    final displayTitle = categoryStr.isNotEmpty ? categoryStr : tagLabel;
    String subTag = categoryStr.isNotEmpty ? tagLabel : '';
    if (isCashOut && subTag.toLowerCase() == 'business expense') {
      subTag = '';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppTheme.cardBorder)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    border: Border.all(color: badgeBorder),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeText),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryText),
                      ),
                      if (subTag.isNotEmpty && subTag.toLowerCase() != displayTitle.toLowerCase()) ...[
                        const SizedBox(height: 2),
                        Text('Tag: $subTag', style: const TextStyle(fontSize: 11, color: AppTheme.secondaryText)),
                      ],
                      const SizedBox(height: 2),
                      Text(dateStr, style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isCashIn ? '+' : '-'}৳${amt.toStringAsFixed(2)}',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: amtColor),
                    ),
                    if (fee > 0)
                      Text(
                        'Fee: ৳${fee.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.expenseText, fontStyle: FontStyle.italic),
                      ),
                  ],
                ),
              ],
            ),
            if (note != null && note.toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppTheme.inputBg, borderRadius: BorderRadius.circular(6)),
                child: Text('Note: ${note.toString()}', style: const TextStyle(fontSize: 12, color: AppTheme.primaryText)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTransfer(dynamic it) {
    final isOut = it['isOut'] == true;
    final amt = _toDouble(it['amount']);
    final fee = _toDouble(it['fee'] ?? it['metadata']?['fee']);
    final status = (it['status'] ?? 'pending').toString().toUpperCase();
    final channel = (it['channel'] ?? it['metadata']?['channel'] ?? '').toString().toUpperCase();
    final counterparty = isOut ? (it['toCustodian'] ?? it['to_custodian']) : (it['fromCustodian'] ?? it['from_custodian']);
    final cpName = counterparty?['name'] ?? 'Custodian Account';
    final cpEmail = counterparty?['linkedUser']?['email'] ?? counterparty?['email'] ?? '';
    final note = _parseNote(it);
    final date = (it['date'] as DateTime).toLocal();
    final dateStr = "${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')} ${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}";

    final isConfirmed = status == 'CONFIRMED';
    final isPending = status == 'PENDING';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppTheme.cardBorder)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isOut ? AppTheme.pendingBg : AppTheme.inflowBg,
                    border: Border.all(color: isOut ? AppTheme.pendingBorder : AppTheme.inflowBorder),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${channel.isNotEmpty ? channel : "CASH"} • Ref: ${it['receiptNo'] ?? ''}'.toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isOut ? AppTheme.pendingAccent : AppTheme.inflowText),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isConfirmed ? AppTheme.confirmedBg : isPending ? AppTheme.pendingBg : AppTheme.expenseBg,
                    border: Border.all(color: isConfirmed ? AppTheme.confirmedBorder : isPending ? AppTheme.pendingBorder : AppTheme.expenseBorder),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isConfirmed ? AppTheme.confirmedText : isPending ? AppTheme.pendingAccent : AppTheme.expenseText),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOut ? 'Handover Sent' : 'Handover Received',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryText),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isOut ? 'To: $cpName' : 'From: $cpName',
                        style: const TextStyle(color: AppTheme.secondaryText, fontSize: 12),
                      ),
                      if (cpEmail.isNotEmpty)
                        Text(cpEmail, style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
                      Text(dateStr, style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isOut ? '-' : '+'}৳${amt.toStringAsFixed(2)}',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isOut ? AppTheme.expenseText : AppTheme.inflowText),
                    ),
                    if (fee > 0)
                      Text(
                        'Fee: ৳${fee.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.expenseText, fontStyle: FontStyle.italic),
                      ),
                  ],
                ),
              ],
            ),
            if (note != null && note.toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppTheme.inputBg, borderRadius: BorderRadius.circular(6)),
                child: Text('Note: ${note.toString()}', style: const TextStyle(fontSize: 12, color: AppTheme.primaryText)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
