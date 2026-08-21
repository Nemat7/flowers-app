import 'package:flutter/material.dart';

import '../../api/models/product.dart';
import '../../common/widgets/app_network_image.dart';
import '../../theme/colors.dart';

/// Карусель баннеров главной (макет v5 01-home, `.banners` + `.dots`):
/// карточки 300×108 с тёмным градиентом слева, подпись-тег зелёным,
/// заголовок белым; под каруселью — точки, активная вытянута в пилюлю.
class BannerCarousel extends StatefulWidget {
  const BannerCarousel({required this.banners, super.key});

  final List<PromoBanner> banners;

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  late final PageController _controller;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    // 300px карточка + 10px зазор на макете шириной 390 — следующая выглядывает.
    _controller = PageController(viewportFraction: 310 / 390);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: SizedBox(
            height: 108,
            child: PageView.builder(
              controller: _controller,
              padEnds: false,
              onPageChanged: (page) => setState(() => _page = page),
              itemCount: widget.banners.length,
              itemBuilder: (_, index) => Padding(
                padding: const EdgeInsets.only(left: 16),
                child: _BannerCard(banner: widget.banners[index]),
              ),
            ),
          ),
        ),
        if (widget.banners.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.banners.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: i == _page ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? AppColors.accent
                            : const Color(0xFFDEDEDE),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.banner});

  final PromoBanner banner;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppNetworkImage(
            url: banner.image,
            height: 108,
            placeholderSeed: banner.id,
          ),
          // .banner::after — затемнение слева направо под текст.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0x9E000000), Color(0x2E000000), Colors.transparent],
                stops: [0, 0.65, 1],
              ),
            ),
          ),
          Positioned(
            left: 14,
            bottom: 12,
            right: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (banner.tag.isNotEmpty)
                  Text(
                    banner.tag.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: Color(0xFF7BE3AE),
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  banner.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
