import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/accounts.dart';
import 'data/app_settings.dart';
import 'data/cloud_cups.dart';
import 'data/cloud_matches.dart';
import 'data/demo_data.dart';
import 'data/error_log.dart';
import 'data/local_match_repository.dart';
import 'data/local_team_repository.dart';
import 'data/match_repository.dart';
import 'data/scheduled_match.dart';
import 'data/syncing_cups.dart';
import 'data/syncing_match_repository.dart';
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
  final hasCloud = accounts is FirebaseAccounts;
  final cloud = hasCloud ? FirestoreCloudMatches(FirebaseFirestore.instance) : null;
  final cups = hasCloud ? FirestoreCloudCups(FirebaseFirestore.instance) : null;
  final MatchRepository repository = cloud == null ? local : SyncingMatchRepository(local, cloud, accounts);
  final teams = LocalTeamRepository(prefs);
  final localTournaments = LocalTournamentRepository(prefs);
  final localSchedules = LocalScheduleRepository(prefs);
  final TournamentRepository tournaments =
      cups == null ? localTournaments : SyncingTournamentRepository(localTournaments, cups, accounts);
  final ScheduleRepository schedules =
      cups == null ? localSchedules : SyncingScheduleRepository(localSchedules, cups, accounts);
  if (demoMode) {
    // Straight to the phone: demo matches are never published.
    await seedDemoMatches(local);
    await seedDemoTeams(teams);
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
        matchRepositoryProvider.overrideWithValue(repository),
        teamRepositoryProvider.overrideWithValue(teams),
        tournamentRepositoryProvider.overrideWithValue(tournaments),
        scheduleRepositoryProvider.overrideWithValue(schedules),
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
