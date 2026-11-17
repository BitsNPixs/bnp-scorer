# Architecture

How BNP Scorer works, for anyone extending it. Rules for changing it are in
`AGENTS.md`.

## Repository layout

```
packages/cricket_engine/        Pure Dart scoring engine (no Flutter)
  lib/cricket_engine.dart       Public exports
  lib/src/models.dart           Player, Team, MatchRules, MatchSetup, enums
  lib/src/events.dart           MatchEvent (sealed) + 8 event types, JSON
  lib/src/state.dart            Immutable derived state: MatchState, InningsState, …
  lib/src/engine.dart           ScoringEngine.replay / apply, allowedDismissals
  lib/src/stats.dart            computeStats, MVP points, Player of the Match
  lib/src/tournament.dart       Tournament, Fixture, fixture generation, progressOf
  test/                         Rules, stats, tournament and no-result suites
app/                            Flutter app (package name bnp_scorer)
  lib/main.dart                 Loads SharedPreferences, installs the error handlers,
                                overrides the repositories, seeds demo data in demo builds
  lib/app.dart                  BnpScorerApp (MaterialApp, light/dark themes, saved theme mode)
  lib/data/                     Records, repositories, LocalDocuments, Backup,
                                DeviceFiles, AppSettings, ErrorLog, app version,
                                demo data, newId
  lib/state/                    providers.dart (repositories, lists, stats, theme mode),
                                live_match.dart
  lib/screens/                  Home (the shell), MatchesTab, NewMatch, Scoring (with the
                                scorecard tabs), Stats, player and team stats, Tournaments,
                                Tournament, NewTournament, Teams, TeamEdit, Backup
  lib/widgets/                  Score hero, over strip, crease panel, pad, sheets, panels,
                                charts, overs timeline, wagon wheel, share card, bottom
                                bar, settings sheet, floodlight and confetti, match card,
                                number tiles, stumps art
  lib/theme/app_theme.dart      AppColors, AppFonts, AppTheme, scoreStyle()
  lib/ui/                       format.dart, feedback.dart, inputs.dart, motion.dart,
                                error_handling.dart
  test/                         fakes, unit tests, widget tests per feature
  tool/                         generate_app_icon_test.dart: draws the app icon and
                                splash PNGs into android/ (run by hand)
docs/                           This file and ROADMAP.md
```

## 1. Engine (`packages/cricket_engine`)

### Event sourcing
A match is `MatchSetup` (teams, rules, toss, venue) plus an ordered list of
`MatchEvent`s. `ScoringEngine.replay(setup, events)` folds the list into an
immutable `MatchState`. Nothing derived is ever stored.

- **Undo** = replay without the last event.
- **Validation** = `ScoringEngine.apply(setup, events, next)` replays and
  applies `next`. It throws `ScoringException(message)` if the event is illegal
  now and returns the new state otherwise. Messages are written for scorers
  ("Select a bowler first.", "Bowled is not possible on a free hit.").
- Replay cost is linear in events. A 20-over match is about 150 events, which
  is trivial. Cache snapshots only if profiling shows a need.

### Events (JSON envelope: `{type, id, at, ...payload}`)
| Class | `type` | Payload | Meaning |
| --- | --- | --- | --- |
| `OpenersSelected` | `openersSelected` | `strikerId`, `nonStrikerId` | Starts an innings |
| `BowlerChanged` | `bowlerChanged` | `bowlerId` | Bowler for the next over, or a mid-over replacement |
| `BallBowled` | `ballBowled` | `runsOffBat`, `extra` (`none/wide/noBall/bye/legBye`), `extraRuns`, `boundary`, `wicket?` {`type`, `batterOutId`, `fielderId?`, `end?` (run outs: `striker/bowler`)}, `shotZone?`, `legByes?` (no-balls) | One delivery |
| `NewBatter` | `newBatter` | `batterId` | Fills the empty slot (also a returning retired-hurt batter) |
| `BatterRetired` | `batterRetired` | `batterId`, `hurt` | Retired hurt (not out, may return) or retired out (a wicket) |
| `StrikeSwapped` | `strikeSwapped` | — | Manual correction |
| `InningsClosed` | `inningsClosed` | `reason` | Declared / ended early |
| `MatchAbandoned` | `matchAbandoned` | `reason` | Ends the match with no result |

