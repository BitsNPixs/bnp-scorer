# AGENTS.md — start here

Instructions for any coding agent (Claude Code, Codex, Cursor, Copilot, etc.) or
developer continuing **BNP Scorer**. Read this file fully before changing code.

## What this is
- **BNP Scorer**: a ball-by-ball cricket scoring app for local / gully matches,
  Android + iOS, built with Flutter. Owned by **Bits N Pixs (BNP)**.
- Long-term goal: a CricHeroes-style platform (live scores, teams, tournaments,
  stats). Scope is **cricket only**. v0.1 is the offline scorer.
- The UI must be **simple for local scorers and eye-catching** (big keys, clear
  colours, readable in sunlight). Keep that bar for every screen you add.

## Read in this order
1. `AGENTS.md` (this file): rules, status, gotchas.
2. `docs/ROADMAP.md`: product context, decisions, **what to do next**, open issues.
3. `docs/ARCHITECTURE.md`: how the engine, events, state, storage and UI fit.
4. `README.md`: setup and verify commands.
5. `CHANGELOG.md`: what changed and what is unverified.

## Current status (keep this section up to date)
- v0.1 **builds and runs on Android**. On 2026-11-06 analyze was clean for the
  app and engine, all tests passed (app 11, engine 46), and a debug APK was
  installed and launched on a physical phone (Android 17). Scoring has not been
  exercised by hand on a device yet. Only the debug build has been tried.
- Git is initialised. Commit each finished, verified piece of work.
- `app/android` is generated. `app/ios` is **not generated yet** and iOS is
  unverified (needs a Mac). See README "Setup".
- Saved teams work offline. A squad can gain players but there is no screen yet
  to remove one or to rename a player: delete the team and re-enter it.
- Stats (`computeStats`) cover finished matches only, grouped by team and player
  id, leaving out Super Overs. `StatsScreen` covers every match, and
  `TournamentScreen` covers one tournament.
- Abandoned matches give a point each, stay out of team run rates and totals, and
  still count for player stats.
- Tournament formats: one league or two groups (no more), one or two legs, and no
  knockouts, a final, or semi-finals and a final. Groups are split by the order of
  the team list and cannot be arranged by hand. League ties share a point and only
  knockout games go to a Super Over. Knockout rounds are offered by
  `TournamentProgress.nextRound`, and the scorer confirms them with one tap.
- Demo builds: `--dart-define=BNP_DEMO=true` seeds sample matches at launch
  (README "Demo data"). There is no tournament feature yet: the cup is only a
  set of ordinary matches, labelled through `venue`.
- `kotlin.incremental=false` in `app/android/gradle.properties` works around a
  Kotlin cache failure when the pub cache and project are on different drives.

## Working rules (from the project owner, mandatory)
1. Never assume. If requirements, behaviour or architecture are unclear, inspect
   the code first or ask.
2. Inspect before modifying: read the related code, config and docs first.
3. Reuse before creating (DRY). Search for an existing helper, widget or rule
   first. See "Reuse map" below.
4. Preserve consistency with existing architecture, naming and style.
5. Keep changes focused. Don't touch unrelated code.
6. Prefer simple, maintainable solutions. No new dependencies or abstractions
   without a clear need.
7. Every behaviour change gets tests (unit for logic, widget for UI flows),
   covering success, failure and edge cases. Never skip, weaken or delete a
   test to make the suite pass. Find the root cause instead.
