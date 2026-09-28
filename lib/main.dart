import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_boss/theme.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/screens/login_screen.dart';
import 'package:task_boss/screens/register_screen.dart';
import 'package:task_boss/screens/main_navigation.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: const MainApp(),
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Task BOS',
      theme: AppTheme.themeData,
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool isLoginMode = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (!appState.isReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (appState.user == null || appState.token == null) {
      if (isLoginMode) {
        return LoginScreen(
          onSwitchToRegister: () => setState(() => isLoginMode = false),
        );
      } else {
        return RegisterScreen(
          onSwitchToLogin: () => setState(() => isLoginMode = true),
        );
      }
    }

    return const MainNavigation();
  }
}
