/// The app's version, shown in Settings and in problem reports. It must match
/// `version:` in pubspec.yaml (`test/app_info_test.dart` checks), so it needs
/// no plugin to read it at run time.
const appVersion = '0.9.0-beta.2';
const appBuild = 3;

const appVersionLabel = '$appVersion (build $appBuild)';
