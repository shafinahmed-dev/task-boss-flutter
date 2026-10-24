import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import 'ledger_details_screen.dart';

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
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ledgers',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Project and operational budget books',
                          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showCreateLedgerSheet(context),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Ledger', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) { setState(() => _searchQuery = v); _loadLedgers(); },
                  decoration: InputDecoration(
                    hintText: 'Search ledger by name or code...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E2638)))
                : _ledgers.isEmpty
                    ? const Center(child: Text('No ledgers found.', style: TextStyle(color: Color(0xFF64748B))))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _ledgers.length,
                        itemBuilder: (context, index) {
                          final l = _ledgers[index];
                          final isDefault = l['code'] == 'GEN-OPS';
                          final inflow = double.tryParse(l['inflow']?.toString() ?? l['totalInflow']?.toString() ?? '0') ?? 0.0;
                          final outflow = double.tryParse(l['outflow']?.toString() ?? l['totalOutflow']?.toString() ?? '0') ?? 0.0;
                          final managersList = l['managers'] as List? ?? [];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDefault ? const Color(0xFFFBBF24) : const Color(0xFF34D399),
                                width: isDefault ? 1.4 : 1.2,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => LedgerDetailsScreen(
                                        ledgerId: l['id'].toString(),
                                        initialName: l['name']?.toString() ?? 'Ledger',
                                      ),
                                    ),
                                  ).then((_) => _loadLedgers());
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              l['name']?.toString() ?? 'Unnamed Ledger',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              l['description']?.toString().isNotEmpty == true ? l['description'] : 'Segments: ${l['segmentsCount'] ?? 0} • Managers: ${managersList.length}',
                                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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
                                          Text('+৳ ${inflow.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13)),
                                          Text('-৳ ${outflow.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 13)),
                                        ],
                                      ),
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
    );
  }
}
