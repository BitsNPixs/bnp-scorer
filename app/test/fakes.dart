import 'dart:async';
import 'dart:typed_data';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/app_links.dart';
import 'package:bnp_scorer/data/cloud_cups.dart';
import 'package:bnp_scorer/data/cloud_matches.dart';
import 'package:bnp_scorer/data/cloud_teams.dart';
import 'package:bnp_scorer/data/device_contacts.dart';
import 'package:bnp_scorer/data/device_files.dart';
import 'package:bnp_scorer/data/device_notifications.dart';
import 'package:bnp_scorer/data/match_record.dart';
import 'package:bnp_scorer/data/player_directory.dart';
import 'package:bnp_scorer/data/push_messages.dart';
import 'package:bnp_scorer/data/match_repository.dart';
import 'package:bnp_scorer/data/photo_store.dart';
import 'package:bnp_scorer/data/scheduled_match.dart';
import 'package:bnp_scorer/data/team_repository.dart';
import 'package:bnp_scorer/data/tournament_repository.dart';
import 'package:bnp_scorer/state/reminders.dart';

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

  @override
  Future<String?> idToken() async => _current == null ? null : 'token-${_current!.uid}';

  /// The code the next SMS carries.
  String smsCode = '123456';

  /// When true, the phone confirms the number by itself: no code to type.
  bool autoVerify = false;

  /// When set, sending a code fails with this message.
  String? phoneFailWith;

  /// Every number a code was sent to, resends included.
  final codesSentTo = <String>[];

  /// The account a number signs in to when nobody is signed in: an existing
  /// one by number, else a new account with no name.
  final accountsByPhone = <String, Scorer>{};

  /// What linking Google does: the name it brings, or a failure message.
  String googleName = 'Asha Google';
  String? linkGoogleFailsWith;

  @override
  Future<PhoneCodeRequest?> requestPhoneCode(String e164, {PhoneCodeRequest? resend}) async {
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
  Future<void> confirmPhone(PhoneCodeRequest request, String code) async {
    if (code.trim() != smsCode) throw AccountsException(phoneErrorMessage('invalid-verification-code'));
    _setPhone(request.phone);
  }

  /// Signed in, puts the number on the account; signed out, signs in with it.
  void _setPhone(String e164) {
    final scorer = _current;
    _current = scorer == null
        ? accountsByPhone[e164] ?? Scorer(uid: 'phone-$e164', name: unnamedScorer, phone: e164, hasGoogle: false)
        : Scorer(uid: scorer.uid, name: scorer.name, phone: e164, hasGoogle: scorer.hasGoogle);
    _changes.add(_current);
  }

  void _replace(Scorer scorer) {
    _current = scorer;
    _changes.add(scorer);
  }

  @override
  Future<void> setName(String name) async {
    final s = _current;
    if (s == null) throw const AccountsException('Sign in first.');
    _replace(Scorer(uid: s.uid, name: publicScorerName(name), phone: s.phone, hasGoogle: s.hasGoogle));
  }

  @override
  Future<Scorer?> linkGoogle() async {
    final s = _current;
    if (s == null) throw const AccountsException('Sign in first.');
    final failure = linkGoogleFailsWith;
    if (failure != null) throw AccountsException(failure);
    _replace(Scorer(uid: s.uid, name: s.needsName ? googleName : s.name, phone: s.phone));
    return _current;
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

  /// Each publish's highlight, in order (null for an ordinary ball).
  final highlights = <MatchHighlight?>[];

  @override
  Future<void> publish(MatchRecord record, Scorer owner, {MatchHighlight? highlight}) async {
    if (failWrites) throw StateError('No connection');
    published[record.id] = record;
    owners[record.id] = owner;
    highlights.add(highlight);
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
  Future<void> saveDetails(PlayerProfile profile) async {
    _checkSignal();
    players[profile.id] = profile;
    _changes.add(null);
  }

  @override
  Stream<PlayerProfile?> watch(String playerId) async* {
    yield players[playerId];
    await for (final _ in _changes.stream) {
      yield players[playerId];
    }
  }
}

/// The contact picker: [next] is what the next pick returns (null as if the
/// user backed out); [failWith] makes it fail.
class FakeContacts implements DeviceContacts {
  FakeContacts({this.next});

  PickedContact? next;
  String? failWith;
  int picks = 0;

  @override
  bool get available => true;

  @override
  Future<PickedContact?> pickContact() async {
    picks++;
    final failure = failWith;
    if (failure != null) throw DeviceContactsException(failure);
    return next;
  }
}

/// Shared teams and join requests as maps. [offline] makes every call fail.
class FakeCloudTeams implements CloudTeams {
  final teams = <String, PublishedTeam>{};
  final requests = <String, Map<String, JoinRequest>>{};
  bool offline = false;
  final _changes = StreamController<void>.broadcast();

  void _checkSignal() {
    if (offline) throw StateError('No connection');
  }

  @override
  Future<void> publishTeam(Team team, Scorer owner) async {
    _checkSignal();
    teams[team.id] = PublishedTeam(team: team, ownerUid: owner.uid, ownerName: owner.name);
  }

  @override
  Future<void> unpublishTeam(String teamId) async {
    _checkSignal();
    teams.remove(teamId);
  }

  @override
  Future<PublishedTeam?> teamByCode(String code) async {
    _checkSignal();
    return teams.values.where((t) => joinCodeOf(t.team.id) == code).firstOrNull;
  }

  @override
  Future<List<PublishedTeam>> teamsOfPlayer(String playerId) async {
    _checkSignal();
    return [for (final t in teams.values) if (t.team.hasPlayer(playerId)) t];
  }

  List<JoinRequest> _joinsOf(String teamId) => [...?requests[teamId]?.values];

  @override
  Stream<List<JoinRequest>> joins(String teamId) async* {
    yield _joinsOf(teamId);
    await for (final _ in _changes.stream) {
      yield _joinsOf(teamId);
    }
  }

  @override
  Future<void> requestJoin(String teamId, {required String playerId, required String name}) async {
    _checkSignal();
    (requests[teamId] ??= {})[playerId] = JoinRequest(playerId: playerId, name: name);
    _changes.add(null);
  }

  @override
  Future<void> dismissJoin(String teamId, String playerId) async {
    _checkSignal();
    requests[teamId]?.remove(playerId);
    _changes.add(null);
  }
}

/// Links that open the app: [initial] once, then whatever [send] pushes.
class FakeAppLinks implements AppLinks {
  FakeAppLinks({this.initial});

  Uri? initial;
  final _links = StreamController<Uri>.broadcast();

  void send(Uri link) => _links.add(link);

  @override
  Future<Uri?> initialLink() async {
    final link = initial;
    initial = null;
    return link;
  }

  @override
  Stream<Uri> get links => _links.stream;
}

/// The photos Worker as a map of uploads. [failWith] makes calls fail.
class FakePhotoStore implements PhotoStore {
  Uint8List? avatar;
  int uploads = 0;
  String? failWith;

  void _check() {
    final failure = failWith;
    if (failure != null) throw PhotoException(failure);
  }

  @override
  Future<String> uploadAvatar(Uint8List image) async {
    _check();
    avatar = image;
    uploads++;
    return 'https://photos.example/img/avatars/me.img?v=$uploads';
  }

  @override
  Future<void> removeAvatar() async {
    _check();
    avatar = null;
  }

  final logos = <String, Uint8List>{};

  @override
  Future<String> uploadTeamLogo(String teamId, Uint8List image) async {
    _check();
    logos[teamId] = image;
    uploads++;
    return 'https://photos.example/img/teams/me/$teamId.img?v=$uploads';
  }

  @override
  Future<void> removeTeamLogo(String teamId) async {
    _check();
    logos.remove(teamId);
  }
}

/// The photo picker: [next] is what the next pick returns.
class FakeDevicePhotos implements DevicePhotos {
  FakeDevicePhotos({this.next});

  Uint8List? next;

  @override
  Future<Uint8List?> pickPhoto() async => next;
}

/// The phone's notifications as a list of scheduled reminders. [allowedNow]
/// is the permission; [grant] is what the permission prompt answers.
class FakeDeviceNotifications implements DeviceNotifications {
  FakeDeviceNotifications({this.allowedNow = false, this.grant = true, this.launch});

  bool allowedNow;
  bool grant;
  String? launch;
  int prompts = 0;
  List<Reminder> scheduled = const [];
  final _taps = StreamController<String>.broadcast();

  /// Acts as if the user tapped a reminder while the app is open.
  void tap(String payload) => _taps.add(payload);

  @override
  bool get available => true;

  @override
  Future<bool> allowed() async => allowedNow;

  @override
  Future<bool> requestPermission() async {
    prompts++;
    allowedNow = grant;
    return grant;
  }

  @override
  Future<void> replaceReminders(List<Reminder> reminders) async => scheduled = reminders;

  final shown = <PushNotice>[];

  @override
  Future<void> show(PushNotice notice) async => shown.add(notice);

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<String?> launchPayload() async {
    final payload = launch;
    launch = null;
    return payload;
  }
}

/// Cloud Messaging with a fixed [token] (null: none to be had).
class FakePushMessages implements PushMessages {
  FakePushMessages({this.token = 'token-1'});

  String? token;
  bool enabled = false;
  final _refreshes = StreamController<String>.broadcast();
  final _foreground = StreamController<PushNotice>.broadcast();

  void refresh(String next) {
    token = next;
    _refreshes.add(next);
  }

  void arrive(PushNotice notice) => _foreground.add(notice);

  @override
  bool get available => true;

  @override
  Future<String?> enable() async {
    enabled = true;
    return token;
  }

  @override
  Future<void> disable() async => enabled = false;

  @override
  Stream<String> get tokenRefreshes => _refreshes.stream;

  @override
  Stream<PushNotice> get foreground => _foreground.stream;

  final _opened = StreamController<PushNotice>.broadcast();

  /// Acts as if the user tapped a push while the app was in the background.
  void tapInBackground(PushNotice notice) => _opened.add(notice);

  @override
  Stream<PushNotice> get opened => _opened.stream;

  @override
  Future<PushNotice?> launchNotice() async => null;
}

/// pushDevices as a map. Like the rules, a device id already saved under
/// another owner cannot be changed.
class FakePushDevices implements PushDevices {
  final saved = <String, PushDevice>{};
  final tests = <String>[];
  bool failDelete = false;

  @override
  Future<void> save(PushDevice device) async {
    final existing = saved[device.id];
    if (existing != null && existing.ownerUid != device.ownerUid) {
      throw StateError('permission-denied');
    }
    saved[device.id] = device;
  }

  @override
  Future<void> delete(String id) async {
    if (failDelete) throw StateError('offline');
    saved.remove(id);
  }

  @override
  Future<void> requestTest(String id) async => tests.add(id);
}
