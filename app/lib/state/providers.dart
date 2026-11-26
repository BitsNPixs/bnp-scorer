import 'dart:convert';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/accounts.dart';
import '../data/app_links.dart';
import '../data/app_settings.dart';
import '../data/cloud_cups.dart';
import '../data/cloud_matches.dart';
import '../data/cloud_teams.dart';
import '../data/device_contacts.dart';
import '../data/device_notifications.dart';
import '../data/device_files.dart';
import '../data/error_log.dart';
import '../data/match_record.dart';
import '../data/match_repository.dart';
import '../data/photo_store.dart';
import '../data/push_messages.dart';
import '../data/push_registration.dart';
import '../data/player_directory.dart';
import '../data/scheduled_match.dart';
import '../data/syncing_teams.dart';
import '../data/team_repository.dart';
import '../data/tournament_repository.dart';
import 'reminders.dart';
import 'upcoming.dart';

/// Overridden in `main()` with the real implementation.
final matchRepositoryProvider = Provider<MatchRepository>(
  (ref) => throw UnimplementedError('matchRepositoryProvider must be overridden'),
);

/// Overridden in `main()` with the real implementation.
final appSettingsProvider = Provider<AppSettings>(
  (ref) => throw UnimplementedError('appSettingsProvider must be overridden'),
);

/// System, light or dark, as the scorer chose in Settings.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(appSettingsProvider).themeMode;

  /// Switches at once and saves in the background. A failed save only means
  /// the choice is forgotten at the next launch.
  Future<void> select(ThemeMode mode) async {
    state = mode;
    try {
      await ref.read(appSettingsProvider).setThemeMode(mode);
    } on Object catch (e) {
      debugPrint('Could not save the theme: $e');
    }
  }
}

/// Google sign-in. `main()` overrides it when the cloud is set up; tests and
/// builds without `google-services.json` get no sign-in.
final accountsProvider = Provider<Accounts>((ref) => const LocalOnlyAccounts());

/// The signed-in scorer, or null.
final scorerProvider = StreamProvider<Scorer?>((ref) {
  final accounts = ref.watch(accountsProvider);
  return accounts.changes;
});

/// Published matches. `main()` overrides it when the cloud is set up; null in
/// tests and builds without `google-services.json`.
final cloudMatchesProvider = Provider<CloudMatches?>((ref) => null);

/// A published match and its state, for the "Everyone" list.
typedef PublishedSummary = ({PublishedMatch match, MatchState state});

/// The latest published matches, live. Empty without the cloud. A match whose
/// log does not replay is left out, like a broken match on the phone.
///
/// No automatic retry: Firestore reconnects by itself, and its errors (such
/// as a refused read) do not mend on their own, while each retry costs reads.
final publicMatchesProvider = StreamProvider.autoDispose<List<PublishedSummary>>(
  (ref) {
    final cloud = ref.watch(cloudMatchesProvider);
    if (cloud == null) return Stream.value(const []);
    return cloud.recent().map((matches) => [
          for (final match in matches) ?_summaryOf(match),
        ]);
  },
  retry: _noRetry,
);

Duration? _noRetry(int retryCount, Object error) => null;

PublishedSummary? _summaryOf(PublishedMatch match) {
  try {
    return (match: match, state: ScoringEngine.replay(match.record.setup, match.record.events));
  } on Object catch (e) {
    debugPrint('Leaving out published match ${match.record.id}: $e');
    return null;
  }
}

/// One published match as it is scored. Null once it is unpublished. A match
/// this app cannot read stays an error: retrying would not help.
final publishedMatchProvider = StreamProvider.autoDispose.family<PublishedMatch?, String>(
  (ref, matchId) {
    final cloud = ref.watch(cloudMatchesProvider);
    if (cloud == null) return Stream.value(null);
    return cloud.watch(matchId);
  },
  retry: _noRetry,
);

/// Players by mobile number. Null without the cloud, like
/// [cloudMatchesProvider].
final playerDirectoryProvider = Provider<PlayerDirectory?>((ref) => null);

/// One player in the directory, live. Null when there is no such player or no
/// cloud.
final playerProfileProvider = StreamProvider.autoDispose.family<PlayerProfile?, String>(
  (ref, playerId) => ref.watch(playerDirectoryProvider)?.watch(playerId) ?? Stream.value(null),
  retry: _noRetry,
);