`id` must be unique per event (`newId()`). It is the key for idempotent cloud
sync later. `at` is stored as UTC ISO-8601.

### Phases (`MatchPhase`) drive the UI
`awaitingOpeners → awaitingBowler → inPlay ⇄ awaitingBatter`, then
`inningsBreak` (innings 1 complete; the next `OpenersSelected` starts innings 2
with target = first innings runs + 1), then `completed` (result set).

### Rules implemented (each has tests)
- **Strike:** rotates on odd *completed* runs; swaps at the end of an over.
  A new batter takes the dismissed batter's end (so after a caught dismissal
  the new batter faces, unless the over just ended).
- **Run-out ends (Law 38):** a run out records the end where the wicket was put
  down (`Wicket.end`). The not-out batter goes to the other end, whoever had
  crossed, and the new batter comes in at the run-out end; the end-of-over swap
  still follows. The wicket sheet pre-selects the end the out batter was running
  to and shows who faces next, from `LiveMatchNotifier.previewWicketBall`. Run
  outs logged before the field existed follow the runs completed.
- **Wide:** not a legal ball and not faced by the batter. Penalty
  (`wideRuns`, default 1) plus any runs go to wides and are charged to the
  bowler.
- **No-ball:** not a legal ball, but faced. Bat runs go to the batter. The
  penalty (`noBallRuns`) and bat runs are charged to the bowler; other runs off
  a no-ball are byes, or leg byes when `BallBowled.legByes` is set (only allowed
  on a no-ball, with no bat runs). The next ball is a **free hit** (configurable)
  and stays a free hit through wides / no-balls.
- **Byes / leg byes:** legal and faced, at least 1 run, not charged to the
  bowler.
- **Dismissals allowed per delivery** (`allowedDismissals`):
  - free hit, no-ball, bye or leg bye: run out and obstructing the field only;
  - wide: stumped, hit wicket, run out and obstructing;
  - legal ball: everything.

  Only run out and obstructing can dismiss the non-striker or come with runs.
  Bowled, caught, lbw, stumped and hit wicket are credited to the bowler.
- **No wicket after the winning runs:** a ball whose runs reach the target
  can't also carry a wicket (Law 16.6: the match ended first).
- **Retirements:** retired hurt is not a wicket and the batter may return.
  Retired out is a wicket.
- **Bowling:**
  - a bowler can't bowl two overs in a row, or parts of two consecutive overs
    (Law 17.8);
  - a mid-over change is allowed, and that over can't be a maiden;
  - optional max overs per bowler, where a part over counts against the limit;
  - nobody is ever left unable to bowl. When no one is free under the usual
    rules, `bowlingRelaxation` eases them in steps and uses the first that frees
    someone: a bowler from part of the last over (not the bowler of its last
    ball), then the overs limit lifted, then the bowler of the last over (only
    needed mid-over). It is derived from the state, so nothing new is stored and
    old matches replay the same. `bowlerBlockReasons` gives each greyed-out
    bowler a short reason for the picker;
  - a bowler gets a figures row only after bowling a ball.
- **Innings end:**
  - all out (`teamSize - 1` wickets, or `teamSize` with last man stands);
  - overs completed;
  - target reached;
  - closed manually.
- **Last man stands:** the lone batter is always on strike.
- **Result:** won by wickets (with balls remaining), won by runs, tie, or no result
  when abandoned.
- **Super Over:** `MatchRules.superOver` ends an innings at two wickets.

### Derived state (`state.dart`)
`MatchState`:
- `setup`, `phase`, `innings[]`, `result?`, `eventCount`;
- `current`: the latest innings.

