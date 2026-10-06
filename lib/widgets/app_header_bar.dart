import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_boss/theme.dart';
import 'package:task_boss/services/app_state.dart';
import 'package:task_boss/screens/account_screen.dart';
import 'package:task_boss/widgets/notifications_sheet.dart';

class AppHeaderBar extends StatefulWidget {
  const AppHeaderBar({super.key});

  @override
  State<AppHeaderBar> createState() => _AppHeaderBarState();
}

class _AppHeaderBarState extends State<AppHeaderBar> {
  bool _showBalance = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _toggleBalance() {
    _hideTimer?.cancel();
    if (!_showBalance) {
      setState(() => _showBalance = true);
      _hideTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _showBalance = false);
      });
    } else {
      setState(() => _showBalance = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final userName = app.user?.name ?? 'User';
    final balance = app.balance;
    final pendingCount = app.pendingCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(gradient: AppTheme.slateCardGradient),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildUserPill(context, userName),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildBalancePill(balance),
              const SizedBox(width: 10),
              _buildNotificationBell(context, pendingCount),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserPill(BuildContext context, String userName) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AccountScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              userName,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: Color(0xFF475569),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalancePill(double balance) {
    return GestureDetector(
      onTap: _toggleBalance,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: _showBalance
              ? Row(
                  key: const ValueKey('balance_visible'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '৳${balance.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Icon(
                      Icons.visibility_outlined,
                      size: 14,
                      color: Color(0xFF64748B),
                    ),
                  ],
                )
              : const Row(
                  key: ValueKey('balance_hidden'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '৳ ••••••',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: Color(0xFF111827),
                      ),
                    ),
                    SizedBox(width: 5),
                    Icon(
                      Icons.visibility_off_outlined,
                      size: 14,
                      color: Color(0xFF64748B),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildNotificationBell(BuildContext context, int pendingCount) {
    return IconButton(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 24),
          if (pendingCount > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF161F2E),
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
      onPressed: () => NotificationsSheet.show(context),
    );
  }
}

