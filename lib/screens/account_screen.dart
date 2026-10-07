import 'dart:convert';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:task_boss/models/models.dart';
import 'package:task_boss/theme.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/screens/history_screen.dart';

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


class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const AccountScreen();
  }
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _loading = true;
  double _inf = 0, _outf = 0;
  String _formatAmount(dynamic val) {
    final d = _toDouble(val);
    return d % 1 == 0 ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
  }
  List<dynamic> _inflowItems = [];
  List<dynamic> _outflowItems = [];

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

      final mUri = Uri.parse('${app.apiBaseUrl}/ledger/custodians/$cId/movements?companyId=$cmp');
      final tUri = Uri.parse('${app.apiBaseUrl}/custody/transfers?custodianId=$cId&companyId=$cmp');

      final results = await Future.wait([
        app.authRequest('GET', mUri).catchError((_) => http.Response('{}', 500)),
        app.authRequest('GET', tUri).catchError((_) => http.Response('[]', 500)),
      ]);

      double i = 0, o = 0;
      final List<dynamic> infs = [];
      final List<dynamic> outfs = [];

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
            if (fee > 0 && dir == 'out') {
              o += fee;
              outfs.add({
                'uiType': 'fee',
                'title': 'Transfer Fee',
                'amount': fee,
                'date': m['date'],
                'notes': m['notes'] ?? m['note'] ?? m['metadata']?['note'] ?? m['metadata']?['notes'],
                'channel': m['channel'] ?? m['metadata']?['channel'],
              });
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
              o += fee;
              outfs.add({
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

          final bool isCashIn = dir == 'in' || dirTab == 'in' || movementType == 'cash in' || tag == 'inflow';
          final bool isCashOut = !isCashIn;

          if (isCashIn) {
            i += amt;
            infs.add(m);
            if (fee > 0) {
              o += fee;
              outfs.add({
                'uiType': 'fee',
                'title': 'Movement Fee (${categoryStr.isNotEmpty ? categoryStr : (tag.isNotEmpty ? tag : "Cash In")})',
                'amount': fee,
                'date': m['date'],
                'notes': m['notes'] ?? m['note'] ?? m['metadata']?['note'] ?? m['metadata']?['notes'],
                'channel': m['channel'] ?? m['metadata']?['channel'],
              });
            }
          } else if (isCashOut) {
            o += amt;
            outfs.add(m);
            if (fee > 0) {
              o += fee;
              outfs.add({
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

      if (mounted) {
        setState(() {
          _inf = i;
          _outf = o;
          _inflowItems = infs;
          _outflowItems = outfs;
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
      appBar: AppBar(
        backgroundColor: AppTheme.canvas,
        foregroundColor: AppTheme.primaryText,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Account',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryText,
          ),
        ),
        centerTitle: true,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await app.refreshBalance();
          await _loadData();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const Center(child: Padding(padding: EdgeInsets.only(bottom: 20), child: CircularProgressIndicator(strokeWidth: 2))),
            _buildStatementCard(u, app.balance),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'WORKSPACE PROFILE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: AppTheme.secondaryText,
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _showEditWorkspaceDetails(u),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_outlined, size: 14, color: Color(0xFF475569)),
                          SizedBox(width: 4),
                          Text(
                            'Edit',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _buildWorkspaceProfile(u),
            const SizedBox(height: 32),
            Center(
              child: SizedBox(
                width: 280,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.outflowText,
                    side: const BorderSide(color: AppTheme.outflowBorder),
                    backgroundColor: AppTheme.outflowBg.withValues(alpha: 0.5),
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _confirmLogout(app),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(AppState app) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out of your account?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.secondaryText)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.outflowText,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              app.logout();
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatementCard(u, double bal) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.slateCardGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  child: Text(
                    u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(u.email, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  ),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_rounded, size: 16, color: Colors.white),
                        SizedBox(width: 5),
                        Text(
                          'History',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text('Available Balance', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text('৳${bal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 24),
          Divider(color: Colors.white.withValues(alpha: 0.15), height: 1),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _showDetailsModal('Inflow Transactions', _inflowItems, AppTheme.inflowText),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        const Text(
                          'Inflows',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '+৳ ${_formatAmount(_inf)}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                height: 32,
                width: 1,
                color: Colors.white.withValues(alpha: 0.12),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => _showDetailsModal('Outflow Transactions', _outflowItems, AppTheme.pendingAccent),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        const Text(
                          'Outflows',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '-৳ ${_formatAmount(_outf)}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
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
                  Text('৳${amt.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.outflowText)),
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
      final cpName = counterparty?['name'] ?? 'User Account';
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
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isOut ? AppTheme.outflowText : AppTheme.inflowText),
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
                Text('Fee: ৳${fee.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.outflowText, fontSize: 11, fontStyle: FontStyle.italic)),
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

    final bool isCashIn = dir == 'in' || dirTab == 'in' || movementType == 'cash in';
    final bool isCashOut = !isCashIn;

    String badgeLabel = isCashIn ? 'INFLOW' : 'OUTFLOW';
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
                  Text('Fee: ৳${fee.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.outflowText, fontSize: 11, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
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

  Widget _buildWorkspaceProfile(AuthUser u) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: [
          _buildProfileTile(
            icon: Icons.badge_outlined,
            title: 'Designation',
            trailing: Text(
              u.designation.isNotEmpty ? u.designation : 'Not Set',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryText,
              ),
            ),
          ),
          const Divider(height: 1),
          _buildProfileTile(
            icon: Icons.business_outlined,
            title: 'Department',
            trailing: Text(
              u.department.isNotEmpty ? u.department : 'General',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryText,
              ),
            ),
          ),
          const Divider(height: 1),
          _buildProfileTile(
            icon: Icons.lock_outline_rounded,
            title: 'Security & Passcode',
            trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText, size: 20),
            onTap: _showSecuritySheet,
          ),
          const Divider(height: 1),
          _buildProfileTile(
            icon: Icons.developer_mode_outlined,
            title: 'System Diagnostics & IDs',
            trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText, size: 20),
            onTap: () => _showSystemDiagnostics(u),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTile({required IconData icon, required String title, required Widget trailing, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.secondaryText),
            const SizedBox(width: 14),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.primaryText))),
            trailing,
          ],
        ),
      ),
    );
  }

  void _showEditWorkspaceDetails(AuthUser u) {
    final desCtl = TextEditingController(text: u.designation);
    final depCtl = TextEditingController(text: u.department);
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Edit Profile & Security',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryText),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Update your designation and department information.',
                    style: TextStyle(fontSize: 13, color: AppTheme.secondaryText),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Designation',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: desCtl,
                    decoration: InputDecoration(
                      hintText: 'e.g., Senior Cashier, Accounts Manager',
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Department',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: depCtl,
                    decoration: InputDecoration(
                      hintText: 'e.g., Operations, Finance',
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          elevation: 4,
                          shadowColor: const Color(0xFF0F172A).withValues(alpha: 0.25),
                        ),
                        onPressed: saving ? null : () async {
                          setModalState(() => saving = true);
                          final newDes = desCtl.text.trim();
                          final newDep = depCtl.text.trim();
                          final messenger = ScaffoldMessenger.of(context);
                          await context.read<AppState>().updateProfileMeta(
                                designation: newDes,
                                department: newDep,
                              );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Profile details updated'),
                                backgroundColor: AppTheme.confirmedText,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        child: saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Text('Save Changes', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showSecuritySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _SecuritySheet(),
    );
  }


  void _showSystemDiagnostics(u) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      backgroundColor: AppTheme.cardBg,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 20),
              const Text('System Diagnostics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryText)),
              const SizedBox(height: 20),
              _buildDiagRow('User ID', u.userId.isNotEmpty ? u.userId : u.custodianId),
              if (u.custodianId.isNotEmpty && u.custodianId != u.userId) ...[
                const SizedBox(height: 16),
                _buildDiagRow('Account ID', u.custodianId),
              ],
              const SizedBox(height: 32),
              const Center(child: Text('App Version: 1.0.0 (Build 12)', style: TextStyle(fontSize: 12, color: AppTheme.mutedText))),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiagRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: AppTheme.primaryText))),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.primaryGradientFallback),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied!'), duration: const Duration(seconds: 1)));
              },
            ),
          ],
        ),
      ],
    );
  }
}
class _SecuritySheet extends StatefulWidget {
  const _SecuritySheet();