`InningsState`:
- **score:** runs, wickets, legal balls, extras;
- **players:** `batters` (`BatterScore`), `bowlers` (`BowlerFigures`);
- **crease:** striker, non-striker and bowler ids, `lastOverBowlerId`;
- **overs:** `completedOvers` and `currentOver` (`BallSummary`: label, kind, runs,
  batter, bowler, direction and the score after the ball), with `overs`
  (`OverSummary`) and `shots` for the Overs tab and charts;
- **innings record:** fall of wickets, partnership runs and balls (balls faced,
  wides excluded);
- **status:** free hit, target, complete and close reason;
- **rule helpers:** `availableBatterIds`, `eligibleBowlerIds`;
- **getters:** `oversText`, `runRate`, `runsNeeded`, `requiredRunRate`,
  `ballsRemaining`, `batter(id)`, `bowler(id)`.

### Stats (`stats.dart`)
`computeStats` folds finished matches, oldest first, into a `StatsBook` of
`PlayerStats` and `TeamStats`. Nothing is stored. Definitions:
- Average: runs per dismissal, with no value until the batter is out. Retired
  hurt is not out.
- Bowling average is runs per wicket, strike rate balls per wicket, economy
  runs per over. Run outs are not credited to the bowler.
- Points: 2 for a win, 1 for a tie.
- Net run rate: runs per over scored minus conceded. A side bowled out is charged
  its full overs. A chase that ends early uses the overs actually faced.

MVP points (`matchPoints`): a run is a point, +1 a four, +2 a six, +5 for 30,
+10 for 50, +20 for 100, 20 a wicket, 10 a maiden, 8 for a catch, stumping or run
out. Player of the Match is the top score with winners weighted by 1.25, so a
standout performance on the losing side can still take it.

### Tournaments (`tournament.dart`)
A `Tournament` holds teams, groups and `Fixture`s, and each fixture may name the
match played for it. `progressOf` joins them with the matches to derive a table
per group (league games only, including teams yet to play), a `StatsBook` of every
game, `nextRound` (fixtures ready to schedule) and the champion. A deleted match
reopens its fixture.

Knockouts: one group pairs 1 v 4 and 2 v 3, or 1 v 2 for a final. Two groups pair
A1 v B2 and B1 v A2, or the group winners for a final. A tied knockout game gets a
decider fixture (`deciderOf`) played as a one-over match with
`MatchRules.superOver`, so an innings ends at two wickets and the side that batted
second bats first. A tied Super Over gets another. If a result changes after a knockout game is
scheduled, `outdated` offers that game with the teams the results now call for.

### Adding a rule or event (checklist)
1. Write the failing test in `engine_test.dart` using the `Scorer` helper
   (`start()`, `runs()`, `wide()`, `out()`, `rejects()`).
2. For a new event: add the class plus `typeName` in `events.dart`, add a
   `fromJson` switch case, handle it in `_MatchBuilder.apply` (the switch is
   exhaustive over the sealed class), and add a JSON round-trip assertion.
3. Make the derived state expose what the UI needs. The UI must not compute
   cricket logic.
4. Update this file's rule list and CHANGELOG.

## 2. App (`app/`)

### Data
- `MatchRecord` = `setup` + `events` + `createdAt` / `updatedAt`.
  `withEvents()` returns a copy.
- `MatchRepository`: `loadAll()` (newest first), `load(id)`, `save(record)`
  (upsert the whole record), `delete(id)`.
- `LocalDocuments`: generic JSON documents in shared_preferences, used by the
  match, team and tournament repositories. `read(id)` gives one document, or
  null if it is missing or unreadable.
- `LocalMatchRepository` (shared_preferences, through `LocalDocuments`):
  - storage layout:
    - `bnp_scorer.matchIds`: a list of ids;
    - `bnp_scorer.match.<id>`: the JSON of one `MatchRecord`;
  - a corrupt document is skipped, not fatal;
  - fine for hundreds of matches; move to Drift/SQLite before tournaments
    and stats.

- `TeamRepository`: `loadAll()` (by name), `save(team)`, `delete(id)`.
  `LocalTeamRepository` stores `bnp_scorer.teamIds` and `bnp_scorer.team.<id>`.
  `mergeIntoSquad` decides what to store when a match starts: the saved squad
  stays whole, newcomers are added, and "Fill to 11" placeholders are dropped.
