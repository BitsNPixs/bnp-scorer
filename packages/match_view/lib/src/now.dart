/// A match that is not finished and has not been saved for this long is
/// "stopped", not "live": its scorer went home without ending it. One more
/// ball makes it live again.
const stoppedAfter = Duration(hours: 6);

/// What a match is doing now. A saved match cannot say this by itself,
/// because it does not change as time passes. The API sends it by name as
/// `state`; the app shows LIVE only for [live].
enum MatchNow { live, stopped, finished }

/// [lastSaved] is when the match was last saved; a match with no known save
/// time is taken as live rather than hidden.
MatchNow matchNow({required bool finished, required DateTime? lastSaved, required DateTime now}) {
  if (finished) return MatchNow.finished;
  if (lastSaved != null && now.difference(lastSaved) >= stoppedAfter) return MatchNow.stopped;
  return MatchNow.live;
}
