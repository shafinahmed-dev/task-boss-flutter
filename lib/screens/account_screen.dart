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


class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _loading = true;
  double _inf = 0, _outf = 0, _exp = 0;
  List<dynamic> _inflowItems = [];
  List<dynamic> _outflowItems = [];
  List<dynamic> _expenseItems = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final app = context.read<AppState>();
    if (app.user == null) return;
    setState(() => _loading = true);
    try {
      final cId = app.user!.custodianId;
      final cmp = app.user!.companyId;
      final headers = {
        'Authorization': 'Bearer ${app.token}',
        'x-company-id': cmp,
      };

      final mUri = Uri.parse('${app.apiBaseUrl}/ledger/custodians/$cId/movements?companyId=$cmp');
      final tUri = Uri.parse('${app.apiBaseUrl}/custody/transfers?custodianId=$cId&companyId=$cmp');

      final results = await Future.wait([
        http.get(mUri, headers: headers).catchError((_) => http.Response('{}', 500)),
        http.get(tUri, headers: headers).catchError((_) => http.Response('[]', 500)),
      ]);

      double i = 0, o = 0, e = 0;
      final List<dynamic> infs = [];
      final List<dynamic> outfs = [];
      final List<dynamic> exps = [];

      // 1. Process Movements
      if (results[0].statusCode == 200) {
        final data = jsonDecode(results[0].body);
        final items = data['items'] as List? ?? [];
        for (var m in items) {
          m['uiType'] = 'movement';
          m['date'] = DateTime.tryParse(m['occurredAt'] ?? m['createdAt'] ?? '') ?? DateTime.now();

          final amt = _toDouble(m['amount']);
          final fee = _toDouble(m['fee'] ?? m['metadata']?['fee']);
          final dir = (m['direction'] ?? '').toString().toLowerCase();
          final tag = (m['entryTag'] ?? '').toString().toLowerCase();
          if (tag == 'internal_transfer') {
            // Internal transfers between sub-ledger wallets do not count toward external Inflows/Outflows
            final fee = _toDouble(m['fee'] ?? m['metadata']?['fee']);
            if (fee > 0 && dir == 'out') {
              e += fee;
            }
            continue;
          }

          // ── Explicit Handover KPI handling ──
          if (tag == 'handover_in') {
            i += amt;
            infs.add(m);
            continue;
          }
          if (tag == 'handover_out') {
            o += amt;
            outfs.add(m);
            if (fee > 0) {
              e += fee;
              exps.add({
                'uiType': 'fee',
                'title': 'Handover Fee',
                'amount': fee,
                'date': m['date'],
                'notes': m['notes'] ?? m['note'] ?? m['metadata']?['note'] ?? m['metadata']?['notes'],
                'channel': m['channel'] ?? m['metadata']?['channel'],
              });
            }
            continue;
          }

          final dirTab = (m['metadata']?['directionTab'] ?? '').toString().toLowerCase();
          final movementType = (m['metadata']?['movementType'] ?? '').toString().toLowerCase();
          final categoryStr = (m['metadata']?['category'] ?? '').toString();

          final bool isExpense = dirTab == 'expense' ||
                                 movementType == 'expense' ||
                                 (tag == 'business_expense' && dirTab != 'out' && movementType != 'cash out');

          final bool isCashOut = (dir == 'out' && !isExpense) ||
                                 dirTab == 'out' ||
                                 movementType == 'cash out' ||
                                 tag == 'outflow';

          final bool isCashIn = dir == 'in' || dirTab == 'in' || movementType == 'cash in';

          if (isCashIn) {
            i += amt;
            infs.add(m);
            if (fee > 0) {
              e += fee;
            }
          } else if (isExpense) {
            e += amt;
            exps.add(m);
            if (fee > 0) {
              e += fee;
            }
          } else if (isCashOut) {
            o += amt;
            outfs.add(m);
            if (fee > 0) {
              e += fee;
              exps.add({
                'uiType': 'fee',
                'title': 'Movement Fee (${categoryStr.isNotEmpty ? categoryStr : (tag.isNotEmpty ? tag : "Cash Out")})',
                'amount': fee,
                'date': m['date'],
                'notes': m['notes'] ?? m['note'] ?? m['metadata']?['note'] ?? m['metadata']?['notes'],
                'channel': m['channel'] ?? m['metadata']?['channel'],
              });
            }
          }
        }
      }

      // 2. Process Transfers
      if (results[1].statusCode == 200) {
        final rawTransfers = jsonDecode(results[1].body);
        List transfers = [];
        if (rawTransfers is List) {
          transfers = rawTransfers;
        } else if (rawTransfers is Map && rawTransfers['transfers'] is List) {
          transfers = rawTransfers['transfers'];
        }
        for (var t in transfers) {
          final status = (t['status'] ?? '').toString().toLowerCase();
          // Confirmed transfers are already tracked via generated MoneyMovement records (handover_out / handover_in)
          if (status == 'confirmed') continue;
          t['uiType'] = 'transfer';
          t['date'] = DateTime.tryParse(t['requestedAt'] ?? t['createdAt'] ?? '') ?? DateTime.now();
        }
      }

      infs.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
      outfs.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
      exps.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));

      if (mounted) {
        setState(() {
          _inf = i;
          _outf = o;
          _exp = e;
          _inflowItems = infs;
          _outflowItems = outfs;
          _expenseItems = exps;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final u = app.user;
    if (u == null) return const SizedBox();

    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: RefreshIndicator(
        onRefresh: () async {
          await app.refreshBalance();
          await _loadData();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHead(u, app.balance),
            const SizedBox(height: 20),
            _buildGrid(),
            const SizedBox(height: 20),
            _buildInfo(u),
            const SizedBox(height: 24),
            Center(
              child: SizedBox(
                width: 280,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.expenseText,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: app.logout,
                  child: const Text('Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHead(u, double bal) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppTheme.primaryGradientStart, AppTheme.primaryGradientEnd]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 35,
            backgroundColor: Colors.white24,
            child: Text(
              u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          Text(u.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
            child: Text(u.email, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24),
          const SizedBox(height: 8),
          const Text('AVAILABLE BALANCE', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Text('৳${bal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => _showDetailsModal('Inflow Transactions', _inflowItems, AppTheme.inflowText),
            borderRadius: BorderRadius.circular(14),
            child: _kpi('INFLOWS', _inf, AppTheme.inflowBg, AppTheme.inflowBorder, AppTheme.inflowText),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: () => _showDetailsModal('Outflow Transactions', _outflowItems, AppTheme.pendingAccent),
            borderRadius: BorderRadius.circular(14),
            child: _kpi('OUTFLOWS', _outf, AppTheme.pendingBg, AppTheme.pendingBorder, AppTheme.pendingAccent),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: () => _showDetailsModal('Expense Transactions', _expenseItems, AppTheme.expenseText),
            borderRadius: BorderRadius.circular(14),
            child: _kpi('EXPENSES', _exp, AppTheme.expenseBg, AppTheme.expenseBorder, AppTheme.expenseText),
          ),
        ),
      ],
    );
  }

  Widget _kpi(String title, double val, Color bg, Color border, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.primaryText, letterSpacing: 0.5)),
              const SizedBox(width: 2),
              Icon(Icons.touch_app_outlined, size: 10, color: text.withValues(alpha: 0.7)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '৳${val.toStringAsFixed(2)}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: text),
          ),
        ],
      ),
    );
  }

  void _showDetailsModal(String title, List<dynamic> items, Color accentColor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: AppTheme.canvas,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 5,
                decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(10)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: accentColor)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? Center(child: Text('No $title found.', style: const TextStyle(color: AppTheme.secondaryText)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          return _buildModalItemCard(items[index]);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalItemCard(dynamic item) {
    final uiType = item['uiType'] ?? '';

    if (uiType == 'fee') {
      final title = item['title'] ?? 'Transaction Fee';
      final amt = _toDouble(item['amount']);
      final dt = item['date'] as DateTime?;
      final dateStr = dt != null 
          ? "${dt.toLocal().year}-${dt.toLocal().month.toString().padLeft(2,'0')}-${dt.toLocal().day.toString().padLeft(2,'0')} ${dt.toLocal().hour.toString().padLeft(2,'0')}:${dt.toLocal().minute.toString().padLeft(2,'0')}"
          : '';
      final note = _parseNote(item);

      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppTheme.cardBorder)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryText))),
                  Text('৳${amt.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.expenseText)),
                ],
              ),
              if (dateStr.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(dateStr, style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
              ],
              if (note != null && note.toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: AppTheme.inputBg, borderRadius: BorderRadius.circular(4)),
                  child: Text('Note: ${note.toString()}', style: const TextStyle(fontSize: 11, color: AppTheme.primaryText)),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (uiType == 'transfer') {
      final isOut = item['isOut'] == true;
      final amt = _toDouble(item['amount']);
      final fee = _toDouble(item['fee'] ?? item['metadata']?['fee']);
      final status = (item['status'] ?? 'pending').toString().toUpperCase();
      final counterparty = isOut ? (item['toCustodian'] ?? item['to_custodian']) : (item['fromCustodian'] ?? item['from_custodian']);
      final cpName = counterparty?['name'] ?? 'Custodian Account';
      final channel = (item['channel'] ?? item['metadata']?['channel'] ?? '').toString().toUpperCase();
      final note = _parseNote(item);
      final dt = item['date'] as DateTime?;
      final dateStr = dt != null 
          ? "${dt.toLocal().year}-${dt.toLocal().month.toString().padLeft(2,'0')}-${dt.toLocal().day.toString().padLeft(2,'0')} ${dt.toLocal().hour.toString().padLeft(2,'0')}:${dt.toLocal().minute.toString().padLeft(2,'0')}"
          : '';

      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppTheme.cardBorder)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      isOut ? 'Handover to: $cpName' : 'Handover from: $cpName',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryText),
                    ),
                  ),
                  Text(
                    '${isOut ? '-' : '+'}৳${amt.toStringAsFixed(2)}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isOut ? AppTheme.expenseText : AppTheme.inflowText),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(dateStr, style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
                  Text(status, style: const TextStyle(color: AppTheme.confirmedText, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
              if (fee > 0) ...[
                const SizedBox(height: 2),
                Text('Fee: ৳${fee.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.expenseText, fontSize: 11, fontStyle: FontStyle.italic)),
              ],
              if (channel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('Channel: $channel', style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
              ],
              if (note != null && note.toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: AppTheme.inputBg, borderRadius: BorderRadius.circular(4)),
                  child: Text('Note: ${note.toString()}', style: const TextStyle(fontSize: 11, color: AppTheme.primaryText)),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return _buildModalMovementCard(item);
  }

  Widget _buildModalMovementCard(dynamic item) {
    final dir = (item['direction'] ?? '').toString().toLowerCase();
    final tag = (item['entryTag'] ?? '').toString().toLowerCase();
    final dirTab = (item['metadata']?['directionTab'] ?? '').toString().toLowerCase();
    final movementType = (item['metadata']?['movementType'] ?? '').toString().toLowerCase();
    final category = item['metadata']?['category'] ?? item['category'];
    final categoryStr = (category ?? '').toString();
    final note = _parseNote(item);
    final amt = _toDouble(item['amount']);
    final fee = _toDouble(item['fee'] ?? item['metadata']?['fee']);
    final channel = (item['channel'] ?? item['metadata']?['channel'] ?? '').toString().toUpperCase();
    final dt = item['date'] as DateTime?;
    final dateStr = dt != null 
        ? "${dt.toLocal().year}-${dt.toLocal().month.toString().padLeft(2,'0')}-${dt.toLocal().day.toString().padLeft(2,'0')} ${dt.toLocal().hour.toString().padLeft(2,'0')}:${dt.toLocal().minute.toString().padLeft(2,'0')}"
        : '';

    final bool isExpense = dirTab == 'expense' ||
                           movementType == 'expense' ||
                           (tag == 'business_expense' && dirTab != 'out' && movementType != 'cash out');

    final bool isCashOut = (dir == 'out' && !isExpense) ||
                           dirTab == 'out' ||
                           movementType == 'cash out' ||
                           tag == 'outflow';

    final bool isCashIn = dir == 'in' || dirTab == 'in' || movementType == 'cash in';

    String badgeLabel = isCashIn ? 'CASH IN' : (isCashOut ? 'CASH OUT' : 'EXPENSE');
    if (channel.isNotEmpty) badgeLabel += ' • $channel';

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

    final tagLabel = _formatTag(tag);
    final displayTitle = categoryStr.isNotEmpty ? categoryStr : tagLabel;
    String subTag = categoryStr.isNotEmpty ? tagLabel : '';
    if (isCashOut && subTag.toLowerCase() == 'business expense') {
      subTag = '';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppTheme.cardBorder)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: badgeBg, border: Border.all(color: badgeBorder), borderRadius: BorderRadius.circular(6)),
                  child: Text(badgeLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeText)),
                ),
                Text(
                  '${isCashIn ? '+' : '-'}৳${amt.toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: amtColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryText)),
            if (subTag.isNotEmpty && subTag.toLowerCase() != displayTitle.toLowerCase()) ...[
              const SizedBox(height: 2),
              Text('Tag: $subTag', style: const TextStyle(fontSize: 11, color: AppTheme.secondaryText)),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(dateStr, style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
                if (fee > 0)
                  Text('Fee: ৳${fee.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.expenseText, fontSize: 11, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
              ],
            ),
            if (channel.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('Channel: $channel', style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
            ],
            if (note != null && note.toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: AppTheme.inputBg, borderRadius: BorderRadius.circular(4)),
                child: Text('Note: ${note.toString()}', style: const TextStyle(fontSize: 11, color: AppTheme.primaryText)),
              ),
            ],
          ],
        ),
      ),
    );
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

  Widget _buildInfo(u) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.cardBg, border: Border.all(color: AppTheme.cardBorder), borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          _r('User Name', u.name), const Divider(),
          _r('Email', u.email), const Divider(),
          _r('User ID', u.userId), const Divider(),
          _r('Custodian ID', u.custodianId),
        ],
      ),
    );
  }

  Widget _r(String l, String v) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l, style: const TextStyle(fontSize: 13, color: AppTheme.secondaryText)),
          Flexible(child: Text(v, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
        ],
      );
}
