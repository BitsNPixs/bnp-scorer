import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/player_directory.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import '../widgets/avatars.dart';
import '../widgets/edit_profile_sheet.dart';
import '../widgets/match_card.dart';
import '../widgets/scoring_sheets.dart';
import '../widgets/stat_widgets.dart';
import '../widgets/surface_panel.dart';
import 'scoring_screen.dart';
import 'watch_match_screen.dart';

/// The span a career table covers.
enum CareerPeriod {
  career('Career'),
  thisYear('This year'),
  lastTen('Last 10');

  const CareerPeriod(this.label);

  final String label;
}

/// The matches of [played] (oldest first) that [period] covers.
List<CareerMatch> matchesIn(List<CareerMatch> played, CareerPeriod period, DateTime now) => switch (period) {
      CareerPeriod.career => played,
      CareerPeriod.thisYear => [
          for (final m in played)
            if (m.record.createdAt.toLocal().year == now.year) m,
        ],
      CareerPeriod.lastTen => played.length <= 10 ? played : played.sublist(played.length - 10),
    };

/// The columns of a career table: every match, then one column per format,
/// but only when the player has played more than one format (otherwise the
/// format column would repeat the first).
List<(String label, List<CareerMatch> matches)> careerColumns(List<CareerMatch> played, List<CareerMatch> inPeriod) {
  final formats = {for (final m in played) formatOf(m.state.setup.rules)};
  return [
    ('All', inPeriod),
    if (formats.length > 1)
      for (final format in MatchFormat.values)
        if (formats.contains(format))
          (format.label, [for (final m in inPeriod) if (formatOf(m.state.setup.rules) == format) m]),
  ];
}

/// Opens a player's profile: their career from every match on this phone and,
/// in cloud builds, everyone's published matches they were picked in.
void openPlayer(BuildContext context, String playerId) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlayerProfileScreen(playerId: playerId)),
    );

class PlayerProfileScreen extends ConsumerStatefulWidget {
  const PlayerProfileScreen({super.key, required this.playerId});

  final String playerId;

