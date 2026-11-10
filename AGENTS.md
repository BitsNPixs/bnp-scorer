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
- Latest run (2026-11-10): analyze clean, 146 engine and 209 app tests passing,
  and a debug demo build installed on a phone (Android 17).
- **UI redesign (2026-11-10):** night-pitch and neon-green look, a bottom bar
  (Matches, Tournaments, a raised "+" for a new match, Stats, Teams), and a
  System / Light / Dark switch in Settings, saved on the device. Animations follow
  the content: cards slide in, the overs ring fills, FOUR! / SIX! / WICKET! burst
  on the score card, confetti on a win. All are skipped when the phone asks for
  reduced motion.
- **Checked by hand on the phone so far:** launch, Home and its filter, Stats, a
  tournament's matches, New match with saved teams, the Overs tab. After the
  redesign: Home in dark and light, the Teams tab, the new icon, and the
  release build (screenshots, no taps). The Home chips no longer clip.
- **Not yet checked on a real phone:** the splash screen's mark, the redesigned
  Scorecard (seen only in test renders with the real fonts), the redesigned
  scoring screen, the bursts and confetti, the Settings sheet, the Tournaments
  and Stats tabs, sharing to WhatsApp, backup and restore (tests replace the
  share sheet and file picker), charts, the wagon wheel, Super Overs, and a full
  match scored by hand. See ROADMAP "Open issues".
- A release build (`flutter build apk --release`) was installed and ran on the
  phone on 2026-11-10. It is signed with the debug key, so it installs over a
  debug build; the Play Store will need a real upload key. iOS is untried.
- Work happens on the `dev` branch, which has not been merged to `main` or pushed.
  Commit each finished, verified piece of work.
- `test-team.xlsx` in the repo root holds real names. The owner wants it left out
  of git. The same names are in `app/lib/data/demo_data.dart`, which is tracked.
- App icon and splash: the BNP letters over a red seam on night. The PNGs are
  drawn by `app/tool/generate_app_icon_test.dart` with the bundled font; edit
  the art there and run it (`flutter test tool/generate_app_icon_test.dart`),
  never by hand. `test/app_icon_test.dart` checks sizes and wiring.
- `app/android` is generated. `app/ios` is **not generated yet** and iOS is
  unverified (needs a Mac). See README "Setup".
- Saved teams work offline and are edited on the Teams tab.
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
- Backups (`data/backup.dart`) are versioned JSON. Bump the version only for a
  change old readers cannot handle, and keep old files readable. Restore adds
  missing records and never overwrites.
- Demo builds: `--dart-define=BNP_DEMO=true` seeds teams, five finished
  tournaments and two friendlies at launch (README "Demo data"). All of it is
  simulated through the engine. Normal builds contain none of it.
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
- **Navigation:** plain `Navigator` (13 screens). `HomeScreen` is the shell:
  a bottom bar over four tabs (Matches, Tournaments, Stats, Teams) kept in an
  `IndexedStack`, built on first visit. Every other screen is pushed over it.
  Back on a tab other than Matches returns to Matches. Add go_router only with
  deep links (shared scorecards).
