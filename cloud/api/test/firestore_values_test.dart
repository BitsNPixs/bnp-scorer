import 'package:bnp_api/firestore_values.dart';
import 'package:test/test.dart';

void main() {
  test('plain JSON survives the trip through Firestore values', () {
    final json = <String, Object?>{
      'name': 'Kings',
      'runs': 42,
      'rate': 7.5,
      'live': true,
      'none': null,
      'balls': [1, 'W', <String, Object?>{'k': 4}],
      'setup': <String, Object?>{'overs': 6, 'empty': <Object?>[]},
    };
    expect(plainFields(typedFields(json)), json);
  });
}