  @override
  ConsumerState<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends ConsumerState<PlayerProfileScreen> {
  CareerPeriod _period = CareerPeriod.career;

  Future<void> _share(String name, PlayerStats? stats) async {
    try {
      await ref.read(deviceFilesProvider).shareText(profileShareText(name, stats), subject: name);
    } on Object catch (e) {
      if (mounted) showMessage(context, 'Could not open sharing: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final career = ref.watch(playerCareerProvider(widget.playerId));
    final profile = ref.watch(playerProfileProvider(widget.playerId)).value;
    return career.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(profile?.name ?? 'Player')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(profile?.name ?? 'Player')),
        body: Center(child: Text('Could not load this player.\n$error', textAlign: TextAlign.center)),
      ),
      data: (career) {
        final view = _CareerView(widget.playerId, career.matches);
        final name = profile?.name ?? view.stats?.name ?? 'Player';
        final me = ref.watch(scorerProvider).value ?? ref.watch(accountsProvider).current;
        final mine = profile != null && me != null && profile.ownerUid == me.uid;
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            // The name is in the card below; the bar takes the player back, and
            // lets the owner edit their profile.
            appBar: AppBar(
              actions: [
                IconButton(
                  tooltip: 'Share profile',
                  onPressed: () => _share(name, view.stats),
                  icon: const Icon(Icons.share_rounded),
                ),
                if (mine)
                  IconButton(
                    tooltip: 'Edit profile',
                    onPressed: () => showEditProfileSheet(context, profile),
                    icon: const Icon(Icons.edit_rounded),
                  ),
              ],
            ),
            body: Column(
              children: [
                _Hero(name: name, view: view, profile: profile),
                const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [Tab(text: 'Info'), Tab(text: 'Batting'), Tab(text: 'Bowling'), Tab(text: 'Career')],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _InfoTab(view: view, name: name, profile: profile, cloudMissed: career.cloudMissed),
                      _TableTab(
                        view: view,
                        period: _period,
                        onPeriod: (p) => setState(() => _period = p),
                        spec: _battingSpec,
                      ),
                      _TableTab(
                        view: view,
                        period: _period,
                        onPeriod: (p) => setState(() => _period = p),
                        spec: _bowlingSpec,
                      ),
                      _CareerTab(view: view),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A player's matches worked out once for every tab.
class _CareerView {
  _CareerView(this.playerId, this.matches) {
    final byId = {for (final m in matches) m.record.id: m};
    lines = playerMatchLines(playerId, matches.map((m) => m.state));
    played = [for (final line in lines) byId[line.matchId]!];
    stats = statsOf(played);
  }

  final String playerId;

  /// Every match the player is in, oldest first, finished or not.
  final List<CareerMatch> matches;

  /// One line per finished match, oldest first, matching [played].
  late final List<PlayerMatchLine> lines;
  late final List<CareerMatch> played;
  late final PlayerStats? stats;

  bool get isEmpty => played.isEmpty;

  PlayerStats? statsOf(Iterable<CareerMatch> some) =>
      computeStats(some.map((m) => m.state)).players.where((p) => p.playerId == playerId).firstOrNull;

  CareerMatch matchOf(PlayerMatchLine line) => played[lines.indexOf(line)];

  /// The role set in the player's latest match.
  PlayerRole? get role {
    if (lines.isEmpty) return null;
    final line = lines.last;
    final team = matchOf(line).state.setup.teamById(line.teamId);
    return team.players.firstWhere((p) => p.id == playerId).role;
  }
}

Future<void> _openMatch(BuildContext context, WidgetRef ref, CareerMatch match) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => match.onPhone ? ScoringScreen(matchId: match.record.id) : WatchMatchScreen(matchId: match.record.id),
    ),
  );
  if (context.mounted && match.onPhone) ref.invalidate(matchListProvider);
}

class _Hero extends StatelessWidget {
  const _Hero({required this.name, required this.view, required this.profile});

  final String name;
  final _CareerView view;
  final PlayerProfile? profile;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final team = view.lines.lastOrNull?.teamName;
    final profile = this.profile;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.neon.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          PlayerAvatar(name: name, radius: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  plural(view.played.length, 'match'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (team != null) _HeroChip(icon: TeamBadge(name: team, size: 18), label: team),
                    if (profile != null && profile.claimed)
                      const _HeroChip(
                        icon: Icon(Icons.verified_rounded, size: 18, color: AppColors.neon),
                        label: 'Verified',
                      )
                    else if (profile != null)
                      const _HeroChip(
                        icon: Icon(Icons.mark_email_unread_outlined, size: 18, color: Colors.white70),
                        label: 'Invited, not claimed yet',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      );
}

const _noMatches = StatsEmpty(message: 'No finished matches yet.');

class _InfoTab extends ConsumerWidget {
  const _InfoTab({required this.view, required this.name, required this.profile, required this.cloudMissed});

  final _CareerView view;
  final String name;
  final PlayerProfile? profile;
  final bool cloudMissed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = view.stats;
    final teams = <String>[];
    for (final line in view.lines.reversed) {
      if (!teams.contains(line.teamName)) teams.add(line.teamName);
    }
    // Shared squads they are in, even before playing for them.
    for (final name in ref.watch(playerTeamsProvider(view.playerId)).value ?? const <String>[]) {
      if (!teams.contains(name)) teams.add(name);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (cloudMissed) ...[
          const NoticeBanner(
            icon: Icons.cloud_off_rounded,
            text: 'Could not reach the cloud. Showing matches on this phone only.',
            background: AppColors.four,
            foreground: AppColors.night,
          ),
          const SizedBox(height: 12),
        ],
        KeyValueTable(
          title: 'Personal information',
          rows: [
            ('Full name', name),
            // The player's own choice wins over the role in their latest match.
            ('Role', (profile?.role ?? view.role)?.label ?? 'Not set'),
            if (profile != null) ...[
              ('Batting', profile!.battingStyle?.label ?? 'Not set'),
              ('Bowling', profile!.bowlingStyle ?? 'Not set'),
              ('Home town', profile!.homeTown ?? 'Not set'),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (view.isEmpty) _noMatches else _RecentForm(view: view),
        if (teams.isNotEmpty) ...[
          const SizedBox(height: 12),
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Teams'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final team in teams)
                      Chip(avatar: TeamBadge(name: team, size: 22), label: Text(team)),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (stats != null) ...[
          const SizedBox(height: 12),
          StatGrid(
            title: 'Awards',
            stats: [
              ('MVP points', '${stats.mvpPoints}'),
              ('Player of the Match', '${stats.playerOfMatchAwards}'),
            ],
          ),
          const SizedBox(height: 12),
          StatGrid(
            title: 'Fielding',
            stats: [
              ('Catches', '${stats.fielding.catches}'),
              ('Stumpings', '${stats.fielding.stumpings}'),
              ('Run outs', '${stats.fielding.runOuts}'),
            ],
          ),
        ],
      ],
    );
  }
}

/// The last five innings, newest first, each opening its match.
class _RecentForm extends ConsumerWidget {
  const _RecentForm({required this.view});

  final _CareerView view;

  static const _shown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final innings = [
      for (final line in view.lines.reversed)
        if (line.batting != null) line,
    ].take(_shown).toList();
    final header = text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700);

    Widget cells(List<String> values, TextStyle? style, {Widget? trailing}) => Row(
          children: [
            for (final (i, flex) in const [3, 4, 3, 3].indexed)
              Expanded(
                flex: flex,
                child: Text(values[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
              ),
            SizedBox(width: 24, child: trailing),
          ],
        );

    return SurfacePanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: SectionLabel('Recent form · batting')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: cells(const ['SCORE', 'OPPN.', 'FORMAT', 'DATE'], header),
          ),
          if (innings.isEmpty)
            const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 12), child: Text('Has not batted yet.')),
          for (final line in innings)
            InkWell(
              onTap: () => _openMatch(context, ref, view.matchOf(line)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: cells(
                  [
                    '${line.batting!.runs}${line.batting!.isOut ? '' : '*'} (${line.batting!.balls})',
                    line.opponentName,
                    line.format.label,
                    shortDate(view.matchOf(line).record.createdAt.toLocal()),
                  ],
                  text.bodyMedium,
                  trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          const Divider(height: 1),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => _PlayerMatchesScreen(view: view)),
            ),
            child: const Text('View all matches'),
          ),
        ],
      ),
    );
  }
}

typedef _Rows = List<(String label, String Function(PlayerStats stats) value)>;

/// What one of the two number tabs shows: three headline numbers, the full
/// table, and what to say when the player has not done it yet.
class _TableSpec {
  const _TableSpec({required this.headline, required this.rows, required this.did, required this.notYet});