- **Theme:** colours come from `Theme.of(context).colorScheme` or `AppColors`.
  Neon (`AppColors.neon`) is a fill and an accent on dark surfaces. Text on light
  surfaces uses `colorScheme.primary`, which is deep green in the light theme.
  Hero cards stay dark in both themes.
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
| Colours, fonts, numbers | `AppColors`, `AppTheme`, `AppFonts.display`, `scoreStyle()` (`theme/app_theme.dart`) |
| Card edge, section heading | `cardShape`, `SectionTitle` (`widgets/surface_panel.dart`) |
| Entrance, pop and reduced motion | `EntranceFade`, `PopIn`, `reduceMotion` (`ui/motion.dart`) |
| Screen glow, confetti | `Floodlight`, `ConfettiBurst` (`widgets/stadium_effects.dart`) |
| Bottom bar | `AppBottomBar` (`widgets/app_bottom_bar.dart`) |
| Match card, number tiles, stumps art | `MatchCard`, `SummaryTiles`, `StumpsArt` (`widgets/`) |
| Match summary card, one innings' scorecard | `ResultHero` (`widgets/result_hero.dart`), `InningsScorecard` (`widgets/innings_scorecard.dart`) |
| Light / dark choice | `themeModeProvider`, `AppSettings` (`data/app_settings.dart`), `showSettingsSheet` |
| New ids | `newId()` (`data/ids.dart`) |
| Stat lists and number grids | `LeaderRow`, `StatGrid`, `StatsEmpty` (`widgets/stat_widgets.dart`) |
| Stat text (`+1.25`, `48*`, `3/16`) | `decimal`, `signedDecimal`, `highScoreText`, `bestBowlingText` (`ui/format.dart`) |
| JSON documents in prefs | `LocalDocuments` (`data/local_documents.dart`) |
| Overs stepper and presets | `OversPicker` (`widgets/overs_picker.dart`) |
| Tournament logic | `roundRobinFixtures`, `leagueFixtures`, `progressOf` (`cricket_engine`, `tournament.dart`) |
| Charts | `MatchCharts` (`widgets/match_charts.dart`), `AppColors.chartSeries`. Run the dataviz palette check before changing colours |
| Share sheet, file picker | `DeviceFiles` (`data/device_files.dart`), `deviceFilesProvider`. Override it in tests |
| Over-by-over data | `InningsState.overs`, `OverSummary`, `overHeadline` (`ui/format.dart`) |
| Saved squads | `TeamRepository`, `mergeIntoSquad` (`data/team_repository.dart`), `showSavedTeamsSheet` (`widgets/saved_teams_sheet.dart`) |

## Gotchas
- **Overflow:** any `Text` in a `Row` must be `Expanded`/`Flexible` with
  `maxLines` + ellipsis. Widget tests run at 360 dp in the FlutterTest font,
  where every glyph is 1em wide, so long labels overflow and fail the test.
- **Fonts:** widget tests must set `AppFonts.useGoogleFonts = false`
  (`setUpAll`). The app ships Inter and Barlow Condensed in
  `app/assets/google_fonts/` and never downloads them (README "Fonts"). Using a
  new weight or italic means adding it to the lists in `AppFonts` and its
  `.ttf` to that folder, or it draws in the system font. `main()` awaits
  `AppFonts.preload()` (at most 3 s) so no text is laid out in a fallback font
  first.
- **Riverpod 3 specifics used here:** `ref.mounted` after `await`;
  `AsyncValue.value` is nullable; tests build
  `ProviderContainer(retry: (_, _) => null)` and keep auto-dispose providers
  alive with `container.listen`.
- **Async UI:** guard every use of `context`/`ref` after `await` with
  `context.mounted` (lint `use_build_context_synchronously`).
- **Dart 3.8 features in use:** null-aware collection elements (`{?x}`) and
  wildcard `_` parameters. Don't lower the SDK constraint.
- Storage keys are `bnp_scorer.matchIds`, `bnp_scorer.match.<id>`,
  `bnp_scorer.teamIds`, `bnp_scorer.team.<id>`, `bnp_scorer.tournamentIds`,
  `bnp_scorer.tournament.<id>` and `bnp_scorer.themeMode`. Changing them loses
  users' data.
- **Animations in tests:** an animation starts its clock on the first frame after
  it starts, and reports done only once its time is past. After a tap, pump once,
  then pump past the duration (see `celebrations_test.dart`). Decorative
  animations must check `reduceMotion(context)`, and none may run longer than a
  test's settle step if it changes text a test reads.
- **`AnimatedDefaultTextStyle` replaces the inherited style** rather than merging
  it. Build its style from the theme (`textTheme.labelSmall!.copyWith`), or the
  text falls back to a serif face, as the bottom bar's labels once did.
- **Wrap and chips:** a `Container` with `alignment` fills its parent's width. Size
  to the content with `Center(widthFactor: 1)`, and test sizes as well as presence:
  `BallChip` once stretched across the screen with every test passing.
- **Wide tab bars:** scrollable tabs can start off-screen at 360 dp. Call
  `ensureVisible` before tapping one in a test.
- **Installing on a phone:** use `adb install -r`, which keeps saved data.
  `flutter install` can uninstall first.
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
