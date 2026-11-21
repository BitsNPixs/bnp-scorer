import 'dart:async';
import 'dart:typed_data';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/cloud_cups.dart';
import 'package:bnp_scorer/data/cloud_matches.dart';
import 'package:bnp_scorer/data/device_files.dart';
import 'package:bnp_scorer/data/match_record.dart';
import 'package:bnp_scorer/data/player_directory.dart';
import 'package:bnp_scorer/data/match_repository.dart';
import 'package:bnp_scorer/data/scheduled_match.dart';
import 'package:bnp_scorer/data/team_repository.dart';
import 'package:bnp_scorer/data/tournament_repository.dart';

class InMemoryMatchRepository implements MatchRepository {
  final records = <String, MatchRecord>{};

  /// When true, [save] throws, simulating a storage failure.
  bool failSaves = false;

  @override
  Future<List<MatchRecord>> loadAll() async =>
      records.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<MatchRecord?> load(String id) async => records[id];

  @override
  Future<void> save(MatchRecord record) async {
    if (failSaves) throw StateError('Storage is full');
    records[record.id] = record;
  }

  @override
  Future<void> delete(String id) async {
    records.remove(id);
  }
}

class InMemoryTournamentRepository implements TournamentRepository {
  final tournaments = <String, Tournament>{};

  /// When true, [save] throws, simulating a storage failure.
  bool failSaves = false;

  @override
  Future<List<Tournament>> loadAll() async =>
      tournaments.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<void> save(Tournament tournament) async {
    if (failSaves) throw StateError('Storage is full');
    tournaments[tournament.id] = tournament;
  }

  @override
  Future<void> delete(String id) async {
    tournaments.remove(id);
  }
}

class InMemoryScheduleRepository implements ScheduleRepository {
  final schedules = <String, ScheduledMatch>{};

  @override
  Future<List<ScheduledMatch>> loadAll() async =>
      schedules.values.toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  @override
  Future<void> save(ScheduledMatch match) async => schedules[match.id] = match;

  @override
  Future<void> delete(String id) async => schedules.remove(id);
}

class InMemoryTeamRepository implements TeamRepository {
  final teams = <String, Team>{};

  /// When true, [save] throws, simulating a storage failure.
  bool failSaves = false;

  @override
  Future<List<Team>> loadAll() async =>
      teams.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<void> save(Team team) async {
    if (failSaves) throw StateError('Storage is full');
    teams[team.id] = team;
  }

  @override
  Future<void> delete(String id) async {
    teams.remove(id);
  }
}

Team _team(String id, List<String> names) => Team(
      id: id,
      name: id == 'a' ? 'Ammapet Kings' : 'Bazaar Strikers',
      players: [
        for (var i = 0; i < names.length; i++) Player(id: '$id${i + 1}', name: names[i]),
      ],
    );

/// Team "a" (Asha, Arun, Anil, Abdul) bats first against team "b".
MatchRecord sampleRecord({
  String id = 'm1',
  int overs = 2,
  List<MatchEvent> events = const [],
  DateTime? updatedAt,
}) {
  final at = DateTime.utc(2026, 11, 5);
  return MatchRecord(
    setup: MatchSetup(
      id: id,
      teamA: _team('a', ['Asha', 'Arun', 'Anil', 'Abdul']),
      teamB: _team('b', ['Bilal', 'Bharat', 'Bose', 'Bala']),
      rules: MatchRules(oversPerInnings: overs),
      tossWinnerId: 'a',
      tossDecision: TossDecision.bat,
    ),
    events: events,
    createdAt: at,
    updatedAt: updatedAt ?? at,
  );
}

/// Sign-in without Google. [nextSignIn] is who the next sign-in returns; null
/// acts as the scorer cancelling.
class FakeAccounts implements Accounts {
  FakeAccounts({Scorer? signedIn}) : _current = signedIn;

  Scorer? _current;
  Scorer? nextSignIn = const Scorer(uid: 'u1', name: 'Asha Scorer');

  /// When set, sign-in fails with this message.
  String? failWith;
  int signInCalls = 0;
  final _changes = StreamController<Scorer?>.broadcast();

  @override
  bool get available => true;

  @override
  Scorer? get current => _current;

  @override
  Stream<Scorer?> get changes async* {
    yield _current;
    yield* _changes.stream;
  }

  @override
  Future<Scorer?> signIn() async {
    signInCalls++;
    final failure = failWith;
    if (failure != null) throw AccountsException(failure);
    if (nextSignIn != null) {
      _current = nextSignIn;
      _changes.add(_current);
    }
    return nextSignIn;
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _changes.add(null);
  }

