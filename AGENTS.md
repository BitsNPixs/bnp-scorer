# AGENTS.md — start here

Instructions for any coding agent (Claude Code, Codex, Cursor, Copilot, etc.) or
developer continuing **BNP Scorer**. Read this file fully before changing code.

## What this is
- **BNP Scorer**: a ball-by-ball cricket scoring app for local / gully matches,
  Android + iOS, built with Flutter. Owned by **BitsNPixs Technologies Private Limited (BNP)**.
- Long-term goal: a CricHeroes-style platform (live scores, teams, tournaments,
  stats). Scope is **cricket only**. v0.1 is the offline scorer.
- The UI must be **simple for local scorers and eye-catching** (big keys, clear
  colours, readable in sunlight). Keep that bar for every screen you add.

## Read in this order
1. `AGENTS.md` (this file): rules, status, gotchas.
2. `docs/ROADMAP.md`: product context, decisions, **what to do next**, open issues.
   `docs/PLAYER_PROFILES.md`: the registered-players work, step by step.
3. `docs/ARCHITECTURE.md`: how the engine, events, state, storage and UI fit.
4. `README.md`: setup and verify commands.
5. `CHANGELOG.md`: what changed and what is unverified.

## Current status (keep this section up to date)
- **Website and API, stage 3 of 6: the public API (2026-11-27), deployed.**
  Planned with the owner (docs/ROADMAP.md "Website and API"): a Dart
  service on Cloud Run replays each saved match with `cricket_engine` and
  stores ready-to-read copies that an API, the website and later an admin
  page read. Live: `packages/match_view` (pure Dart, 15 tests: the wording
  moved from `ui/format.dart`, re-exported there, `matchCard` / `matchView`
  and `matchNow`); the private service `bnp-api-projector` with its
  trigger, storing `matchCards/{id}` and `matchViews/{id}` on every save
  (tried from the owner's phone: balls, undos and a deleted match); and
  the public read-only API `bnp-api`
  (`https://bnp-api-482745302753.asia-south1.run.app`, `/v1/matches` and
  `/v1/matches/{id}`, 41 tests in `cloud/api`), checked against the live
  service (README "API server"). The owner runs `sh cloud/api/deploy.sh`:
  the assistant's permission check refuses to deploy a public service. A
  match not finished and not saved for six hours is `stopped`, never live
  for ever: the API sends it as `state`, and the app shows STOPPED on
  match cards and the watch screen and leaves it out of the Live tile
  (seen in a real-font render, not on a phone). **Stage 4 is done and
  live** (pushed 2026-11-27, pages checked on GitHub Pages): `site/matches.html` and `site/match.html?id=…` read the API
  (`site/matches.js`, `site/matches.css`, 17 Node tests in `site_tests/`),
  approved by the owner from renders at 360 dp; the home page and privacy
  policy link and cover them; and a published match's share sheet has
  "Share a link to the match" (545 app tests). Not seen in a phone's
  browser, and the link not shared from a phone, yet. Next: stage 5, the app reads the
  stored copies.
- **Notifications, stage 3 of 5: follow a live match (2026-11-26).** The
  engine's `momentOf` (`moments.dart`) finds the start, a wicket, a fifty or
  hundred, a five-for, the innings break and the result from the state
  before and after one event; `matchHighlight` (`ui/format.dart`) words it,
  and `SyncingMatchRepository` publishes it as `highlight` on the match
  (clipped to the rules' 120/200 characters). The Function `matchHighlight`
  sends a new `seq` once to devices whose `follows` holds the match and want
  "follow", never to the scorer. A bell on `WatchMatchScreen` follows
  (`followedMatchesProvider`, two days), turning the kind on if needed; a
  tapped update opens the match. Tests pass; **the new rules must be in the
  console before this build reaches a phone** (it writes `follows`), then
  deploy the Function and try two phones.
- **Notifications, stage 2 of 5: push setup (2026-11-26).** The Firebase
  CLI (Homebrew) and `cloud/functions` (TypeScript, Node 22, `asia-south1`,
  9 Vitest tests) with `pushTest`; the app (`firebase_messaging`, Android
  only until an APNs key) registers a signed-in phone in `pushDevices`
  once a kind is on in Settings > Notifications, removes it before sign-out,
  and shows pushes that arrive while open. Rules for `pushDevices` are in
  `firestore.rules`. **Deployed 2026-11-26:** the project is on Blaze
  (upgraded that day), the rules are in the console, `pushTest` is live in
  asia-south1 with a 1-day build-image cleanup policy. **Tried on the
  owner's phone (2026-11-26):** a debug build from the Mac (its debug key
  now registered in Firebase), signed in, Team activity on, and the test
  push arrived (Function log: sent 1, failed 0). The phone had a backup made
  first, then beta.7 was uninstalled for the differently signed build. The
  three kinds' switches send nothing until stages 3 to 5, so don't release
  between stages.
- **Notifications, stage 1 of 5: match reminders (2026-11-26).** Decided
  with the owner: all four kinds (reminders, following a live match, team
  activity, cup updates), pushes sent by Firebase Functions, Android first
  and iOS push once the paid Apple account exists, permission asked at the
  moment it is needed (docs/ROADMAP.md "Notifications"). Built: reminders
  made on the phone (`flutter_local_notifications`, `timezone`), an offer
  above the Upcoming strip, a Remind me switch on each upcoming sheet (one
  switch for this phone's matches; per match for Everyone's), a bell on
  reminded cards, Settings > Notifications with how long before, and a tap
  opening the match. AGP is now 9.1.1 and compileSdk 37 (the plugin needs
  both). Tests, analyze and both builds pass; not yet seen firing on a phone.
- **Registered players, all built (2026-11-21), beta 0.9.0-beta.7 (build 8):**
  analyze clean, 192 engine, 477 app and 8 Worker tests passing, built with
  Firebase and upload-signed (`dist/bnp-scorer-0.9.0-beta.7.apk`), installed
  on the owner's phone (`adb install -r`), **not released**; the owner pushes.
  In it: sign in with Google or a mobile number (SMS code; a number account
  is asked for a name once and can link Google); confirm a number to claim a
  player profile; the `PlayerProfileScreen` (big photo header that collapses,
  Info, Batting, Bowling, Career, after the owner's CricHeroes and Cricbuzz
  references) built from everyone's published matches with the player's id
  (`playerIds`); owner-edited role, styles, home town and photo; add players
  by number, typed or from contacts (Android's picker, no permission), on a
  team's page and New match; shared teams with join code, QR, WhatsApp text
  and `site/join.html`, join requests the captain accepts; team logos;
  scorecard rows open profiles; tab pills inset app-wide (owner's feedback).
  Photos and logos go to the R2 bucket `bnp-photos` through the Worker
  `cloud/photos-worker`, live at https://bnp-photos.quikfly-api.workers.dev
  (the app's default `BNP_PHOTOS_URL`). New dependencies: `qr_flutter`,
  `image_picker`.
  **Tried on the owner's phone (2026-11-21):** confirming a test number
  (after turning on the Phone provider and the SMS region policy, which
  blocks test numbers too) and uploading a profile photo. **Not yet tried
  on a phone:** number sign-in from signed out, add by number, the contact
  picker, invites and joins, team logos, the new header with a 1024 px
  photo, opening the app from the join page, and anything with two phones.
  Owner's open steps and what is next: docs/ROADMAP.md "Next, in order" and
  docs/PLAYER_PROFILES.md.
- Previous run (2026-11-18): analyze clean, 182 engine and 357 app tests passing,
  beta 0.9.0-beta.6 (build 7) built with Firebase and upload-signed
  (`dist/bnp-scorer-0.9.0-beta.6.apk`): beta.5 (cups, prizes, upcoming
  matches, cloud, ball logo, brand green, pasting and importing squads, the
  CSV template) with the company spelled BitsNPixs in Settings and the
  licences screen. Published as GitHub Release `v0.9.0-beta.6` (asset
  `bnp-scorer.apk`), which the website's Download for Android button serves
  (README "Beta builds"), and installed on the owner's phone. The privacy policy
  covers the clipboard read and imported files. A two-phone try of
  cups and schedules is still to come. **What to do next is in
  docs/ROADMAP.md "Next, in order".**
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
  restored everything on it. On 2026-11-18: beta.4 installed over beta.3
  keeping data, and a screenshot showed Home in the brand green with the ball
  logo in the header; beta.5 and then beta.6 installed over it, keeping data.
- **Not yet checked on a real phone:** pasting a list, importing a CSV and
  sharing the template (tests and real-font renders only), the ball logo as
  launcher icon and splash, the scorecard tabs and Result tab (seen only in
  test renders with the real fonts), the bursts and confetti, the Settings sheet and its Report a problem, the new
  wicket and no-ball sheet choices, the run-out end and the eased-rule note in
  the bowler picker, and the error panel (test renders only), the Tournaments and Stats tabs,
  sharing a scorecard image to WhatsApp (the tests replace the share sheet),
  charts, the wagon wheel, and Super Overs.
- A release build (`flutter build apk --release`) was installed and ran on the
  phone on 2026-11-10. Until `key.properties` exists it is signed with the debug
  key, so it installs over a debug build. Once a real key is used, phones must
  uninstall the debug-signed app first, which deletes their data. iOS runs in the Simulator only (below).
- Since 2026-11-17 work happens on `main`, which the owner pushed to
  `github.com/BitsNPixs/bnp-scorer` (a **public** repo); there is no `dev` branch.
  Commit each finished, verified piece of work; the owner pushes.
- `test-team.xlsx` in the repo root holds real names. The owner wants it left out
  of git. The same names are in `app/lib/data/demo_data.dart`, which is tracked;
  the owner is fine with them being public (2026-11-17).
- **Brand green (2026-11-18):** the app and website accent moved from mint
  neon to the BitsNPixs green, with the night surfaces warmed to match, after
  the owner approved a preview of every screen in both themes. Chart colours
  passed the dataviz check on the new card surfaces. Website screens and the
  link preview were re-rendered.
- Logo, app icon and splash (2026-11-18): a cricket ball in the BitsNPixs
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
  and wiring, site included. Beta.4 carries it. The bottom bar's Matches
  tab keeps its bat and ball icon (owner's call, 2026-11-18).
- Website screens: `app/tool/generate_screenshots_test.dart` renders the app with
  the demo data, and `app/tool/build_site_assets.py` makes `site/img/` and
  `site/fonts/` (README "Website and privacy policy"). Rerun both after a visible
  change; never edit the images by hand.
- `app/android` and `app/ios` are generated. **iOS (2026-11-26):** generated
  on the owner's Mac (bundle ID `com.bitsnpixs.bnpscorer`, minimum iOS 15,
  plugins through Swift Package Manager, no Podfile); a debug build ran in
  the iPhone 17e Simulator (iOS 27.2) to the Matches home. The contact
  picker and invite links have no Swift side yet (both fall back quietly). Cloud: the iOS app is in Firebase and its gitignored
  `GoogleService-Info.plist` is copied in, with the sign-in URL schemes, by
  the Runner build step "Copy Firebase Config" (README "Cloud"); installed
  on the iPhone, sign-in not yet tried there. The iOS app icon is still Flutter's default: the icon generator
  writes Android only. A release, signed by the owner's free Personal
  Team through the gitignored `ios/Flutter/Signing.xcconfig`, was installed
  on an iPhone 16 Pro Max the same day and opens there. See README "Setup" and
  docs/ROADMAP.md "iOS".
- Saved teams work offline and are edited on the Teams tab.
- **Squad import (2026-11-18):** "Paste a list" on New match and the team page
  reads a WhatsApp-style list (marks like (c) and (wk) apply on the team page);
  the Teams tab imports a CSV saved from Excel or Google Sheets, in either of
  two shapes, with a preview before saving, after a first sheet that shows the
  format and shares the CSV template. No new dependency: .xlsx is refused with
  save-as-CSV steps. Released in beta.5 (beta.6 too) and on the owner's phone, not yet
  tried there.
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
   website → review the full diff for dead code, duplication and side effects.
   **Website:** a feature users can see also goes into the feature list on
   `site/index.html` (and its FAQ when it answers a common question), and a
   change to a screen shown there re-renders the screenshots (README "Website
   and privacy policy"). Owner's rule, 2026-11-18: the site always lists every
   feature in the app.
9. Don't call a task done until the checks pass. Report clearly anything you
   could not test and why.
10. If you use sub-agents, they follow these same rules, and you review their
    output before accepting it.

## Architecture rules
- **How a match reads lives in `packages/match_view`** (pure Dart): the words
  for scores, dismissals and results, and the JSON of a match (`matchCard`,
  `matchView`). Its field names are a storage and API format: add, never
  rename. The app re-exports the wording from `ui/format.dart`.
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
  deep links (shared scorecards). Team invite links come in through
  `AppLinks` and open a sheet, not a route.
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
| Live indicator, status word (RESULT, STOPPED) | `LivePill`, `StatusTag` (`widgets/score_header.dart`) |
| Coloured notice strip (failed save, free hit, eased rule) | `NoticeBanner` (`widgets/surface_panel.dart`) |
| Big pad keys | `PadButton` (`widgets/score_pad.dart`) |
| A published match's page on the website, and the message that shares it | `matchPageLink`, `matchPageAddress`, `matchLinkText`, `shareText(state, link:)` (`ui/format.dart`); `showShareScorecardSheet(..., publishedMatchId:)` |
| Names, scores, figures, dismissal text, result line, rupees (`rupees`, Indian grouping) | `ui/format.dart` (the match wording comes from `packages/match_view`; add shared wording there) |
| A match as JSON for the API and website | `matchCard`, `matchView`, `stageOf`, `matchViewVersion` (`packages/match_view`) |
| Is a match live, stopped or finished right now; the time in a widget | `matchNow`, `MatchNow`, `stoppedAfter` (`packages/match_view`); `nowOf`, `clockProvider` (`state/providers.dart`; override the clock in tests) |
| The server's stored copies of a match | `copiesOf`, `Projector`, `MatchStore`, `FirestoreMatchStore`, `projectorHandler`, `cardsCollection`, `viewsCollection` (`cloud/api/lib`); `FakeMatchStore`, `matchDoc` in its tests |
| The website's match pages | `site/matches.js` (helpers `sides`, `tabsOf`, `groupMatches`, `ago`, `trustedLogo`, `refreshMs`; `BnpMatches.initList`, `initMatch`), `site/matches.css`; sample API answers for previews: `dart run tool/sample_views.dart <folder>` in `packages/match_view` |
| The public API over the copies | `apiHandler`, `MatchReads`, `FirestoreMatchReads`, `matchNow`, `MatchNow`, `stoppedAfter`, `saveTimeText`, `liveSeconds`, `finishedSeconds` (`cloud/api/lib`); `FakeReads` in its tests |
| Snackbars / action results | `showMessage`, `reportResult` (`ui/feedback.dart`) |
| Text field styling | `fieldDecoration` (`ui/inputs.dart`) |
| Pick a day and time, ask for a ground | `pickDateTime`, `askGround` (`ui/pickers.dart`) |
| Match reminders: plan, settings, switches, the phone's notifications | `planReminders`, `ReminderLead`, `WatchedReminder`, `isReminderPayload` (`state/reminders.dart`), `reminderSettingsProvider`, `reminderSyncProvider`, `deviceNotificationsProvider`; `DeviceNotifications` (`data/device_notifications.dart`); `ReminderOffer`, `ReminderSwitch`, `ReminderSettingsPanel` (`widgets/reminders.dart`); `FakeDeviceNotifications` in tests |
| Match moments for followers: find, word, follow | engine `momentOf`, `MatchMoment`, `MomentKind` (`moments.dart`); `momentText`, `matchHighlight`, `scoreVersus`, `clip` (`ui/format.dart`); `MatchHighlight` (`data/cloud_matches.dart`); `followedMatchesProvider`, `FollowMatchButton` (`widgets/push_settings.dart`); Functions `newHighlight`, `sendHighlight` |
| Push: kinds, registration, sending | `PushKind`, `PushMessages`, `PushDevices`, `PushDevice` (`data/push_messages.dart`), `PushRegistration` (`data/push_registration.dart`), `pushKindsProvider`, `pushSyncProvider`, `pushRegistrationProvider`, `permitNotifications`; `PushSettingsPanel` (`widgets/push_settings.dart`); Functions: `sendToUsers`, `sendToDevices` (`cloud/functions/src/push.ts`); `FakePushMessages`, `FakePushDevices` in tests |
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
| Label and value rows, numbers by row and column | `KeyValueTable`, `StatsTable` (keys `stat:<row>:<column>` for tests) (`widgets/stat_widgets.dart`) |
| A player's profile and career | `openPlayer`, `PlayerProfileScreen`, `careerColumns`, `matchesIn` (`screens/player_profile_screen.dart`), `playerCareerProvider`; engine `playerMatchLines`, `formatOf` |
| Players by mobile number, numbers | `PlayerDirectory`, `PlayerProfile` (`data/player_directory.dart`), `playerDirectoryProvider`, `playerProfileProvider`; `normalizePhone`, `maskPhone`, `phoneHash` (`data/phone_numbers.dart`); `FakePlayerDirectory` in tests |
| Add a player by mobile number, same-name check | `showAddByNumberSheet`, `confirmSamePlayer`, `signInToAddByNumber` (`widgets/add_by_number_sheet.dart`); `mergeIntoSquad(..., sameAs:)` |
| A player edits their own profile | `showEditProfileSheet` (`widgets/edit_profile_sheet.dart`), `PlayerDirectory.saveDetails`, `BattingStyle`, `BowlingArm`, `BowlingType` |
| Confirm the scorer's own number | `showPhoneLinkSheet` (`widgets/phone_link_sheet.dart`), `myProfileProvider` |
| Tab bar pill | `PillTabIndicator` (`theme/app_theme.dart`), set in both themes |
| Stat text (`+1.25`, `48*`, `3/16`) | `decimal`, `signedDecimal`, `highScoreText`, `bestBowlingText` (`ui/format.dart`) |
| JSON documents in prefs | `LocalDocuments` (`data/local_documents.dart`) |
| Sign-in, the scorer | `Accounts` (Google, or a mobile number with `requestPhoneCode`/`confirmPhone`, `setName`, `linkGoogle`), `Scorer`, `accountsProvider`, `scorerProvider` (`data/accounts.dart`); `FakeAccounts` in tests |
| Published matches | `CloudMatches`, `PublishedMatch`, `parsePublishedMatch` (`data/cloud_matches.dart`), `SyncingMatchRepository`, `publisherOf`, `sendInBackground`, `cloudMatchesProvider`, `publicMatchesProvider`, `publishedMatchProvider`; `FakeCloudMatches` in tests |
| Published tournaments and friendlies | `CloudCups`, `PublishedTournament`, `PublishedSchedule` (`data/cloud_cups.dart`), `SyncingTournamentRepository`, `SyncingScheduleRepository` (`data/syncing_cups.dart`), `cloudCupsProvider`, `publicTournamentsProvider`, `publicUpcomingProvider`, `publicTournamentProgressProvider`; `FakeCloudCups` in tests |
| A tournament's tabs, own or watched | `TournamentView` (`screens/tournament_screen.dart`) |
| Gone or unreadable notice | `ScreenMessage` (`screens/watch_match_screen.dart`) |
| Overs stepper and presets | `OversPicker` (`widgets/overs_picker.dart`) |
| Tournament logic | `roundRobinFixtures`, `leagueFixtures`, `knockoutFixtures`, `knockoutBracket`, `Tournament.bracket`, `sideName`, `progressOf` (`cricket_engine`, `tournament.dart`) |
| Charts | `MatchCharts` (`widgets/match_charts.dart`), `AppColors.chartSeries`. Run the dataviz palette check before changing colours |
| Share sheet, file picker | `DeviceFiles` (`data/device_files.dart`), `deviceFilesProvider`. Override it in tests |
| Shared teams, join codes, invites, join requests | `CloudTeams`, `PublishedTeam`, `JoinRequest`, `joinCodeOf`, `normalizeJoinCode` (`data/cloud_teams.dart`), `SyncingTeamRepository`, `TeamSharing` (`data/syncing_teams.dart`), `showJoinTeamSheet` (`widgets/join_team_sheet.dart`), `teamInviteText`, `joinPageAddress` (`ui/format.dart`), `site/join.html`; `FakeCloudTeams` in tests |
| Links that open the app, team invite sheet with QR, profile share line | `AppLinks`, `joinCodeFromLink` (`data/app_links.dart`), `appLinksProvider`; `showTeamInviteSheet` (`widgets/team_invite_sheet.dart`); `joinPageLink`, `profileShareText` (`ui/format.dart`); `FakeAppLinks` in tests |
| Photos and team logos: upload, pick, show | `PhotoStore`, `HttpPhotoStore`, `DevicePhotos`, `photosBaseUrl`, `trustedPhoto` (`data/photo_store.dart`), `photoStoreProvider`, `devicePhotosProvider`, `PlayerAvatar(photoUrl:)`, `TeamBadge(logoUrl:)`; the Worker is `cloud/photos-worker`; `FakePhotoStore`, `FakeDevicePhotos` in tests |
| Contact picker (one tapped contact, no permission) | `DeviceContacts`, `PickedContact` (`data/device_contacts.dart`), `deviceContactsProvider`, channel in `MainActivity.kt`; `FakeContacts` in tests |
| Over-by-over data | `InningsState.overs`, `OverSummary`, `overHeadline` (`ui/format.dart`) |
| Saved squads | `TeamRepository`, `mergeIntoSquad` (`data/team_repository.dart`), `showSavedTeamsSheet` (`widgets/saved_teams_sheet.dart`) |
| Read a pasted list or a CSV of teams, add players to a squad | `parsePlayerList`, `parsePlayerLine`, `parseTeamsCsv`, `parseCsv`, `addToSquad`, `planImport` (`data/squad_import.dart`), `showPastePlayersSheet` (`widgets/paste_players_sheet.dart`), `decodeTextFile` (`data/device_files.dart`); the CSV template is `teamsTemplateCsv` (same text as `site/teams-template.csv`, tested) |

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
  `bnp_scorer.schedule.<id>`, `bnp_scorer.themeMode`,
  `bnp_scorer.errorLog`, `bnp_scorer.playerIdsBackfill`,
  `bnp_scorer.sharedTeamIds`, `bnp_scorer.reminders`,
  `bnp_scorer.reminderLead`, `bnp_scorer.watchedReminders`,
  `bnp_scorer.pushKinds`, `bnp_scorer.deviceId`,
  `bnp_scorer.pushRegistered` and `bnp_scorer.followedMatches`. Changing them loses users' data.
- **Cloud config:** `app/android/app/google-services.json` is gitignored. Builds
  without it have no sign-in. Firestore field names on `matches/{id}` are a
  storage format: never rename them. Rule changes go in `firestore.rules` and
  are pasted into the console by the owner. `matchCards/{id}` and
  `matchViews/{id}` are written only by the server (`cloud/api`); their
  field names are a storage and API format too.
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
# Functions (push)
cd cloud/functions && npm ci && npx tsc --noEmit && npx vitest run
# API server; the image builds from the repo root (deploy: sh cloud/api/deploy.sh)
cd cloud/api && dart pub get && dart analyze && dart test
docker build -f cloud/api/Dockerfile -t bnp-api .
# photos Worker (run from an uppercase D: path on Windows, or Vitest loads twice)
cd cloud/photos-worker && npm ci && npx tsc --noEmit && npx vitest run && npx wrangler deploy --dry-run
# website match pages (their logic; needs Node, no packages)
node --test site_tests
# engine
cd packages/cricket_engine && dart pub get && dart analyze && dart test
# match view (wording and the API's JSON)
cd packages/match_view && dart pub get && dart analyze && dart test
# app
cd app && flutter pub get && flutter analyze && flutter test && flutter build apk --debug
```

## Definition of done for a change
Analyze is clean, all tests pass (new tests added), the debug build succeeds,
docs are updated (incl. "Current status" above and CHANGELOG), the website lists
any new feature and shows current screens, and the diff is reviewed. Commit
messages describe the why.
