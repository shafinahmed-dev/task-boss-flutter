import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:task_boss/theme.dart';
import 'package:task_boss/services/app_state.dart';

class RegisterScreen extends StatefulWidget {
  final VoidCallback onSwitchToLogin;
  const RegisterScreen({super.key, required this.onSwitchToLogin});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _designationController = TextEditingController();
  final _departmentController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _designationController.dispose();
    _departmentController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (_passwordController.text != _confirmController.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final appState = context.read<AppState>();
      final url = Uri.parse('${appState.apiBaseUrl}/auth/register');
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': _nameController.text.trim(),
          'designation': _designationController.text.trim(),
          'department': _departmentController.text.trim(),
          'email': _emailController.text.trim(),
          'phone': _phoneController.text.trim(),
          'password': _passwordController.text,
          'role': 'company_admin',
        }),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final prefs = await SharedPreferences.getInstance();
        if (_designationController.text.trim().isNotEmpty) {
          await prefs.setString('@user_designation', _designationController.text.trim());
        }
        if (_departmentController.text.trim().isNotEmpty) {
          await prefs.setString('@user_department', _departmentController.text.trim());
        }
        widget.onSwitchToLogin();
      } else {
        final data = jsonDecode(resp.body);
        final msg = data['message'];
        final errStr = msg is List ? msg.join(', ') : (msg?.toString() ?? 'Registration failed');
        throw Exception(errStr);
      }
    } catch (e, stack) {
      debugPrint('Registration connection error: $e\n$stack');
      String errorMsg = e.toString().replaceFirst('Exception: ', '');
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
                  'Register Admin',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryGradientFallback,
                  ),
                ),
                const SizedBox(height: 24),
                _buildField(_nameController, 'Name'),
                _buildField(_designationController, 'Designation (e.g., Accounts Manager)'),
                _buildField(_departmentController, 'Department (e.g., Finance & Operations)'),
                _buildField(_emailController, 'Email', keyboard: TextInputType.emailAddress),
                _buildField(_phoneController, 'Phone', keyboard: TextInputType.phone),
                _buildField(_passwordController, 'Password', obscure: true),
                _buildField(_confirmController, 'Confirm Password', obscure: true),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGradientFallback,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _loading ? null : _handleRegister,
                    child: _loading 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Register', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: AppTheme.expenseText, fontWeight: FontWeight.bold)),
                ],
                const SizedBox(height: 16),
                TextButton(
                  onPressed: widget.onSwitchToLogin,
                  child: const Text('Already have an account? Login', style: TextStyle(color: AppTheme.primaryGradientStart)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String hint, {bool obscure = false, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
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
        ),
        obscureText: obscure,
        keyboardType: keyboard,
      ),
    );
  }
}
