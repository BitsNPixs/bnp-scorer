import 'package:cricket_engine/cricket_engine.dart' show Json;
import 'package:googleapis/firestore/v1.dart';

import 'firestore_values.dart';
import 'store.dart';

/// The stored copies, for reading only. Firestore in production (with an
/// account that cannot write), a fake in tests.
abstract interface class MatchReads {
  /// A match's full view, or null when there is none.
  Future<Json?> view(String id);

  /// Cards, the most recently saved match first. [stages] narrows them to
  /// those stage names, [savedSince] to matches saved at or after that time
  /// and [savedBefore] to ones saved earlier; [before] continues after the
  /// card with that `sourceUpdateTime`.
  Future<List<Json>> cards({
    required int limit,
    List<String>? stages,
    DateTime? savedSince,
    DateTime? savedBefore,
    String? before,
  });
}

/// [time] to the second, as the start of how Firestore writes a save time
/// ("2026-11-27T10:05:01"), to compare as text with a card's
/// `sourceUpdateTime`. It has no fraction and no closing "Z" on purpose:
/// every save in or after that second ("…:01Z", "…:01.5Z") then sorts at or
/// after it, and every earlier save before it. With the "Z", a save at
/// "…:01.5Z" would sort before "…:01Z".
String saveTimeText(DateTime time) => time.toUtc().toIso8601String().substring(0, 19);

class FirestoreMatchReads implements MatchReads {
  FirestoreMatchReads(FirestoreApi api, String project)
      : _docs = api.projects.databases.documents,
        _root = 'projects/$project/databases/(default)/documents';

  final ProjectsDatabasesDocumentsResource _docs;
  final String _root;

  @override
  Future<Json?> view(String id) async {
    try {
      return plainFields((await _docs.get('$_root/$viewsCollection/$id')).fields);
    } on DetailedApiRequestError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  /// Ordered by Firestore's save time of the match, which no phone's clock
  /// can upset. With [stages] it needs the index in `firestore.indexes.json`.
  @override
  Future<List<Json>> cards({
    required int limit,
    List<String>? stages,
    DateTime? savedSince,
    DateTime? savedBefore,
    String? before,
  }) async {
    Filter saved(String op, DateTime time) => Filter(
          fieldFilter: FieldFilter(
            field: FieldReference(fieldPath: 'sourceUpdateTime'),
            op: op,
            value: Value(stringValue: saveTimeText(time)),
          ),
        );
    final filters = [
      if (stages != null)
        Filter(
          fieldFilter: FieldFilter(
            field: FieldReference(fieldPath: 'stage'),
            op: 'IN',
            value: Value(arrayValue: ArrayValue(values: [for (final s in stages) Value(stringValue: s)])),
          ),
        ),
      if (savedSince != null) saved('GREATER_THAN_OR_EQUAL', savedSince),
      if (savedBefore != null) saved('LESS_THAN', savedBefore),
    ];
    final query = StructuredQuery(
      from: [CollectionSelector(collectionId: cardsCollection)],
      where: switch (filters) {
        [] => null,
        [final only] => only,
        _ => Filter(compositeFilter: CompositeFilter(op: 'AND', filters: filters)),
      },
      orderBy: [Order(field: FieldReference(fieldPath: 'sourceUpdateTime'), direction: 'DESCENDING')],
      startAt: before == null ? null : Cursor(values: [Value(stringValue: before)], before: false),
      limit: limit,
    );
    final rows = await _docs.runQuery(RunQueryRequest(structuredQuery: query), _root);
    return [
      for (final row in rows)
        if (row.document case final doc?) plainFields(doc.fields),
    ];
  }
}
