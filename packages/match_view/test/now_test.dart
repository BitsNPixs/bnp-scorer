import 'package:match_view/match_view.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 27, 12);
  MatchNow at(Duration ago, {bool finished = false}) =>
      matchNow(finished: finished, lastSaved: now.subtract(ago), now: now);

  test('a match being scored is live', () {
    expect(at(Duration.zero), MatchNow.live);
    expect(at(const Duration(hours: 5, minutes: 59, seconds: 59)), MatchNow.live);
  });

  test('a match nobody has scored for six hours is stopped', () {
    expect(stoppedAfter, const Duration(hours: 6));
    expect(at(stoppedAfter), MatchNow.stopped);
    expect(at(const Duration(days: 30)), MatchNow.stopped);
  });

  test('a finished match is finished, however long ago', () {
    expect(at(Duration.zero, finished: true), MatchNow.finished);
    expect(at(const Duration(days: 30), finished: true), MatchNow.finished);
  });

  test('a save in the future (a phone with a wrong clock) is live', () {
    expect(at(const Duration(hours: -3)), MatchNow.live);
  });

  test('with no save time it is live, not hidden', () {
    expect(matchNow(finished: false, lastSaved: null, now: now), MatchNow.live);
  });
}
