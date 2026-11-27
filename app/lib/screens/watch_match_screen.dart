import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:match_view/match_view.dart' show MatchNow;

import '../data/cloud_matches.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/crease_panel.dart';
import '../widgets/match_tabs_view.dart';
import '../widgets/over_strip.dart';
import '../widgets/score_header.dart';
import '../widgets/share_scorecard_sheet.dart';
import '../widgets/surface_panel.dart';
import '../widgets/push_settings.dart';

/// Someone else's published match, read-only, updating as each ball is
/// scored: the same tabs as the scorer sees, without the pad or scoring menu.
class WatchMatchScreen extends ConsumerWidget {
  const WatchMatchScreen({super.key, required this.matchId});

  final String matchId;

  static const goneMessage = 'This match is no longer published.';
  static const unreadableMessage =
      'This match cannot be shown. It may come from a newer version of BNP Scorer.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(publishedMatchProvider(matchId));
    return match.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => const ScreenMessage(icon: Icons.report_outlined, text: unreadableMessage),
      data: (published) {
        if (published == null) return const ScreenMessage(icon: Icons.cloud_off_rounded, text: goneMessage);
        final MatchState state;
        try {
          state = ScoringEngine.replay(published.record.setup, published.record.events);
        } on Object {
          return const ScreenMessage(icon: Icons.report_outlined, text: unreadableMessage);
        }
        return MatchTabsView(
          state: state,
          actions: [
            FollowMatchButton(matchId: matchId, ownerUid: published.ownerUid, finished: state.isCompleted),
            IconButton(
              tooltip: 'Share',
              onPressed: () => showShareScorecardSheet(context, state, publishedMatchId: matchId),
              icon: const Icon(Icons.share_rounded),
            ),
          ],
          liveTab: _WatchLiveTab(state: state, published: published),
        );
      },
    );
  }
}

/// The score, this over and who is at the crease, for watching.
class _WatchLiveTab extends ConsumerWidget {
  const _WatchLiveTab({required this.state, required this.published});

  final MatchState state;
  final PublishedMatch published;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final stopped = nowOf((record: published.record, state: state), ref.watch(clockProvider)()) == MatchNow.stopped;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        ScoreHeader(state: state, stopped: stopped),
        if (state.current.isFreeHit) ...[
          const SizedBox(height: 12),
          const NoticeBanner(
            icon: Icons.bolt_rounded,
            text: 'FREE HIT · only a run out counts',
            background: AppColors.neon,
            foreground: AppColors.night,
          ),
        ],
        const SizedBox(height: 12),
        OverStrip(state: state),
        const SizedBox(height: 12),
        CreasePanel(state: state),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.visibility_outlined, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                stopped
                    ? 'Scored by ${published.ownerName}. No ball for some hours; it updates if play goes on.'
                    : 'Scored by ${published.ownerName}. Updates as each ball is bowled.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A full-screen notice with a back button: a match or tournament that is
/// gone, or cannot be read.
class ScreenMessage extends StatelessWidget {
  const ScreenMessage({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ),
      );
}
