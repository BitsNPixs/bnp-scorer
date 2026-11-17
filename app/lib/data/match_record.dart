import 'package:cricket_engine/cricket_engine.dart';

/// What gets stored for a match: the setup plus the event log. All scores
/// are derived by replaying the log, so this is all a backend needs to sync.
class MatchRecord {
  MatchRecord({
    required this.setup,
    required List<MatchEvent> events,
    required this.createdAt,
    required this.updatedAt,
    this.publishedBy,
  }) : events = List.unmodifiable(events);

  final MatchSetup setup;
  final List<MatchEvent> events;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The signed-in scorer (their account id) who publishes this match for
  /// everyone to follow. Null for a match that stays on this phone.
  final String? publishedBy;

  String get id => setup.id;

  MatchRecord withEvents(List<MatchEvent> events) => MatchRecord(
        setup: setup,
        events: events,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        publishedBy: publishedBy,
      );

  Json toJson() => {
        'setup': setup.toJson(),
        'events': [for (final e in events) e.toJson()],
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        // Written only when set, so private matches read the same as before.
        if (publishedBy != null) 'publishedBy': publishedBy,
      };

  factory MatchRecord.fromJson(Json json) => MatchRecord(
        setup: MatchSetup.fromJson(json['setup']! as Json),
        events: [
          for (final e in json['events']! as List<Object?>)
            MatchEvent.fromJson(e! as Json),
        ],
        createdAt: DateTime.parse(json['createdAt']! as String),
        updatedAt: DateTime.parse(json['updatedAt']! as String),
        publishedBy: json['publishedBy'] as String?,
      );
}
