import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../theme/colors.dart';
import 'refund_policy_screen.dart';

/// Профиль клиента (макет v5 05-profile): имя крупным + круглый аватар,
/// 3 серые плитки, строки с иконками, «Выйти» серым.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    user?.displayName ?? '—',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.accent,
                  child: Text(
                    _initials(user?.displayName),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            if (user != null) ...[
              const SizedBox(height: 4),
              Text(
                user.phone,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Row(
              children: [
                _Tile(icon: Icons.favorite_border_rounded, label: 'Избранное'),
                SizedBox(width: 10),
                _Tile(icon: Icons.location_on_outlined, label: 'Адреса'),
                SizedBox(width: 10),
                _Tile(icon: Icons.receipt_long_rounded, label: 'Заказы'),
              ],
            ),
            const SizedBox(height: 14),
            const _Row(icon: Icons.notifications_outlined, label: 'Уведомления'),
            const _Row(icon: Icons.local_offer_outlined, label: 'Промокоды'),
            const _Row(icon: Icons.help_outline_rounded, label: 'Помощь'),
            _Row(
              icon: Icons.assignment_return_outlined,
              label: 'Правила возврата',
              onTap: () => openRefundPolicy(context),
            ),
            const _Row(
              icon: Icons.language_rounded,
              label: 'Язык',
              value: 'Русский',
            ),
            const _Row(icon: Icons.info_outline_rounded, label: 'О приложении'),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => context.read<AuthController>().logout(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2, vertical: 14),
                child: Text(
                  'Выйти',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Инициалы для аватара: первые буквы двух слов (или одна буква телефона).
  static String _initials(String? displayName) {
    if (displayName == null || displayName.isEmpty) return '?';
    final words =
        displayName.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }
}

/// Серая плитка быстрого доступа (визуально; разделы — следующие этапы).
class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: AppColors.textPrimary),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Строка-раздел с иконкой (разделы без [onTap] — следующие этапы).
class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, this.value, this.onTap});

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 15),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textPrimary),
          const SizedBox(width: 14),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (value != null) ...[
            const Spacer(),
            Text(
              value!,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}
