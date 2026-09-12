import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:task_boss/theme.dart';
import 'package:task_boss/services/app_state.dart';

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
  String _channel = 'cash';
  String _tag = '';
  bool _saving = false;
  String? _error;

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
    // Tab is 'out'
    if (tag == 'Cash Withdrawal') return 'personal_partner';
    return 'outflow'; // Changed from 'business_expense'
  }

  Future<void> _submit() async {
    setState(() => _error = null);
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
    final app = context.read<AppState>();
    if (app.user == null) {
      setState(() => _error = 'Session expired. Please log in again.');
      return;
    }
    setState(() => _saving = true);
    try {
      final payload = {
        'idempotencyKey': const Uuid().v4(),
        'direction': _tab == 'in' ? 'in' : 'out',
        'amount': amt,
        'currency': 'BDT',
        'channel': _channel,
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
          'channel': _channel,
          'directionTab': _tab,
        },
      };

      final res = await http.post(
        Uri.parse('${app.apiBaseUrl}/ledger/movements'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${app.token}', 'x-company-id': app.user!.companyId},
        body: jsonEncode(payload),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        _amtCtl.clear(); _chgCtl.clear(); _noteCtl.clear();
        setState(() { _tag = _tags[_tab]![0]; });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Record saved successfully!'), backgroundColor: AppTheme.confirmedText));
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
    final amtVal = double.tryParse(_amtCtl.text.trim()) ?? 0.0;
    final feeVal = double.tryParse(_chgCtl.text.trim()) ?? 0.0;
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Record Money Movement', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryGradientFallback)),
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
            Row(children: [
              const Text('Note / Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              if (_isOtherTag) const Text(' * (Required)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.expenseText)),
            ]),
            const SizedBox(height: 6),
            TextField(
              controller: _noteCtl,
              decoration: InputDecoration(hintText: _isOtherTag ? "Required for 'Other'..." : "Note...", filled: true, fillColor: AppTheme.inputBg, border: const OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            const Text('Payment Channel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _channel,
              items: ['cash', 'bkash', 'nagad', 'bank', 'cheque', 'rtgs', 'npsb', 'other'].map((c) => DropdownMenuItem(value: c, child: Text(c.toUpperCase()))).toList(),
              onChanged: (v) => setState(() => _channel = v ?? 'cash'),
              decoration: const InputDecoration(filled: true, fillColor: AppTheme.inputBg, border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Base Amount (৳)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: _amtCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: '0.00', filled: true, fillColor: AppTheme.inputBg, border: OutlineInputBorder()), onChanged: (_) => setState(() {})),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Fee / Charge (৳)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: _chgCtl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: '0.00', filled: true, fillColor: AppTheme.inputBg, border: OutlineInputBorder()), onChanged: (_) => setState(() {})),
              ])),
            ]),
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGradientFallback, minimumSize: const Size(double.infinity, 50)),
              onPressed: _saving ? null : _submit,
              child: _saving ? const CircularProgressIndicator(color: Colors.white) : const Text('Save Record', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBtn(String l, String v, Color c) => Expanded(
    child: GestureDetector(
      onTap: () => setState(() { _tab = v; _tag = _tags[v]![0]; _error = null; }),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4), padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: _tab == v ? c : Colors.grey[200], borderRadius: BorderRadius.circular(8)),
        child: Text(l, textAlign: TextAlign.center, style: TextStyle(color: _tab == v ? Colors.white : AppTheme.secondaryText, fontWeight: FontWeight.bold)),
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
