import 'package:shared_preferences/shared_preferences.dart';

import 'local_documents.dart';
import 'match_record.dart';
import 'match_repository.dart';

/// Offline-first storage on the device. Each match is one JSON document.
class LocalMatchRepository implements MatchRepository {
  LocalMatchRepository(SharedPreferences prefs)
      : _documents = LocalDocuments(
          prefs: prefs,
          indexKey: 'bnp_scorer.matchIds',
          keyPrefix: 'bnp_scorer.match.',
          fromJson: MatchRecord.fromJson,
          toJson: (record) => record.toJson(),
        );

  final LocalDocuments<MatchRecord> _documents;

  @override
  Future<List<MatchRecord>> loadAll() async =>
      _documents.readAll()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<MatchRecord?> load(String id) async => _documents.read(id);

  @override
  Future<void> save(MatchRecord record) => _documents.save(record.id, record);

  @override
  Future<void> delete(String id) => _documents.delete(id);
}
