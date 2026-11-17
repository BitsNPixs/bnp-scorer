import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/new_match_screen.dart';
import '../screens/watch_tournament_screen.dart';
import '../state/providers.dart';
import '../state/upcoming.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import '../ui/pickers.dart';
import 'surface_panel.dart';

/// Upcoming matches as a row of cards, soonest first. Tapping one opens what
/// can be done with it: everything for this phone's own, or an invite and the
/// cup when [watching] other people's.
class UpcomingStrip extends ConsumerWidget {
  const UpcomingStrip({super.key, required this.matches, this.watching = false});

  final List<UpcomingMatch> matches;
  final bool watching;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: matches.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) => _UpcomingCard(
          match: matches[i],
          now: now,
          onTap: () => showUpcomingSheet(context, ref, matches[i], watching: watching),
        ),
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.match, required this.now, required this.onTap});

  final UpcomingMatch match;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final when = match.startsAt!;
    final due = when.isBefore(now);
    return SizedBox(
      width: 260,
      child: Material(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.neon.withValues(alpha: 0.3)),
        ),
        child: Ink(
          decoration: const BoxDecoration(gradient: AppColors.heroGradient),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(due ? Icons.schedule_rounded : Icons.event_rounded,
                          size: 16, color: due ? AppColors.four : AppColors.neon),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          due ? 'Due since ${clockTime(when)}' : upcomingWhen(when, now),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelLarge?.copyWith(
                            color: due ? AppColors.four : AppColors.neon,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '${match.homeName} v ${match.awayName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: scoreStyle(22, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [match.title, ?match.venue].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Start, time, ground, invite and cancel for a fixture or scheduled friendly.
/// When [watching] someone else's, only the invite and the cup.
Future<void> showUpcomingSheet(BuildContext context, WidgetRef ref, UpcomingMatch match, {bool watching = false}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _UpcomingSheet(match: match, ref: ref, host: context, watching: watching),
    );

class _UpcomingSheet extends StatelessWidget {
  const _UpcomingSheet({required this.match, required this.ref, required this.host, required this.watching});

  final UpcomingMatch match;
  final bool watching;

  /// From the screen that opened the sheet, which outlives it.
  final WidgetRef ref;
  final BuildContext host;

  /// Saves a change to the fixture's tournament or to the friendly.
  Future<void> _change({DateTime? startsAt, bool clearDate = false, String? ground}) async {
    try {
      if (match.schedule case final s?) {
        var changed = startsAt == null ? s : s.withStart(startsAt);
        if (ground != null) changed = changed.withVenue(ground);
        await ref.read(scheduleRepositoryProvider).save(changed);
        ref.invalidate(schedulesProvider);
      } else {
        final fixture = match.fixture!;
        var changed = match.tournament!;
        if (startsAt != null || clearDate) changed = changed.withFixtureDate(fixture.id, startsAt);
        if (ground != null) changed = changed.withFixtureVenue(fixture.id, ground);
        await ref.read(tournamentRepositoryProvider).save(changed);
        ref.invalidate(tournamentsProvider);
      }
    } on Object catch (e) {
      if (host.mounted) showMessage(host, 'Could not save it: $e', isError: true);
    }
  }

  Future<void> _invite() async {
    try {
      await ref.read(deviceFilesProvider).shareText(inviteText(match), subject: 'Match invite');
    } on Object catch (e) {
      if (host.mounted) showMessage(host, 'Could not open sharing: $e', isError: true);
    }
  }

  Future<void> _cancel() async {
    try {
      await ref.read(scheduleRepositoryProvider).delete(match.schedule!.id);
      ref.invalidate(schedulesProvider);
      if (host.mounted) showMessage(host, 'Match cancelled');
    } on Object catch (e) {
      if (host.mounted) showMessage(host, 'Could not cancel it: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final when = match.startsAt;
    final navigator = Navigator.of(context);
    void close() => navigator.pop();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${match.homeName} v ${match.awayName}',
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            [match.title, if (when != null) fixtureDate(when), ?match.venue].join(' · '),
            style: text.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: 16),
          if (watching) ...[
            if (match.tournament case final tournament?)
              FilledButton.icon(
                onPressed: () {
                  close();
                  Navigator.of(host).push(
                    MaterialPageRoute<void>(builder: (_) => WatchTournamentScreen(tournamentId: tournament.id)),
                  );
                },
                icon: const Icon(Icons.emoji_events_rounded),
                label: const Text('Open the cup'),
              ),
            const SizedBox(height: 8),
            SurfacePanel(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.share_rounded),
                title: const Text('Send invite'),
                subtitle: const Text('On WhatsApp or any app'),
                onTap: () async {
                  close();
                  await _invite();
                },
              ),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: () async {
                close();
                if (match.schedule case final s?) {
                  await startScheduledMatch(host, ref, s);
                } else {
                  await startFixtureMatch(host, ref, match.tournament!, match.fixture!);
                }
                if (host.mounted) ref.invalidate(matchListProvider);
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start match'),
            ),
            const SizedBox(height: 8),
            SurfacePanel(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.event_rounded),
                    title: Text(when == null ? 'Set a time' : 'Change time'),
                    onTap: () async {
                      close();
                      final picked = await pickDateTime(host, initial: when);
                      if (picked != null) await _change(startsAt: picked);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: const Text('Change ground'),
                    onTap: () async {
                      close();
                      final ground = await askGround(host, current: match.venue);
                      if (ground != null) await _change(ground: ground);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.share_rounded),
                    title: const Text('Send invite'),
                    subtitle: const Text('On WhatsApp or any app'),
                    onTap: () async {
                      close();
                      await _invite();
                    },
                  ),
                  if (match.schedule != null)
                    ListTile(
                      leading: Icon(Icons.event_busy_rounded, color: Theme.of(context).colorScheme.error),
                      title: const Text('Cancel this match'),
                      onTap: () async {
                        close();
                        await _cancel();
                      },
                    )
                  else if (when != null)
                    ListTile(
                      leading: const Icon(Icons.event_busy_rounded),
                      title: const Text('Remove the time'),
                      onTap: () async {
                        close();
                        await _change(clearDate: true);
                      },
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
