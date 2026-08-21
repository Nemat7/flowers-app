import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../auth/screens/phone_screen.dart';
import '../courier/courier_shell.dart';
import '../shell/main_shell.dart';
import '../theme/colors.dart';

/// Splash/auth-gate: валидная сессия → главная по роли, иначе OTP-вход.
/// Роль courier → курьерский интерфейс (CourierShell), остальные — клиентский.
/// Сплеш показываем минимум 1.2 c, даже если auth готов раньше.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _minDelayPassed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _minDelayPassed = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (auth.status == AuthStatus.unknown || !_minDelayPassed) {
      return const SplashScreen();
    }
    return switch (auth.status) {
      AuthStatus.unknown => const SplashScreen(),
      AuthStatus.unauthenticated => const PhoneScreen(),
      AuthStatus.authenticated => auth.user?.role == 'courier'
          ? const CourierShell()
          : const MainShell(),
    };
  }
}

/// Сплеш (v5): белый экран, зелёный круглый badge с белым цветком,
/// название Inter 800.
/// TODO(brand): заменить иконку-заглушку на фирменный логотип, когда будет.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_florist,
                size: 46,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Flowers & Sweets',
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
