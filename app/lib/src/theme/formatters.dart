/// Форматтеры отображения (цены в сомони, расстояния, рейтинг).
library;

/// «450 с.», «1 250 с.», «450,50 с.» — без копеек, если сумма целая.
String formatSomoni(num value) {
  final intPart = value.truncate();
  final frac = ((value - intPart) * 100).round();
  final buffer = StringBuffer(_groupThousands(intPart));
  if (frac != 0) {
    buffer
      ..write(',')
      ..write(frac.toString().padLeft(2, '0'));
  }
  buffer.write(' с.');
  return buffer.toString();
}

/// Парсит decimal-строку API («350.00») и форматирует как цену.
String formatPrice(String? raw) {
  final value = double.tryParse(raw ?? '');
  return value == null ? '—' : formatSomoni(value);
}

String _groupThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    buffer.write(digits[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(' ');
  }
  return buffer.toString();
}

/// «350 м» / «1,2 км». Null (детальный ответ без координат) → пусто.
String formatDistance(double? meters) {
  if (meters == null) return '';
  if (meters < 1000) return '${meters.round()} м';
  final km = meters / 1000;
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} км';
}

/// «4.9» — одна цифра после точки, целые без дробной части.
String formatRating(double rating) {
  return rating == rating.roundToDouble()
      ? rating.round().toString()
      : rating.toStringAsFixed(1);
}
