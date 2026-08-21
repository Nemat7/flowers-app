import 'package:flowers_client/src/theme/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatSomoni', () {
    test('целая сумма — без копеек', () {
      expect(formatSomoni(450), '450 с.');
      expect(formatSomoni(350.00), '350 с.');
    });

    test('тысячи группируются пробелом', () {
      expect(formatSomoni(1250), '1 250 с.');
      expect(formatSomoni(1000000), '1 000 000 с.');
    });

    test('дробная сумма — два знака через запятую', () {
      expect(formatSomoni(10.5), '10,50 с.');
    });
  });

  group('formatPrice', () {
    test('decimal-строка API', () {
      expect(formatPrice('450.00'), '450 с.');
      expect(formatPrice('90.00'), '90 с.');
    });

    test('мусор → прочерк', () {
      expect(formatPrice(null), '—');
      expect(formatPrice('abc'), '—');
    });
  });

  group('formatDistance', () {
    test('метры и километры', () {
      expect(formatDistance(350), '350 м');
      expect(formatDistance(2303.9), '2,3 км');
      expect(formatDistance(null), '');
    });
  });

  group('formatRating', () {
    test('целый рейтинг без дробной части', () {
      expect(formatRating(5), '5');
      expect(formatRating(4.9), '4.9');
    });
  });
}
