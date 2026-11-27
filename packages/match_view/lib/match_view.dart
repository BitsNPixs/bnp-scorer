/// How a match reads to people: the words for scores, dismissals and results
/// ([matchStatus], [dismissalText]), and the JSON the API serves and the
/// website shows ([matchCard], [matchView]), and whether a match is being
/// played right now ([matchNow]).
///
/// The app and the server both use this, so a scorecard says the same thing
/// on a phone and on the web. Rules stay in `cricket_engine`.
library;

export 'src/now.dart';
export 'src/view.dart';
export 'src/wording.dart';