/// The signed-in scorer's own player profile, claimed under their confirmed
/// number: the one a captain invited, or a new one. Null when signed out,
/// without a confirmed number or a name, or without the cloud. Claiming again is only
/// reads, so this is safe to rebuild.
final myProfileProvider = FutureProvider.autoDispose<PlayerProfile?>(
  (ref) async {
    final directory = ref.watch(playerDirectoryProvider);
    final scorer = ref.watch(scorerProvider).value ?? ref.watch(accountsProvider).current;
    if (directory == null || scorer == null || scorer.phone == null) return null;
    // A first sign-in with a number has no name yet: wait for it, or the new
    // profile would be called "Scorer".
    if (scorer.needsName) return null;
    return directory.claim(scorer);
  },
  retry: _noRetry,
);

/// Shared teams and join requests. Null without the cloud.
final cloudTeamsProvider = Provider<CloudTeams?>((ref) => null);

/// Sharing a saved team's invite. `main()` points it at the same
/// `SyncingTeamRepository` as [teamRepositoryProvider]; null without the cloud.
final teamSharingProvider = Provider<TeamSharing?>((ref) => null);

/// Players asking to join a team, live, for its captain. Empty without the
/// cloud.
final teamJoinsProvider = StreamProvider.autoDispose.family<List<JoinRequest>, String>(
  (ref, teamId) => ref.watch(cloudTeamsProvider)?.joins(teamId) ?? Stream.value(const []),
  retry: _noRetry,
);

/// The names of the shared teams a player is in, for their profile. Empty
/// without the cloud or when it cannot be read.
final playerTeamsProvider = FutureProvider.autoDispose.family<List<String>, String>(
  (ref, playerId) async {
    final cloud = ref.watch(cloudTeamsProvider);
    if (cloud == null) return const [];
    try {
      return [for (final t in await cloud.teamsOfPlayer(playerId)) t.team.name];
    } on Object catch (e) {
      debugPrint('Could not read the teams of $playerId: $e');
      return const [];
    }
  },
  retry: _noRetry,
);

/// Published tournaments and friendlies. Null without the cloud, like
/// [cloudMatchesProvider].
final cloudCupsProvider = Provider<CloudCups?>((ref) => null);

/// The latest published tournaments, live. Empty without the cloud.
final publicTournamentsProvider = StreamProvider.autoDispose<List<PublishedTournament>>(
  (ref) => ref.watch(cloudCupsProvider)?.recentTournaments() ?? Stream.value(const []),
  retry: _noRetry,
);

/// Published friendlies still to come, live. Empty without the cloud.
final publicSchedulesProvider = StreamProvider.autoDispose<List<PublishedSchedule>>(
  (ref) =>
      ref.watch(cloudCupsProvider)?.upcomingSchedules(from: DateTime.now().subtract(upcomingGrace)) ??
      Stream.value(const []),
  retry: _noRetry,
);

/// Everyone's upcoming fixtures and friendlies, soonest first. Empty while
/// loading or offline.
final publicUpcomingProvider = Provider.autoDispose<List<UpcomingMatch>>((ref) {
  final tournaments = ref.watch(publicTournamentsProvider).value ?? const [];
  final schedules = ref.watch(publicSchedulesProvider).value ?? const [];
  return upcomingMatches(
    [for (final p in tournaments) p.tournament],
    [for (final p in schedules) p.schedule],
    DateTime.now(),
  );
});

/// One published tournament as it changes. Null once unpublished.
final publishedTournamentProvider = StreamProvider.autoDispose.family<PublishedTournament?, String>(
  (ref, id) => ref.watch(cloudCupsProvider)?.watchTournament(id) ?? Stream.value(null),
  retry: _noRetry,
);

/// A published tournament with its table, bracket and stats, from the matches
/// its organiser published. A match not published (scored signed out) counts
/// as not played yet.
final publicTournamentProgressProvider =
    Provider.autoDispose.family<AsyncValue<(TournamentProgress, String)?>, String>((ref, id) {
  return ref.watch(publishedTournamentProvider(id)).whenData((published) {
    if (published == null) return null;
    final states = <String, MatchState>{};
    for (final fixture in published.tournament.fixtures) {
      final matchId = fixture.matchId;
      if (matchId == null) continue;
      final match = ref.watch(publishedMatchProvider(matchId)).value;
      if (match == null) continue;
      try {
        states[matchId] = ScoringEngine.replay(match.record.setup, match.record.events);
      } on Object catch (e) {
        debugPrint('Leaving out published match $matchId: $e');
      }
    }
    return (progressOf(published.tournament, states), published.ownerName);
  });
});

/// Overridden in `main()` with the log the error handlers write to.
final errorLogProvider = Provider<ErrorLog>(
  (ref) => throw UnimplementedError('errorLogProvider must be overridden'),
);

