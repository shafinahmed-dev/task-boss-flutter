import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:task_boss/theme.dart';
import 'package:task_boss/models/models.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/utils/show_receipt_modal.dart';

import 'package:shared_preferences/shared_preferences.dart';
/// Enables mouse-drag (and trackpad/stylus) scrolling on Flutter Web/Desktop.
/// By default Flutter Web restricts drag-scroll to touch pointers only.
class WebDragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class CaptureMovementScreen extends StatefulWidget {
  const CaptureMovementScreen({super.key});
  @override
  State<CaptureMovementScreen> createState() => _CaptureState();
}

class _CaptureState extends State<CaptureMovementScreen> {
  String _flowType = 'INFLOW'; // INFLOW | OUTFLOW
  Map<String, dynamic>? _selectedCategory;
  final TextEditingController _categorySearchCtrl = TextEditingController();
  String _catSearchQuery = '';

  final _amtCtl = TextEditingController();
  final _chgCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  
  String? _selectedWalletId;
  String? _selectedPaymentMethod;
  bool _saving = false;
  String? _error;
  String get _tab => _flowType == 'INFLOW' ? 'in' : 'out';

  Map<String, dynamic>? _lastSavedReceipt;

  @override
  void initState() {
  String _getEffectiveCompanyId(AppState app) {
    if (app.selectedManagerCompanyId != null && app.selectedManagerCompanyId!.isNotEmpty) {
      return app.selectedManagerCompanyId!;
    }
    final overviewCompanyId = app.managerOverviewData['company']?['id']?.toString();
    if (overviewCompanyId != null && overviewCompanyId.isNotEmpty) {
      return overviewCompanyId;
    }
    if (app.wallets.isNotEmpty) {
      final walletCompanyId = app.wallets.first['companyId']?.toString();
      if (walletCompanyId != null && walletCompanyId.isNotEmpty) {
        return walletCompanyId;
      }
    }
    return '';
  }


    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      final cid = _getEffectiveCompanyId(app);
      if (cid.isNotEmpty) {
        app.fetchCategories(companyId: cid);
      }
    });
    _loadDraft();
  }

  @override
  void dispose() {
    _categorySearchCtrl.dispose();
    super.dispose();
  }

  void _showAddCategoryModal(BuildContext context, AppState app) {
    String name = _categorySearchCtrl.text.trim();
    String type = 'BOTH';
    final cid = _getEffectiveCompanyId(app);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('New Category / Project Ledger', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: TextEditingController(text: name),
                onChanged: (val) => name = val,
                decoration: const InputDecoration(labelText: 'Category Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ChoiceChip(label: const Text('Inflow Only'), selected: type == 'INFLOW', onSelected: (s) => setModalState(() => type = 'INFLOW')),
                  ChoiceChip(label: const Text('Outflow Only'), selected: type == 'OUTFLOW', onSelected: (s) => setModalState(() => type = 'OUTFLOW')),
                  ChoiceChip(label: const Text('Both'), selected: type == 'BOTH', onSelected: (s) => setModalState(() => type = 'BOTH')),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (name.isEmpty) return;
                  final newCat = await app.createCategory(name: name, type: type, companyId: cid);
                  if (newCat != null && mounted) {
                    setState(() {
                      _selectedCategory = newCat;
                      _categorySearchCtrl.clear();
                    });
                    Navigator.pop(context);
                  }
                },
                child: const Text('Create Category'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _flowType = prefs.getString('draft_flow') ?? 'INFLOW';
        _amtCtl.text = prefs.getString('draft_amt') ?? '';
        _chgCtl.text = prefs.getString('draft_chg') ?? '';
        _noteCtl.text = prefs.getString('draft_note') ?? '';
      });
    }
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('draft_flow', _flowType);
    await prefs.setString('draft_amt', _amtCtl.text);
    await prefs.setString('draft_chg', _chgCtl.text);
    await prefs.setString('draft_note', _noteCtl.text);
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('draft_flow');
    await prefs.remove('draft_amt');
    await prefs.remove('draft_chg');
    await prefs.remove('draft_note');
  }

  bool get _isOtherTag => false;

  String _getEntryTag(String flowType, String? catName) {
    if (flowType == 'INFLOW') {
      return 'client_payment';
    }
    return 'outflow';
  }

  List<dynamic> _getCategories(AppState app) {
    return app.concernCategories.where((c) => c['type'] == 'BOTH' || c['type'] == _flowType).toList();
  }


  Future<void> _submit() async {
    setState(() => _error = null);
    final app = context.read<AppState>();
    if (app.user == null) {
      setState(() => _error = 'Session expired. Please log in again.');
      return;
    }

    final wallets = app.wallets;
    Wallet? selectedWallet;
    if (_selectedWalletId != null && wallets.isNotEmpty) {
      selectedWallet = wallets.firstWhere((w) => w.id == _selectedWalletId, orElse: () => wallets.first);
    } else if (wallets.isNotEmpty) {
      selectedWallet = wallets.first;
    }

    if (selectedWallet == null) {
      setState(() => _error = 'No active wallet found. Please create a wallet first.');
      return;
    }

    final amt = double.tryParse(_amtCtl.text.trim());
    if (amt == null || amt <= 0) {
      setState(() => _error = 'Enter an amount to continue');
      return;
    }
    final feeText = _chgCtl.text.trim();
    final feeVal = feeText.isEmpty ? 0.0 : (double.tryParse(feeText) ?? -1.0);
    if (feeVal < 0) {
      setState(() => _error = 'Please enter a valid fee/charge (0 or greater).');
      return;
    }
    final noteText = _noteCtl.text.trim();

    if (_selectedCategory == null) {
      setState(() => _error = 'Please select a Category / Project Ledger.');
      return;
    }

    final availableMethods = PaymentRails.getMethods(selectedWallet.type, _flowType == 'INFLOW' ? 'in' : 'out');
    final paymentMethod = (_selectedPaymentMethod != null && availableMethods.contains(_selectedPaymentMethod))
        ? _selectedPaymentMethod!
        : availableMethods.first;

    setState(() => _saving = true);
    try {
      final receiptNo = 'TRX-${const Uuid().v4().substring(0, 8).toUpperCase()}';
      final payload = {
        'idempotencyKey': const Uuid().v4(),
        'direction': _flowType == 'INFLOW' ? 'in' : 'out',
        'amount': amt,
        'currency': 'BDT',
        'channel': selectedWallet.type.toLowerCase(),
        'walletId': selectedWallet.id,
        'paymentMethod': paymentMethod,
        'companyId': app.user!.companyId,
        'collectorId': app.user!.userId,
        'custodianId': app.user!.custodianId,
        'entryTag': _getEntryTag(_flowType, _selectedCategory?['name']),
        'categoryId': _selectedCategory?['id'],
        'occurredAt': DateTime.now().toIso8601String(),
        'notes': noteText.isNotEmpty ? noteText : null,
        'note': noteText.isNotEmpty ? noteText : null,
        'description': noteText.isNotEmpty ? noteText : null,
        'metadata': {
          'category': _selectedCategory?['name'],
          'categoryId': _selectedCategory?['id'],
          'movementType': _flowType == 'INFLOW' ? 'Cash In' : 'Cash Out',
          'note': noteText,
          'notes': noteText,
          'baseAmount': amt,
          'fee': feeVal,
          'channel': selectedWallet.type.toLowerCase(),
          'walletId': selectedWallet.id,
          'paymentMethod': paymentMethod,
          'walletName': selectedWallet.name,
          'directionTab': _flowType == 'INFLOW' ? 'in' : 'out',
          'voucherNumber': receiptNo,
        },
      };

      final res = await app.authRequest(
        'POST',
        Uri.parse('${app.apiBaseUrl}/ledger/movements'),
        headers: {
          'Content-Type': 'application/json',
          'x-company-id': app.user!.companyId
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final resData = jsonDecode(res.body);
        final returnedNo = resData['receiptNo'] ?? resData['metadata']?['voucherNumber'] ?? receiptNo;

        setState(() {
          _lastSavedReceipt = {
            'receiptNo': returnedNo,
            'date': DateTime.now(),
            'type': _flowType == 'INFLOW' ? 'Cash In' : 'Cash Out',
            'category': _selectedCategory?['name'],
            'wallet': selectedWallet!.name,
            'method': paymentMethod,
            'note': noteText,
            'amount': amt,
            'fee': feeVal,
          };
          _amtCtl.clear();
          _chgCtl.clear();
          _noteCtl.clear(); _clearDraft();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transaction saved successfully!'),
              backgroundColor: AppTheme.confirmedText,
            ),
          );
        }
        await app.refreshBalance();
      } else {
        final err = jsonDecode(res.body)['message'];
        throw Exception(err is List ? err.join(', ') : (err?.toString() ?? 'Failed (HTTP ${res.statusCode})'));
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wallets = app.wallets;

    if (_selectedWalletId == null && wallets.isNotEmpty) {
      final defaultWallet = wallets.firstWhere((w) => w.isDefault, orElse: () => wallets.first);
      _selectedWalletId = defaultWallet.id;
    }

    Wallet? selectedWallet;
    if (_selectedWalletId != null && wallets.isNotEmpty) {
      selectedWallet = wallets.firstWhere(
        (w) => w.id == _selectedWalletId,
        orElse: () => wallets.first,
      );
    }

    final availableMethods = selectedWallet != null
        ? PaymentRails.getMethods(selectedWallet.type, _tab)
        : ['Physical Cash'];

    if (_selectedPaymentMethod == null || !availableMethods.contains(_selectedPaymentMethod)) {
      _selectedPaymentMethod = availableMethods.first;
    }

    final amtVal = double.tryParse(_amtCtl.text.trim()) ?? 0.0;
    final feeVal = double.tryParse(_chgCtl.text.trim()) ?? 0.0;
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.slateDark)),
            const SizedBox(height: 12),
            if (_error != null) _banner(_error!),
            _buildFlowPill(),
            const SizedBox(height: 14),
            _buildCategoryCard(context.watch<AppState>()),
            const SizedBox(height: 14),
            // Card 2: Wallet & Method
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined, size: 18, color: AppTheme.slateMid),
                      SizedBox(width: 8),
                      Text(
                        'Source Wallet & Method',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppTheme.primaryText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Wallet',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          )),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        key: ValueKey('wallet_$_selectedWalletId'),
                        initialValue: _selectedWalletId,
                        items: wallets.map((w) => DropdownMenuItem<String>(value: w.id, child: Text('${w.name} (৳${w.currentBalance.toStringAsFixed(0)})', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)))).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _selectedWalletId = v;
                              final newlySelected = wallets.firstWhere((w) => w.id == v);
                              final methods = PaymentRails.getMethods(newlySelected.type, _tab);
                              _selectedPaymentMethod = methods.first;
                            });
                          }
                        },
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Method',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          )),
                      const SizedBox(height: 6),
                      selectedWallet?.type.toUpperCase() == 'CASH'
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Text('Physical Cash',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                  overflow: TextOverflow.ellipsis),
                            )
                          : DropdownButtonFormField<String>(
                              key: ValueKey('method_${selectedWallet?.id}_$_selectedPaymentMethod'),
                              initialValue: availableMethods.contains(_selectedPaymentMethod) ? _selectedPaymentMethod : availableMethods.first,
                              items: availableMethods.map((m) => DropdownMenuItem<String>(value: m, child: Text(m, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => _selectedPaymentMethod = v);
                              },
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFFF1F5F9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            ),
                ],
              ),
          ),
          const SizedBox(height: 14),
          // Card 3: Amount Details
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.payments_outlined, size: 18, color: AppTheme.slateMid),
                    SizedBox(width: 8),
                    Text(
                      'Amount Details',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppTheme.primaryText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
            // Symmetrical 2x2 Layout - Row 2: Amount & Fee
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Amount',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          )),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _amtCtl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          hintText: '0.00',
                          hintStyle: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFCBD5E1),
                          ),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 14, right: 6),
                            child: Text(
                              '৳',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                        ),
                        onChanged: (_) { _saveDraft(); setState(() {}); },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Fee / Charge',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _chgCtl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          hintText: '0.00',
                          hintStyle: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFCBD5E1),
                          ),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 14, right: 6),
                            child: Text(
                              '৳',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                        ),
                        onChanged: (_) {
                          _saveDraft();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Note input field below them with comfortable spacing
            Row(
              children: [
                const Text(
                  'Note',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
                if (_isOtherTag)
                  const Text(
                    ' * (Required)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: AppTheme.expenseText,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _noteCtl,
              decoration: InputDecoration(
                hintText: _isOtherTag ? "Required for 'Other'..." : "Note...",
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onChanged: (_) {
                _saveDraft();
                setState(() {});
              },
            ),
          ],
        ),
      ),
            const SizedBox(height: 14),
            if (amtVal > 0 || feeVal > 0) Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.cardBg, border: Border.all(color: AppTheme.cardBorder), borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                _row('Base Amount:', '৳${amtVal.toStringAsFixed(2)}'),
                if (feeVal > 0) _row('Fee / Charge (Expense):', '৳${feeVal.toStringAsFixed(2)}'),
                const Divider(),
                _row(_tab == 'in' ? 'Total Inflow:' : 'Total Outflow:', _tab == 'in' ? '৳${amtVal.toStringAsFixed(2)}' : '৳${(amtVal + feeVal).toStringAsFixed(2)}', bold: true),
              ]),
            ),
            const SizedBox(height: 20),
            Center(
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.slateButtonGradient,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 18),
                    label: Text(
                      _saving ? 'Saving...' : 'Save',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: _lastSavedReceipt == null
                  ? const Text(
                      'Hit Save to Generate Receipt',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
                    )
                  : TextButton.icon(
                      onPressed: () {
                        final r = _lastSavedReceipt!;
                        showReceiptModal(
                          context,
                          receiptNo: r['receiptNo'],
                          date: r['date'],
                          type: r['type'],
                          categoryOrRecipient: r['category'],
                          wallet: r['wallet'],
                          method: r['method'],
                          note: r['note'],
                          amount: r['amount'],
                          fee: r['fee'],
                        );
                      },
                      icon: const Icon(Icons.download_rounded, color: Color(0xFF2563EB), size: 18),
                      label: const Text(
                        'Download Receipt',
                        style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _banner(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF2F2),
      border: Border.all(color: const Color(0xFFFEE2E2)),
 );
  Widget _buildCategoryCard(AppState app) {
    final isManager = app.currentUser?.role != 'EMPLOYEE';
    final categories = app.concernCategories.where((c) {
      final matchesFlow = c['type'] == _flowType || c['type'] == 'BOTH';
      final matchesSearch = c['name'].toString().toLowerCase().contains(_categorySearchCtrl.text.trim().toLowerCase());
      return matchesFlow && matchesSearch;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.category_outlined, size: 18, color: Color(0xFF0F172A)),
              const SizedBox(width: 8),
              const Text('Category', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _categorySearchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search categories or projects...',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF64748B)),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
              ),
              if (isManager) ...[
                const SizedBox(width: 8),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(10)),
                  child: IconButton(icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20), onPressed: () => _showAddCategoryModal(context, app)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (categories.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: categories.map((c) {
                  final isSelected = _selectedCategory?['id'] == c['id'];
                  final isInflow = _flowType == 'INFLOW';
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedCategory = c),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? (isInflow ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2)) : Colors.white,
                          border: Border.all(color: isSelected ? (isInflow ? const Color(0xFF10B981) : const Color(0xFFEF4444)) : const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            if (isSelected) ...[Icon(Icons.check_rounded, size: 14, color: isInflow ? const Color(0xFF10B981) : const Color(0xFFEF4444)), const SizedBox(width: 4)],
                            Text(c['name'], style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: const Color(0xFF475569))),
                          ],
                        ),
                      ),
                    ),
                  ),
                }).toList(),
              ),
            )
          else if (isManager && _categorySearchCtrl.text.isNotEmpty)
            GestureDetector(
              onTap: () => _showAddCategoryModal(context, app),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(20)),
                child: Text('+ Create "${_categorySearchCtrl.text.trim()}"', style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
              ),
            )
          else
            const Text("No categories found. Tap + to add one.", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
        ],
      ),
    );
  }


      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFDC2626)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            t,
            style: const TextStyle(
              color: Color(0xFFDC2626),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _row(String l, String v, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      Text(v, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w900 : FontWeight.bold, color: bold ? AppTheme.primaryGradientFallback : Colors.black)),
    ]),
  );
  Widget _buildFlowPill() {
    final isInflow = _flowType == 'INFLOW';
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2638),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Inflow Segment
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (_flowType != 'INFLOW') {
                  setState(() {
                    _flowType = 'INFLOW';
                    _selectedCategory = null;
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isInflow ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isInflow
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.arrow_downward_rounded,
                      size: 16,
                      color: isInflow ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Inflow',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isInflow ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Outflow Segment
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (_flowType != 'OUTFLOW') {
                  setState(() {
                    _flowType = 'OUTFLOW';
                    _selectedCategory = null;
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: !isInflow ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: !isInflow
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.arrow_upward_rounded,
                      size: 16,
                      color: !isInflow ? const Color(0xFFEF4444) : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Outflow',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: !isInflow ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}
