# BNP Scorer

By BitsNPixs Technologies Private Limited (BNP, https://bitsnpixs.com/).

Ball-by-ball cricket scoring for local matches, for Android and iOS (Flutter).
Offline-first: scoring works with no network and every match is stored on the device.

> Status: **v0.1, builds and runs on Android, debug and release.** Release
> builds are debug-signed until an upload key is set up ("Release signing").
> iOS builds and runs in the Simulator (2026-11-26), phone-only: no cloud,
> contact picker or invite links on iOS yet, and not tried on an iPhone.
> Run the checks in "Verify" below before building on it.

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
- **Look:** a night pitch in the BitsNPixs green, with light and dark themes. Pick
  System, Light or Dark in Settings (top of Home). A bottom bar holds Matches,
  Tournaments, Stats and Teams, with a big "+" to start a match from anywhere.
- **Teams:** edit a squad from the Teams tab: rename players, set roles, and
  mark the captain, vice-captain and wicket-keeper. Scorecards show (c) and (wk).
- **Paste a list:** on New match and on a team's page, "Paste a list" takes a
  squad as it arrives on WhatsApp, one name per line. Numbering, bullets and
  emoji are skipped; on a team's page, (c), (vc), (wk) and roles such as
  (bowler) set the captain, vice-captain, keeper and role. A list already
  copied is pasted in when the sheet opens, and every name can be taken off
  before adding. In a numbered list, an unnumbered line such as the team name
  starts taken off, with a tap to bring it back.
- **Import teams from a sheet:** the button at the top of the Teams tab reads a
  CSV file saved from Excel (File > Save As > CSV UTF-8) or Google Sheets (File
  > Download > CSV). Either one column per team with its name on top, or
  columns headed Team and Player, with an optional Role column (Captain, WK,
  Bowler). A team with a saved team's name adds its new players to that squad.
  A preview shows each team before anything is saved. Real .xlsx files are not
  read: the app says how to save one as CSV. The import button first shows the
  format and offers "Share the template", which sends a ready CSV to WhatsApp,
  email or Drive to fill in.
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
- **Report a problem:** Settings sends a short report with recent error details
  to any app. Errors are kept on the phone and nothing is sent by itself.
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
2. `app/android` and `app/ios` are in the repo (iOS generated on 2026-11-26
   with `flutter create . --org com.bitsnpixs --project-name bnp_scorer
   --platforms ios`; if you ever regenerate, delete the counter-app
   `test/widget_test.dart` it adds).

   App IDs: Android `com.bitsnpixs.bnp_scorer`, iOS `com.bitsnpixs.bnpscorer`
   (iOS bundle IDs cannot contain underscores; owner's choice, 2026-11-26).
   The name under the icon is **BNP Scorer** on both
   (`android:label` in `AndroidManifest.xml`, `CFBundleDisplayName` in
   `ios/Runner/Info.plist`).

   **iOS on a Mac:** Xcode with an iOS Simulator runtime
   (`xcodebuild -downloadPlatform iOS`) and CocoaPods (`brew install
   cocoapods`). Plugins come in through Swift Package Manager (there is no
   Podfile); the first build fetches the Firebase and Google Sign-In
   packages. Minimum iOS is 15. Sign-in and the cloud need
   `GoogleService-Info.plist` (see "Cloud"); without it iOS builds run
   phone-only, like Android builds without `google-services.json`.

   ```sh
   cd app
   flutter build ios --simulator --debug
   ```

   (In Xcode 27 the simulator window is in DeviceHub, inside Xcode.app.)

   **iOS on a phone:** add an Apple ID in Xcode > Settings > Accounts (a
   free Personal Team works: the app stops opening after 7 days), connect
   the iPhone, tap Trust, and turn on Settings > Privacy & Security >
   Developer Mode. Put the team in `app/ios/Flutter/Signing.xcconfig`
   (gitignored, so a personal team never reaches this public repo; the
   Debug and Release configs include it when it exists):

   ```
   DEVELOPMENT_TEAM = <team id>
   CODE_SIGN_STYLE = Automatic
   ```

   The first time, let Xcode make the certificate and profile, then build
   and install a release (a debug build opens only from the Mac):

   ```sh
   cd app/ios && xcodebuild -workspace Runner.xcworkspace -scheme Runner \
     -configuration Release -destination id=<iPhone UDID> \
     -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
   cd .. && flutter build ios --release
   xcrun devicectl device install app --device <iPhone UDID> build/ios/iphoneos/Runner.app
   ```

   On the phone, allow the developer once under Settings > General > VPN &
   Device Management. `xcrun devicectl list devices` shows the UDID.
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
keytool -genkeypair -v -keystore C:/Users/<you>/bnp-upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
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

## Cloud

Signed-in scorers publish their matches to Firebase (project `bnp-scorer`) so
everyone can follow them. Design and decisions: docs/ROADMAP.md "Cloud: shared
matches"; registered players: docs/PLAYER_PROFILES.md.

- **Config:** `app/android/app/google-services.json`, downloaded from the Firebase
  console (Project settings > Your apps > BNP Scorer). It is gitignored. Without
  it the app still builds and runs on the phone only, with no sign-in.
- **iOS config:** `app/ios/Runner/GoogleService-Info.plist`, from the iOS app
  `com.bitsnpixs.bnpscorer` on the same console page (registered 2026-11-26).
  Also gitignored. The Runner build step "Copy Firebase Config" copies it into
  the app when present and adds the two URL schemes it implies (the reversed
  client id for Google sign-in, the encoded app id for phone sign-in's
  reCAPTCHA) to the built Info.plist, so no Firebase ids are committed. Without
  APNs (it needs the paid Apple account) phone sign-in shows a reCAPTCHA page
  before the SMS.
- **Sign-in fingerprints:** Google sign-in only works in builds signed with a key
  whose SHA-1 and SHA-256 are listed on that console page: the debug key, the
  upload key, and later the Play app-signing key. Read them with
  `keytool -list -v -keystore <file>`, or from an APK with
  `apksigner verify --print-certs`.
- **Security rules:** `firestore.rules` in the repo root. After changing it, paste
  it into Firestore Database > Rules and Publish. Anyone may read matches,
  tournaments and schedules; only each one's owner may write it, and a
  tournament carrying `paid` is refused.
- **Phone numbers (beta.7 on):** confirming a number uses Firebase phone auth,
  which needs the **Blaze** plan (about $0.07 an SMS in India after 10 free a
  day). In the console: upgrade with a budget alert; Authentication > Sign-in
  method > Phone, on; Settings > SMS region policy, allow India (stops SMS
  fraud; it blocks test numbers too, so also allow the United States while
  testing with +1 650-555 numbers, and keep real numbers off the test list); add test numbers under Phone numbers for testing (fictional, such
  as +1 650-555-3434, each with a six-digit code like 123456; no SMS is sent and
  nothing is billed); and enable the Play Integrity API on the Google Cloud
  project, or users see a reCAPTCHA page in the browser first (it proves the
  request comes from the real app, so nobody can use the project to send SMS;
  sideloaded betas may get the page anyway). The same SHA-1 and SHA-256 fingerprints as sign-in apply.
  In the Rules Playground, check that `hashing.sha256(...).toHexString().lower()`
  gives the same lowercase hex as `phoneHash` in the app (the test number's
  hash is in `test/phone_numbers_test.dart`).
- **Privacy:** a cloud build uses the internet and publishes match content,
  including player names and the scorer's Google name (never the email,
  `publicScorerName`). `site/privacy.html` says so; update it before a build
  that publishes anything new reaches testers.
- **Play Data safety answers** (for the cloud build): data is collected, all of
  it optional (only when signed in), encrypted in transit, and deletable on
  request (an account made with a mobile number has no email: its name is
  the one typed). Photos and videos > Photos: only a profile photo the
  player chooses to add (app functionality; shown publicly on their profile).
  Collected: Personal info > Name, Email address, User IDs and Phone
  number (account management and app functionality; the name is shown publicly
  as "Scored by" and on the player profile, the number never is; numbers
  captains type or pick from contacts for other players are sent only as a
  SHA-256 hash to find or create their profile; the contact picker hands over
  one tapped contact, with no contacts permission, so Contacts stay "not
  collected"); App activity > Other
  user-generated content (published matches, tournaments, scheduled matches
  and teams whose invite was shared, including player names; app
  functionality). Entry fee payments are
  not collected: they stay on the phone. Not collected: location, contacts, photos, files, crash logs
  or diagnostics (problem reports are sent by the user through the share sheet),
  device ids. Not shared with third parties; Firebase is a processor. No ads.

## Push (Firebase Functions)

Live updates (docs/ROADMAP.md "Notifications") are sent by Cloud Functions in
`cloud/functions` (TypeScript, Node 22, region `asia-south1`) when Firestore
changes. The app registers a signed-in phone in `pushDevices/{installId}`
(token, owner, platform, the kinds chosen in Settings > Notifications); no
token is made until a kind is turned on, and signing out deletes it first.
Android only until iOS has an APNs key (the paid Apple developer account,
uploaded under Firebase > Project settings > Cloud Messaging).

```sh
brew install firebase-cli && firebase login     # once, as the project owner
cd cloud/functions && npm ci && npx tsc --noEmit && npx vitest run
cd ../.. && firebase deploy --only functions     # needs the Blaze plan
```

The first deploy (2026-11-26) turned on the Google Cloud services Functions
need; the Eventarc permission takes a few minutes, so a first deploy can fail
once and pass on a retry. Old build images are deleted after a day
(`firebase functions:artifacts:setpolicy --location asia-south1`), so they
never build up a storage bill. `firebase login` stores the sign-in for the
Mac user; run it in Terminal, not through an agent.

- `pushTest` answers Settings > Send me a test notification: the app sets
  `testRequestedAt` on its device document and the Function pushes back.
- `matchHighlight` sends a match's `highlight` (written by the scorer's app
  with the ball that made it: `momentOf` in the engine, worded by
  `matchHighlight` in `ui/format.dart`) once per `seq` to devices whose
  `follows` holds the match. It runs on every match write and stops at the
  first check when there is nothing new.
- `push.ts` holds the sending rules (who wants which kind, batches of 500,
  removing devices whose token is gone), tested with fakes; `adapters.ts`
  connects them to Firestore and Cloud Messaging.
- The rules for `pushDevices` are in `firestore.rules`: paste them into the
  console as before (`firebase deploy --only firestore:rules` does the same,
  but replaces whatever is in the console).
- Play Data safety: Device or other IDs (the push token), collected for app
  functionality, optional, deleted when updates are turned off.

## Photos (Cloudflare R2)

Player photos (and, next, team logos) live in the R2 bucket `bnp-photos`
behind the Worker in `cloud/photos-worker`, which checks each upload's
Firebase sign-in token. The app never holds R2 keys.

1. In the Cloudflare dashboard, enable R2 (a payment method is asked for;
   the free tier is 10 GB with free downloads).
2. From `cloud/photos-worker`: `npm ci`, `npx wrangler login`, then
   `npx wrangler r2 bucket create bnp-photos` and `npx wrangler deploy`.
   Wrangler prints the Worker's address (`https://bnp-photos.<account>.workers.dev`).
3. The app's default address is the live Worker,
   `https://bnp-photos.quikfly-api.workers.dev` (deployed 2026-11-21 to the
   owner's Cloudflare account); `--dart-define=BNP_PHOTOS_URL=<address>`
   points a build elsewhere, and an empty value turns photos off. Paste the
   updated `firestore.rules` (it checks photo and logo addresses).
4. Later, a custom domain on Cloudflare in front of the Worker is better
   than `workers.dev` for real traffic.

Tests: `npx tsc --noEmit && npx vitest run`. On Windows run them from an
uppercase `D:` path (PowerShell `Set-Location D:\...`): with a lowercase
drive letter Vitest loads twice and fails before any test runs.

## Beta builds

Testers get the APK from the website's download button (a GitHub Release) or
directly over WhatsApp or Google Drive. It costs nothing,
and updates install over the top as long as every build is signed with the same
upload key ("Release signing").

1. Bump `version:` in `app/pubspec.yaml` and `app/lib/data/app_info.dart` together,
   e.g. `0.9.0-beta.7+8` after beta.6 (build 7). The number after `+` must always go up.
2. Build and copy it out (PowerShell, from `app/`):

   ```powershell
   flutter build apk --release
   New-Item -ItemType Directory -Force ..\dist | Out-Null
   Copy-Item build\app\outputs\flutter-apk\app-release.apk ..\dist\bnp-scorer-0.9.0-beta.7.apk
   ```

   No `BNP_DEMO`, so testers start empty. No `--obfuscate` either, so the stack
   traces in Settings > Report a problem stay readable. `dist/` is gitignored.
3. Check it is signed with the upload key, not the debug key:
   `apksigner verify --print-certs ..\dist\bnp-scorer-0.9.0-beta.7.apk`
   (in the Android SDK's `build-tools`) should not say `CN=Android Debug`.
4. Publish it as a GitHub Release, which the website's "Download for Android"
   button serves. Upload the APK under the fixed name `bnp-scorer.apk` and mark
   the release as latest, **not** pre-release: the button links to
   `releases/latest/download/bnp-scorer.apk`, which skips pre-releases.

   ```powershell
   Copy-Item ..\dist\bnp-scorer-0.9.0-beta.7.apk $env:TEMP\bnp-scorer.apk
   gh release create v0.9.0-beta.7 $env:TEMP\bnp-scorer.apk --target <full commit hash> `
     --title "BNP Scorer 0.9.0-beta.7" --notes-file <notes.md> --latest
   ```

   The repo is public, so a release is public at once: only publish a build
   whose privacy policy is already live.
5. Or send the file with the tester message below. In WhatsApp, attach it as a
   **Document**, so it arrives as a file.

Tester message (edit the version):

> BNP Scorer beta 0.9.0-beta.6 is attached. New: paste a team list straight
> from WhatsApp, or import all your teams from an Excel or Google Sheets file
> (template under Teams > import). To install: tap the file, allow
> "install unknown apps" for WhatsApp (or Files) when asked, then Install. Updates
> come the same way and keep your matches. Please back up from Settings now and
> then. If anything goes wrong, use Settings > Report a problem and send it to me.
> Privacy: https://bitsnpixs.github.io/bnp-scorer/privacy.html

Someone who has a debug-signed build (the owner's phone, or an early demo
install) must back up, uninstall and then install the beta once. Android refuses
an update signed with a different key, and uninstalling deletes the data.

## Website and privacy policy

`site/` is a two-page website: a home page and the privacy policy the Play
Store listing links to. `.github/workflows/pages.yml` publishes only that folder
to GitHub Pages (free for this public repo) whenever `site/` changes on `main`:

- home: https://bitsnpixs.github.io/bnp-scorer/
- privacy policy: https://bitsnpixs.github.io/bnp-scorer/privacy.html

The home page lists every feature in the app: add each new one there (and to
its FAQ when it answers a common question) in the same change. It also offers
`site/teams-template.csv`, the CSV template for importing teams. The app shares
the same text (`teamsTemplateCsv`); tests check the two are identical and that
the template imports, so change both together.

The home page shows real screens of the app. To refresh them after a visible
change (from `app/`):

```sh
flutter test tool/generate_screenshots_test.dart   # PNGs into build/screenshots/
python tool/build_site_assets.py                    # WebP screens, web fonts, link preview
```

The first renders the screens with the demo data and the bundled fonts; the
second (needs `pip install pillow fonttools brotli`) writes `site/img/` and
`site/fonts/`. The same PNGs can go on the Play Store listing. The site's
favicon and header mark (`site/img/icon-64.png`), touch icon (`icon-512.png`)
and the logo on the link preview (`logo.png`) are the app logo, drawn by
`flutter test tool/generate_app_icon_test.dart` together with the Android
icon.

Update the policy, and its effective date, **before** releasing anything that
changes what the app stores or sends: an internet permission, accounts, live
scores or crash reporting. The pages use system fonts, so a visit loads nothing
from another server.

## Fonts and offline first launch

Inter and Barlow Condensed ship inside the app (`app/assets/google_fonts/`, with
their OFL licences, shown in Settings > Open-source licences). `AppFonts.useBundledFonts()`
in `main()` turns off downloading, so the app never needs the internet, even on
first launch. The files are the ones `google_fonts` would download, checked
against its SHA-256 hashes. A new weight or style needs its file added there
(named like `Inter-SemiBold.ttf`) and its weight to the lists in `AppFonts`.
`main()` loads every font before the first frame, waiting at most 3 seconds.
