# BNP Scorer

By Bits N Pixs (BNP).

Ball-by-ball cricket scoring for local matches, for Android and iOS (Flutter).
Offline-first: scoring works with no network and every match is stored on the device.

> Status: **v0.1, builds and runs on Android, debug and release.** Release
> builds are debug-signed until an upload key is set up ("Release signing").
> iOS has not been tried. Run the checks in "Verify" below before building on it.

## Documentation
| File | For |
| --- | --- |
| [AGENTS.md](AGENTS.md) | **Start here** (people and coding agents): rules, current status, reuse map, gotchas |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Product context, stack decisions, next phases, open issues |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Engine, events, rules implemented, app state, screens, design system, tests |
| [CHANGELOG.md](CHANGELOG.md) | What changed |
| [CLAUDE.md](CLAUDE.md) | Imports AGENTS.md for Claude Code |

## What's in v0.1

- **Match setup** in one screen: team names, players (type names or "Fill to 11"),
  overs (presets or stepper), toss, venue, and house rules (wide/no-ball run,
  free hit, last man stands, max overs per bowler, shot direction).
- **Look:** a night-pitch and neon-green design with light and dark themes. Pick
  System, Light or Dark in Settings (top of Home). A bottom bar holds Matches,
  Tournaments, Stats and Teams, with a big "+" to start a match from anywhere.
- **Teams:** edit a squad from the Teams tab: rename players, set roles, and
  mark the captain, vice-captain and wicket-keeper. Scorecards show (c) and (wk).
- **Saved teams:** a team is remembered when its first match starts, then
  "Saved teams" fills in its name and players next time. With more than 11 in
  the squad the rest sit out, and one tap swaps a player in.
- **Tournaments:** pick saved teams and get a full fixture list. Choose one league
  or two groups, once or home and away, with no knockouts, a final, or semi-finals
  and a final. Tied knockout games go to a Super Over. Pick a start date to date
  every fixture, and long-press a fixture to move it. Each tournament has its own
  points tables, batting, bowling and boundary leaderboards, and champion.
- **Home filter:** chips narrow the match list to a tournament or to friendlies.
- **Overs:** every scorecard lists each over, newest first: the score it ended on,
  who bowled to whom, and every ball.
- **Charts:** every scorecard has runs per over (Manhattan) and the run race (worm),
  with wickets marked. Tap or drag to read an over. Turn on "Record shot direction"
  in the house rules to add a wagon wheel, by innings or batter.
- **Backup:** save everything to one file from Settings, and restore it on
  this or another phone. Restoring only adds what is missing.
- **Share:** send any scorecard to WhatsApp or anywhere else as a branded picture
  with a caption.
- **Awards:** Player of the Match on every result, MVP rankings, and Player of the
  Tournament for each champion.
- **Stats:** team table with points, net run rate and form, batting, bowling, MVP
  and boundary leaderboards, and a full profile for each team and player. Worked
  out from finished matches, so they always agree with the scorecards.
- **Live scoring:**
  - one-tap 0–4 and 6, wides, no-balls (bat runs or byes), byes and leg byes;
  - wickets: only legal dismissal types are offered, including on free hits;
  - run outs at either end with runs completed, plus the fielder or keeper;
  - undo, swap strike, mid-over bowler change, retire hurt or out, end innings,
    abandon the match with no result.
- **Guided flow**: the bottom panel always shows the next thing to do
  (openers → bowler → score → new batter → next over → innings break → result).
- **Scorecard**: tabs on the match screen, a tap away while scoring: batting,
  extras, total, yet to bat, fall of wickets and bowling for each innings, plus
  Overs and Charts. A finished match opens on its result, with the stars of the
  match and shortcuts into each tab. Share is in the top bar.
- **Home**: match list with live/result status, filter chips, long-press to delete,
  and shortcuts to Tournaments, Stats, Teams and Backup.

```
packages/cricket_engine/   Pure Dart scoring engine (no Flutter) + rules test suite
app/                       Flutter app (package bnp_scorer)
docs/                      Architecture and roadmap
```

## Setup

1. Install Flutter (stable, 3.32 or newer) and run `flutter doctor`.
2. `app/android` is already in the repo. For iOS, generate the folder on a Mac
   (this does not touch `lib/`):

   ```sh
   cd app
   flutter create . --org com.bitsnpixs --project-name bnp_scorer --platforms ios
   flutter pub get
   ```

   Then set the name shown under the app icon to **BNP Scorer**:
   - Android: `android:label="BNP Scorer"` in `android/app/src/main/AndroidManifest.xml`.
   - iOS: `CFBundleDisplayName` = `BNP Scorer` in `ios/Runner/Info.plist`.

   App IDs: Android `com.bitsnpixs.bnp_scorer`, iOS `com.bitsnpixs.bnpScorer`
   (as generated by `flutter create`).

   If `flutter create` adds `test/widget_test.dart` (a counter-app test), delete
   that file.
3. Run on a device or emulator: `flutter run`.

## Demo data

Build with `--dart-define=BNP_DEMO=true` to fill the app with sample data:

- the four full squads, in Saved teams;
- five finished tournaments: BNP Cup, Pongal Trophy (every format at once, with a
  tied final and a Super Over), Monsoon League, Summer Shield and Winter Bash;
- a friendly left in progress, so scoring can be shown straight away;
- an Exhibition match with a wagon wheel.

All performances are simulated through the scoring engine, so they are invented
even though the squad names are real.

```sh
cd app
flutter build apk --debug --dart-define=BNP_DEMO=true
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Use `adb install -r` to keep what is already saved on the phone. Demo matches
are added at launch only if missing, so a match scored in a demo is kept and a
deleted one comes back on the next launch. Teams and tournaments work the same
way. Normal builds contain no demo data, but anything already stored on a phone
stays there.

## Verify

Run these in order and fix anything that fails before committing:

```sh
cd packages/cricket_engine
dart pub get
dart analyze
dart test

cd ../../app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug      # and `flutter build ios --no-codesign` on a Mac
```

## Release signing

Release builds are signed with the key named in `app/android/key.properties`.
Without that file they fall back to the debug key: fine for a phone, refused
by the Play Store. The file and any `*.jks` are gitignored.

Create the upload key once (free; `keytool` comes with the JDK). Keep it
outside the repo:

```sh
keytool -genkeypair -v -keystore ~/bnp-upload-keystore.jks -storetype JKS   -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then write `app/android/key.properties`:

```properties
storePassword=<the keystore password>
keyPassword=<the key password>
keyAlias=upload
storeFile=C:/Users/<you>/bnp-upload-keystore.jks
```

**Back up the `.jks` file and both passwords in two places** (for example a
password manager and a USB drive). If you lose the key you cannot update the
app. With Play App Signing, Google holds the app signing key and this one
only uploads, so a lost upload key can be reset through Play support.

Build for the Play Store with `flutter build appbundle --release`. Phones that
have a debug-signed build must uninstall it before installing a release-signed
one (Android refuses an update signed with a different key), which deletes
their data, so back up first.

## Fonts and offline first launch

Inter and Barlow Condensed ship inside the app (`app/assets/google_fonts/`, with
their OFL licences, shown in Settings > Open-source licences). `AppFonts.useBundledFonts()`
in `main()` turns off downloading, so the app never needs the internet, even on
first launch. The files are the ones `google_fonts` would download, checked
against its SHA-256 hashes. A new weight or style needs its file added there
(named like `Inter-SemiBold.ttf`) and its weight to the lists in `AppFonts`.
`main()` loads every font before the first frame, waiting at most 3 seconds.
