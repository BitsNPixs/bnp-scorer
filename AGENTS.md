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
- Latest run (2026-11-18): analyze clean, 182 engine and 308 app tests passing,
  beta 0.9.0-beta.3 (build 4) built with Firebase and upload-signed
  (`dist/bnp-scorer-0.9.0-beta.3.apk`), with cups, prizes, upcoming matches and
  their cloud. Pushed, with the policy live; the owner pasted the new
  `firestore.rules` and the owner's phone runs beta.3 (2026-11-17). Published
  as GitHub Release `v0.9.0-beta.3` (asset `bnp-scorer.apk`), which the
  website's Download for Android button serves (README "Beta builds"). A
  two-phone try of cups and schedules is still to come. **What to do next is
  in docs/ROADMAP.md "Next, in order".**
- **Cloud, step 4 (2026-11-17):** the privacy policy, website and Settings text
  cover sign-in and publishing, and the scorer name never falls back to the
  email. Beta.2 may go to testers once the site is pushed, so the policy link
  shows the new text. Before the Play upload: Data safety answers (README
  "Cloud"), in-app account deletion and a private contact for privacy requests
  (docs/ROADMAP.md "Cloud: shared matches").
- **Cloud, step 1 (2026-11-17):** Google sign-in in Settings and publishing a
  signed-in scorer's matches to Firestore (README "Cloud", docs/ROADMAP.md
  "Cloud: shared matches").
- **Cloud, step 3 (2026-11-17):** in cloud builds the Matches tab has a "My
  matches / Everyone" switch; Everyone lists the latest 30 published matches
  live, and tapping one opens `WatchMatchScreen`, a read-only view with the same
  tabs as scoring. Tried on 2026-11-17 across two phones: a match scored on the
  owner's phone updated live on a Pixel 9a (Android 16) that was not signed in.
  Step 1 was tried on the owner's phone on
  2026-11-17: Google sign-in worked, a new match was published as it was
  scored, older matches stayed private, and the cloud copy replays to the same
  score.
