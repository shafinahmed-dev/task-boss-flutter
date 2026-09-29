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
  String _tab = 'in';
  final _amtCtl = TextEditingController();
  final _chgCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  
  String? _selectedWalletId;
  String? _selectedPaymentMethod;
  
  String _tag = '';
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _lastSavedReceipt;

  final Map<String, List<String>> _tags = {
    'in': ['Client Payment', 'Vendor Collection', 'Investor / Funding', 'Loan', 'Refund Received', 'Other Inflow'],
    'out': ['Vendor / Supplier Payout', 'Refund to Client', 'Cash Withdrawal', 'Salary / Advance Disbursed', 'Other Outflow'],
    'expense': ['Food & Meals', 'Commute & Fuel', 'Office Supplies', 'Client Meeting', 'Courier & Logistics', 'Utility / Bill', 'Other Expense']
  };

  @override
  void initState() {
    super.initState();
    _tag = _tags['in']![0];
    _loadDraft();
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _tab = prefs.getString('draft_tab') ?? 'in';
        _tag = prefs.getString('draft_tag') ?? _tags[_tab]![0];
        _amtCtl.text = prefs.getString('draft_amt') ?? '';
        _chgCtl.text = prefs.getString('draft_chg') ?? '';
        _noteCtl.text = prefs.getString('draft_note') ?? '';
      });
    }
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('draft_tab', _tab);
    await prefs.setString('draft_tag', _tag);
    await prefs.setString('draft_amt', _amtCtl.text);
    await prefs.setString('draft_chg', _chgCtl.text);
    await prefs.setString('draft_note', _noteCtl.text);
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('draft_tab');
    await prefs.remove('draft_tag');
    await prefs.remove('draft_amt');
    await prefs.remove('draft_chg');
    await prefs.remove('draft_note');
  }

  bool get _isOtherTag => _tag.startsWith('Other');

  String _getEntryTag(String tab, String tag) {
    if (tab == 'expense') return 'business_expense';
    if (tab == 'in') {
      if (tag == 'Investor / Funding') return 'partner_funding';
      if (tag == 'Loan') return 'loan_received';
      return 'client_payment';
    }
    if (tag == 'Cash Withdrawal') return 'personal_partner';
    return 'outflow';
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
    if (_isOtherTag && noteText.isEmpty) {
      setState(() => _error = "Note is required when selecting an 'Other' category.");
      return;
    }

    final availableMethods = PaymentRails.getMethods(selectedWallet.type, _tab);
    final paymentMethod = (_selectedPaymentMethod != null && availableMethods.contains(_selectedPaymentMethod))
        ? _selectedPaymentMethod!
        : availableMethods.first;

    setState(() => _saving = true);
    try {
      final receiptNo = 'TRX-${const Uuid().v4().substring(0, 8).toUpperCase()}';
      final payload = {
        'idempotencyKey': const Uuid().v4(),
        'direction': _tab == 'in' ? 'in' : 'out',
        'amount': amt,
        'currency': 'BDT',
        'channel': selectedWallet.type.toLowerCase(),
        'walletId': selectedWallet.id,
        'paymentMethod': paymentMethod,
        'companyId': app.user!.companyId,
        'collectorId': app.user!.userId,
        'custodianId': app.user!.custodianId,
        'entryTag': _getEntryTag(_tab, _tag),
        'occurredAt': DateTime.now().toIso8601String(),
        'notes': noteText.isNotEmpty ? noteText : null,
        'note': noteText.isNotEmpty ? noteText : null,
        'description': noteText.isNotEmpty ? noteText : null,
        'metadata': {
          'category': _tag,
          'movementType': _tab == 'in' ? 'Cash In' : (_tab == 'out' ? 'Cash Out' : 'Expense'),
          'note': noteText,
          'notes': noteText,
          'baseAmount': amt,
          'fee': feeVal,
          'channel': selectedWallet.type.toLowerCase(),
          'walletId': selectedWallet.id,
          'paymentMethod': paymentMethod,
          'walletName': selectedWallet.name,
          'directionTab': _tab,
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
            'type': _tab == 'in' ? 'Cash In' : (_tab == 'out' ? 'Cash Out' : 'Expense'),
            'category': _tag,
            'wallet': selectedWallet!.name,
            'method': paymentMethod,
            'note': noteText,
            'amount': amt,
            'fee': feeVal,
          };
          _amtCtl.clear();
          _chgCtl.clear();
          _noteCtl.clear(); _clearDraft();
          _tag = _tags[_tab]![0];
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
            _buildSegmentTrack(),
            const SizedBox(height: 16),
            const Text('Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            SizedBox(
              height: 42,
              child: ScrollConfiguration(
                behavior: WebDragScrollBehavior(),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      ..._tags[_tab]!.asMap().entries.map((entry) {
                        final t = entry.value;
                        final isFirst = entry.key == 0;
                        final isSelected = _tag == t;
                        final Color accentColor = _tab == 'in'
                            ? const Color(0xFF10B981)
                            : _tab == 'out'
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFFEF4444);
                        return Padding(
                          padding: EdgeInsets.only(left: isFirst ? 0 : 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _tag = t),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeInOut,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.white : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected ? accentColor : Colors.grey.shade300,
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.06),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isSelected) ...[
                                    Icon(Icons.check_rounded, size: 13, color: accentColor),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    t,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      color: isSelected ? accentColor : const Color(0xFF4B5563),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      // Trailing spacer so the last pill is never flush against the edge
                      const SizedBox(width: 16),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            Row(children: [
              const Text('Note',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  )),
              if (_isOtherTag) const Text(' * (Required)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.expenseText)),
            ]),
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
              onChanged: (_) { _saveDraft(); setState(() {}); },
            ),
            const SizedBox(height: 16),
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
                      const Text('Fee',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          )),
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
                        onChanged: (_) { _saveDraft(); setState(() {}); },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Text(
                            'Save',
                            style: TextStyle(
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

  Widget _buildSegmentTrack() {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF111827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            alignment: _tab == 'in'
                ? Alignment.centerLeft
                : _tab == 'out'
                    ? Alignment.center
                    : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 1 / 3,
              child: Container(
                height: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              _buildSegmentItem('Cash In', 'in', Icons.arrow_downward_rounded, const Color(0xFF10B981)),
              _buildSegmentItem('Cash Out', 'out', Icons.arrow_upward_rounded, const Color(0xFFF59E0B)),
              _buildSegmentItem('Expense', 'expense', Icons.receipt_outlined, const Color(0xFFEF4444)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentItem(String label, String value, IconData icon, Color activeColor) {
    final isActive = _tab == value;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _tab = value;
          _tag = _tags[value]![0];
          _error = null;
          if (_selectedWalletId != null) {
            final app = context.read<AppState>();
            if (app.wallets.isNotEmpty) {
              final wallet = app.wallets.firstWhere(
                (w) => w.id == _selectedWalletId,
                orElse: () => app.wallets.first,
              );
              final methods = PaymentRails.getMethods(wallet.type, _tab);
              _selectedPaymentMethod = methods.first;
            }
          }
        }),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isActive ? activeColor : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? const Color(0xFF111827)
                      : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
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
}