8. Before every commit, in this order: implementation → tests → lint/analyze →
   build → docs (README / docs/ / CHANGELOG / this file's "Current status") →
   review the full diff for dead code, duplication and side effects.
9. Don't call a task done until the checks pass. Report clearly anything you
   could not test and why.
10. If you use sub-agents, they follow these same rules, and you review their
    output before accepting it.

## Architecture rules
- **Cricket rules live only in `packages/cricket_engine`** (pure Dart, no
  Flutter). Widgets ask the engine (`MatchPhase`, `allowedDismissals`,
  `InningsState.eligibleBowlerIds`, `availableBatterIds`) and never re-implement
  rules.
- **Event sourcing:** a match is `MatchSetup` + an ordered list of `MatchEvent`.
  All state is derived by `ScoringEngine.replay`. Never store or edit derived
  numbers. New scoring action = new event class (with JSON and a `fromJson`
  case) + handling in `engine.dart` + tests.
- **Validation before storage:** `ScoringEngine.apply` throws `ScoringException`
  (scorer-friendly message). The UI shows the message; illegal events never
  reach the log.
- **Event JSON is a storage format.** Existing type names and field names must
  stay readable. Add fields as optional with defaults. Never rename them.
- **Storage goes through `MatchRepository`, `TeamRepository` and
  `TournamentRepository`.** A tournament stores only fixtures and the match played
  for each: tables and champions are derived. A match keeps
  its own copy of its teams, so editing a saved squad never changes a past
  scorecard. Firebase / Drift become new
  implementations, not rewrites of the notifier.
- **State:** Riverpod 3 without code generation. One `AsyncNotifier` per live
  match (`liveMatchProvider(matchId)`). Notifier actions return
  `String?` (null = OK, else the error message to show).
- **Stats are derived too:** add a number to `stats.dart`, never store one.
- **Navigation:** plain `Navigator` (10 screens). Add go_router only with deep
  links (shared scorecards).
- **No code generation in v0.1** (no freezed, json_serializable, Drift or
  riverpod_generator). Models are hand-written and immutable.

## Reuse map (check before writing new UI)
| Need | Use |
| --- | --- |
| Card / panel surface | `SurfacePanel`, `SectionLabel` (`widgets/surface_panel.dart`) |
| Pick players | `PlayerChoiceGrid` (`widgets/player_choice_grid.dart`) |
| Bottom sheets | `SheetBody`, `RoundOption` (`widgets/scoring_sheets.dart`) |
| Avatars / team badges | `PlayerAvatar`, `TeamBadge`, `colorForName` (`widgets/avatars.dart`) |
| Ball chips (dot/4/6/W/extras) | `BallChip` (`widgets/over_strip.dart`) |
| Live indicator | `LivePill` (`widgets/score_header.dart`) |
| Big pad keys | `PadButton` (`widgets/score_pad.dart`) |
| Names, scores, figures, dismissal text, result line | `ui/format.dart` |
| Snackbars / action results | `showMessage`, `reportResult` (`ui/feedback.dart`) |
| Text field styling | `fieldDecoration` (`ui/inputs.dart`) |
| Colours, fonts, numbers | `AppColors`, `AppTheme`, `scoreStyle()` (`theme/app_theme.dart`) |
| New ids | `newId()` (`data/ids.dart`) |
| Stat lists and number grids | `LeaderRow`, `StatGrid`, `StatsEmpty` (`widgets/stat_widgets.dart`) |
| Stat text (`+1.25`, `48*`, `3/16`) | `decimal`, `signedDecimal`, `highScoreText`, `bestBowlingText` (`ui/format.dart`) |
| JSON documents in prefs | `LocalDocuments` (`data/local_documents.dart`) |
| Overs stepper and presets | `OversPicker` (`widgets/overs_picker.dart`) |
| Tournament logic | `roundRobinFixtures`, `leagueFixtures`, `progressOf` (`cricket_engine`, `tournament.dart`) |
| Saved squads | `TeamRepository`, `mergeIntoSquad` (`data/team_repository.dart`), `showSavedTeamsSheet` (`widgets/saved_teams_sheet.dart`) |

## Gotchas
- **Overflow:** any `Text` in a `Row` must be `Expanded`/`Flexible` with
  `maxLines` + ellipsis. Widget tests run at 360 dp in the FlutterTest font,
  where every glyph is 1em wide, so long labels overflow and fail the test.
- **Fonts:** widget tests must set `AppFonts.useGoogleFonts = false`
  (`setUpAll`). The app fetches Inter / Space Grotesk at runtime (README).
- **Riverpod 3 specifics used here:** `ref.mounted` after `await`;
  `AsyncValue.value` is nullable; tests build
  `ProviderContainer(retry: (_, _) => null)` and keep auto-dispose providers
  alive with `container.listen`.
- **Async UI:** guard every use of `context`/`ref` after `await` with
  `context.mounted` (lint `use_build_context_synchronously`).
- **Dart 3.8 features in use:** null-aware collection elements (`{?x}`) and
  wildcard `_` parameters. Don't lower the SDK constraint.
- Storage keys are `bnp_scorer.matchIds`, `bnp_scorer.match.<id>`,
  `bnp_scorer.teamIds`, `bnp_scorer.team.<id>`, `bnp_scorer.tournamentIds` and
  `bnp_scorer.tournament.<id>`. Changing them loses users' data.
- Name clash: "Crease" is another cricket app. The product name is BNP Scorer.
  The words crease / `CreasePanel` refer to the cricket crease, not the old name.

## Commands
```sh
# engine
cd packages/cricket_engine && dart pub get && dart analyze && dart test
# app
cd app && flutter pub get && flutter analyze && flutter test && flutter build apk --debug
```

## Definition of done for a change
Analyze is clean, all tests pass (new tests added), the debug build succeeds,
docs are updated (incl. "Current status" above and CHANGELOG), and the diff is
reviewed. Commit messages describe the why.