  /// The code the next SMS carries.
  String smsCode = '123456';

  /// When true, the phone confirms the number by itself: no code to type.
  bool autoVerify = false;

  /// When set, sending a code fails with this message.
  String? phoneFailWith;

  /// Every number a code was sent to, resends included.
  final codesSentTo = <String>[];

  @override
  Future<PhoneCodeRequest?> requestPhoneCode(String e164, {PhoneCodeRequest? resend}) async {
    if (_current == null) throw const AccountsException('Sign in with Google first.');
    final failure = phoneFailWith;
    if (failure != null) throw AccountsException(failure);
    codesSentTo.add(e164);
    if (autoVerify) {
      _setPhone(e164);
      return null;
    }
    return PhoneCodeRequest(phone: e164, verificationId: 'v${codesSentTo.length}', resendToken: 1);
  }

  @override
  Future<void> linkPhone(PhoneCodeRequest request, String code) async {
    if (_current == null) throw const AccountsException('Sign in with Google first.');
    if (code.trim() != smsCode) throw AccountsException(phoneErrorMessage('invalid-verification-code'));
    _setPhone(request.phone);
  }

  void _setPhone(String e164) {
    final scorer = _current!;
    _current = Scorer(uid: scorer.uid, name: scorer.name, phone: e164);
    _changes.add(_current);
  }
}

/// The cloud as two maps: what is published, and by whom. [recent] and
/// [watch] act like Firestore snapshots: the current state, then every change.
class FakeCloudMatches implements CloudMatches {
  final published = <String, MatchRecord>{};
  final owners = <String, Scorer>{};
  final unpublished = <String>[];

  /// When true, every write fails, as with no connection and no queue.
  bool failWrites = false;

  /// When true, [byPlayer] fails, as when the cloud cannot be reached.
  bool failReads = false;

  /// Documents this app cannot read, by match id: [watch] reports an error.
  final unreadable = <String>{};

  final _changes = StreamController<void>.broadcast();

  @override
  Future<void> publish(MatchRecord record, Scorer owner) async {
    if (failWrites) throw StateError('No connection');
    published[record.id] = record;
    owners[record.id] = owner;
    _changes.add(null);
  }

  @override
  Future<void> unpublish(String matchId) async {
    if (failWrites) throw StateError('No connection');
    published.remove(matchId);
    unpublished.add(matchId);
    _changes.add(null);
  }

  PublishedMatch _published(String id) =>
      PublishedMatch(record: published[id]!, ownerUid: owners[id]!.uid, ownerName: owners[id]!.name);

  List<PublishedMatch> _recent(int limit) {
    final newest = published.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [for (final r in newest.take(limit)) _published(r.id)];
  }

  @override
  Stream<List<PublishedMatch>> recent({int limit = 30}) async* {
    yield _recent(limit);
    await for (final _ in _changes.stream) {
      yield _recent(limit);
    }
  }

  @override
  Future<List<PublishedMatch>> byPlayer(String playerId, {int limit = 100}) async {
    if (failReads) throw StateError('No connection');
    return [
      for (final record in published.values)
        if (matchPlayerIds(record.setup).contains(playerId)) _published(record.id),
    ].take(limit).toList();
  }

  @override
  Stream<PublishedMatch?> watch(String matchId) async* {
    PublishedMatch? current() {
      if (unreadable.contains(matchId)) throw const FormatException('Cannot read this match');
      return published.containsKey(matchId) ? _published(matchId) : null;
    }

    yield current();
    await for (final _ in _changes.stream) {
      yield current();
    }
  }
}

/// Published tournaments and friendlies, in memory, updating live. Keeps what
/// was sent ([sentTournaments]) so tests can check nothing private left.
class FakeCloudCups implements CloudCups {
  final tournaments = <String, PublishedTournament>{};
  final schedules = <String, PublishedSchedule>{};
  final sentTournaments = <String, Json>{};

  /// Ids whose [watchTournament] reports an error, as for a newer format.
  final unreadable = <String>{};

  final _changes = StreamController<void>.broadcast();

  Map<String, Object?> _owned(Json json, Scorer owner) =>
      {...json, 'ownerUid': owner.uid, 'ownerName': owner.name, 'schema': 1};

  @override
  Future<void> publishTournament(Tournament tournament, Scorer owner) async {
    final json = tournament.toPublicJson();
    sentTournaments[tournament.id] = json;
    tournaments[tournament.id] = parsePublishedTournament(_owned(json, owner));
    _changes.add(null);
  }