- `TournamentRepository`: newest first. `LocalTournamentRepository` stores
  `bnp_scorer.tournamentIds` and `bnp_scorer.tournament.<id>`.
- `Backup`: versioned JSON of matches, teams and tournaments. `Backup.decode` checks
  the whole file first, and `restoreBackup` only adds missing records.
- **Cloud** (docs/ROADMAP.md "Cloud: shared matches"):
  - `Accounts` (`data/accounts.dart`): Google sign-in through Firebase Auth
    (`FirebaseAccounts`), or `LocalOnlyAccounts` in builds without the cloud and
    in tests. `accountsProvider`, `scorerProvider`.
  - `CloudMatches` (`data/cloud_matches.dart`): `matches/{id}` in Firestore, the
    `MatchRecord` JSON plus `ownerUid`, `ownerName`, `schema` and `savedAt`. The
    field names are a storage format, like the event JSON: never rename them.
  - Reading: `CloudMatches.recent` (newest 30 by `savedAt`, live) and `watch`
    (one match, live); `parsePublishedMatch` refuses a newer `schema`.
    `publicMatchesProvider` replays each match and leaves out ones that do not
    replay; `publishedMatchProvider` streams one. Neither retries on error:
    Firestore reconnects by itself, and retries cost reads.
  - `SyncingMatchRepository`: wraps the local repository. Saves locally first,
    then publishes the match if `MatchRecord.publishedBy` is the signed-in
    scorer, without awaiting the cloud (Firestore queues writes offline).
  - `main()` starts Firebase with `Firebase.initializeApp()`; the Android config
    comes from `google-services.json` through the Google Services Gradle plugin,
    which `app/build.gradle.kts` applies only when the file exists.
- `DeviceFiles`: the share sheet (image, file or plain text) and file picker,
  replaced in tests.
- `ErrorLog`: the last 20 uncaught errors with the top of their stack, in
  `bnp_scorer.errorLog`. A repeat of the newest error raises its count instead
  of adding an entry. `installErrorHandlers` (in `main()`) feeds it from
  `FlutterError.onError` and `PlatformDispatcher.onError`, still printing to the
  console, and replaces Flutter's error box with `FriendlyErrorPanel`. Nothing
  leaves the phone: Settings > Report a problem puts `problemReport` text (version,
  platform, a space to write, the errors) on the share sheet.

### State (Riverpod 3)
- `matchRepositoryProvider`: overridden in `main()` and in tests. It throws if
  not overridden.
- `teamRepositoryProvider` and `tournamentRepositoryProvider`, the same way.
- `savedTeamsProvider`, `tournamentsProvider` (with derived progress) and
  `statsProvider`, which follow the match list.
- `deviceFilesProvider`: defaults to the real platform, overridden in tests.
- `matchListProvider`: `FutureProvider.autoDispose` of
  `({MatchRecord record, MatchState state})` for the home list.
- `liveMatchProvider(matchId)`: `LiveMatchNotifier` (`AsyncNotifier`) holding
  `LiveMatch {record, state, saveFailed}`.
  - **Actions:** `openers`, `bowler`, `ball`, `newBatter`, `retire`,
    `swapStrike`, `closeInnings`, `abandon` each return `String?`. Null means success;
    otherwise it's the error to show. `undo()` returns `bool`.
    `previewWicketBall` returns the state a wicket would lead to without
    recording it, or null if it is not allowed.
  - **Flow:** `_add(event)` validates through `ScoringEngine.apply`, updates
    the state immediately (optimistic), then `_persist()` saves in the
    background.
  - **Save failure:** sets `saveFailed`, which shows a banner. The next
    successful save clears it, because every save writes the full log.

### A tap, end to end
Pad key → `ScoringScreen` handler (may open a sheet for runs / wicket details)
→ `notifier.ball(...)` → engine validates → new `MatchState` → widgets rebuild
from `state.phase` / `state.current` → record saved → home list invalidated.

