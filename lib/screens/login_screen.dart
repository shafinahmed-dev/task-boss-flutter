import 'dart:convert';
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
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  bool _loading = false;
  String? _error;

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
          'email': _emailCtl.text.trim(),
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
        final userEmail = data['user']?['email'] ?? _emailCtl.text;

        if (custodianId.toString().isEmpty || companyId.toString().isEmpty || userId.toString().isEmpty) {
          throw Exception('User has no assigned user or company account.');
        }

        final designation = (data['user']?['designation'] ?? decodedPayload['designation'])?.toString() ?? '';
        final department = (data['user']?['department'] ?? decodedPayload['department'])?.toString() ?? '';

        final user = AuthUser(
          userId: userId.toString(),
          role: (data['user']?['role'] ?? decodedPayload['role'])?.toString() ?? 'collector',
          name: (data['user']?['name'] ?? userEmail)?.toString() ?? userEmail,
          email: userEmail.toString(),
          custodianId: custodianId.toString(),
          companyId: companyId.toString(),
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
                  'TASK BOS Login',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryGradientFallback,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _emailCtl,
                  decoration: _inputDecoration('Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passCtl,
                  decoration: _inputDecoration('Password'),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGradientFallback,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _loading ? null : _handleLogin,
                    child: _loading 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Login', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: AppTheme.expenseText, fontWeight: FontWeight.bold)),
                ],
                const SizedBox(height: 16),
                TextButton(
                  onPressed: widget.onSwitchToRegister,
                  child: const Text('Need an account? Register', style: TextStyle(color: AppTheme.primaryGradientStart)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
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
    );
  }
}
