import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_links.dart';
import '../state/providers.dart';
import '../state/reminders.dart';
import '../ui/feedback.dart';
import '../ui/motion.dart';
import '../widgets/app_bottom_bar.dart';
import '../widgets/join_team_sheet.dart';
import '../widgets/upcoming.dart';
import 'matches_tab.dart';
import 'new_match_screen.dart';
import 'stats_screen.dart';
import 'teams_screen.dart';
import 'tournaments_screen.dart';
import 'watch_match_screen.dart';
import 'watch_tournament_screen.dart';

const _tabs = <BottomBarItem>[
  (icon: Icons.sports_cricket_outlined, selectedIcon: Icons.sports_cricket_rounded, label: 'Matches'),
  (icon: Icons.emoji_events_outlined, selectedIcon: Icons.emoji_events_rounded, label: 'Tournaments'),
  (icon: Icons.leaderboard_outlined, selectedIcon: Icons.leaderboard_rounded, label: 'Stats'),
  (icon: Icons.groups_outlined, selectedIcon: Icons.groups_rounded, label: 'Teams'),
];

/// The app's home: matches, tournaments, stats and teams behind a bottom bar,
/// with "new match" one tap away on every tab.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;
  StreamSubscription<Uri>? _links;
  StreamSubscription<String>? _reminderTaps;
  StreamSubscription<Object>? _foregroundPushes;
  StreamSubscription<Object>? _openedPushes;

  @override
  void initState() {
    super.initState();
    final links = ref.read(appLinksProvider);
    _links = links.links.listen(_openLink);
    links.initialLink().then((link) {
      if (link != null && mounted) _openLink(link);
    });
    final notifications = ref.read(deviceNotificationsProvider);
    _reminderTaps = notifications.taps.listen(_openPayload);
    notifications.launchPayload().then((payload) {
      if (payload != null && mounted) _openPayload(payload);
    });
    // The phone shows no push while the app is open; show it the same way.
    final push = ref.read(pushMessagesProvider);
    _foregroundPushes = push.foreground.listen(notifications.show);
    _openedPushes = push.opened.listen((notice) => _openPayload(notice.data['open']));
    push.launchNotice().then((notice) {
      if (notice != null && mounted) _openPayload(notice.data['open']);
    });
  }

  @override
  void dispose() {
    _links?.cancel();
    _reminderTaps?.cancel();
    _foregroundPushes?.cancel();
    _openedPushes?.cancel();
    super.dispose();
  }

  /// Pushes about a followed match say `match:<id>` for what to open.
  static const _matchPrefix = 'match:';

  /// A tapped notification opens what it is about: a followed match live; a
  /// reminder's match on its sheet, ready to start, or a followed cup fixture
  /// on the cup.
  Future<void> _openPayload(String? payload) async {
    if (payload == null) return;
    if (payload.startsWith(_matchPrefix)) {
      _select(0);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => WatchMatchScreen(matchId: payload.substring(_matchPrefix.length))),
      );
      return;
    }
    if (!isReminderPayload(payload)) return;
    _select(0);
    if (payload.startsWith(ownReminderPrefix)) {
      final id = payload.substring(ownReminderPrefix.length);
      final upcoming = await ref.read(upcomingProvider.future);
      final match = upcoming.where((m) => m.id == id).firstOrNull;
      if (!mounted) return;
      if (match == null) {
        showMessage(context, 'That match has started or was cancelled.');
      } else {
        await showUpcomingSheet(context, ref, match);
      }
    } else if (payload.startsWith(watchedReminderPrefix)) {
      final id = payload.substring(watchedReminderPrefix.length);
      final watched = ref.read(reminderSettingsProvider).watched.where((w) => w.id == id).firstOrNull;
      if (watched?.tournamentId case final tournamentId?) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => WatchTournamentScreen(tournamentId: tournamentId)),
        );
      }
    }
  }

  /// A team invite opens the Teams tab with the join sheet, code filled in.
  Future<void> _openLink(Uri link) async {
    final code = joinCodeFromLink(link);
    if (code == null || ref.read(cloudTeamsProvider) == null) return;
    _select(3);
    final joined = await showJoinTeamSheet(context, code: code);
    if (joined != null && mounted) showMessage(context, 'Asked to join $joined. Your captain adds you.');
  }

  /// Tabs are built on first visit, then kept, so each keeps its scroll
  /// position and nothing is loaded before it is wanted.
  final _visited = <int>{0};

  void _select(int tab) => setState(() {
    _tab = tab;
    _visited.add(tab);
  });

  Future<void> _newMatch() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NewMatchScreen()));
    if (!mounted) return;
    ref.invalidate(matchListProvider);
    _select(0);
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the phone's reminders in line with what is coming up.
    ref.watch(reminderSyncProvider);
    // And this phone's push registration with who is signed in.
    ref.watch(pushSyncProvider);
    final pages = [
      MatchesTab(onNewMatch: _newMatch),
      const TournamentsScreen(),
      const StatsScreen(),
      const TeamsScreen(),
    ];
    return PopScope(
      // Back goes to Matches first, then leaves the app.
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            for (var i = 0; i < pages.length; i++)
              _TabPage(active: i == _tab, child: _visited.contains(i) ? pages[i] : const SizedBox.shrink()),
          ],
        ),
        bottomNavigationBar: AppBottomBar(items: _tabs, selected: _tab, onSelected: _select, onCreate: _newMatch),
      ),
    );
  }
}

/// Fades a tab in each time it is chosen, without rebuilding what is inside.
class _TabPage extends StatefulWidget {
  const _TabPage({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_TabPage> createState() => _TabPageState();
}

class _TabPageState extends State<_TabPage> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 240), value: 1);

  @override
  void didUpdateWidget(_TabPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !reduceMotion(context)) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    return TickerMode(
      enabled: widget.active,
      child: FadeTransition(
        opacity: curve,
        child: ScaleTransition(scale: Tween(begin: 0.98, end: 1.0).animate(curve), child: widget.child),
      ),
    );
  }
}
