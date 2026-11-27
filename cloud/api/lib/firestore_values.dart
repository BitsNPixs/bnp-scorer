import 'package:googleapis/firestore/v1.dart';

/// Firestore's REST API wraps every field in a typed [Value]. These turn a
/// document into the plain JSON the app stores, and back.
Map<String, Object?> plainFields(Map<String, Value>? fields) => {
      for (final MapEntry(:key, :value) in (fields ?? const <String, Value>{}).entries)
        key: plainValue(value),
    };

Object? plainValue(Value value) {
  if (value.stringValue != null) return value.stringValue;
  if (value.integerValue != null) return int.parse(value.integerValue!);
  if (value.doubleValue != null) return value.doubleValue;
  if (value.booleanValue != null) return value.booleanValue;
  if (value.timestampValue != null) return value.timestampValue;
  if (value.mapValue != null) return plainFields(value.mapValue!.fields);
  if (value.arrayValue != null) {
    return [for (final v in value.arrayValue!.values ?? const <Value>[]) plainValue(v)];
  }
  return null;
}

Map<String, Value> typedFields(Map<String, Object?> json) => {
      for (final MapEntry(:key, :value) in json.entries) key: typedValue(value),
    };

Value typedValue(Object? value) => switch (value) {
      null => Value(nullValue: 'NULL_VALUE'),
      String v => Value(stringValue: v),
      bool v => Value(booleanValue: v),
      int v => Value(integerValue: '$v'),
      double v => Value(doubleValue: v),
      List<Object?> v => Value(arrayValue: ArrayValue(values: [for (final e in v) typedValue(e)])),
      Map<String, Object?> v => Value(mapValue: MapValue(fields: typedFields(v))),
      _ => throw ArgumentError('Cannot store ${value.runtimeType} in Firestore'),
    };
