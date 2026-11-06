# Architecture

How BNP Scorer works, for anyone extending it. Rules for changing it are in
`AGENTS.md`.

## Repository layout

```
packages/cricket_engine/        Pure Dart scoring engine (no Flutter)
  lib/cricket_engine.dart       Public exports
  lib/src/models.dart           Player, Team, MatchRules, MatchSetup, enums
  lib/src/events.dart           MatchEvent (sealed) + 7 event types, JSON
  lib/src/state.dart            Immutable derived state: MatchState, InningsState, …
  lib/src/engine.dart           ScoringEngine.replay / apply, allowedDismissals
  test/engine_test.dart         Rules test suite (Scorer test helper)
app/                            Flutter app (package name bnp_scorer)
  lib/main.dart                 Loads SharedPreferences, overrides the repository
  lib/app.dart                  BnpScorerApp (MaterialApp, light/dark themes)
  lib/data/                     MatchRecord, MatchRepository, LocalMatchRepository, newId
  lib/state/                    providers.dart (repository, match list), live_match.dart
  lib/screens/                  Home, NewMatch, Scoring, Scorecard
  lib/widgets/                  Score hero, over strip, crease panel, pad, sheets, panels
  lib/theme/app_theme.dart      AppColors, AppFonts, AppTheme, scoreStyle()
  lib/ui/                       format.dart, feedback.dart, inputs.dart
  test/                         fakes, notifier tests, storage tests, scoring flow widget test
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
| `BallBowled` | `ballBowled` | `runsOffBat`, `extra` (`none/wide/noBall/bye/legBye`), `extraRuns`, `boundary`, `wicket?` {`type`, `batterOutId`, `fielderId?`} | One delivery |
| `NewBatter` | `newBatter` | `batterId` | Fills the empty slot (also a returning retired-hurt batter) |
| `BatterRetired` | `batterRetired` | `batterId`, `hurt` | Retired hurt (not out, may return) or retired out (a wicket) |
| `StrikeSwapped` | `strikeSwapped` | — | Manual correction |
| `InningsClosed` | `inningsClosed` | `reason` | Declared / ended early |

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
- **Wide:** not a legal ball and not faced by the batter. Penalty
  (`wideRuns`, default 1) plus any runs go to wides and are charged to the
  bowler.
- **No-ball:** not a legal ball, but faced. Bat runs go to the batter. The
  penalty (`noBallRuns`) and bat runs are charged to the bowler; other runs off
  a no-ball are counted as byes. The next ball is a **free hit** (configurable)
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
  - a bowler gets a figures row only after bowling a ball.
- **Innings end:**
  - all out (`teamSize - 1` wickets, or `teamSize` with last man stands);
  - overs completed;
  - target reached;
  - closed manually.
- **Last man stands:** the lone batter is always on strike.
- **Result:** won by wickets (with balls remaining), won by runs, or tie.

### Derived state (`state.dart`)
`MatchState`:
- `setup`, `phase`, `innings[]`, `result?`, `eventCount`;
- `current`: the latest innings.

`InningsState`:
- **score:** runs, wickets, legal balls, extras;
- **players:** `batters` (`BatterScore`), `bowlers` (`BowlerFigures`);
- **crease:** striker, non-striker and bowler ids, `lastOverBowlerId`;
- **overs:** `completedOvers` and `currentOver` (`BallSummary` label + kind,
  for the chips);
- **innings record:** fall of wickets, partnership runs and balls (balls faced,
  wides excluded);
- **status:** free hit, target, complete and close reason;
- **rule helpers:** `availableBatterIds`, `eligibleBowlerIds`;
- **getters:** `oversText`, `runRate`, `runsNeeded`, `requiredRunRate`,
  `ballsRemaining`, `batter(id)`, `bowler(id)`.

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
- `LocalMatchRepository` (shared_preferences):
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

### State (Riverpod 3)
- `matchRepositoryProvider`: overridden in `main()` and in tests. It throws if
  not overridden.
- `teamRepositoryProvider`, the same way, and `savedTeamsProvider` for the list.
- `matchListProvider`: `FutureProvider.autoDispose` of
  `({MatchRecord record, MatchState state})` for the home list.
- `liveMatchProvider(matchId)`: `LiveMatchNotifier` (`AsyncNotifier`) holding
  `LiveMatch {record, state, saveFailed}`.
  - **Actions:** `openers`, `bowler`, `ball`, `newBatter`, `retire`,
    `swapStrike`, `closeInnings` each return `String?`. Null means success;
    otherwise it's the error to show. `undo()` returns `bool`.
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
- **Home:** brand header, match cards (live pill or result, teams, scores),
  long-press to delete, lime "New match" FAB, empty state.
- **New match:**
  - teams and players (type names, or "Fill to 11");
  - overs (stepper and presets 5/6/8/10/12/15/20);
  - toss winner and decision;
  - house rules: wide / no-ball runs, free hit, last man stands, max overs per
    bowler (ceil(overs/5));
  - venue;
  - a sticky Start button that explains what is missing (`_blocker`).
- **Scoring:**
  - `ScoreHeader`: navy gradient hero, animated score, CRR / target / RRR or
    projected;
  - free-hit and save-failure banners;
  - `OverStrip`: this over's chips;
  - `CreasePanel`: batters, partnership, swap, bowler figures;
  - a bottom panel that switches by phase: `OpenersPanel`, `BowlerPanel`,
    `BatterPanel`, `ScorePad`, `InningsBreakPanel`, `ResultPanel`;
  - AppBar: undo, scorecard, and a menu with change bowler, retire batter and
    end innings.
- **Score pad (3×4):**
  - `0 1 2 3` (long-press 3 for 5+);
  - `4 6 WD NB`: WD and NB open sheets for extra runs; the NB sheet chooses bat
    runs or byes;
  - `BYE LB OUT Undo`: OUT opens the wicket sheet, which offers only the
    dismissal types the engine allows for the chosen delivery, plus who is out,
    runs completed and the fielder / keeper.
- **Scorecard:** a tab per innings with batting, extras, total, yet to bat,
  fall of wickets and bowling.

### Design system
- Light theme by default (readable in sunlight); dark theme supported.
- **Brand:**
  - ink navy `#0E1430` to `#26338A` for the hero gradient and primary;
  - floodlight lime `#D4FF3F` as the accent.
