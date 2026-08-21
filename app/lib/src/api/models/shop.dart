/// Магазин из `GET /shops/` (список) и `GET /shops/{id}/` (детали).
/// Decimal-поля API приходят строками («50.00») — парсим в double.
class Shop {
  const Shop({
    required this.id,
    required this.name,
    required this.rating,
    required this.ratingCount,
    required this.minOrder,
    required this.isOpen,
    this.logo,
    this.coverPhoto,
    this.isOwn = false,
    this.kind,
    this.deliveryFeeFrom,
    this.deliveryTimeEst,
    this.distanceM,
    this.description,
    this.addressText,
    this.phone,
    this.cardPrice,
    this.workingHours = const [],
  });

  factory Shop.fromJson(Map<String, dynamic> json) => Shop(
        id: json['id'] as int,
        name: json['name'] as String,
        logo: json['logo'] as String?,
        coverPhoto: json['cover_photo'] as String?,
        isOwn: json['is_own'] as bool? ?? false,
        kind: json['kind'] as String?,
        deliveryFeeFrom: (json['delivery_fee_from'] as num?)?.toDouble(),
        rating: double.tryParse('${json['rating']}') ?? 0,
        ratingCount: json['rating_count'] as int? ?? 0,
        deliveryTimeEst: json['delivery_time_est'] as int?,
        minOrder: double.tryParse('${json['min_order']}') ?? 0,
        isOpen: json['is_open'] as bool? ?? false,
        distanceM: (json['distance_m'] as num?)?.toDouble(),
        description: json['description'] as String?,
        addressText: json['address_text'] as String?,
        phone: json['phone'] as String?,
        cardPrice: double.tryParse('${json['card_price']}'),
        workingHours: (json['working_hours'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(WorkingHours.fromJson)
            .toList(),
      );

  final int id;
  final String name;
  final String? logo;

  /// Обложка витрины для карточки на главной; если пусто — падаем на [logo].
  final String? coverPhoto;

  /// Магазин платформы — бейдж «Наш магазин» (макет v5 01-home).
  final bool isOwn;

  /// Профиль магазина по его товарам: «Цветы», «Сладости».
  final String? kind;

  /// «Доставка от X с.» — минимальная база по зонам; точная сумма — при оформлении.
  final double? deliveryFeeFrom;
  final double rating;
  final int ratingCount;
  final int? deliveryTimeEst;
  final double minOrder;
  final bool isOpen;
  final double? distanceM;

  // Детальные поля (только из /shops/{id}/).
  final String? description;
  final String? addressText;
  final String? phone;
  final double? cardPrice;
  final List<WorkingHours> workingHours;

  /// Картинка карточки: обложка витрины, а логотип — только как запасной вариант.
  String? get coverImage {
    final cover = coverPhoto;
    return (cover != null && cover.isNotEmpty) ? cover : logo;
  }

  /// «35–45 мин» — оценка с запасом, как в макетах (сервер даёт одно число).
  String? get deliveryTimeRange {
    final estimate = deliveryTimeEst;
    return estimate == null ? null : '$estimate–${estimate + 10} мин';
  }

  /// «Открыто до 22:00» — по часам работы сегодняшнего дня, если известны.
  String? get openUntilLabel {
    if (!isOpen) return null;
    // Backend: weekday 0 = понедельник; Dart DateTime.monday = 1.
    final todayBackendWeekday = DateTime.now().weekday - 1;
    for (final hours in workingHours) {
      if (hours.weekday == todayBackendWeekday && !hours.isDayOff) {
        final close = hours.closeTime;
        if (close != null && close.length >= 5) {
          return 'Открыто до ${close.substring(0, 5)}';
        }
      }
    }
    return null;
  }
}

class WorkingHours {
  const WorkingHours({
    required this.weekday,
    this.openTime,
    this.closeTime,
    this.isDayOff = false,
  });

  factory WorkingHours.fromJson(Map<String, dynamic> json) => WorkingHours(
        weekday: json['weekday'] as int,
        openTime: json['open_time'] as String?,
        closeTime: json['close_time'] as String?,
        isDayOff: json['is_day_off'] as bool? ?? false,
      );

  final int weekday;
  final String? openTime;
  final String? closeTime;
  final bool isDayOff;
}
