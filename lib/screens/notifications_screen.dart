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
  List<dynamic> _items = [];
  String? _processingId;

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
        final pending = data['pendingTransfers'] as List? ?? [];
        final recent = data['recentMovements'] as List? ?? [];
        
        List<dynamic> merged = [];
        for (var p in pending) {
          merged.add({...p, '_notifType': 'pending'});
        }
        for (var r in recent) {
          merged.add({...r, '_notifType': 'recent'});
        }
        
        setState(() {
          _items = merged;
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
    setState(() => _processingId = id);
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
      if (mounted) setState(() => _processingId = null);
    }
  }

  Future<void> _disputeTransfer(String id) async {
    final app = context.read<AppState>();
    setState(() => _processingId = id);
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
      if (mounted) setState(() => _processingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primaryText,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchNotifs,
        child: _loading && _items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? Center(
                    child: Text(
                      _error ?? 'No pending handovers or activity.',
                      style: const TextStyle(color: AppTheme.secondaryText),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _items.length,
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, index) {
                      final it = _items[index];
                      return _NotificationRow(
                        item: it,
                        currentUserId: app.user?.custodianId ?? '',
                        isProcessing: _processingId == it['id'],
                        onAccept: () => _confirmTransfer(it['id']),
                        onReject: () => _disputeTransfer(it['id']),
                      );
                    },
                  ),
      ),
    );
  }
}

class _NotificationRow extends StatefulWidget {
  final dynamic item;
  final String currentUserId;
  final bool isProcessing;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _NotificationRow({
    required this.item,
    required this.currentUserId,
    required this.isProcessing,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<_NotificationRow> createState() => _NotificationRowState();
}

class _NotificationRowState extends State<_NotificationRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.item;
    final isPending = r['_notifType'] == 'pending';
    
    String title = '';
    String metaLine = '';
    String rightTopLabel = '';
    String rightBottomLabel = '';
    
    Color avatarBg = Colors.grey.shade100;
    Color avatarIconColor = Colors.grey;
    IconData avatarIcon = Icons.notifications_active_outlined;
    
    String expandedFullMsg = '';
    String expandedRef = '';
    final note = _parseNote(r);
    final amt = _toDouble(r['amount']);
    
    DateTime? dt = DateTime.tryParse(r['createdAt'] ?? r['occurredAt'] ?? '');
    String dateStr = dt != null 
        ? "${dt.toLocal().year}-${dt.toLocal().month.t
