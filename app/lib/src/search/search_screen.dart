import 'package:flutter/material.dart';

import '../shell/placeholder_screen.dart';

/// Поиск по магазинам и букетам — следующий этап (макеты v5, таб «Поиск»).
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const PlaceholderScreen(title: 'Поиск', icon: Icons.search_rounded);
}
