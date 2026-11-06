import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/demo_data.dart';
import 'data/local_match_repository.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final repository = LocalMatchRepository(prefs);
  if (demoMode) await seedDemoMatches(repository);
  runApp(
    ProviderScope(
      overrides: [
        matchRepositoryProvider.overrideWithValue(repository),
      ],
      child: const BnpScorerApp(),
    ),
  );
}