- **Beta prep (2026-11-17):** run outs off a bye or leg bye and leg byes off a
  no-ball now score correctly; release signing reads `app/android/key.properties`
  (README "Release signing"; the key is `C:/Users/AswinBlix/bnp-upload-keystore.jks`
  on the owner's machine, never in git); uncaught
  errors are kept on the phone (`ErrorLog`) and sent from Settings > Report a
  problem; Settings shows the version and a privacy note. The bowler picker never
  leaves the scorer stuck (`bowlingRelaxation`), and a run out records the end it
  happened at. The privacy policy is `site/privacy.html`, published to
  https://bitsnpixs.github.io/bnp-scorer/privacy.html (README "Website and
  privacy policy"). Beta 0.9.0-beta.1 (build 2) is an upload-signed APK, no demo
  data, shared over WhatsApp or Drive (README "Beta builds"). The remaining beta
  steps are in docs/ROADMAP.md "Beta readiness".
- **UI redesign (2026-11-10):** night-pitch and neon-green look, a bottom bar
  (Matches, Tournaments, a raised "+" for a new match, Stats, Teams), and a
  System / Light / Dark switch in Settings, saved on the device. Animations follow
  the content: cards slide in, the overs ring fills, FOUR! / SIX! / WICKET! burst
  on the score card, confetti on a win. All are skipped when the phone asks for
  reduced motion.
- **Checked by hand on the phone so far:** launch, Home and its filter, Stats, a
  tournament's matches, New match with saved teams, the Overs tab. After the
  redesign: Home in dark and light, the Teams tab, the new icon, the release
  build, and the scoring screen through to a result, scored by the owner. The
  Home chips no longer clip. On 2026-11-17: the beta (upload-signed) installed
  after an uninstall and launched cleanly, and a backup made on the old build
  restored everything on it.
- **Not yet checked on a real phone:** the new logo as icon and splash, the scorecard
  tabs and Result tab (seen only in test renders with the real fonts), the
  bursts and confetti, the Settings sheet and its Report a problem, the new
  wicket and no-ball sheet choices, the run-out end and the eased-rule note in
  the bowler picker, and the error panel (test renders only), the Tournaments and Stats tabs,
  sharing a scorecard image to WhatsApp (the tests replace the share sheet),
  charts, the wagon wheel, and Super Overs.
- A release build (`flutter build apk --release`) was installed and ran on the
  phone on 2026-11-10. Until `key.properties` exists it is signed with the debug
  key, so it installs over a debug build. Once a real key is used, phones must
  uninstall the debug-signed app first, which deletes their data. iOS is untried.
- Since 2026-11-17 work happens on `main`, which the owner pushed to
  `github.com/BitsNPixs/bnp-scorer` (a **public** repo); there is no `dev` branch.
  Commit each finished, verified piece of work; the owner pushes.
- `test-team.xlsx` in the repo root holds real names. The owner wants it left out
  of git. The same names are in `app/lib/data/demo_data.dart`, which is tracked;
  the owner is fine with them being public (2026-11-17).
- **Brand green (2026-11-18):** the app and website accent moved from mint
  neon to the Bits N Pixs green, with the night surfaces warmed to match, after
  the owner approved a preview of every screen in both themes. Chart colours
  passed the dataviz check on the new card surfaces. Website screens and the
  link preview were re-rendered.
- Logo, app icon and splash (2026-11-18): a cricket ball in the Bits N Pixs
  green (`AppColors.brandGreen`) with the company logo's thin b and p across
  it, after the owner's sketch `bnp-logo-idea.png` (repo root, untracked,
  like the company logo `bitsnpixs-offical-logo.webp`). On night the b is a
  cut-out and the p chalk, its stem running out of the ball.
  The art is `paintLogo` in `lib/widgets/logo_mark.dart`; `LogoMark` shows
  the ball in the Matches header and on the shared scorecard card, and
  `app/tool/generate_app_icon_test.dart` writes the Android icon layers, the
  splash mark and the website's `site/img/icon-64.png` (ball alone),
  `icon-512.png` (on night) and `logo.png` (ball, for the link preview) from
  it; edit the art in the widget and run the generator
  (`flutter test tool/generate_app_icon_test.dart`), never by hand, then
  `python tool/build_site_assets.py`. `test/app_icon_test.dart` checks sizes
  and wiring, site included. An upload-signed release (still beta.3, build 4)
  goes on the owner's phone after each icon change; whether it looks right
  there is not yet confirmed.
- Website screens: `app/tool/generate_screenshots_test.dart` renders the app with
  the demo data, and `app/tool/build_site_assets.py` makes `site/img/` and
  `site/fonts/` (README "Website and privacy policy"). Rerun both after a visible
  change; never edit the images by hand.
- `app/android` is generated. `app/ios` is **not generated yet** and iOS is
  unverified (needs a Mac). See README "Setup".
- Saved teams work offline and are edited on the Teams tab.
- Stats (`computeStats`) cover finished matches only, grouped by team and player
  id, leaving out Super Overs. `StatsScreen` covers every match, and
  `TournamentScreen` covers one tournament.
- Abandoned matches give a point each, stay out of team run rates and totals, and
  still count for player stats.
- Tournament formats: one league or two groups (no more), one or two legs, and no
  knockouts, a final, semi-finals or quarter-finals; or a straight knockout cup
  of up to 64 teams with byes, drawn in the order teams are ticked (Shuffle
  draw on New tournament). Cups and quarter-finals, the Bracket tab and the
  draw, and the Prizes tab with entry fees, are seen only in tests and
  real-font renders, not on a phone yet. Groups are
  split by the order of the team list and cannot be arranged by hand. League ties
  share a point and only knockout games go to a Super Over. Every knockout game
  is in `Tournament.bracket`; `TournamentProgress.nextRound` offers each as soon
  as its teams are known, and the scorer confirms with one tap. Prizes, entry
  fee, amounts paid (never published: `toPublicJson`) and rules are on the
  Prizes tab.
