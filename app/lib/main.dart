import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/app_settings.dart';
import 'data/demo_data.dart';
import 'data/local_match_repository.dart';
import 'data/local_team_repository.dart';
import 'data/tournament_repository.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final repository = LocalMatchRepository(prefs);
  final teams = LocalTeamRepository(prefs);
  final tournaments = LocalTournamentRepository(prefs);
  if (demoMode) {
    await seedDemoMatches(repository);
    await seedDemoTeams(teams);
    await seedDemoTournaments(tournaments);
  }
  runApp(
    ProviderScope(
      overrides: [
        appSettingsProvider.overrideWithValue(AppSettings(prefs)),
        matchRepositoryProvider.overrideWithValue(repository),
        teamRepositoryProvider.overrideWithValue(teams),
        tournamentRepositoryProvider.overrideWithValue(tournaments),
      ],
      child: const BnpScorerApp(),
    ),
  );
}