  final _Rows headline;
  final _Rows rows;
  final bool Function(PlayerStats stats) did;
  final String notYet;
}

final _Rows _battingRows = [
  ('Matches', (s) => '${s.matches}'),
  ('Innings', (s) => '${s.batting.innings}'),
  ('Runs', (s) => '${s.batting.runs}'),
  ('Balls', (s) => '${s.batting.balls}'),
  ('Highest', (s) => highScoreText(s.batting.high)),
  ('Average', (s) => decimal(s.batting.average)),
  ('Strike rate', (s) => decimal(s.batting.strikeRate)),
  ('Not out', (s) => '${s.batting.notOuts}'),
  ('Fours', (s) => '${s.batting.fours}'),
  ('Sixes', (s) => '${s.batting.sixes}'),
  ('Fifties', (s) => '${s.batting.fifties}'),
  ('Hundreds', (s) => '${s.batting.hundreds}'),
  ('Ducks', (s) => '${s.batting.ducks}'),
];

final _battingSpec = _TableSpec(
  headline: [
    ('Runs', (s) => '${s.batting.runs}'),
    ('Average', (s) => decimal(s.batting.average)),
    ('Strike rate', (s) => decimal(s.batting.strikeRate, 1)),
  ],
  rows: _battingRows,
  did: (s) => s.batting.innings > 0,
  notYet: 'Has not batted in these matches.',
);

final _bowlingSpec = _TableSpec(
  headline: [
    ('Wickets', (s) => '${s.bowling.wickets}'),
    ('Economy', (s) => decimal(s.bowling.economy)),
    ('Best', (s) => bestBowlingText(s.bowling.best)),
  ],
  rows: _bowlingRows,
  did: (s) => s.bowling.innings > 0,
  notYet: 'Has not bowled in these matches.',
);

final _Rows _bowlingRows = [
  ('Matches', (s) => '${s.matches}'),
  ('Innings', (s) => '${s.bowling.innings}'),
  ('Overs', (s) => s.bowling.oversText),
  ('Runs', (s) => '${s.bowling.runs}'),
  ('Wickets', (s) => '${s.bowling.wickets}'),
  ('Best', (s) => bestBowlingText(s.bowling.best)),
  ('Average', (s) => decimal(s.bowling.average)),
  ('Economy', (s) => decimal(s.bowling.economy)),
  ('Strike rate', (s) => decimal(s.bowling.strikeRate)),
  ('Maidens', (s) => '${s.bowling.maidens}'),
  ('Dot balls', (s) => '${s.bowling.dots}'),
  ('Wides', (s) => '${s.bowling.wides}'),
  ('No-balls', (s) => '${s.bowling.noBalls}'),
];

/// A period choice, three headline numbers, then the full table with one
/// column per format.
class _TableTab extends StatelessWidget {
  const _TableTab({required this.view, required this.period, required this.onPeriod, required this.spec});

