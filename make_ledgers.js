const fs = require('fs');

const path = 'c:\\Users\\Task\\Desktop\\Task boss flutter\\lib\\screens\\suite\\suite_ledgers_screen.dart';

fs.writeFileSync(path, `import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';

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
      if (mounted) setState(() { _ledgers = results; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }
`, 'utf-8');

console.log('Part 1 written');
