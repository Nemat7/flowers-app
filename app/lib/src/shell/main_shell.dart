import 'package:flutter/material.dart';

import '../home/home_screen.dart';
import '../orders/orders_screen.dart';
import '../profile/profile_screen.dart';
import '../search/search_screen.dart';
import '../theme/theme.dart';

/// Высота плавающего таббара с отступом снизу — контент экранов
/// должен оставлять столько места снизу, чтобы круги его не перекрывали.
const double kFloatingTabBarClearance = 92;

/// Корневой экран после входа (макеты v5): плавающие раздельные круги
/// без общей подложки — Главная / Поиск (овал) / Заказы / Профиль.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  final _ordersKey = GlobalKey<OrdersScreenState>();

  late final _screens = [
    const HomeScreen(),
    const SearchScreen(),
    OrdersScreen(key: _ordersKey),
    const ProfileScreen(),
  ];

  void _select(int index) {
    setState(() => _index = index);
    // Свежие заказы при каждом открытии вкладки (после оплаты и т.п.).
    if (index == 2) _ordersKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _index, children: _screens),
          Positioned(
            left: 20,
            right: 20,
            bottom: bottom + 18,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _TabCircle(
                  icon: Icons.home_rounded,
                  selected: _index == 0,
                  onTap: () => _select(0),
                ),
                _TabCircle(
                  icon: Icons.search_rounded,
                  label: 'Поиск',
                  selected: _index == 1,
                  onTap: () => _select(1),
                ),
                _TabCircle(
                  icon: Icons.receipt_long_rounded,
                  selected: _index == 2,
                  onTap: () => _select(2),
                ),
                _TabCircle(
                  icon: Icons.person_rounded,
                  selected: _index == 3,
                  onTap: () => _select(3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Один таб: белый круг 52px с тенью; активный — чёрный, иконка белая.
/// Таб с [label] — овальный («Поиск» в макетах v5).
class _TabCircle extends StatelessWidget {
  const _TabCircle({
    required this.icon,
    required this.selected,
    required this.onTap,
    this.label,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? Colors.white : const Color(0xFF757575);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: label == null ? null : const EdgeInsets.symmetric(horizontal: 18),
        width: label == null ? 52 : null,
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(999),
          boxShadow: kFloatingShadow,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: foreground),
            if (label != null) ...[
              const SizedBox(width: 7),
              Text(
                label!,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