/// The share sheet and file picker. Tests override this.
final deviceFilesProvider = Provider<DeviceFiles>((ref) => const PlatformDeviceFiles());

/// Player photos in the photos Worker. Null without the cloud or before the
/// Worker's address is set (`BNP_PHOTOS_URL`).
final photoStoreProvider = Provider<PhotoStore?>((ref) => null);

/// The phone's photo picker. Tests override this.
final devicePhotosProvider = Provider<DevicePhotos>((ref) => const PlatformDevicePhotos());

/// Links that open the app (team invites). Tests override this.
final appLinksProvider = Provider<AppLinks>((ref) => PlatformAppLinks());

/// The phone's contact picker. Tests override this.
final deviceContactsProvider = Provider<DeviceContacts>((ref) => const PlatformDeviceContacts());

/// The phone's notifications. `main()` overrides it on Android and iOS;
/// tests and other platforms get none.
final deviceNotificationsProvider = Provider<DeviceNotifications>((ref) => const NoDeviceNotifications());

/// What reminders this phone wants: before its own matches ([ownOn], null
/// until offered), how long before, and other people's matches it follows.
typedef ReminderSettings = ({bool? ownOn, ReminderLead lead, List<WatchedReminder> watched});

final reminderSettingsProvider = NotifierProvider<ReminderSettingsNotifier, ReminderSettings>(
  ReminderSettingsNotifier.new,
);

/// Said when the phone refuses notifications.
const notificationsOffMessage =
    "Notifications are off for BNP Scorer. Turn them on in your phone's Settings, then try again.";

/// Asks the phone, at the moment the user turns something on, whether the
/// app may notify. Null when allowed, else what to tell the user.
Future<String?> permitNotifications(DeviceNotifications device) async {
  if (!device.available) return 'Notifications are not available on this phone.';
  if (await device.allowed() || await device.requestPermission()) return null;
  return notificationsOffMessage;
}

class ReminderSettingsNotifier extends Notifier<ReminderSettings> {
  AppSettings get _settings => ref.read(appSettingsProvider);

  @override
  ReminderSettings build() {
    final settings = ref.watch(appSettingsProvider);
    return (
      ownOn: settings.remindersOn,
      lead: settings.reminderLead,
      watched: liveWatched(settings.watchedReminders, DateTime.now()),
    );
  }

  Future<String?> _permit() => permitNotifications(ref.read(deviceNotificationsProvider));

  /// Turns reminders before this phone's matches on or off. Turning them on
  /// asks for permission at that moment; a refusal leaves them off. Returns
  /// null when done, else the message to show.
  Future<String?> setOwn(bool on) async {
    if (on) {
      final refused = await _permit();
      if (refused != null) return refused;
    }
    state = (ownOn: on, lead: state.lead, watched: state.watched);
    await _settings.setRemindersOn(on);
    return null;
  }

  Future<void> setLead(ReminderLead lead) async {
    state = (ownOn: state.ownOn, lead: lead, watched: state.watched);
    await _settings.setReminderLead(lead);
  }

  bool isWatched(String upcomingId) => state.watched.any((w) => w.id == upcomingId);

  /// Follows or stops following someone else's [match]. Null when done,
  /// else the message to show.
  Future<String?> toggleWatched(UpcomingMatch match) async {
    if (isWatched(match.id)) {
      await _saveWatched([for (final w in state.watched) if (w.id != match.id) w]);
      return null;
    }
    final refused = await _permit();
    if (refused != null) return refused;
    await _saveWatched([...state.watched, WatchedReminder.of(match)]);
    return null;
  }

  /// Takes the latest time, ground and names of followed matches from
  /// [live], so a moved match moves its reminder. Saves only on a change.
  Future<void> refreshWatched(List<UpcomingMatch> live) async {
    final byId = {for (final m in live) m.id: m};
    final updated = [
      for (final w in state.watched)
        if (byId[w.id] case final m? when m.startsAt != null) WatchedReminder.of(m) else w,
    ];
    String encode(List<WatchedReminder> list) => jsonEncode([for (final w in list) w.toJson()]);
    if (encode(updated) != encode(state.watched)) await _saveWatched(updated);
  }

  Future<void> _saveWatched(List<WatchedReminder> watched) async {
    state = (ownOn: state.ownOn, lead: state.lead, watched: watched);
    await _settings.setWatchedReminders(watched);
  }
}

