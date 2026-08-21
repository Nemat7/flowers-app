import 'package:flutter/material.dart';

import '../profile/profile_screen.dart';
import 'courier_earnings_screen.dart';
import 'courier_orders_screen.dart';

/// Корневой экран курьера (роль courier): нижняя навигация
/// Заказы / Заработок / Профиль.
class CourierShell extends StatefulWidget {
  const CourierShell({super.key});

  @override
  State<CourierShell> createState() => _CourierShellState();
}

class _CourierShellState extends State<CourierShell> {
  int _index = 0;

  final _screens = const [
    CourierOrdersScreen(),
    CourierEarningsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'Заказы',
          ),
          NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            selectedIcon: Icon(Icons.payments),
            label: 'Заработок',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }
}
