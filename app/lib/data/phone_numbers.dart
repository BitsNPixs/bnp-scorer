import 'dart:convert';

import 'package:crypto/crypto.dart';

/// India, where nearly every BNP Scorer player is. A number typed without a
/// country code is read as Indian.
const indiaCode = '+91';

final _separators = RegExp(r'[\s\-.() ]');
final _digits = RegExp(r'^\d+$');
final _indianMobile = RegExp(r'^[6-9]\d{9}$');

/// [raw] as an E.164 number such as +919876543210, or null when it cannot be
/// one. Spaces, dashes, dots and brackets are ignored, a leading 00 means +,
/// and a ten-digit Indian mobile number needs no code: 98765 43210,
/// 098765 43210 and 91 98765 43210 all give +919876543210. Any other country
/// needs its + code.
String? normalizePhone(String raw) {
  var number = raw.trim().replaceAll(_separators, '');
  if (number.startsWith('00')) number = '+${number.substring(2)}';
  if (number.startsWith('+')) {
    final digits = number.substring(1);
    if (!_digits.hasMatch(digits) || digits.length < 8 || digits.length > 15) return null;
    if (number.startsWith(indiaCode)) {
      return _indianMobile.hasMatch(digits.substring(2)) ? number : null;
    }
    return number;
  }
  if (!_digits.hasMatch(number)) return null;
  final local = switch (number.length) {
    10 => number,
    11 when number.startsWith('0') => number.substring(1),
    12 when number.startsWith('91') => number.substring(2),
    _ => null,
  };
  return local != null && _indianMobile.hasMatch(local) ? '$indiaCode$local' : null;
}

/// An E.164 number with all but its last four digits hidden, for showing a
/// player their own number: +91 •••• 3210.
String maskPhone(String e164) {
  final tail = e164.substring(e164.length - 4);
  return e164.startsWith(indiaCode) ? '$indiaCode •••• $tail' : '•••• $tail';
}

/// The key a number is looked up by in the cloud: SHA-256 of the E.164 text,
/// in lowercase hex. The number itself is never stored there.
String phoneHash(String e164) => sha256.convert(utf8.encode(e164)).toString();