- **Outcome colours** (the same in both themes):
  - four: amber `#FFB21E`;
  - six: violet `#7C4DFF`;
  - wicket: `#FF4D5E`;
  - extras: teal `#12B5A6`;
  - dot: `#9AA3B5`;
  - live: `#FF3B5C`.
- **Type:** Inter for UI and Space Grotesk for numbers with tabular figures,
  through `scoreStyle()`.
- **Interaction:**
  - 64 px pad keys with a press-scale animation and haptics;
  - score changes animate;
  - the next action is always shown in the bottom panel, so scorers never
    hunt for a menu.

## 3. Tests
- **Engine** (`dart test`): 46 tests in groups toss, phases, runs and strike,
  extras, wickets, retirements, bowling, innings and result and event log,
  plus the `allowedDismissals` and `formatOvers` tests.
- **App** (`flutter test`):
  - `local_match_repository_test` (4): save/load newest first, re-save
    without duplicates, delete, corrupt record skipped;
  - `live_match_test` (6): legal and illegal events, undo, persistence, save
    failure, unknown id;
  - `scoring_flow_test` (1, widget): openers, then bowler, then a four, then
    undo, at 360 dp.
- `test/fakes.dart`: `InMemoryMatchRepository` (with `failSaves`) and
  `sampleRecord()` (team "a": Asha, Arun, Anil, Abdul; team "b": Bilal,
  Bharat, Bose, Bala; ids `a1…a4` and `b1…b4`; team "a" bats first).
