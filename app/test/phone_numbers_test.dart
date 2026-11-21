import 'package:bnp_scorer/data/phone_numbers.dart';
import 'package:flutter_test/flutter_test.dart';

// A made-up number: never put a real player's number in a test.
const _number = '+919876543210';

void main() {
  group('normalizePhone', () {
    test('reads an Indian mobile number however it is typed', () {
      for (final raw in [
        '9876543210',
        '98765 43210',
        '98765-43210',
        '098765 43210',
        '91 98765 43210',
        '+91 98765 43210',
        '+91-98765-43210',
        '(+91) 98765.43210',
        '0091 9876543210',
        ' +919876543210 ',
        '98765 43210',
      ]) {
        expect(normalizePhone(raw), _number, reason: raw);
      }
    });

    test("keeps another country's number given with its code", () {
      expect(normalizePhone('+44 7700 900123'), '+447700900123');
      expect(normalizePhone('0044 7700 900123'), '+447700900123');
      expect(normalizePhone('+1 (415) 555-0100'), '+14155550100');
    });

    test('refuses what cannot be a mobile number', () {
      for (final raw in [
        '',
        '   ',
        '12345',
        '1234567890', // an Indian mobile starts with 6 to 9
        '5876543210',
        '987654321', // nine digits
        '98765432101', // eleven digits, not starting 0
        '+91 5876543210',
        '+91 987654321',
        '+12345', // too short
        '+1234567890123456', // too long
        '98765 4321x',
        'Asha',
      ]) {
        expect(normalizePhone(raw), isNull, reason: raw);
      }
    });
  });

  test('maskPhone shows only the last four digits', () {
    expect(maskPhone(_number), '+91 •••• 3210');
    expect(maskPhone('+447700900123'), '•••• 0123');
  });

  group('phoneHash', () {
    test('is the lowercase hex SHA-256 of the E.164 text', () {
      expect(phoneHash(_number), 'f3a47ce5ce3d4ca8ad15225a245b2759022f79489f5c62719b8c9490f7aab90e');
      expect(phoneHash(normalizePhone('98765 43210')!), phoneHash(_number));
    });

    test('differs for different numbers', () {
      expect(phoneHash(_number), isNot(phoneHash('+919876543211')));
    });
  });
}