/// Keeps the phone's pending reminders in line with the upcoming matches and
/// [reminderSettingsProvider]. Watched by the home screen, so it reruns
/// whenever either changes.
final reminderSyncProvider = FutureProvider.autoDispose<List<Reminder>>((ref) async {
  final settings = ref.watch(reminderSettingsProvider);
  final device = ref.watch(deviceNotificationsProvider);
  final own = await ref.watch(upcomingProvider.future);
  final plan = planReminders(
    own: own,
    watched: settings.watched,
    ownOn: settings.ownOn ?? false,
    lead: settings.lead,
    now: DateTime.now(),
  );
  if (device.available) await device.replaceReminders(plan);
  return plan;
}, retry: _noRetry);

/// Overridden in `main()` with the real implementation.
final teamRepositoryProvider = Provider<TeamRepository>(
  (ref) => throw UnimplementedError('teamRepositoryProvider must be overridden'),
);

final savedTeamsProvider = FutureProvider.autoDispose<List<Team>>(
  (ref) => ref.watch(teamRepositoryProvider).loadAll(),
);

/// Overridden in `main()` with the real implementation.
final tournamentRepositoryProvider = Provider<TournamentRepository>(
  (ref) => throw UnimplementedError('tournamentRepositoryProvider must be overridden'),
);

/// Every tournament with its derived table, stats and champion.
final tournamentsProvider = FutureProvider.autoDispose<List<TournamentProgress>>((ref) async {
  final tournaments = await ref.watch(tournamentRepositoryProvider).loadAll();
  final matches = await ref.watch(matchListProvider.future);
  final byId = {for (final m in matches) m.record.id: m.state};
  return [for (final t in tournaments) progressOf(t, byId)];
});

/// Overridden in `main()` with the real implementation.
final scheduleRepositoryProvider = Provider<ScheduleRepository>(
  (ref) => throw UnimplementedError('scheduleRepositoryProvider must be overridden'),
);

final schedulesProvider = FutureProvider.autoDispose<List<ScheduledMatch>>(
  (ref) => ref.watch(scheduleRepositoryProvider).loadAll(),
);

/// Dated fixtures not started yet and scheduled friendlies, soonest first.
final upcomingProvider = FutureProvider.autoDispose<List<UpcomingMatch>>((ref) async {
  final tournaments = await ref.watch(tournamentsProvider.future);
  final schedules = await ref.watch(schedulesProvider.future);
  return upcomingMatches([for (final p in tournaments) p.tournament], schedules, DateTime.now());
});

/// A stored match with its replayed state, for lists.
typedef MatchSummary = ({MatchRecord record, MatchState state});

/// A match in a player's career. One [onPhone] opens for scoring; any other
/// was published by someone else and opens read-only.
typedef CareerMatch = ({MatchRecord record, MatchState state, bool onPhone});

/// A player's matches, oldest first: those on this phone and, in cloud builds,
/// everyone's published matches carrying their id. [cloudMissed] is true when
/// the cloud could not be read, so only this phone's matches are shown.
typedef PlayerCareer = ({List<CareerMatch> matches, bool cloudMissed});

final playerCareerProvider = FutureProvider.autoDispose.family<PlayerCareer, String>(
  (ref, playerId) async {
    final byId = <String, CareerMatch>{};
    for (final m in await ref.watch(matchListProvider.future)) {
      if (matchPlayerIds(m.record.setup).contains(playerId)) {
        byId[m.record.id] = (record: m.record, state: m.state, onPhone: true);
      }
    }
    var cloudMissed = false;
    final cloud = ref.watch(cloudMatchesProvider);
    if (cloud != null) {
      try {
        for (final published in await cloud.byPlayer(playerId)) {
          if (byId.containsKey(published.record.id)) continue;
          final summary = _summaryOf(published);
          if (summary != null) byId[published.record.id] = (record: published.record, state: summary.state, onPhone: false);
        }
      } on Object catch (e) {
        debugPrint('Could not read the published matches of $playerId: $e');
        cloudMissed = true;
      }
    }
    final matches = byId.values.toList()..sort((a, b) => a.record.createdAt.compareTo(b.record.createdAt));
    return (matches: matches, cloudMissed: cloudMissed);
  },
  retry: _noRetry,
);

/// Career numbers from every finished match. Derived, never stored.
final statsProvider = FutureProvider.autoDispose<StatsBook>((ref) async {
  final matches = await ref.watch(matchListProvider.future);
  final oldestFirst = [...matches]
    ..sort((a, b) => a.record.createdAt.compareTo(b.record.createdAt));
  return computeStats(oldestFirst.map((m) => m.state));
});

