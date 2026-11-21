import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_links.dart';
import '../state/providers.dart';
import '../ui/feedback.dart';
import '../ui/motion.dart';
import '../widgets/app_bottom_bar.dart';
import '../widgets/join_team_sheet.dart';
import 'matches_tab.dart';
import 'new_match_screen.dart';
import 'stats_screen.dart';
import 'teams_screen.dart';
import 'tournaments_screen.dart';

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

  @override
  void initState() {
    super.initState();
    final links = ref.read(appLinksProvider);
    _links = links.links.listen(_openLink);
    links.initialLink().then((link) {
      if (link != null && mounted) _openLink(link);
    });
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
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
