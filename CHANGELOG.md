# Changelog

## Unreleased

### Added
- Website and API, stage 0 (a trial, nothing users can see): `cloud/api`, a
  Dart service that reads a published match from Firestore, replays it with
  `cricket_engine` and can store its score line, for Cloud Run. Run on the
  Mac against real matches and as a container, then deployed as the private
  Cloud Run service `bnp-api-trial` with a Firestore trigger: 13 balls
  scored on the owner's phone were each replayed and stored within 1.0 to
  2.4 seconds. The plan is in docs/ROADMAP.md "Website and API".
- Follow a live match (Android, cloud builds, signed in): a bell on a match
  under Everyone follows it, turning on "Matches you follow" (and asking for
  permission) the first time. Followers get a notification for the start,
  each wicket ("WICKET! Arun c Bharat b Bilal 2 (2)" with the score), a
  fifty or hundred, a five-for, the innings break with the target, and the
  result; tapping one opens the match live. The scorer's app finds the
  moment with the engine (`momentOf`, new) and publishes it with the ball;
  the Function `matchHighlight` sends it once. Follows end after two days.
  Firestore rules: `highlight` on matches, `follows` on devices (paste them
  before installing this build). Privacy policy: followed matches.
- Push setup (Android, cloud builds): Settings > Notifications gains a switch
  for each kind of live update (matches you follow, team activity, cup
  updates) while signed in, and "Send me a test notification". Turning one
  on asks for permission then and registers the phone in
  `pushDevices/{installId}`; no push token exists before that, turning all
  off or signing out removes it, and pushes that arrive while the app is open
  are shown like reminders. Firebase Functions in `cloud/functions` send
  them (`pushTest` for now); the kinds start sending in the next stages. New
  dependency: `firebase_messaging`. Privacy policy: the push token. Not yet
  deployed or tried on a phone.
- Match reminders (Android and iOS, made on the phone, nothing sent): the
  first time a match is coming up, Matches offers "Get a reminder before
  each match", and the permission prompt follows only from Turn on. Each
  upcoming sheet has a Remind me switch (one switch for this phone's
  fixtures and friendlies; for a match under Everyone, just that match), a
  bell marks reminded cards, Settings > Notifications sets how long before
  (15 min, 30 min, 1 hour, 2 hours, 1 day), and tapping a reminder opens the
  match ready to start, or the cup for a followed fixture. A followed match
  moved by its organiser moves its reminder. New dependencies:
  `flutter_local_notifications`, `timezone`; Android Gradle Plugin 9.1.1,
  compileSdk 37 and core library desugaring, which the plugin needs, and a
  notification icon drawn from the logo by the icon generator. Privacy
  policy: the notification and restart permissions. Not yet seen firing on
  a phone.