### Screens
- **Home (the shell):** a floating bottom bar with four tabs (Matches,
  Tournaments, Stats, Teams) and a raised neon "+" that opens New match from any
  tab. Tabs live in an `IndexedStack`, are built on first visit and fade in when
  chosen. Back on another tab returns to Matches.
- **Matches tab:** brand header with a Settings button (System / Light / Dark,
  Account with Google sign-in in cloud builds, Backup, then About: version and privacy note inline (in cloud builds: public only once signed in, and the policy address), Report a problem and the
  licences), a floodlit hero card with a "New match" button and stumps art, three
  number tiles (played, live, tournaments), filter chips, match cards (live pill
  with an overs bar and a neon edge, or a result tag with the winner's trophy),
  long-press to delete with a warning for tournament matches, empty state. In
  cloud builds a "My matches / Everyone" switch sits under the header; Everyone
  shows published matches, live, with who scores each, and opens them to watch.
- **New match:**
  - teams and players (type names, "Fill to 11", or pick a saved team, with extra
    squad members sitting out);
  - overs (stepper and presets 5/6/8/10/12/15/20);
  - toss winner and decision;
  - house rules: wide / no-ball runs, free hit, last man stands, max overs per
    bowler (ceil(overs/5)), shot direction;
  - venue;
  - a sticky Start button that explains what is missing (`_blocker`);
  - for a tournament fixture, teams and title are filled and locked. A Super Over
    also hides the overs and toss, because the rules decide them.
- **Scoring:**
  - `ScoreHeader`: floodlit hero; runs and wickets roll up when they change; an
    overs ring fills through the innings; CRR / target / RRR or projected in
    glass tiles; a FOUR!, SIX! or WICKET! burst for the ball just bowled (not on
    undo or reopening), and a shake on a wicket;
  - confetti when the match is won while scoring (not on reopening a result);
  - free-hit and save-failure banners;
  - `OverStrip`: this over's chips;
  - `CreasePanel`: batters, partnership, swap, bowler figures;
  - a bottom panel that switches by phase: `OpenersPanel`, `BowlerPanel`,
    `BatterPanel`, `ScorePad`, `InningsBreakPanel`;
  - AppBar: undo, share, and a menu with change bowler, retire batter, end
    innings and abandon match;
  - tabs under the AppBar: Live (Result once finished), one per innings, Overs
    and Charts. Swiping between tabs is off while the match is in play, so a
    hurried drag on the pad cannot leave the Live tab; tapping a tab works.
    A new innings adds its tab (the controller is keyed by the tab count);
  - once finished, the first tab is `MatchResultTab`: `ResultHero` with
    tappable innings lines, Top batter and Best bowler cards that open the
    innings they came from, and shortcut tiles to the scorecard, Overs and
    Charts.
- **Score pad (3×4):**
  - `0 1 2 3` (long-press 3 for 5+);
  - `4 6 WD NB`: WD and NB open sheets for extra runs; the NB sheet chooses bat
    runs, byes or leg byes;
  - `BYE LB OUT Undo`: OUT opens the wicket sheet. Its delivery is legal, wide,
    no-ball, bye or leg bye, and it offers only the dismissal types the engine
    allows for that delivery, plus who is out, runs completed (extras on a
    wide, bye or leg bye), where a run out happened, who faces next, and the
    fielder / keeper.
- **Scorecard (tabs on the Scoring screen):** a tab per innings
  (`InningsScorecard`), then an Overs tab and a Charts tab. Each innings tab has:
  - `ResultHero`: every innings, the result or the state of play (LIVE), and the
    Player of the Match; the open innings is marked in neon, and tapping
    another innings switches to its tab;
  - batting, with a run bar under each batter scaled to the top score (neon for
    the top scorer), `*` for not out, and 4s and 6s in coloured badges;
  - extras as chips (only kinds that happened) and a floodlit total band;
  - yet to bat as chips;
  - the fall of wickets as a horizontal timeline of red markers;
  - bowling, with the best figures (most wickets, then fewest runs) highlighted
    and wickets in a red badge.
  Columns are sized per column (`_battingWidths`, `_bowlingWidths`) so names keep
  room at 360 dp.
- **Stats:** Teams, Batting, Bowling, MVP and Boundaries across every match, leading
  to team and player profiles.
- **Tournaments:** the list, then one tournament with Matches, Table, Batting,
  Bowling, MVP and Boundaries tabs. The Matches tab offers the next round in one
  tap and flags knockout games that a changed result has made wrong.
- **New tournament:** name, venue, teams, overs, optional dates, format.
- **Teams and Team edit:** squads, roles, captain, vice-captain, keeper.
- **Backup:** create a backup file, or restore from one.
- **Watch match:** someone else's published match, read-only and live. Same
  frame as scoring (`MatchTabsView`), with the score, this over and the crease on
  the Live tab, who scores it, and Share; no pad, undo or scoring menu. A match
  that is unpublished, or that this app cannot read, gets a plain message.

### Design system
- Light, dark, or follow the phone, chosen in Settings and stored as
  `bnp_scorer.themeMode` (`AppSettings`, `themeModeProvider`).
- **Brand:**
  - night `#07100C`, with the hero gradient `#173F2F` to `#0B1A14`. Hero cards
    (score, champions, leaders, share card) stay dark in both themes, like a
    floodlit scoreboard;
  - neon green `#2CF59E` as the accent and the fill of primary buttons, always
    with night text;
  - turf green `#007A4D` as `colorScheme.primary` in the light theme, for text
    and icons on light surfaces, where neon is too faint;
  - cards have a hairline edge (`cardShape`) for a glassy look in the dark.
- **Outcome colours** (the same in both themes):
  - four: amber `#FFB21E`;
  - six: violet `#7C4DFF`;
  - wicket: `#FF4D5E`;
  - extras: blue `#1C72D8`, so extras never read as the green of runs;
  - dot: `#9AA3B5`;
  - live: `#FF3B5C`.
- **Type:** Inter for UI. Barlow Condensed, the tall scoreboard face, for
  headings and for numbers with tabular figures, through `scoreStyle()` and
  `AppFonts.display`. Both ship in `app/assets/google_fonts/` and are never
  downloaded (`AppFonts.useBundledFonts()`); their OFL licences show in
  Settings > Open-source licences.
- **Motion** (`ui/motion.dart`), skipped when the phone asks for reduced motion:
  - list cards fade and lift in, staggered for the first eight (`EntranceFade`);
  - trophies spring in (`PopIn`);
  - screens rise and fade in on Android;
  - charts grow their bars and draw the worm when opened.
- **Interaction:**
  - 64 px pad keys with a press-scale animation and haptics. 4, 6 and OUT have
    a gradient and a glow;
  - score changes animate;
  - the next action is always shown in the bottom panel, so scorers never
    hunt for a menu.

## 3. Tests
- **Engine** (`dart test`, 146 tests):
  - `engine_test`: toss, phases, runs and strike, extras, wickets, retirements,
    bowling, innings and result, event log, `allowedDismissals`, `formatOvers`;
  - `stats_test`: batting, bowling, fielding, teams, no result, overs, MVP;
  - `tournament_test`: fixtures, formats, scheduling, progress, tied and abandoned
    knockouts, corrected results, storage;
  - `no_result_test`: abandoning a match and shot direction.
- **App** (`flutter test`, 161 tests):
  - data: `local_match_repository_test`, `team_repository_test`, `backup_test`,
    `demo_data_test`;
  - state: `live_match_test`;
  - flows, mostly at 360 dp: `scoring_flow_test`, `new_match_saved_teams_test`,
    `team_edit_test`, `tournament_screens_test`, `stats_screen_test`,
    `overs_timeline_test`, `match_charts_test`, `wagon_wheel_test`,
    `share_scorecard_test`.
- `test/fakes.dart`: in-memory match, team and tournament repositories (with
  `failSaves`) and `sampleRecord()` (team "a": Asha, Arun, Anil, Abdul; team "b": Bilal,
  Bharat, Bose, Bala; ids `a1…a4` and `b1…b4`; team "a" bats first).