  @override
  State<_SecuritySheet> createState() => _SecuritySheetState();
}

class _SecuritySheetState extends State<_SecuritySheet> {
  bool _isLoading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  final _currentPwdCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();

  bool _hasPin = false;
  bool _requirePin = false;

  @override
  void initState() {
    super.initState();
    _loadSec();
  }

  Future<void> _loadSec() async {
    final app = context.read<AppState>();
    final h = await app.hasSecurityPin();
    final r = await app.isPinRequiredForTransactions();
    if (mounted) {
      setState(() {
        _hasPin = h;
        _requirePin = r;
      });
    }
  }

  void _showMsg(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _updatePassword() async {
    final cur = _currentPwdCtrl.text;
    final newP = _newPwdCtrl.text;
    final conf = _confirmPwdCtrl.text;

    if (cur.isEmpty || newP.isEmpty || conf.isEmpty) {
      _showMsg('All password fields are required.');
      return;
    }
    if (newP.length < 6) {
      _showMsg('New password must be at least 6 characters.');
      return;
    }
    if (newP != conf) {
      _showMsg('New passwords do not match.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final app = context.read<AppState>();
      final res = await app.authRequest(
        'POST',
        Uri.parse('${app.apiBaseUrl}/auth/change-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'currentPassword': cur, 'newPassword': newP}),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        _showMsg('Password updated successfully.');
        _currentPwdCtrl.clear();
        _newPwdCtrl.clear();
        _confirmPwdCtrl.clear();
      } else {
        final d = jsonDecode(res.body);
        _showMsg(d['message'] ?? 'Failed to update password.');
      }
    } catch (e) {
      _showMsg('Error updating password.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePinChange() async {
    final app = context.read<AppState>();
    if (_hasPin) {
      final old = await _promptPin('Enter Current PIN');
      if (old == null) return;
      final ok = await app.verifySecurityPin(old);
      if (!ok) {
        _showMsg('Incorrect PIN.');
        return;
      }
    }

    final newP = await _promptPin('Enter New 4-Digit PIN');
    if (newP == null || newP.length < 4) return;
    
    final confP = await _promptPin('Confirm New PIN');
    if (confP == null) return;
    if (newP != confP) {
      _showMsg('PINs do not match.');
      return;
    }

    await app.setSecurityPin(newP);
    _showMsg('Security PIN updated.');
    _loadSec();
  }

  Future<String?> _promptPin(String title) async {
    String pin = '';
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(pin.padRight(4, '○').replaceAll(RegExp(r'[0-9]'), '●'), style: const TextStyle(fontSize: 32, letterSpacing: 8)),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: List.generate(12, (index) {
                    if (index == 9) return const SizedBox(width: 50, height: 50);
                    if (index == 11) {
                      return InkWell(
                        onTap: () {
                          if (pin.isNotEmpty) setDialogState(() => pin = pin.substring(0, pin.length - 1));
                        },
                        child: Container(
                          width: 50, height: 50, alignment: Alignment.center,
                          child: const Icon(Icons.backspace_outlined),
                        ),
                      );
                    }
                    final num = index == 10 ? 0 : index + 1;
                    return InkWell(
                      onTap: () {
                        if (pin.length < 4) {
                          setDialogState(() => pin += num.toString());
                          if (pin.length == 4) {
                            Navigator.pop(ctx, pin);
                          }
                        }
                      },
                      child: Container(
                        width: 50, height: 50, alignment: Alignment.center,
                        decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                        child: Text('$num', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                    );
                  }),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppTheme.secondaryText))),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 10, 20, bottomInset + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 5,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const Text('Security & Access', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryText)),
            const SizedBox(height: 4),
            const Text('Manage login password and transaction authorization PIN.', style: TextStyle(color: AppTheme.secondaryText, fontSize: 13)),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppTheme.canvas, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.cardBorder)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('App Unlock & PIN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.primaryText)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _hasPin ? const Color(0xFFDCFCE7) : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_hasPin ? 'Status: PIN Active' : 'Status: Not Set', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _hasPin ? const Color(0xFF16A34A) : Colors.grey.shade600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryText,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _handlePinChange,
                          child: Text(_hasPin ? 'Change PIN' : 'Set PIN', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                      if (_hasPin) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.outflowText,
                              side: const BorderSide(color: AppTheme.outflowBorder),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              final app = context.read<AppState>();
                              await app.removeSecurityPin();
                              _loadSec();
                              _showMsg('PIN removed.');
                            },
                            child: const Text('Remove', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                      ]
                    ],
                  ),
                  if (_hasPin) ...[
                    const Divider(height: 30),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(child: Text('Require PIN for Handovers & Cash Movements', style: TextStyle(fontSize: 13, color: AppTheme.primaryText))),
                        Switch(
                          value: _requirePin,
                          activeThumbColor: AppTheme.primaryGradientFallback,
                          onChanged: (val) async {
                            await context.read<AppState>().setPinRequiredForTransactions(val);
                            _loadSec();
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text('Account Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryText)),
            const SizedBox(height: 4),
            const Text('Update backend account login password.', style: TextStyle(color: AppTheme.secondaryText, fontSize: 13)),
            const SizedBox(height: 16),
            _pwdField('Current Password', _currentPwdCtrl, _obscureCurrent, (val) => setState(() => _obscureCurrent = val)),
            const SizedBox(height: 12),
            _pwdField('New Password', _newPwdCtrl, _obscureNew, (val) => setState(() => _obscureNew = val)),
            const SizedBox(height: 12),
            _pwdField('Confirm New Password', _confirmPwdCtrl, _obscureConfirm, (val) => setState(() => _obscureConfirm = val)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGradientFallback,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isLoading ? null : _updatePassword,
                child: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Update Password', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pwdField(String label, TextEditingController ctrl, bool obscure, Function(bool) onTg) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, color: AppTheme.secondaryText),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: AppTheme.secondaryText),
          onPressed: () => onTg(!obscure),
        ),
      ),
    );
  }
}

