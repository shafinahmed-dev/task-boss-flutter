import json

code = """import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:task_boss/theme.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/models/models.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onSwitchToRegister;
  const LoginScreen({super.key, required this.onSwitchToRegister});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _handleCtl = TextEditingController();
  final _passCtl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscurePass = true;

  @override
  void dispose() {
    _handleCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final appState = context.read<AppState>();
      final url = Uri.parse('${appState.apiBaseUrl}/auth/login');
      final resp = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'handle': _handleCtl.text.trim(),
          'password': _passCtl.text,
        }),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = jsonDecode(resp.body);
        final token = data['access_token'];
        
        final jwtParts = token.split('.');
        if (jwtParts.length != 3) throw Exception('Invalid token');
        
        String normalized = base64Url.normalize(jwtParts[1]);
        String payloadString = utf8.decode(base64Url.decode(normalized));
        final decodedPayload = jsonDecode(payloadString);
        
        final companyId = (data['user']?['companyIds'] != null && data['user']['companyIds'].isNotEmpty) 
            ? data['user']['companyIds'][0] 
            : (decodedPayload['companyIds'] != null && decodedPayload['companyIds'].isNotEmpty) 
                ? decodedPayload['companyIds'][0] 
                : '';
        final custodianId = data['user']?['custodianId'] ?? '';
        final userId = data['user']?['id'] ?? decodedPayload['sub'] ?? '';
        
        final userHandle = data['user']?['handle'] ?? decodedPayload['handle'] ?? _handleCtl.text;
        final tenantId = data['user']?['tenantId'] ?? decodedPayload['tenantId'];

        if (custodianId.toString().isEmpty || companyId.toString().isEmpty || userId.toString().isEmpty) {
          throw Exception('User has no assigned user or company account.');
        }

        final designation = (data['user']?['designation'] ?? decodedPayload['designation'])?.toString() ?? '';
        final department = (data['user']?['department'] ?? decodedPayload['department'])?.toString() ?? '';

        final user = AuthUser(
          userId: userId.toString(),
          handle: userHandle.toString(),
          role: (data['user']?['role'] ?? decodedPayload['role'])?.toString() ?? 'EMPLOYEE',
          name: (data['user']?['name'] ?? userHandle)?.toString() ?? userHandle,
          email: (data['user']?['email'])?.toString() ?? '',
          custodianId: custodianId.toString(),
          companyId: companyId.toString(),
          tenantId: tenantId?.toString(),
          designation: designation,
          department: department,
        );

        await appState.login(token, user);
      } else {
        final data = jsonDecode(resp.body);
        final msg = data['message'];
        final errStr = msg is List ? msg.join(', ') : (msg?.toString() ?? 'Login failed');
        throw Exception(errStr);
      }
    } catch (e, stack) {
      debugPrint('Login connection error: $e\n$stack');
      String errorMsg = 'Login failed. Network or server error: ${e.toString()}';
      if (e.toString().contains('SocketException') || e.toString().contains('ClientException') || e.toString().contains('Failed host lookup')) {
        errorMsg = 'Unable to reach server. Please check your internet connection.';
      } else if (e.toString().contains('TimeoutException')) {
        errorMsg = 'Request timed out. Please try again.';
      }
      setState(() => _error = errorMsg);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showCompanyRegistration() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: const _RegisterCompanyForm(),
        ),
      ),
    ).then((result) {
      if (result != null && result is String) {
        setState(() {
          _handleCtl.text = result;
          _passCtl.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Company registered! Please sign in with your Suite handle.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            backgroundColor: AppTheme.incomeText,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'TASK BOS',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryGradientFallback,
                  ),
                ),
                const Text(
                  'Enterprise Suite',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _handleCtl,
                  decoration: InputDecoration(
                    labelText: 'User Handle',
                    hintText: 'e.g. suite.taskgroup or shafinahmed.taskgroup',
                    filled: true,
                    fillColor: AppTheme.inputBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.inputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.inputBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passCtl,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    filled: true,
                    fillColor: AppTheme.inputBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.inputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.inputBorder),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility, color: AppTheme.textMuted),
                      onPressed: () => s
