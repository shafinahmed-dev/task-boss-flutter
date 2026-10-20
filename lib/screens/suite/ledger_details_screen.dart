import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_boss/services/app_state.dart';

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

  void _openEditModal() {
    if (_ledger == null) return;
    final ledger = _ledger!;
    final nameCtrl = TextEditingController(text: ledger['name']?.toString() ?? '');
    final descCtrl = TextEditingController(text: ledger['description']?.toString() ?? '');
    String status = ledger['status']?.toString() ?? 'ACTIVE';
    bool isPerpetual = ledger['isPerpetual'] ?? true;
    
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

                            return CheckboxListTile(
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
                            );
                          },
                        ),
                      ),

                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: ctx,
                                builder: (dialogCtx) => AlertDialog(
                                  title: const Text('Delete Ledger'),
                                  content: const Text('Are you sure you want to delete this ledger? If movements exist, it will be archived.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('Cancel')),
                                    TextButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                final success = await app.deleteLedger(ledger['id']);
                                if (success && context.mounted) {
                                  Navigator.of(ctx).pop();
                                  Navigator.of(context).pop();
                                }
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () async {
                              final name = nameCtrl.text.trim();
                              if (name.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Ledger name cannot be empty.')),
                                );
                                return;
                              }

                              final payload = {
                                'name': name,
                                'description': descCtrl.text.trim(),
                                'status': status,
                                'isPerpetual': isPerpetual,
                                'managerUserIds': selectedManagerIds.toList(),
                              };

                              final success = await app.updateLedger(ledger['id'], payload);
                              if (success && context.mounted) {
                                Navigator.of(ctx).pop();
                                _loadDetails();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddSegmentSheet(BuildContext context) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 20,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
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
                        'Create New Segment',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(modalCtx).pop(),
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  const Divider(color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 16),
                  const Text('Segment Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g., Construction Phase 2, Marketing',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Description (Optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Optional description of this segment...',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Segment name cannot be empty.')),
                          );
                          return;
                        }
                        final app = context.read<AppState>();
                        final success = await app.createSegmentInLedger(widget.ledgerId, name, description: descCtrl.text.trim());
                        if (success && context.mounted) {
                          Navigator.of(modalCtx).pop();
                          _loadDetails();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Create Segment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  void _exportReport() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exporting PDF report for ${_ledger?['name'] ?? widget.initialName}...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ledgerName = _ledger?['name']?.toString() ?? widget.initialName;
    final status = _ledger?['status']?.toString() ?? 'ACTIVE';
    final segments = (_ledger?['segments'] as List?) ?? [];

    final filteredSegments = segments.where((s) {
      if (_searchQuery.isEmpty) return true;
      final name = s['name']?.toString().toLowerCase() ?? '';
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    double filteredInflow = 0;
    double filteredOutflow = 0;
    for (var s in filteredSegments) {
      filteredInflow += double.tryParse(s['totalInflow']?.toString() ?? '0') ?? 0;
      filteredOutflow += double.tryParse(s['totalOutflow']?.toString() ?? '0') ?? 0;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                ledgerName,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: status == 'ACTIVE' ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: status == 'ACTIVE' ? const Color(0xFF059669) : const Color(0xFFB45309),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Color(0xFF0F172A)),
            onPressed: () => _showAddSegmentSheet(context),
            tooltip: 'Add Segment',
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: Color(0xFF0F172A)),
            onPressed: _openEditModal,
            tooltip: 'Edit Ledger',
          ),
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
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.folder_open_rounded, size: 48, color: Color(0xFF94A3B8)),
                                  const SizedBox(height: 12),
                                  Text(
                                    segments.isEmpty ? 'No segments found in this ledger.' : 'No matching segments found.',
                                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 15),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: () => _showAddSegmentSheet(context),
                                    icon: const Icon(Icons.add_rounded, size: 18),
                                    label: Text(segments.isEmpty ? 'Add First Segment' : 'Add Segment'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0F172A),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ],
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
                                  padding: const EdgeInsets.all(16),
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
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '+৳ ${inflow.toStringAsFixed(2)}',
                                            style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '-৳ ${outflow.toStringAsFixed(2)}',
                                            style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),

                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Inflow', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                            Text(
                              '+৳ ${filteredInflow.toStringAsFixed(2)}',
                              style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed: _exportReport,
                          icon: const Icon(Icons.picture_as_pdf_rounded, size: 16, color: Color(0xFF0F172A)),
                          label: const Text('Export PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F172A))),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Outflow', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                            Text(
                              '-৳ ${filteredOutflow.toStringAsFixed(2)}',
                              style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

