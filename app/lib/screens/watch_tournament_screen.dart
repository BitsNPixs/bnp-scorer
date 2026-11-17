import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'tournament_screen.dart';
import 'watch_match_screen.dart';

/// Someone else's published tournament, read-only and live: the same tabs as
/// the organiser sees, without anything to set up, edit or pay.
class WatchTournamentScreen extends ConsumerWidget {
  const WatchTournamentScreen({super.key, required this.tournamentId});

  final String tournamentId;

  static const goneMessage = 'This tournament is no longer published.';
  static const unreadableMessage =
      'This tournament cannot be shown. It may come from a newer version of BNP Scorer.';

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(publicTournamentProgressProvider(tournamentId)).when(
            loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
            error: (_, _) => const ScreenMessage(icon: Icons.report_outlined, text: unreadableMessage),
            data: (watched) => switch (watched) {
              null => const ScreenMessage(icon: Icons.cloud_off_rounded, text: goneMessage),
              (final progress, final organiser) => TournamentView(progress: progress, organiser: organiser),
            },
          );
}
