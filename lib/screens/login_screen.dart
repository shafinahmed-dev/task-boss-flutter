import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:task_boss/theme.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/models/models.dart';
import 'package:task_boss/screens/main_navigation.dart';

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

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const MainNavigation()),
            (route) => false,
          );
        }
      } else {
        final data = jsonDecode(resp.body);
        final msg = data['message'];
        throw Exception(msg is List ? msg.join(', ') : (msg?.toString() ?? 'Invalid credentials. Please try again.'));
      }
    } catch (e) {
      String errorMsg;
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('socketexception') || errStr.contains('clientexception') || errStr.contains('failed host lookup') || errStr.contains('connection')) {
        errorMsg = 'Unable to connect to the server. Please check your internet connection.';
      } else if (errStr.contains('timeoutexception')) {
        errorMsg = 'Request timed out. Please try again.';
      } else {
        errorMsg = e.toString().replaceAll('Exception: ', '').replaceAll('FormatException: ', '').trim();
        if (errorMsg.isEmpty || errorMsg.contains('null')) {
          errorMsg = 'Incorrect handle or password. Please try again.';
        }
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
        if (!mounted) return;
        setState(() {
          _handleCtl.text = result;
          _passCtl.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Company registered! Please sign in with your Suite handle.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            backgroundColor: AppTheme.inflowText,
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
                    color: AppTheme.mutedText,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _handleCtl,
                  decoration: InputDecoration(
                    labelText: 'User Handle',
                    hintText: 'e.g. suite.taskgroup etc.',
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
                      icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility, color: AppTheme.mutedText),
                      onPressed: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                  obscureText: _obscurePass,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: AppTheme.slateButtonGradient,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: _loading ? null : _handleLogin,
                      child: _loading 
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Login', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
                if (_error != null && _error!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Color(0xFFEF4444), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFB91C1C),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: _showCompanyRegistration,
                  icon: const Icon(Icons.domain_add_rounded, color: AppTheme.primaryGradientStart),
                  label: const Text('Register Workspace', style: TextStyle(color: AppTheme.primaryGradientStart, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RegisterCompanyForm extends StatefulWidget {
  const _RegisterCompanyForm();
  @override
  State<_RegisterCompanyForm> createState() => _RegisterCompanyFormState();
}

class _RegisterCompanyFormState extends State<_RegisterCompanyForm> {
  final _nameCtl = TextEditingController();
  final _slugCtl = TextEditingController();
  final _passCtl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscurePass = true;

  @override
  void dispose() {
    _nameCtl.dispose();
    _slugCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final appState = context.read<AppState>();
      final url = Uri.parse('${appState.apiBaseUrl}/auth/register-company');
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'companyName': _nameCtl.text.trim(),
          'slug': _slugCtl.text.trim(),
          'password': _passCtl.text,
        }),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = jsonDecode(resp.body);
        if (!mounted) return;
        Navigator.pop(context, data['handle']?.toString());
      } else {
        final data = jsonDecode(resp.body);
        final msg = data['message'];
        throw Exception(msg is List ? msg.join(', ') : (msg?.toString() ?? 'Registration failed'));
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.domain_rounded, color: AppTheme.primaryGradientStart, size: 28),
            SizedBox(width: 8),
            Text('Register Company Workspace', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _nameCtl,
          decoration: _inputDecoration('Company Name (e.g. TASK Group)'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _slugCtl,
          onChanged: (_) => setState(() {}),
          decoration: _inputDecoration('Company Slug (e.g. taskgroup)'),
        ),
        if (_slugCtl.text.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              'Your master handle will be: suite.${_slugCtl.text.trim().toLowerCase().replaceAll(RegExp(r"[^a-z0-9]"), "")}',
              style: const TextStyle(color: AppTheme.inflowText, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 16),
        TextField(
          controller: _passCtl,
          obscureText: _obscurePass,
          decoration: _inputDecoration('Master Suite Password').copyWith(
            suffixIcon: IconButton(
              icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility, color: AppTheme.mutedText),
              onPressed: () => setState(() => _obscurePass = !_obscurePass),
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: AppTheme.expenseText, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
        ],
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryGradientStart,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: _loading ? null : _submit,
          child: _loading ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Create Workspace', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppTheme.inputBg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.inputBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.inputBorder)),
    );
  }
}

