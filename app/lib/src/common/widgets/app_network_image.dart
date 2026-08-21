import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../api/api_client.dart';

/// Обложка магазина/фото товара: cached_network_image,
/// при отсутствии фото — нейтральный градиент-плейсхолдер с иконкой.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    required this.url,
    required this.height,
    this.placeholderSeed = 0,
    this.placeholderIcon = Icons.local_florist,
    super.key,
  });

  final String? url;
  final double height;

  /// Меняет оттенок плейсхолдера (например, id сущности).
  final int placeholderSeed;
  final IconData placeholderIcon;

  static const _gradients = [
    [Color(0xFFF1F1F1), Color(0xFFD8D8D8)],
    [Color(0xFFE5F8EE), Color(0xFF9BDEBE)],
    [Color(0xFFEFEFEF), Color(0xFFC9C9C9)],
    [Color(0xFFEAF4EE), Color(0xFFB5D9C6)],
  ];

  @override
  Widget build(BuildContext context) {
    final resolved = resolveMediaUrl(url);
    if (resolved == null) return _placeholder();
    return CachedNetworkImage(
      imageUrl: resolved,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      placeholder: (_, _) => _placeholder(),
      errorWidget: (_, _, _) => _placeholder(),
    );
  }

  Widget _placeholder() {
    final colors =
        _gradients[placeholderSeed.abs() % _gradients.length];
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Icon(
          placeholderIcon,
          size: height.isFinite ? height / 3 : 40,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}
