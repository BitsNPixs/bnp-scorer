# Changelog

## Unreleased

### Added
- Report a problem: uncaught errors are kept on the phone (`ErrorLog`, last 20,
  repeats counted), and Settings shares a report with the version, platform and
  those errors through the share sheet. Needs no internet permission and no new
  dependency.
- A failed widget shows a calm "Something went wrong here" panel instead of
  Flutter's grey or red box (`FriendlyErrorPanel`).
- Settings > About shows the version and a privacy note inline: no account, no
  internet, nothing collected. A test keeps the version in step with pubspec.
- App icon and splash: the BNP letters in the scoreboard type over a red seam,
  on night. An adaptive icon with background, foreground and a monochrome layer
  for themed icons, legacy icons for older Android, and a night splash with the
  mark on Android 12+ and before, in light and dark. The images are drawn by
  `app/tool/generate_app_icon_test.dart`, and a test checks their sizes and
  wiring.
- Fonts ship with the app (`app/assets/google_fonts/`, about 2.4 MB with their
  OFL licences), and nothing is downloaded. The first launch now works offline
  and release builds need no internet permission. The files are the ones
  `google_fonts` fetched, checked against its SHA-256 hashes. Settings has an
  Open-source licences page that lists them.
- Generated the Android platform folder (`app/android`), label "BNP Scorer".
- Demo data behind `--dart-define=BNP_DEMO=true` (`app/lib/data/demo_data.dart`):
  a five-match cup and a live friendly for four real squads. Matches are
  simulated through `ScoringEngine`, and normal builds are unaffected. It has since
  grown to five tournaments, two friendlies and the four squads.
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
- Fixture dates: a start date and matches per day schedule a tournament, later
  rounds are dated after the latest game, and a long press moves a fixture.
- Boundary leaderboards, overall and per tournament.
- Charts: Manhattan and worm on a new scorecard tab, drawn from the ball data with
  no new dependency.
- Overs tab on the scorecard, listing every over ball by ball.
- Wagon wheel: an optional house rule records where scoring shots go, with a chart
  by innings and batter and a table of runs per zone.
- Backup and restore to a single file. A file is checked in full before anything
  is written, and restoring only adds what is missing. Adds `file_picker`.
- Share a scorecard as a branded image with a caption, through the phone's share
  sheet. Adds `share_plus`, behind `DeviceFiles`.
- Awards: Player of the Match, MVP rankings and Player of the Tournament, all
  derived from the matches by `matchPoints`.
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

- A bottom bar replaces Home's header buttons and More menu: Matches,
  Tournaments, Stats and Teams tabs around a raised "+" that starts a match from
  any tab. Back on another tab returns to Matches.
- Settings (top of Home): System, Light or Dark, applied at once and remembered
  (`bnp_scorer.themeMode`), plus the way into Backup.
- Animations fitted to what they show: match, tournament, team and leader cards
  slide in; the score rolls up; an overs ring fills on the score card; FOUR!, SIX!
  and WICKET! burst over it; a wicket shakes it; confetti falls on a win; charts
  draw in; trophies spring in; tabs fade between each other. All of them are
  skipped when the phone asks for reduced motion.

### Changed
- Release builds sign with an upload key from `app/android/key.properties`
  (gitignored; README "Release signing"), and fall back to the debug key, with
  a Gradle warning, when it is missing. Keystores are gitignored repo-wide.
- The scorecard is now tabs on the match screen (Live, each innings, Overs,
  Charts) instead of a separate screen behind a "Full scorecard" button.
  Swiping between tabs is off while scoring, so a hurried drag on the pad
  cannot leave the Live tab. A finished match opens on a Result tab: the result
  card (tap an innings to open it), Top batter and Best bowler cards that open
  the innings they came from, and shortcuts to the scorecard, Overs and Charts.
  Share moved to the match screen's top bar.
- Scorecard redesign: a floodlit result card (every innings, the result or LIVE,
  and the Player of the Match), run bars under batters scaled to the top score,
  `*` for not out, coloured badges for 4s, 6s and wickets, extras as chips, a
  total band, yet-to-bat chips, the fall of wickets as a timeline, and the best
  bowling figures highlighted. Columns are sized one by one so names stop
  wrapping onto three lines, and the tab bar no longer touches the screen edge.
  The result line now lives in the innings tabs, not above Overs and Charts.
- `home_screen.dart` is split: the shell stays, and the Matches tab, match card,
  number tiles and stumps art have their own files. No behaviour changed.
- `LocalMatchRepository` now stores through `LocalDocuments`, like teams and
  tournaments, instead of its own copy of the same code. Storage keys are
  unchanged, and a test pins them.
- The app's analyzer is as strict as the engine's (`strict-inference`,
  `strict-raw-types`), so missing generic types are caught.
- New look, after a reference the owner chose: a night pitch with neon green,
  glassy bordered cards, floodlit hero cards in both themes, and Barlow Condensed
  scoreboard numbers in place of Space Grotesk. Home has a hero card with a
  "New match" button and number tiles for played, live and tournament matches.
- Extras are blue (`#1C72D8`) instead of teal, so they never read as runs. Chart
  colours are unchanged and still pass the palette check against the new cards.
- Two tests follow the new layout: the demo Home test scrolls down to a finished
  match, now below the hero card, and the Stats test looks for "Teams" in the
  stats tabs rather than the bottom bar.
- A team typed with a saved team's name now uses that team's ids, so a player's
  stats are not split across two identities.

### Fixed
- A run out off a bye or leg bye gave the completed runs to the batter. The
  wicket sheet now offers Bye and Leg bye deliveries, which need at least one
  run, and the runs go to extras.
- Leg byes off a no-ball were recorded as byes. The no-ball sheet now offers
  Off the bat, Byes or Leg byes. `BallBowled` has an optional `legByes` field,
  written only when true, so older match logs and backups read as before.
- The delivery and no-ball choices are chips that wrap (`OptionChips`), since
  five segments would clip on a 360 dp phone.
- Filter chips on Home lost their last letter ("Pongal Trophy"). The fonts now
  load before the first frame, so no text is laid out in the narrower fallback
  font first. Not reproducible in tests; confirmed fixed on the phone.
- Ball chips stretched across the whole line on the Overs tab. They now size to
  their label, and tests check the size.
- A tournament with results but no boundaries showed a blank Boundaries tab.
- New match: the "Players · N" label no longer overflows next to "Fill to 11"
  on narrow screens.
- Android build: set `kotlin.incremental=false`, because compiling
  `shared_preferences_android` failed on Kotlin's incremental caches. The pub
  cache and project were on different drives, which is the suspected cause.

### Verified
- First real run: analyze clean, app and engine tests pass, debug APK installed
  and launched on a phone.
- Latest run: 146 engine and 184 app tests pass, and existing saved data loaded
  after every update. The redesigned Home was seen on a phone in dark and light;
  the rest of the redesign has been checked by tests only.
- First release build: installed over the debug build with data kept, opened
  in under 0.2 s with no crash, and drew the bundled fonts with no internet
  permission.
- The owner scored a match to its result on the redesigned scoring screen (the
  overs ring, the over strip and the result were seen). The scorecard tabs and
  Result tab that replaced the result panel are not yet seen on a phone.
- Still unverified: iOS, release builds, a full match scored by hand, and on a real
  phone, sharing, backup and restore, charts, the wagon wheel and the Teams screen.

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

### Not verified at the time
- Not compiled or tested: no Dart/Flutter SDK was available when this was
  written. The first real run is recorded under Unreleased.