  final _CareerView view;
  final CareerPeriod period;
  final ValueChanged<CareerPeriod> onPeriod;
  final _TableSpec spec;

  @override
  Widget build(BuildContext context) {
    if (view.isEmpty) return _noMatches;
    final columns = careerColumns(view.played, matchesIn(view.played, period, DateTime.now()));
    final stats = [for (final (_, matches) in columns) view.statsOf(matches)];
    final all = stats.first;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        OptionChips<CareerPeriod>(
          options: CareerPeriod.values,
          labelOf: (p) => p.label,
          selected: period,
          color: AppColors.neon,
          onSelected: onPeriod,
        ),
        const SizedBox(height: 12),
        if (all == null || !spec.did(all))
          SurfacePanel(child: Text(all == null ? 'No matches in this period.' : spec.notYet))
        else ...[
          _Headline(numbers: [for (final (label, value) in spec.headline) (label, value(all))]),
          const SizedBox(height: 12),
          StatsTable(
            columns: [for (final (label, _) in columns) label],
            rows: [
              for (final (label, value) in spec.rows)
                (label, [for (final s in stats) s == null ? '—' : value(s)]),
            ],
          ),
        ],
      ],
    );
  }
}

/// Three big numbers side by side, on the dark hero card.
class _Headline extends StatelessWidget {
  const _Headline({required this.numbers});

  final List<(String label, String value)> numbers;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: AppColors.heroGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.neon.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            for (final (i, (label, value)) in numbers.indexed) ...[
              if (i > 0) Container(width: 1, height: 36, color: Colors.white24),
              Expanded(
                child: Column(
                  children: [
                    Text(value, maxLines: 1, style: scoreStyle(28, color: AppColors.neon)),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
}

/// Debut and latest match, overall and in each format.
class _CareerTab extends ConsumerWidget {
  const _CareerTab({required this.view});

  final _CareerView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (view.isEmpty) return _noMatches;
    final buckets = [
      ('All matches', view.lines),
      for (final format in MatchFormat.values) (format.label, [for (final l in view.lines) if (l.format == format) l]),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (title, lines) in buckets) ...[
          SurfacePanel(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel(title),
                const SizedBox(height: 4),
                _CareerRow(label: 'Debut', line: lines.firstOrNull, view: view),
                _CareerRow(label: 'Last played', line: lines.lastOrNull, view: view),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CareerRow extends ConsumerWidget {
  const _CareerRow({required this.label, required this.line, required this.view});

  final String label;
  final PlayerMatchLine? line;
  final _CareerView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final line = this.line;
    final match = line == null ? null : view.matchOf(line);
    final date = match?.record.createdAt.toLocal();
    final detail = line == null
        ? 'Not played'
        : [
            'vs ${line.opponentName}',
            '${shortDate(date!)} ${date.year}',
            ?line.venue,
          ].join(' · ');
    return InkWell(
      onTap: match == null ? null : () => _openMatch(context, ref, match),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
            Expanded(
              child: Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: match == null ? null : scheme.primary, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every match the player is in, newest first.
class _PlayerMatchesScreen extends ConsumerWidget {
  const _PlayerMatchesScreen({required this.view});

  final _CareerView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = view.matches.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: Text(plural(matches.length, 'match'))),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: matches.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final m = matches[i];
          return MatchCard(
            summary: (record: m.record, state: m.state),
            onTap: m.onPhone ? null : () => _openMatch(context, ref, m),
          );
        },
      ),
    );
  }
}
