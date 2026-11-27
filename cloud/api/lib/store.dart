import 'package:cricket_engine/cricket_engine.dart' show Json;
import 'package:googleapis/firestore/v1.dart';

import 'firestore_values.dart';

/// A published match as the scorer's app saved it.
class SourceMatch {
  const SourceMatch({required this.id, required this.data, required this.updateTime});

  final String id;
  final Json data;

  /// When Firestore last saved it, as Firestore wrote it.
  final String updateTime;
}

/// What is known about a match's stored copy before replacing it.
class CopyState {
  const CopyState({required this.sourceUpdateTime, required this.updateTime});

  /// The save of the match the copy was made from. Null on a damaged copy.
  final String? sourceUpdateTime;

  /// When the copy itself was last written, to notice a rival write.
  final String updateTime;
}

/// Another writer replaced the copy between reading and writing it.
class CopyChanged implements Exception {
  const CopyChanged();
}

/// Where matches are read and their copies kept. Firestore in production,
/// a fake in tests.
abstract interface class MatchStore {
  /// Null when the match is not (or no longer) published.
  Future<SourceMatch?> readMatch(String id);

  /// Null when the match has no copy yet.
  Future<CopyState?> readCopy(String id);

  /// Writes both copies together. Throws [CopyChanged] when the copy is no
  /// longer as [seen] (null: there was none).
  Future<void> writeCopies(String id, {required Json card, required Json view, required CopyState? seen});

  Future<void> deleteCopies(String id);

  /// Every published match, a page at a time, for a rebuild.
  Future<({List<SourceMatch> matches, String? nextPageToken})> listMatches({String? pageToken, int pageSize = 50});
}

/// The collections the copies live in. Names are a storage format the
/// website, the API and later the app read: never rename them.
const cardsCollection = 'matchCards';
const viewsCollection = 'matchViews';

class FirestoreMatchStore implements MatchStore {
  FirestoreMatchStore(FirestoreApi api, String project)
      : _docs = api.projects.databases.documents,
        _database = 'projects/$project/databases/(default)';

  final ProjectsDatabasesDocumentsResource _docs;
  final String _database;

  String get _root => '$_database/documents';

  /// The gRPC status names Firestore answers with when a write's
  /// precondition no longer holds.
  static const _conflicts = {'FAILED_PRECONDITION', 'ALREADY_EXISTS', 'ABORTED', 'NOT_FOUND'};

  @override
  Future<SourceMatch?> readMatch(String id) async {
    try {
      return _source(await _docs.get('$_root/matches/$id'));
    } on DetailedApiRequestError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  @override
  Future<CopyState?> readCopy(String id) async {
    try {
      final doc = await _docs.get('$_root/$viewsCollection/$id', mask_fieldPaths: ['sourceUpdateTime']);
      return CopyState(
        sourceUpdateTime: plainFields(doc.fields)['sourceUpdateTime'] as String?,
        updateTime: doc.updateTime!,
      );
    } on DetailedApiRequestError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> writeCopies(String id, {required Json card, required Json view, required CopyState? seen}) async {
    final request = CommitRequest(writes: [
      Write(update: Document(name: '$_root/$cardsCollection/$id', fields: typedFields(card))),
      Write(
        update: Document(name: '$_root/$viewsCollection/$id', fields: typedFields(view)),
        currentDocument: seen == null ? Precondition(exists: false) : Precondition(updateTime: seen.updateTime),
      ),
    ]);
    try {
      await _docs.commit(request, _database);
    } on DetailedApiRequestError catch (e) {
      final error = e.jsonResponse?['error'];
      if (error is Map && _conflicts.contains(error['status'])) throw const CopyChanged();
      rethrow;
    }
  }

  @override
  Future<void> deleteCopies(String id) => _docs.commit(
        CommitRequest(writes: [
          Write(delete: '$_root/$cardsCollection/$id'),
          Write(delete: '$_root/$viewsCollection/$id'),
        ]),
        _database,
      );

  @override
  Future<({List<SourceMatch> matches, String? nextPageToken})> listMatches({String? pageToken, int pageSize = 50}) async {
    final page = await _docs.list(_root, 'matches', pageSize: pageSize, pageToken: pageToken);
    return (
      matches: [for (final doc in page.documents ?? const <Document>[]) _source(doc)],
      nextPageToken: page.nextPageToken,
    );
  }

  SourceMatch _source(Document doc) => SourceMatch(
        id: doc.name!.split('/').last,
        data: plainFields(doc.fields),
        updateTime: doc.updateTime!,
      );
}
