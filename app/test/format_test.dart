import 'package:bnp_scorer/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rupees', () {
    test('groups thousands, then by two digits, the Indian way', () {
      expect(rupees(0), '₹0');
      expect(rupees(500), '₹500');
      expect(rupees(2500), '₹2,500');
      expect(rupees(25000), '₹25,000');
      expect(rupees(100000), '₹1,00,000');
      expect(rupees(12345678), '₹1,23,45,678');
    });

    test('keeps a minus sign in front', () {
      expect(rupees(-1500), '-₹1,500');
    });
  });
}
