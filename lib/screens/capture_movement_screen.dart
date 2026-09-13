import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:task_boss/theme.dart';
import 'package:task_boss/models/models.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/utils/show_receipt_modal.dart';

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
      setState(() => _error = 'Please enter a valid amount greater than 0.');
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

      final res = await http.post(
        Uri.parse('${app.apiBaseUrl}/ledger/movements'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${app.token}',
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
          _noteCtl.clear();
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
            const Text('Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryGradientFallback)),
            const SizedBox(height: 12),
            if (_error != null) _banner(_error!),
            Row(children: [_tabBtn('Cash In', 'in', AppTheme.inflowText), _tabBtn('Cash Out', 'out', AppTheme.pendingAccent), _tabBtn('Expense', 'expense', AppTheme.expenseText)]),
            const SizedBox(height: 16),
            const Text('Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _tags[_tab]!.map((t) => ChoiceChip(
                label: Text(t, style: TextStyle(color: _tag == t ? Colors.white : AppTheme.secondaryText, fontWeight: FontWeight.bold, fontSize: 12)),
                selected: _tag == t,
                selectedColor: _tab == 'in' ? AppTheme.inflowText : _tab == 'out' ? AppTheme.pendingAccent : AppTheme.expenseText,
                onSelected: (_) => setState(() => _tag = t),
              )).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Wallet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                        decoration: const InputDecoration(filled: true, fillColor: AppTheme.inputBg, border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Method', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      selectedWallet?.type.toUpperCase() == 'CASH'
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                              decoration: BoxDecoration(color: AppTheme.inputBg, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade400)),
                              child: const Text('Physical Cash', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 12), overflow: TextOverflow.ellipsis),
                            )
                          : DropdownButtonFormField<String>(
                              key: ValueKey('method_${selectedWallet?.id}_$_selectedPaymentMethod'),
                              initialValue: availableMethods.contains(_selectedPaymentMethod) ? _selectedPaymentMethod : availableMethods.first,
                              items: availableMethods.map((m) => DropdownMenuItem<String>(value: m, child: Text(m, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => _selectedPaymentMethod = v);
                              },
                              decoration: const InputDecoration(filled: true, fillColor: AppTheme.inputBg, border: OutlineInputBorder()),
                            ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Text('Note', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              if (_isOtherTag) const Text(' * (Required)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.expenseText)),
            ]),
            const SizedBox(height: 6),
            TextField(
              controller: _noteCtl,
              decoration: InputDecoration(hintText: _isOtherTag ? "Required for 'Other'..." : "Note...", filled: true, fillColor: AppTheme.inputBg, border: const OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
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
                      const Text('Amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(controller: _amtCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: '0.00', filled: true, fillColor: AppTheme.inputBg, border: OutlineInputBorder()), onChanged: (_) => setState(() {})),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Fee', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(controller: _chgCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: '0.00', filled: true, fillColor: AppTheme.inputBg, border: OutlineInputBorder()), onChanged: (_) => setState(() {})),
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
                width: 280,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGradientFallback, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: _saving ? null : _submit,
                  child: _saving ? const CircularProgressIndicator(color: Colors.white) : const Text('Save', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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

  Widget _tabBtn(String l, String v, Color c) => Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _tab = v;
            _tag = _tags[v]![0];
            _error = null;
            if (_selectedWalletId != null) {
              final app = context.read<AppState>();
              if (app.wallets.isNotEmpty) {
                final wallet = app.wallets.firstWhere((w) => w.id == _selectedWalletId, orElse: () => app.wallets.first);
                final methods = PaymentRails.getMethods(wallet.type, _tab);
                _selectedPaymentMethod = methods.first;
              }
            }
          }),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _tab == v ? c : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              l,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _tab == v ? Colors.white : AppTheme.secondaryText,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );

  Widget _banner(String t) => Container(
    padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(color: AppTheme.expenseBg, border: Border.all(color: AppTheme.expenseBorder), borderRadius: BorderRadius.circular(10)),
    child: Text(t, style: const TextStyle(color: AppTheme.expenseText, fontWeight: FontWeight.bold)),
  );

  Widget _row(String l, String v, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      Text(v, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w900 : FontWeight.bold, color: bold ? AppTheme.primaryGradientFallback : Colors.black)),
    ]),
  );
}
