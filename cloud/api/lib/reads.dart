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
  /// those stage names; [before] continues after the card with that
  /// `sourceUpdateTime`.
  Future<List<Json>> cards({required int limit, List<String>? stages, String? before});
}

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
  Future<List<Json>> cards({required int limit, List<String>? stages, String? before}) async {
    final query = StructuredQuery(
      from: [CollectionSelector(collectionId: cardsCollection)],
      where: stages == null
          ? null
          : Filter(
              fieldFilter: FieldFilter(
                field: FieldReference(fieldPath: 'stage'),
                op: 'IN',
                value: Value(arrayValue: ArrayValue(values: [for (final s in stages) Value(stringValue: s)])),
              ),
            ),
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
