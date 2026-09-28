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

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _pending = [];
  List<dynamic> _recent = [];
  String? _confirmingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchNotifs());
  }

  Future<void> _fetchNotifs() async {
    final app = context.read<AppState>();
    if (app.user == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final url = Uri.parse('${app.apiBaseUrl}/custody/notifications?custodianId=${app.user!.custodianId}&companyId=${app.user!.companyId}');
      final res = await app.authRequest('GET', url, headers: {'Authorization': 'Bearer ${app.token}'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _pending = data['pendingTransfers'] ?? [];
          _recent = data['recentMovements'] ?? [];
        });
        app.refreshBalance();
      } else {
        throw Exception();
      }
    } catch (e) {
      setState(() => _error = 'Failed to load notifications');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _confirmTransfer(String id) async {
    final app = context.read<AppState>();
    setState(() => _confirmingId = id);
    try {
      final url = Uri.parse('${app.apiBaseUrl}/custody/transfers/$id/confirm');
      final res = await app.authRequest('POST',
        url,
        headers: {'Authorization': 'Bearer ${app.token}', 'x-company-id': app.user!.companyId},
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Handover accepted & balance credited!')));
        }
        _fetchNotifs();
      } else {
        throw Exception();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error accepting handover')));
      }
    } finally {
      setState(() => _confirmingId = null);
    }
  }

  Future<void> _disputeTransfer(String id) async {
    final app = context.read<AppState>();
    setState(() => _confirmingId = id);
    try {
      final url = Uri.parse('${app.apiBaseUrl}/custody/transfers/$id/dispute');
      final res = await app.authRequest('POST',
        url,
        headers: {'Authorization': 'Bearer ${app.token}', 'x-company-id': app.user!.companyId},
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Handover rejected.')));
        }
        _fetchNotifs();
      } else {
        throw Exception();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error rejecting handover')));
      }
    } finally {
      setState(() => _confirmingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _pending.isEmpty && _recent.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: RefreshIndicator(
        onRefresh: _fetchNotifs,
        child: _pending.isEmpty && _recent.isEmpty
          ? const Center(child: Text('No pending handovers or activity.'))
          : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null) Text(_error!, style: const TextStyle(color: AppTheme.expenseText)),
              if (_pending.isNotEmpty) ...[
                const Text('Pending Handovers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ..._pending.map((t) => _buildTransferCard(t)),
                const SizedBox(height: 20),
              ],
              const Text('Recent Activity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (_recent.isEmpty) const Text('No recent activity.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              ..._recent.map((r) => _buildMovement(r)),
            ],
          ),
      ),
    );
  }

  Widget _buildTransferCard(dynamic t) {
    final toId = t['toCustodian']?['id'] ?? t['toCustodianId'] ?? t['to_custodian_id'];
    final isMine = context.read<AppState>().user!.custodianId == toId;
    final fromName = t['fromCustodian']?['name'] ?? 'Unknown Custodian';
    final amt = _toDouble(t['amount']);
    final fee = _toDouble(t['fee'] ?? t['metadata']?['fee']);
    final note = _parseNote(t);
    final channel = (t['channel'] ?? t['metadata']?['channel'] ?? '').toString().toUpperCase();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.pendingBorder),
      ),
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
                    color: AppTheme.pendingBg,
                    border: Border.all(color: AppTheme.pendingBorder),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'HANDOVER REQUESTED',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.pendingAccent),
                  ),
                ),
                Text('৳${amt.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppTheme.pendingAccent)),
              ],
            ),
            const SizedBox(height: 8),
            Text('From: $fromName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            if (channel.isNotEmpty)
              Text('Channel: $channel', style: const TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
            if (fee > 0)
              Text('Fee: ৳${fee.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.expenseText, fontSize: 11, fontStyle: FontStyle.italic)),
            if (note != null && note.toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppTheme.inputBg, borderRadius: BorderRadius.circular(6)),
                child: Text('Note: ${note.toString()}', style: const TextStyle(fontSize: 12, color: AppTheme.primaryText)),
              ),
            ],
            const SizedBox(height: 12),
            if (isMine)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.expenseText,
                        side: const BorderSide(color: AppTheme.expenseBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _confirmingId == t['id'] ? null : () => _disputeTransfer(t['id']),
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.confirmedBg,
                        foregroundColor: AppTheme.confirmedText,
                        side: const BorderSide(color: AppTheme.confirmedBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _confirmingId == t['id'] ? null : () => _confirmTransfer(t['id']),
                      icon: _confirmingId == t['id']
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check_circle_outline, size: 16),
                      label: Text(_confirmingId == t['id'] ? 'Processing...' : 'Accept'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovement(dynamic r) {
    final tag = (r['entryTag'] ?? '').toString().toLowerCase();
    final dirTab = (r['metadata']?['directionTab'] ?? '').toString().toLowerCase();
    final movementType = (r['metadata']?['movementType'] ?? '').toString().toLowerCase();
    final category = r['metadata']?['category'] ?? r['category'];
    final categoryStr = (category ?? '').toString();
    final note = _parseNote(r);
    final channel = (r['channel'] ?? r['metadata']?['channel'] ?? '').toString().toUpperCase();
    final dir = (r['direction'] ?? '').toString().toLowerCase();
    final amt = _toDouble(r['amount']);
    final fee = _toDouble(r['fee'] ?? r['metadata']?['fee']);
    
    DateTime? dt = DateTime.tryParse(r['createdAt'] ?? r['occurredAt'] ?? '');
    String dateStr = dt != null 
        ? "${dt.toLocal().year}-${dt.toLocal().month.toString().padLeft(2,'0')}-${dt.toLocal().day.toString().padLeft(2,'0')} ${dt.toLocal().hour.toString().padLeft(2,'0')}:${dt.toLocal().minute.toString().padLeft(2,'0')}"
        : r['createdAt'] ?? '';

    final tagLabel = _formatTag(tag);
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

    final displayTitle = categoryStr.isNotEmpty ? categoryStr : tagLabel;
    String subTag = categoryStr.isNotEmpty ? tagLabel : '';
    if (isCashOut && subTag.toLowerCase() == 'business expense') {
      subTag = '';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
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
                Text(
                  '${isCashIn ? '+' : '-'}৳${amt.toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: amtColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryText)),
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
                  Text('Fee: ৳${fee.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.expenseText, fontSize: 11, fontStyle: FontStyle.italic)),
              ],
            ),
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
}