final matchListProvider = FutureProvider.autoDispose<List<MatchSummary>>((ref) async {
  final records = await ref.watch(matchRepositoryProvider).loadAll();
  final summaries = <MatchSummary>[];
  for (final record in records) {
    try {
      summaries.add((
        record: record,
        state: ScoringEngine.replay(record.setup, record.events),
      ));
    } on ScoringException catch (e) {
      debugPrint('Skipping match ${record.id} with an invalid log: $e');
    }
  }
  return summaries;
});

/// Firebase Cloud Messaging. `main()` overrides it in cloud builds on
/// Android; tests, iOS (until it has an APNs key) and builds without the
/// cloud get none.
final pushMessagesProvider = Provider<PushMessages>((ref) => const NoPushMessages());

/// Where push registrations are kept. Null without the cloud.
final pushDevicesProvider = Provider<PushDevices?>((ref) => null);

final pushRegistrationProvider = Provider<PushRegistration>(
  (ref) => PushRegistration(
    push: ref.watch(pushMessagesProvider),
    devices: ref.watch(pushDevicesProvider),
    settings: ref.watch(appSettingsProvider),
  ),
);

/// The pushes this phone asked for.
final pushKindsProvider = NotifierProvider<PushKindsNotifier, Set<PushKind>>(PushKindsNotifier.new);

class PushKindsNotifier extends Notifier<Set<PushKind>> {
  @override
  Set<PushKind> build() => ref.watch(appSettingsProvider).pushKinds;

  /// Turns one kind on or off. Turning one on needs a signed-in scorer, since
  /// pushes go to people, and asks for permission at that moment. Null when
  /// done, else the message to show.
  Future<String?> set(PushKind kind, bool on) async {
    if (on) {
      if (!ref.read(pushRegistrationProvider).available) return 'Updates are not available on this phone yet.';
      if (ref.read(accountsProvider).current == null) return 'Sign in first, so updates know who they are for.';
      final refused = await permitNotifications(ref.read(deviceNotificationsProvider));
      if (refused != null) return refused;
    }
    state = on ? {...state, kind} : ({...state}..remove(kind));
    await ref.read(appSettingsProvider).setPushKinds(state);
    return null;
  }
}

/// How long a followed match stays followed: past a day's play, a match is
/// over and its pushes with it.
const followFor = Duration(days: 2);

/// Published matches this phone follows, by id, with when it began.
final followedMatchesProvider = NotifierProvider<FollowedMatchesNotifier, Map<String, DateTime>>(
  FollowedMatchesNotifier.new,
);

class FollowedMatchesNotifier extends Notifier<Map<String, DateTime>> {
  @override
  Map<String, DateTime> build() {
    final since = DateTime.now().subtract(followFor);
    return {
      for (final e in ref.watch(appSettingsProvider).followedMatches.entries)
        if (e.value.isAfter(since)) e.key: e.value,
    };
  }

  bool isFollowing(String matchId) => state.containsKey(matchId);

  /// Follows or stops following a published match. Following needs a
  /// signed-in scorer and turns "Matches you follow" on, asking for
  /// permission then if it is the first time. Null when done, else the
  /// message to show.
  Future<String?> toggle(String matchId) async {
    if (isFollowing(matchId)) {
      await _save({...state}..remove(matchId));
      return null;
    }
    if (!ref.read(pushKindsProvider).contains(PushKind.follow)) {
      final refused = await ref.read(pushKindsProvider.notifier).set(PushKind.follow, true);
      if (refused != null) return refused;
    }
    await _save({...state, matchId: DateTime.now()});
    return null;
  }

  Future<void> _save(Map<String, DateTime> followed) async {
    state = followed;
    await ref.read(appSettingsProvider).setFollowedMatches(followed);
  }
}

/// Keeps this phone's push registration in step with the scorer, the kinds
/// chosen, the matches followed, and token changes. Watched by the home
/// screen.
final pushSyncProvider = FutureProvider.autoDispose<void>((ref) async {
  final registration = ref.watch(pushRegistrationProvider);
  if (!registration.available) return;
  final scorer = ref.watch(scorerProvider).value;
  final kinds = ref.watch(pushKindsProvider);
  final follows = ref.watch(followedMatchesProvider).keys.toList()..sort();
  Future<void> sync() => registration.sync(scorer, kinds, follows: follows);
  final refreshes = registration.push.tokenRefreshes.listen((_) => sync());
  ref.onDispose(refreshes.cancel);
  await sync();
}, retry: _noRetry);