  @override
  Future<void> unpublishTournament(String id) async {
    tournaments.remove(id);
    _changes.add(null);
  }

  @override
  Stream<List<PublishedTournament>> recentTournaments({int limit = 20}) async* {
    yield tournaments.values.take(limit).toList();
    await for (final _ in _changes.stream) {
      yield tournaments.values.take(limit).toList();
    }
  }

  @override
  Stream<PublishedTournament?> watchTournament(String id) async* {
    PublishedTournament? current() {
      if (unreadable.contains(id)) throw const FormatException('Cannot read this tournament');
      return tournaments[id];
    }

    yield current();
    await for (final _ in _changes.stream) {
      yield current();
    }
  }

  @override
  Future<void> publishSchedule(ScheduledMatch schedule, Scorer owner) async {
    schedules[schedule.id] = parsePublishedSchedule(_owned(schedule.toJson()..remove('publishedBy'), owner));
    _changes.add(null);
  }

  @override
  Future<void> unpublishSchedule(String id) async {
    schedules.remove(id);
    _changes.add(null);
  }

  @override
  Stream<List<PublishedSchedule>> upcomingSchedules({required DateTime from, int limit = 30}) async* {
    List<PublishedSchedule> list() => (schedules.values.where((p) => !p.schedule.startsAt.isBefore(from)).toList()
          ..sort((a, b) => a.schedule.startsAt.compareTo(b.schedule.startsAt)))
        .take(limit)
        .toList();
    yield list();
    await for (final _ in _changes.stream) {
      yield list();
    }
  }
}

/// Records the last text and text file shared through the share sheet, and
/// hands out [fileToPick] as the file the scorer picks (null: they cancel).
/// With [fail], sharing throws as a phone with nothing to share to would.
class TextShares implements DeviceFiles {
  String? text;
  String? subject;
  String? fileName;
  String? fileContents;
  bool fail = false;
  String? fileToPick;

  @override
  Future<void> shareText(String text, {required String subject}) async {
    if (fail) throw StateError('No apps to share with');
    this.text = text;
    this.subject = subject;
  }

  @override
  Future<void> shareImage(Uint8List png, {required String caption}) async {}

  @override
  Future<void> shareTextFile(String name, String contents) async {
    if (fail) throw StateError('No apps to share with');
    fileName = name;
    fileContents = contents;
  }

  @override
  Future<String?> pickTextFile() async => fileToPick;
}

/// The player directory as two maps: players by id, and numbers (E.164, not
/// hashed, for readable tests) to player ids. Follows the same rules as
/// Firestore: a number taken first wins, and only its holder claims it.
class FakePlayerDirectory implements PlayerDirectory {
  final players = <String, PlayerProfile>{};
  final phones = <String, String>{};

  /// When true, every call fails as if there were no signal.
  bool offline = false;
  int _ids = 0;
  final _changes = StreamController<void>.broadcast();

  /// Adds [name] under [e164], as if another captain had invited them, or
  /// as their own profile when [ownerUid] is given.
  PlayerProfile seed(String name, String e164, {String? ownerUid}) {
    final player = PlayerProfile(id: 'dir${++_ids}', name: name, ownerUid: ownerUid);
    players[player.id] = player;
    phones[e164] = player.id;
    return player;
  }

  void _checkSignal() {
    if (offline) throw const PlayerDirectoryException(offlineMessage);
  }

  @override
  Future<PlayerProfile?> lookupByPhone(String e164) async {
    _checkSignal();
    final id = phones[e164];
    return id == null ? null : players[id];
  }

  @override
  Future<PlayerProfile> invite(String name, String e164, Scorer by) async {
    _checkSignal();
    final first = await lookupByPhone(e164);
    if (first != null) return first;
    final player = seed(name, e164);
    _changes.add(null);
    return player;
  }

  @override
  Future<PlayerProfile> claim(Scorer me) async {
    _checkSignal();
    final phone = me.phone;
    if (phone == null) throw const PlayerDirectoryException('Confirm your mobile number first.');
    final id = phones[phone];
    final claimed = id == null
        ? seed(me.name, phone, ownerUid: me.uid)
        : PlayerProfile(id: id, name: players[id]!.name, ownerUid: me.uid);
    players[claimed.id] = claimed;
    _changes.add(null);
    return claimed;
  }

  @override
  Stream<PlayerProfile?> watch(String playerId) async* {
    yield players[playerId];
    await for (final _ in _changes.stream) {
      yield players[playerId];
    }
  }
}
