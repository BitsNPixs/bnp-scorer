# Changelog

## Unreleased

### Added
- Generated the Android platform folder (`app/android`), label "BNP Scorer".
- Demo data behind `--dart-define=BNP_DEMO=true` (`app/lib/data/demo_data.dart`):
  a five-match cup and a live friendly for four real squads. Matches are
  simulated through `ScoringEngine`, and normal builds are unaffected.

- Saved teams: squads are stored separately from matches (`TeamRepository`,
  keys `bnp_scorer.teamIds` and `bnp_scorer.team.<id>`). New match can fill a
  team from the list, extra players sit out, and teams are remembered when a
  match starts. Team and player ids stay the same across matches.

- Tournaments: round-robin fixtures, an optional final between the top two, a
  points table of league games, leaderboards per tournament and a champion. Stored
  as `bnp_scorer.tournamentIds` and `bnp_scorer.tournament.<id>`. Results stay in
  the matches, so all of it is derived. The demo build adds three past tournaments.
- Tournament formats: two groups, home and away, and semi-finals. New fields are
  optional, so tournaments saved earlier still load.
- Super Overs for tied knockout games, played as a one-over match with an innings
  ending at two wickets (`MatchRules.superOver`). A tied Super Over leads to
  another. They are left out of career stats.
- Teams screen: create and edit squads, with player roles, captain, vice-captain
  and wicket-keeper. Scorecards mark (c) and (wk). Renaming keeps a player's id, so
  their stats stay with them. All new fields are optional.
- No result: a match can be abandoned at any point (`MatchAbandoned`). Each side
  gets a point, it stays out of net run rate, and a knockout game goes to a Super
  Over.
- Home filter chips for each tournament and for friendlies.
- A changed result now flags any knockout game it affects: unplayed games can be
  corrected in one tap, and played ones are explained rather than silently left
  wrong. Deleting a tournament match warns that its table will change.
- Stats: `computeStats` in `cricket_engine` derives player and team numbers from
  finished matches. Home has a Stats button leading to a team table, batting and
  bowling leaderboards, and team and player profiles.

### Changed
- A team typed with a saved team's name now uses that team's ids, so a player's
  stats are not split across two identities.

### Fixed
- New match: the "Players · N" label no longer overflows next to "Fill to 11"
  on narrow screens.
- Android build: set `kotlin.incremental=false`, because compiling
  `shared_preferences_android` failed on Kotlin's incremental caches. The pub
  cache and project were on different drives, which is the suspected cause.

### Verified
- First real run: analyze clean, app and engine tests pass, debug APK installed
  and launched on a phone. iOS, release builds and full on-device scoring are
  still unverified.

## 0.1.0 — 2026-11-05

### Added
- `cricket_engine`: event-sourced scoring engine with validation, phases,
  free hits, house rules (wide/no-ball runs, last man stands, max overs per
  bowler), retirements, results, JSON serialisation, and a rules test suite.
- Flutter app: home, new match, live scoring and scorecard screens; local
  offline storage behind a `MatchRepository` interface; Riverpod 3 state;
  light and dark themes.

### Changed
- Renamed the app from "Crease" to **BNP Scorer** (Dart package `bnp_scorer`,
  storage keys `bnp_scorer.*`): another cricket app already uses "Crease".

### Docs
- Handoff docs for continuing with any coding agent: `AGENTS.md` (entry point:
  rules, status, reuse map, gotchas), `docs/ARCHITECTURE.md`,
  `docs/ROADMAP.md` (decisions, phases, open issues). `CLAUDE.md` imports
  `AGENTS.md`; README links to all of them.

### Fixed (from an independent code review, before first run)
- Scoring screen rows no longer overflow on narrow screens or large text
  (crease panel header, waiting-batter row, bowler figures, home match card).
- Law 17.8: a bowler who bowled any part of the previous over cannot bowl the
  next one (previously only the bowler who finished it was barred).
- Max overs per bowler: a part over counts, so a bowler can't start an over that
  would take them past the limit.
- A wicket can't be recorded on a ball whose runs already reach the target.
- Partnership balls count balls faced (no-balls included, wides excluded).
- A bowler replaced before bowling a ball no longer gets a 0-0-0-0 row.
- Save failures are caught and shown on the scoring screen instead of being
  unhandled; the next successful save recovers the full log.
- Match setup blocks a bowler limit that makes the innings impossible to finish.
- Ink splashes inside panels are visible; score animation no longer leaks a
  `CurvedAnimation`; null-aware collection elements for the Dart 3.8 lint;
  engine package aligned to Dart 3.8 and `lints` 6.

### Not yet verified
- Not compiled or tested: no Dart/Flutter SDK was available when this was
  written. Run the commands in README "Verify".
