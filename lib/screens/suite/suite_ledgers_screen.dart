import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/app_state.dart';
import 'ledger_details_screen.dart';

String formatBdt(num value) {
  final formatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '৳ ',
    decimalDigits: 2,
  );
  return formatter.format(value);
}

class SuiteLedgersScreen extends StatefulWidget {
  const SuiteLedgersScreen({super.key});

  @override
  State<SuiteLedgersScreen> createState() => _SuiteLedgersScreenState();
}

class _SuiteLedgersScreenState extends State<SuiteLedgersScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _ledgers = [];
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLedgers());
  }

  Future<void> _loadLedgers() async {
    setState(() => _isLoading = true);
    final app = context.read<AppState>();
    try {
      final results = await app.fetchSuiteLedgers(search: _searchQuery.isNotEmpty ? _searchQuery : null);
      results.sort((a, b) {
        if (a['code'] == 'GEN-OPS') return -1;
        if (b['code'] == 'GEN-OPS') return 1;
        return 0;
      });
      if (mounted) setState(() { _ledgers = results; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showCreateLedgerSheet(BuildContext context) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool isPerpetual = true;
    DateTime? startDate;
    DateTime? endDate;
    final selectedManagerIds = <String>{};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final app = context.read<AppState>();
            final managers = app.managers;

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
                          'Create Ledger',
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
                        hintText: 'e.g. Barakah Condominium Project',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text('Description (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Brief purpose or scope of this ledger...',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                    ),
                    const SizedBox(height: 14),

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Perpetual Lifecycle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text('Runs indefinitely without expiry or closure dates.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      value: isPerpetual,
                      activeThumbColor: const Color(0xFF10B981),
                      onChanged: (val) => setSheetState(() => isPerpetual = val),
                    ),
                    if (!isPerpetual) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: ctx,
                                  initialDate: startDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                );
                                if (d != null) setSheetState(() => startDate = d);
                              },
                              child: Text(startDate == null ? 'Start Date' : startDate!.toString().split(' ')[0]),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: ctx,
                                  initialDate: endDate ?? DateTime.now().add(const Duration(days: 90)),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                );
                                if (d != null) setSheetState(() => endDate = d);
                              },
                              child: Text(endDate == null ? 'End Date' : endDate!.toString().split(' ')[0]),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),
                    const Text('Assign Responsible Managers', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                    const SizedBox(height: 8),
                    if (managers.isEmpty)
                      const Text('No managers registered in system.', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: managers.map((m) {
                          final userId = (m['userId'] ?? m['id'] ?? m['user']?['id'])?.toString() ?? '';
                          final name = (m['name'] ?? m['user']?['name'] ?? 'Manager').toString();
                          final isSelected = selectedManagerIds.contains(userId);
                          return FilterChip(
                            label: Text(name),
                            selected: isSelected,
                            selectedColor: const Color(0xFFFEF3C7),
                            checkmarkColor: const Color(0xFFB45309),
                            onSelected: (selected) {
                              setSheetState(() {
                                if (selected) {
                                  selectedManagerIds.add(userId);
                                } else {
                                  selectedManagerIds.remove(userId);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter ledger name.')),
                            );
                            return;
                          }

                          final payload = {
                            'name': name,
                            'description': descCtrl.text.trim(),
                            'isPerpetual': isPerpetual,
                            if (!isPerpetual && startDate != null) 'startDate': startDate!.toIso8601String(),
                            if (!isPerpetual && endDate != null) 'endDate': endDate!.toIso8601String(),
                            'managerUserIds': selectedManagerIds.toList(),
                          };

                          final success = await app.createLedger(payload);
                          if (success && ctx.mounted) {
                            Navigator.of(ctx).pop();
                            _loadLedgers();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Create Ledger', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
    @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF070B14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) { setState(() => _searchQuery = val.trim().toLowerCase()); _loadLedgers(); },
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Search Ledger By Name',
                hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w400),
                prefixIcon: Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E2638)))
                : _ledgers.isEmpty
                    ? const Center(child: Text('No ledgers found.', style: TextStyle(color: Color(0xFF64748B))))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _ledgers.length,
                        itemBuilder: (context, index) {
                          return _buildEnterpriseLedgerCard(context, _ledgers[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }
  String formatBdt(num value) {
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '৳ ',
      decimalDigits: 2,
    );
    return formatter.format(value);
  }

  Widget _buildEnterpriseLedgerCard(BuildContext context, Map<String, dynamic> ledger) {
    final isDefault = ledger['code'] == 'GEN-OPS';
    final status = (ledger['status'] ?? 'ACTIVE').toString().toUpperCase();
    final isFrozen = status == 'FROZEN';

    final Color accentColor = isDefault
        ? const Color(0xFFF59E0B)
        : (isFrozen ? const Color(0xFF64748B) : const Color(0xFF10B981));

    final double inflow = (ledger['inflow'] as num? ?? ledger['totalInflow'] as num? ?? 0).toDouble();
    final double outflow = (ledger['outflow'] as num? ?? ledger['totalOutflow'] as num? ?? 0).toDouble();

    return Opacity(
      opacity: isFrozen ? 0.72 : 1.0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              accentColor.withOpacity(0.22),
              accentColor.withOpacity(0.07),
              const Color(0xFF070B14),
              const Color(0xFF000000),
            ],
            stops: const [0.0, 0.16, 0.45, 1.0],
          ),
          border: Border.all(
            color: Colors.white.withOpacity(0.08),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              // Top glass edge highlight
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.18),
                        Colors.white.withOpacity(0.03),
                      ],
                    ),
                  ),
                ),
              ),
              // Card Content with 3.5px left bar
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 3.5, color: accentColor),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LedgerDetailsScreen(
                                ledgerId: ledger['id'].toString(),
                                initialName: ledger['name']?.toString() ?? 'Ledger',
                              ),
                            ),
                          ).then((_) => _loadLedgers());
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Title & Description (No Badges)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      ledger['name']?.toString() ?? 'Ledger',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFF8FAFC),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      ledger['description']?.toString().isNotEmpty == true
                                          ? ledger['description'].toString()
                                          : 'Operational budget container',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Financial balance column (zero-suppression preserved)
                              _buildLedgerBalanceColumn(inflow, outflow),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildLedgerBalanceColumn(double inflow, double outflow) {
    final hasInflow = inflow > 0;
    final hasOutflow = outflow > 0;

    if (!hasInflow && !hasOutflow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            formatBdt(0),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (hasInflow) ...[
          const Text(
            'INFLOW',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Color(0xFF64748B),
            ),
          ),
          Text(
            '+${formatBdt(inflow)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF10B981),
            ),
          ),
        ],
        if (hasInflow && hasOutflow) const SizedBox(height: 6),
        if (hasOutflow) ...[
          const Text(
            'OUTFLOW',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Color(0xFF64748B),
            ),
          ),
          Text(
            '-${formatBdt(outflow)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFEF4444),
            ),
          ),
        ],
      ],
    );
  }
}
