import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/accounts.dart';
import 'data/app_settings.dart';
import 'data/backfill.dart';
import 'data/cloud_cups.dart';
import 'data/cloud_matches.dart';
import 'data/cloud_teams.dart';
import 'data/demo_data.dart';
import 'data/device_notifications.dart';
import 'data/error_log.dart';
import 'data/local_match_repository.dart';
import 'data/local_team_repository.dart';
import 'data/match_repository.dart';
import 'data/photo_store.dart';
import 'data/player_directory.dart';
import 'data/push_messages.dart';
import 'data/scheduled_match.dart';
import 'data/syncing_cups.dart';
import 'data/syncing_match_repository.dart';
import 'data/syncing_teams.dart';
import 'data/team_repository.dart';
import 'data/tournament_repository.dart';
import 'state/providers.dart';
import 'theme/app_theme.dart';
import 'ui/error_handling.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppFonts.useBundledFonts();
  await AppFonts.preload();
  final prefs = await SharedPreferences.getInstance();
  final errors = ErrorLog(prefs);
  installErrorHandlers(errors);
  final local = LocalMatchRepository(prefs);
  final accounts = await _startCloud();
  final notifications = await _startNotifications();
  final hasCloud = accounts is FirebaseAccounts;
  final cloud = hasCloud ? FirestoreCloudMatches(FirebaseFirestore.instance) : null;
  final cups = hasCloud ? FirestoreCloudCups(FirebaseFirestore.instance) : null;
  final players = hasCloud ? FirestorePlayerDirectory(FirebaseFirestore.instance) : null;
  final cloudTeams = hasCloud ? FirestoreCloudTeams(FirebaseFirestore.instance) : null;
  final photos = hasCloud && photosBaseUrl.isNotEmpty ? HttpPhotoStore(accounts) : null;
  // Push on Android only for now: iOS needs an APNs key (the paid Apple
  // developer account) before Firebase can reach it.
  final PushMessages push =
      hasCloud && Platform.isAndroid ? FirebasePushMessages(FirebaseMessaging.instance) : const NoPushMessages();
  final pushDevices = hasCloud ? FirestorePushDevices(FirebaseFirestore.instance) : null;
  final MatchRepository repository = cloud == null ? local : SyncingMatchRepository(local, cloud, accounts);
  final localTeams = LocalTeamRepository(prefs);
  final syncingTeams = cloudTeams == null ? null : SyncingTeamRepository(localTeams, cloudTeams, accounts, prefs);
  final TeamRepository teams = syncingTeams ?? localTeams;
  final localTournaments = LocalTournamentRepository(prefs);
  final localSchedules = LocalScheduleRepository(prefs);
  final TournamentRepository tournaments =
      cups == null ? localTournaments : SyncingTournamentRepository(localTournaments, cups, accounts);
  final ScheduleRepository schedules =
      cups == null ? localSchedules : SyncingScheduleRepository(localSchedules, cups, accounts);
  if (cloud != null) {
    backfillPlayerIdsOnSignIn(accounts: accounts, prefs: prefs, local: local, cloud: cloud);
  }
  if (demoMode) {
    // Straight to the phone: demo matches are never published.
    await seedDemoMatches(local);
    await seedDemoTeams(localTeams);
    await seedDemoTournaments(localTournaments);
  }
  runApp(
    ProviderScope(
      overrides: [
        appSettingsProvider.overrideWithValue(AppSettings(prefs)),
        errorLogProvider.overrideWithValue(errors),
        accountsProvider.overrideWithValue(accounts),
        cloudMatchesProvider.overrideWithValue(cloud),
        cloudCupsProvider.overrideWithValue(cups),
        playerDirectoryProvider.overrideWithValue(players),
        cloudTeamsProvider.overrideWithValue(cloudTeams),
        photoStoreProvider.overrideWithValue(photos),
        teamSharingProvider.overrideWithValue(syncingTeams),
        matchRepositoryProvider.overrideWithValue(repository),
        teamRepositoryProvider.overrideWithValue(teams),
        tournamentRepositoryProvider.overrideWithValue(tournaments),
        scheduleRepositoryProvider.overrideWithValue(schedules),
        deviceNotificationsProvider.overrideWithValue(notifications),
        pushMessagesProvider.overrideWithValue(push),
        pushDevicesProvider.overrideWithValue(pushDevices),
      ],
      child: const BnpScorerApp(),
    ),
  );
}

/// Starts Firebase when this build has it (google-services.json was present
/// at build time). Without it, or if it fails, the app runs on the phone only.
Future<Accounts> _startCloud() async {
  try {
    await Firebase.initializeApp();
    return FirebaseAccounts(FirebaseAuth.instance);
  } on Object catch (e) {
    debugPrint('Cloud not available, working on this phone only: $e');
    return const LocalOnlyAccounts();
  }
}

/// Match reminders on Android and iOS. If the plugin cannot start, the app
/// runs without them and offers no reminder switches.
Future<DeviceNotifications> _startNotifications() async {
  if (!Platform.isAndroid && !Platform.isIOS) return const NoDeviceNotifications();
  try {
    return await PluginDeviceNotifications.start();
  } on Object catch (e) {
    debugPrint('Reminders not available: $e');
    return const NoDeviceNotifications();
  }
}