- **Upcoming (2026-11-17):** an Upcoming strip on Matches (dated fixtures not
  started, and friendlies set with "Schedule for later" on New match), with a
  sheet to start, change the time or ground, send a WhatsApp invite, or cancel.
  A long press on a fixture opens the same sheet. Tests and real-font renders
  only so far.
- **Cloud, cups (2026-11-17):** in cloud builds, a tournament created and a
  friendly scheduled while signed in are published (`firestore.rules` now has
  `tournaments` and `schedules`; payments are never sent, and the rules refuse
  them). Everyone gains Upcoming and Cups, and a cup opens read-only in
  `WatchTournamentScreen`. The rules are in the console (2026-11-17); not yet
  tried against the real Firestore.
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
- **Navigation:** plain `Navigator` (15 screens, with `WatchMatchScreen`,
  `WatchTournamentScreen` and `TournamentDetailsScreen`). `HomeScreen` is the shell:
  a bottom bar over four tabs (Matches, Tournaments, Stats, Teams) kept in an
  `IndexedStack`, built on first visit. Every other screen is pushed over it.
  Back on a tab other than Matches returns to Matches. Add go_router only with
  deep links (shared scorecards).
- **Theme:** colours come from `Theme.of(context).colorScheme` or `AppColors`.
  The accent (`AppColors.neon`, the brand green since 2026-11-18; the name is
  kept) is a fill and an accent on dark surfaces. Text on light surfaces uses
  `colorScheme.primary`, which is deep brand green in the light theme.
  Hero cards stay dark in both themes.
- **No code generation in v0.1** (no freezed, json_serializable, Drift or
  riverpod_generator). Models are hand-written and immutable.