- iOS project (`app/ios`), generated on a Mac with the bundle ID
  `com.bitsnpixs.bnpscorer` (an iOS ID cannot hold the underscore in the
  Android one), the name BNP Scorer, minimum iOS 15, and a photo-library
  reason for picking a profile photo or team logo. Plugins come through Swift
  Package Manager. A debug build runs in the iPhone Simulator, phone-only.
  Still to do: the app icon (Flutter's default for now)
  and the contact picker and invite links on iOS.
- iOS signing reads the Apple team from `app/ios/Flutter/Signing.xcconfig`,
  gitignored, so a personal team stays out of the public repo. A release
  was installed on an iPhone this way (README "Setup").
- iOS sign-in and cloud: with `app/ios/Runner/GoogleService-Info.plist`
  (gitignored) a build step copies it into the app and adds the Google
  sign-in and phone reCAPTCHA URL schemes to the built Info.plist; without it
  iOS builds stay phone-only. Not yet tried on the iPhone.
- `pubspec.lock` moves `meta`, `test_api` and `vector_math` to the versions
  Flutter 3.50 pins.

## 0.9.0-beta.7 — 2026-11-21

Registered players, the CricHeroes way: sign in with Google or a mobile
number, a career profile with a big photo header and details you fill in,
squads by number (typed or from contacts), team invites by code or QR, and
team logos (`docs/PLAYER_PROFILES.md`). Photos and logos live in Cloudflare
R2 behind `cloud/photos-worker`.

### Added
- Team logos (cloud builds, signed in, once the photos Worker is deployed):
  Add, change or remove a logo on a team's page; it uploads at once and the
  team keeps it on Save. `Team.logoUrl` is a new optional field, written only
  when set, so it travels with the team into matches and tournaments and old
  teams read as before. Badges show the logo on the team list, saved-team
  picker, New match, New tournament, the score header, the prizes tab and
  the join sheet. The app loads photo and logo addresses only from its own
  photos service, so a doctored published match cannot make phones fetch
  another server. Rules accept only the captain's own logo address.
- Profile photos (cloud builds, once the photos Worker is deployed): the
  profile's owner adds, changes or removes a photo from the edit sheet. The
  phone shrinks it to 1024 px (about 150 KB) and sends it, with the Firebase
  sign-in token, to `cloud/photos-worker`, a Cloudflare Worker that checks
  the token, keeps the photo in R2 under that account's id only, and serves
  it back. Avatars on the profile, in Settings, on the team page and in Add
  by number show the photo, falling back to initials. New dependency:
  `image_picker` (gallery only; the APK's permissions are unchanged).
- Sign in with your mobile number (cloud builds), beside Google, after the
  owner asked: Settings › Account › Sign in with mobile number texts a code;
  a number already on an account signs in to it, a new one makes an account
  and asks for a name once ("Add your name" stays in Settings if skipped). The
  player profile is claimed once there is a name. A number account can link a
  Google account, so both open the same account on any phone.
- Invite sheet: sharing a team's invite now shows its join code and a QR
  code (dark on white in both themes) that opens the join page, with Send
  invite for WhatsApp. New dependency: `qr_flutter`.
- Opening an invite: the join page has "Open in BNP Scorer", which starts the
  app (`bnpscorer://join?code=...`) on the Teams tab with the join sheet open
  and the code already looked up. Verified Android App Links need a file at
  the root of bitsnpixs.github.io, which this project's site does not
  control, so the page's button does the opening instead.
- Tapping a batter or bowler in a scorecard opens their profile, and a
  profile can be shared as a short line of numbers.
- Team invites (cloud builds): on a saved team's page, the share button
  publishes the team and sends a WhatsApp-ready invite with its six-letter
  join code and a link to the new `site/join.html`, which shows the code and
  how to join. Players tap Join a team on the Teams tab, type the code and
  ask to join under their verified profile; the captain sees "Asked to join"
  on the team's page and taps Add (the player joins under their shared id)
  or Ignore. A shared team keeps its cloud copy in step on later saves and is
  unshared when deleted. A player's profile lists the shared teams they are
  in, even before they play. Rules for `teams` and their join requests are
  in `firestore.rules`.
- Add by number: "Pick from contacts" opens Android's own contact picker.
  The tapped contact's number is looked up straight away, and their name is
  ready if nobody has joined with it. The app sees only that one contact and
  asks for no contacts permission (the APK's permissions are unchanged).
  Android only; iOS waits for its platform folder.
- A player fills in their own profile (pencil on their profile, owner only):
  name, role, batting (right or left hand), bowling arm and type (fast,
  medium or spin) and home town, shown on the Info tab. The player's role
  wins over the role in their latest scorecard. The rules keep the name and
  home town to 60 characters and the creator fixed.
- Engine: career numbers split by format (`formatOf`: T10 up to ten overs,
  T20 up to twenty, 20+ beyond), ducks in batting stats, and
  `playerMatchLines`, one line per finished match a player was picked in
  (sides, ground, result, their batting and bowling) for recent form, debut
  and last match. All derived; nothing stored changes.
- `data/phone_numbers.dart`: reads a mobile number however it is typed
  (spaces, dashes, 0 or 91 in front; India by default, other countries with
  their + code), masks it for its owner (+91 •••• 3210), and hashes it for the
  cloud lookup. `crypto` moves from a transitive to a direct dependency.
- Accounts: a signed-in scorer can confirm a mobile number by SMS code
  (Firebase phone auth, linked to the Google account; Android may confirm it
  without a code). Failures read as plain advice. No screen offers it yet.
- Cloud: a player directory by mobile number. `players/{id}` is the public
  profile; `phones/{sha256}` maps a hashed number to its player, readable one
  at a time when signed in and never listed. A captain can invite a player
  under a number; the first to add a number wins; the number's owner claims
  the profile after confirming it. New rules in `firestore.rules` (to paste
  into the console).
- Published matches carry `playerIds`, everyone picked on both sides, so a
  player's matches can be found for their profile. A signed-in scorer's
  matches published before this are sent again once, on the next sign-in or
  launch. The rules accept the field and keep it optional for older apps.
- A new player profile, after the owner's reference: a hero card, then Info
  (personal details, last five innings that open their match, teams, awards,
  fielding), Batting and Bowling (Career, This year or Last 10; three headline
  numbers; a table split by format when more than one was played) and Career
  (debut and last match, overall and per format). In cloud builds it includes
  everyone's published matches the player was picked in, so a player tapped
  in a watched cup now shows their numbers instead of nothing.

- Settings, signed in (cloud builds): "Add your mobile number" texts a code and
  confirms the number (Android may confirm it without one), then "My
  profile" opens the player profile claimed under it: the player a captain
  already added under that number, so their runs and wickets come along, or
  a new one in the scorer's name. "Change number" swaps it. Offline, the
  profile waits with "Tap to try again". The sign-in notice says the number
  is used only to find the profile and is never shown.

- Add by number (cloud builds, signed in), on a team's page and on New match:
  type a mobile number to find the player who joined with it (their profile
  and career come with them) or, when nobody has, add them by name as
  invited. A found player whose name is already in the team can be linked to
  that member, who keeps their role, captaincy and gloves; on New match the
  saved squad takes the link too. The team page marks players Verified or
  Invited, and a player's actions include View profile.

### Changed
- The player profile opens on a big header, after the owner pointed to
  CricHeroes: the photo across the top (or large initials on the night
  pitch), fading into the name, home town and matches, role and batting
  style, bowling style, team and Verified, with round back, share and edit
  buttons over it. It collapses into the bar as the tabs scroll, and the
  tabs' content never slides under it. Photos now upload at 1024 px so the
  header stays sharp.
- Confirming a number fails with Firebase's code in the message for setup
  problems, and the full error is logged.
- Tab bars: the selected tab's pill is inset to about 30 dp instead of filling
  the whole tab, on every tabbed screen (owner's feedback: too big for a
  phone). Website screens re-rendered.
- Privacy policy, website FAQ and README Data safety answers cover mobile
  numbers (kept by Firebase Authentication; only a SHA-256 hash in our
  database, never listed or shown) and the public player profile.

### Not yet checked
- Tried on the owner's phone: confirming a test number (once the Phone
  provider and the SMS region policy were on; the policy blocks test numbers
  too) and uploading a profile photo through the Worker.
- Not yet on a phone: number sign-in from signed out, add by number, the
  contact picker, team invites and joins, team logos, the photo header with
  a 1024 px photo, and opening the app from the join page. Nothing has been
  tried with two phones. The rules are untried in the Rules Playground.

## 0.9.0-beta.6 — 2026-11-18

The company's name, BitsNPixs, in the app and on the website.

### Changed
- The website's footer names the company in full, "© 2026 BitsNPixs
  Technologies Private Limited. All rights reserved.", with BitsNPixs linking
  to https://bitsnpixs.com/, on the home page and the privacy policy. The
  site spells the name BitsNPixs everywhere, and the privacy policy names the
  company in full in its first line.
- The app spells the company BitsNPixs too: Settings shows "By BitsNPixs"
  under the version, and the open-source licences screen shows "© 2026
  BitsNPixs Technologies Private Limited". The README and docs follow.

## 0.9.0-beta.5 — 2026-11-18

Squads without typing: paste a list from WhatsApp, or import teams from a sheet.

### Added
- "Paste a list" on New match and on a team's page: paste a squad as it comes
  on WhatsApp, one name per line. Numbering, bullets, WhatsApp bold and emoji
  are skipped, names already in the team are left out, and on a team's page
  (c), (vc), (wk) and roles like (bowler) set the captain, vice-captain, keeper
  and role. A list already copied fills the sheet when it opens, and each name
  can be taken off before adding. In a numbered list, an unnumbered line (a
  heading, or a player whose number was forgotten) starts taken off, with a
  tap to bring it back.
- Import teams from a CSV file on the Teams tab, saved from Excel or Google
  Sheets: one column per team, or Team and Player columns with an optional
  Role column, where a blank team cell continues the team above. A preview
  shows each team, whether it is new or adds to a saved team of that name, and
  any team too small to save. An .xlsx file is refused with the steps to save
  it as CSV. Picked files that are not UTF-8 are read as Windows-1252, which
  plain Excel CSVs on Windows use. No new dependency.
- A CSV template to fill in, on the website (`site/teams-template.csv`, Team,
  Player and Role columns). It stays a CSV when edited and saved in Excel, so
  it avoids the .xlsx problem. The app's "could not import" message gives its
  address, and a test imports it.
- The template in the app too: the Teams tab's import button first shows the
  format (a few rows of the template) with "Pick a CSV file" and "Share the
  template", which sends the CSV to WhatsApp, email or Drive to fill in. A
  file that cannot be read offers the template as well. Shared files ending in
  .csv go out as CSV, so Sheets and Excel offer to open them; backups stay
  JSON. The app's copy is tested to match the website's byte for byte.
- The privacy policy covers pasting and importing: the paste sheet reads the
  text last copied, and import reads only the file picked; neither leaves the
  phone.
- The website lists every feature in the app, now including pasting and
  importing squads, following a match live, the over-by-over list, player and
  team profiles, and backup, with a question on bringing teams in from Excel.

### Fixed
- The website no longer scrolls sideways: the floodlight glow behind the hero
  stuck out past both edges, and is now part of the page background.
- The website served the CSV template with Unix line ends while the app
  shares CRLF, and the test comparing them only passed on Windows.
  `.gitattributes` now keeps CSV files at CRLF on every checkout.

## 0.9.0-beta.4 — 2026-11-18

A logo of its own and the Bits N Pixs green throughout.

### Changed
- The accent is the Bits N Pixs green instead of mint neon, in the app and on
  the website, and the night surfaces lean toward that green so the hero cards
  match the logo. The light theme uses a deep brand green for text and icons.
  Scoring colours (4, 6, wicket, extras) and the chart series are unchanged;
  the charts passed the colour check on the new card surfaces, and every text
  pair stays above 4.5:1. The website screens and link preview were redrawn.
- A logo of its own, after the owner's sketch: a cricket ball in the Bits N
  Pixs green, lit from the top left with a stitched seam, and the company
  logo's thin geometric b and p drawn across it, the p's stem running out of
  the ball. On night the b is a cut-out of the ball and the p is chalk; the
  themed (monochrome) icon punches both letters out of a white ball. It is
  the app icon (adaptive, legacy and monochrome layers), the splash mark, the
  website's favicon and header mark (`site/img/icon-64.png`, the ball alone),
  its touch icon (`icon-512.png`, on night) and the logo on the link preview
  (`logo.png`), and the ball replaces the bat-and-ball icon in the Matches
  header and on the shared scorecard card. The art is `paintLogo` in
  `widgets/logo_mark.dart` (`LogoMark` shows it), drawn as paths with no
  font; `app/tool/generate_app_icon_test.dart` writes the files from it.
  `AppColors.brandGreen` holds the company green, used nowhere else.

## 0.9.0-beta.3 — 2026-11-17

Cups, prizes and upcoming matches, public for everyone to follow.

### Added
- Download from the website: "Download for Android" serves the latest GitHub
  Release (`releases/latest/download/bnp-scorer.apk`). Beta.3 is the first
  release there. The website's season section lists cups, prizes and upcoming
  matches.
- Privacy policy, website and the sign-in notice cover tournaments and
  scheduled matches: what each contains when published, that entry fee
  payments never leave the phone, and how to remove them. A website FAQ on
  running a cup.
- Engine, for cups (not in the app yet): a straight knockout cup of 3 to 64
  teams, paired in draw order, with byes for the first teams when the number is
  not a power of two; quarter-finals after a league (1 v 8, 4 v 5, 2 v 7, 3 v 6)
  or two groups (crossed); prizes as free text, an entry fee, what each team has
  paid (left out of `Tournament.toPublicJson`, so it never leaves the phone),
  house rules, and a ground per fixture. All new JSON fields are optional and
  written only when set.

- New tournament: a Format choice, League or Knockout cup. A cup's draw is the
  order teams are ticked, previewed as first-round games and byes, with Shuffle
  draw. Leagues gain Quarters (from 8 teams); the knockout choices are now
  chips, each shown once there are enough teams.
- A Bracket tab on tournaments with knockout games: every game round by round,
  teams still to be decided named ("Winner of Quarter-final 2"), winners
  ticked, byes marked, and games ready to add pointed to Matches. Cups have no
  Table tab. The next-games button names any round ("Set up the
  quarter-finals", "Set up Semi-final 1: A v B").

- A Prizes tab on every tournament: prizes written as announced ("Rs 25,000 +
  trophy"), house rules and notes, and the entry fee with what each team has
  paid and the total collected. Payments stay on this phone and are marked so.
  Edited on a new Tournament details screen. The champions banner shows the
  winner's prize.
- `rupees()`: whole rupees with Indian grouping (Rs 1,00,000).

- Upcoming matches: a strip on Matches with dated fixtures not started and
  scheduled friendlies, soonest first ("Today, 6:00 PM"; "Due since 6:00 PM"
  once late). Each opens a sheet to start it (New match filled in), change the
  time or ground, send a WhatsApp-ready invite, or cancel it. New match has
  "Schedule for later" (teams, overs and ground; the toss comes at the start).
  A long press on a tournament fixture opens the same sheet, which is where a
  fixture's own ground is set.

- Cloud, cups: a tournament created, or a friendly scheduled, while signed in
  is published for everyone, and kept up to date as it changes. Entry fee
  payments never leave the phone (`toPublicJson`), and the security rules
  refuse a tournament that carries them. Everyone gains Upcoming (public
  fixtures and friendlies, with an invite and the cup to open) and Cups, and a
  cup opens read-only with its matches, bracket, table, prizes and stats, live.
  `firestore.rules` gains `tournaments` and `schedules`.

### Changed
- Every knockout game now comes from one bracket (`Tournament.bracket`), and a
  game is offered as soon as both its teams are known. Leagues with a final or
  semi-finals behave exactly as before, with the same fixture ids.

## 0.9.0-beta.2 — 2026-11-17

The first beta with the cloud: sign in to publish, and follow anyone's match
live.

### Changed
- Privacy policy rewritten for sign-in and publishing: what Google sign-in
  gives the app, what a published match contains (teams, player names, every
  ball, the scorer's Google name), that published matches are public, how to
  unpublish or have everything deleted, Firebase as processor, and why the
  internet, network-state, biometric and fingerprint permissions are listed.
  The website's privacy block and FAQ say the same.
- Settings > About in cloud builds says matches stay on the phone unless you
  sign in, and gives the policy's address. The sign-in notice adds that the
  Google name is shown, the email never is, and deleting a match unpublishes it.

### Fixed
- A Google account with no display name (or an email as its name) published
  the email address as "Scored by". It is now "Scorer"; the email is never
  published.

### Added
- Cloud, step 3: a "My matches / Everyone" switch on the Matches tab in cloud
  builds. Everyone lists the latest 30 published matches, live, with who scores
  each. Tapping one opens a read-only live view with the same tabs as scoring
  and no pad or scoring menu; it follows every ball, and says so plainly if the
  match is unpublished or comes from a newer app version.
- `MatchTabsView`: the match screen's frame, now shared by scoring and watching.
- Cloud, step 1: Google sign-in in Settings, behind a notice that new matches
  become public including player names. A signed-in scorer's new matches are
  marked `publishedBy` and sent to Firestore on every save; the phone stays the
  source of truth and a failed or offline cloud write never fails a save.
  Deleting a published match unpublishes it. Matches already on the phone, demo
  matches and matches scored signed out stay private. `firestore.rules` lets
  anyone read and only the owner write. Adds `firebase_core`, `firebase_auth`,
  `cloud_firestore` and `google_sign_in`, and the internet permission. Builds
  without `google-services.json` have no sign-in and work as before.
- A full home page for the website: a live scoreboard whose over is bowled ball
  by ball on load, the match day from squads to the points table beside real
  screens of the app, house rules, privacy, how to get the beta, and questions.
  It uses the app's own fonts, served from the site, and has a link preview for
  WhatsApp. `app/tool/generate_screenshots_test.dart` renders the screens and
  `app/tool/build_site_assets.py` turns them into the site's images and fonts.

## 0.9.0-beta.1 — 2026-11-17

The first beta, shared as an APK over WhatsApp or Drive and signed with the
upload key. Everything below since 0.1.0 is in it.

### Added
- Website with the privacy policy, published from `site/` to GitHub Pages by a
  workflow (`https://bitsnpixs.github.io/bnp-scorer/privacy.html`). It says what
  the app stores, that nothing leaves the phone unless the scorer shares it, and
  that the app asks for no permissions (checked against the release APK).
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
- After a run out, strike followed the runs completed, which is wrong when the
  batters had crossed, so the scorer had to remember "swap strike". The wicket
  sheet now asks where the run out happened (Striker's end / Bowler's end),
  pre-selected as the end the batter was running to, and shows who faces next.
  `Wicket` has an optional `end`, written only for run outs that set it, so older
  matches replay as before.
- A side short of bowlers could get stuck with nobody allowed to bowl (two
  bowlers and a mid-over change, or everyone at the overs limit), leaving only
  "End innings". The engine now eases the rules one step at a time until someone
  can bowl, and the picker says which rule was eased. Greyed-out bowlers show why
  ("Bowled last over", "Overs used up", "Bowling now").
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
- 2026-11-17, cloud step 3 across two phones: the owner scored on their phone
  while a Pixel 9a (Android 16, not signed in) watched from Everyone, and every
  ball appeared on the Pixel live. No errors in the Pixel's log.
- 2026-11-17, cloud step 1 on the owner's phone: Google sign-in worked with the
  upload-signed build, a new match appeared in Firestore with its owner as it
  was scored, older matches stayed private, the security rules allowed public
  reads, and the cloud copy replayed through the engine to the score on the
  phone (57/0 after 2 overs). No errors in the phone's log.
- 2026-11-17, on the owner's phone: the old demo build was backed up and
  uninstalled, beta 0.9.0-beta.1 installed and launched without errors, and the
  restore brought back every match, team and tournament. First real backup and
  restore.
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
