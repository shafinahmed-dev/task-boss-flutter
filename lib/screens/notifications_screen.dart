import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
    String dateStr = '';
    if (dt != null) {
      final localDt = dt.toLocal();
      dateStr = "${localDt.year}-${localDt.month.toString().padLeft(2, '0')}-${localDt.day.toString().padLeft(2, '0')} ${localDt.hour.toString().padLeft(2, '0')}:${localDt.minute.toString().padLeft(2, '0')}";
    } else {
      dateStr = r['createdAt'] ?? '';
    }

    bool isMyActionRequired = false;

    if (isPending) {
      final toId = r['toCustodian']?['id'] ?? r['toCustodianId'] ?? r['to_custodian_id'];
      isMyActionRequired = widget.currentUserId == toId;
      final fromName = r['fromCustodian']?['name'] ?? 'Unknown User';
      final channel = (r['channel'] ?? r['metadata']?['channel'] ?? 'TRANSFER').toString().toUpperCase();
      
      title = isMyActionRequired ? 'Handover Requested' : 'Handover Sent (Pending)';
      metaLine = 'From: $fromName • $dateStr';
      if (!isMyActionRequired) {
        metaLine = 'To: ${r['toCustodian']?['name'] ?? 'Counterparty'} • $dateStr';
      }
      
      avatarBg = const Color(0xFFEFF6FF);
      avatarIconColor = const Color(0xFF2563EB);
      avatarIcon = Icons.swap_horiz_rounded;
      
      rightTopLabel = '৳${amt.toStringAsFixed(2)}';
      rightBottomLabel = 'Pending';
      
      expandedFullMsg = isMyActionRequired 
          ? 'You have received a handover request for ৳${amt.toStringAsFixed(2)} from $fromName via $channel.'
          : 'You sent a handover request for ৳${amt.toStringAsFixed(2)} via $channel, waiting for confirmation.';
          
      expandedRef = r['id']?.toString().toUpperCase() ?? '';
    } else {
      final tag = (r['entryTag'] ?? '').toString().toLowerCase();
      final dirTab = (r['metadata']?['directionTab'] ?? '').toString().toLowerCase();
      final movementType = (r['metadata']?['movementType'] ?? '').toString().toLowerCase();
      final dir = (r['direction'] ?? '').toString().toLowerCase();
      final channel = (r['channel'] ?? r['metadata']?['channel'] ?? '').toString().toUpperCase();
      final category = r['metadata']?['category'] ?? r['category'];
      final categoryStr = (category ?? '').toString();
      final tagLabel = _formatTag(tag);
      
      final bool isExpense = dirTab == 'expense' || movementType == 'expense' || (tag == 'business_expense' && dirTab != 'out' && movementType != 'cash out');
      final bool isCashOut = (dir == 'out' && !isExpense) || dirTab == 'out' || movementType == 'cash out' || tag == 'outflow';
      final bool isCashIn = dir == 'in' || dirTab == 'in' || movementType == 'cash in';
      
      title = categoryStr.isNotEmpty ? categoryStr : tagLabel;
      metaLine = '$tagLabel • $dateStr';
      
      if (isCashIn) {
        avatarBg = const Color(0xFFF0FDF4);
        avatarIconColor = const Color(0xFF16A34A);
        avatarIcon = Icons.arrow_downward_rounded;
        
        rightTopLabel = '+৳${amt.toStringAsFixed(2)}';
        rightBottomLabel = channel.isNotEmpty ? channel : 'CASH IN';
        expandedFullMsg = 'Cash IN transaction logged for ৳${amt.toStringAsFixed(2)}.';
      } else if (isCashOut) {
        avatarBg = const Color(0xFFFFFBEB);
        avatarIconColor = const Color(0xFFD97706);
        avatarIcon = Icons.arrow_upward_rounded;
        
        rightTopLabel = '-৳${amt.toStringAsFixed(2)}';
        rightBottomLabel = channel.isNotEmpty ? channel : 'CASH OUT';
        expandedFullMsg = 'Cash OUT transaction logged for ৳${amt.toStringAsFixed(2)}.';
      } else {
        avatarBg = const Color(0xFFFEF2F2);
        avatarIconColor = const Color(0xFFDC2626);
        avatarIcon = Icons.arrow_upward_rounded;
        
        rightTopLabel = '-৳${amt.toStringAsFixed(2)}';
        rightBottomLabel = 'EXPENSE';
        expandedFullMsg = 'Expense recorded for ৳${amt.toStringAsFixed(2)}.';
      }
      
      expandedRef = r['id']?.toString().toUpperCase() ?? '';
    }
    
    final Color rowBgColor = isPending ? Colors.blue.withValues(alpha: 0.04) : Colors.white;

    return Material(
      color: rowBgColor,
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
                          metaLine,
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
                        rightTopLabel,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: rightTopLabel.startsWith('-') ? const Color(0xFFDC2626) : (rightTopLabel.startsWith('+') ? const Color(0xFF16A34A) : AppTheme.primaryText),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isPending ? const Color(0xFFFEF3C7) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          rightBottomLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isPending ? const Color(0xFFB45309) : Colors.grey.shade600,
                          ),
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        expandedFullMsg,
                        style: const TextStyle(fontSize: 13, color: AppTheme.primaryText, height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      if (expandedRef.isNotEmpty)
                        Row(
                          children: [
                            const Text('Ref ID: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.secondaryText)),
                            Expanded(child: SelectableText(expandedRef, style: const TextStyle(fontSize: 11, color: AppTheme.secondaryText, fontFamily: 'monospace'))),
                          ],
                        ),
                      
                      if (note != null && note.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Text(
                            'Notes: $note',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                          ),
                        ),
                      ],
                      
                      if (isPending && isMyActionRequired) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  foregroundColor: AppTheme.expenseText,
                                  side: const BorderSide(color: AppTheme.expenseBorder),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: widget.isProcessing ? null : widget.onReject,
                                icon: const Icon(Icons.cancel_outlined, size: 16),
                                label: const Text('Reject', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  backgroundColor: const Color(0xFF16A34A),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: widget.isProcessing ? null : widget.onAccept,
                                icon: widget.isProcessing
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.check_circle_outline, size: 16),
                                label: Text(widget.isProcessing ? 'Processing' : 'Accept', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }
}
