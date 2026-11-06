import 'match_record.dart';

/// Storage boundary. The app ships with [LocalMatchRepository]; a Firestore
/// implementation can be added behind this same interface for cloud sync.
abstract interface class MatchRepository {
  /// Most recently updated first. Unreadable records are skipped.
  Future<List<MatchRecord>> loadAll();

  Future<MatchRecord?> load(String id);

  Future<void> save(MatchRecord record);

  Future<void> delete(String id);
}
