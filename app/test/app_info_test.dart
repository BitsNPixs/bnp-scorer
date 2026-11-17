import 'dart:io';

import 'package:bnp_scorer/data/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the version in Settings matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(version, '$appVersion+$appBuild');
    expect(appVersionLabel, '$appVersion (build $appBuild)');
  });
}