## Reuse map (check before writing new UI)
| Need | Use |
| --- | --- |
| Card / panel surface | `SurfacePanel`, `SectionLabel` (`widgets/surface_panel.dart`) |
| Pick players | `PlayerChoiceGrid` (`widgets/player_choice_grid.dart`) |
| Bottom sheets | `SheetBody`, `RoundOption`, `OptionChips` (one choice as wrapping chips) (`widgets/scoring_sheets.dart`) |
| Avatars / team badges | `PlayerAvatar`, `TeamBadge`, `colorForName` (`widgets/avatars.dart`) |
| Ball chips (dot/4/6/W/extras) | `BallChip` (`widgets/over_strip.dart`) |
| Live indicator | `LivePill` (`widgets/score_header.dart`) |
| Coloured notice strip (failed save, free hit, eased rule) | `NoticeBanner` (`widgets/surface_panel.dart`) |
| Big pad keys | `PadButton` (`widgets/score_pad.dart`) |
| Names, scores, figures, dismissal text, result line, rupees (`rupees`, Indian grouping) | `ui/format.dart` |
| Snackbars / action results | `showMessage`, `reportResult` (`ui/feedback.dart`) |
| Text field styling | `fieldDecoration` (`ui/inputs.dart`) |
| Pick a day and time, ask for a ground | `pickDateTime`, `askGround` (`ui/pickers.dart`) |
| Upcoming matches: list, strip, sheet, invite | `upcomingMatches`, `UpcomingMatch` (`state/upcoming.dart`), `upcomingProvider`, `UpcomingStrip`, `showUpcomingSheet` (`widgets/upcoming.dart`), `inviteText`, `upcomingWhen` (`ui/format.dart`) |
| Start a fixture or scheduled friendly | `startFixtureMatch`, `startScheduledMatch` (`screens/new_match_screen.dart`) |
| Fake share sheet in tests | `TextShares` (`test/fakes.dart`) |
| Colours, fonts, numbers | `AppColors`, `AppTheme`, `AppFonts.display`, `AppFonts.body` (outside the theme), `scoreStyle()` (`theme/app_theme.dart`) |
| Card edge, section heading | `cardShape`, `SectionTitle` (`widgets/surface_panel.dart`) |
| Entrance, pop and reduced motion | `EntranceFade`, `PopIn`, `reduceMotion` (`ui/motion.dart`) |
| Screen glow, confetti | `Floodlight`, `ConfettiBurst` (`widgets/stadium_effects.dart`) |
| Bottom bar | `AppBottomBar` (`widgets/app_bottom_bar.dart`) |
| Match card, number tiles, stumps art | `MatchCard`, `SummaryTiles`, `StumpsArt` (`widgets/`) |
| The logo (ball), in a header or drawn to a canvas | `LogoMark`, `paintLogo` (`widgets/logo_mark.dart`) |
| A match screen's frame (title, Live/Result, innings, Overs, Charts, confetti) | `MatchTabsView` (`widgets/match_tabs_view.dart`), used by scoring and watching |
| Match summary card, one innings' scorecard, finished-match tab | `ResultHero` (`widgets/result_hero.dart`), `InningsScorecard` (`widgets/innings_scorecard.dart`), `MatchResultTab` (`widgets/match_result_tab.dart`) |
| Light / dark choice | `themeModeProvider`, `AppSettings` (`data/app_settings.dart`), `showSettingsSheet` |
| New ids | `newId()` (`data/ids.dart`) |
| Error log, problem report text | `ErrorLog`, `problemReport` (`data/error_log.dart`), `errorLogProvider` |
| Error hooks, error box | `installErrorHandlers`, `FriendlyErrorPanel` (`ui/error_handling.dart`) |
| App version | `appVersion`, `appBuild`, `appVersionLabel` (`data/app_info.dart`) |
| Stat lists and number grids | `LeaderRow`, `StatGrid`, `StatsEmpty` (`widgets/stat_widgets.dart`) |
| Stat text (`+1.25`, `48*`, `3/16`) | `decimal`, `signedDecimal`, `highScoreText`, `bestBowlingText` (`ui/format.dart`) |
| JSON documents in prefs | `LocalDocuments` (`data/local_documents.dart`) |
| Sign-in, the scorer | `Accounts`, `Scorer`, `accountsProvider`, `scorerProvider` (`data/accounts.dart`); `FakeAccounts` in tests |
| Published matches | `CloudMatches`, `PublishedMatch`, `parsePublishedMatch` (`data/cloud_matches.dart`), `SyncingMatchRepository`, `publisherOf`, `sendInBackground`, `cloudMatchesProvider`, `publicMatchesProvider`, `publishedMatchProvider`; `FakeCloudMatches` in tests |
| Published tournaments and friendlies | `CloudCups`, `PublishedTournament`, `PublishedSchedule` (`data/cloud_cups.dart`), `SyncingTournamentRepository`, `SyncingScheduleRepository` (`data/syncing_cups.dart`), `cloudCupsProvider`, `publicTournamentsProvider`, `publicUpcomingProvider`, `publicTournamentProgressProvider`; `FakeCloudCups` in tests |
| A tournament's tabs, own or watched | `TournamentView` (`screens/tournament_screen.dart`) |
| Gone or unreadable notice | `ScreenMessage` (`screens/watch_match_screen.dart`) |
| Overs stepper and presets | `OversPicker` (`widgets/overs_picker.dart`) |
| Tournament logic | `roundRobinFixtures`, `leagueFixtures`, `knockoutFixtures`, `knockoutBracket`, `Tournament.bracket`, `sideName`, `progressOf` (`cricket_engine`, `tournament.dart`) |
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
  `bnp_scorer.tournament.<id>`, `bnp_scorer.scheduleIds`,
  `bnp_scorer.schedule.<id>`, `bnp_scorer.themeMode` and
  `bnp_scorer.errorLog`. Changing them loses users' data.
- **Cloud config:** `app/android/app/google-services.json` is gitignored. Builds
  without it have no sign-in. Firestore field names on `matches/{id}` are a
  storage format: never rename them. Rule changes go in `firestore.rules` and
  are pasted into the console by the owner.
- **Version:** bump `version:` in `app/pubspec.yaml` and `data/app_info.dart`
  together (`test/app_info_test.dart` fails otherwise). The build number must
  rise with every Play upload.
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
