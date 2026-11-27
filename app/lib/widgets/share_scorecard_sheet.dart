import 'dart:ui' as ui;

import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import 'logo_mark.dart';
import 'scoring_sheets.dart';

const _imageScale = 3.0;

/// Shares [state] as a picture. A match that is published also offers its
/// page on the website: pass its id as [publishedMatchId].
Future<void> showShareScorecardSheet(BuildContext context, MatchState state, {String? publishedMatchId}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _ShareScorecardSheet(state: state, publishedMatchId: publishedMatchId),
    );

class _ShareScorecardSheet extends ConsumerStatefulWidget {
  const _ShareScorecardSheet({required this.state, required this.publishedMatchId});

  final MatchState state;
  final String? publishedMatchId;

  @override
  ConsumerState<_ShareScorecardSheet> createState() => _ShareScorecardSheetState();
}

class _ShareScorecardSheetState extends ConsumerState<_ShareScorecardSheet> {
  final _card = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    final files = ref.read(deviceFilesProvider);
    setState(() => _sharing = true);
    try {
      final boundary = _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: _imageScale);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await files.shareImage(data!.buffer.asUint8List(), caption: shareText(widget.state, link: _link));
    } on Object catch (e) {
      if (mounted) showMessage(context, 'Could not share: $e', isError: true);
    }
    if (mounted) setState(() => _sharing = false);
  }

  String? get _link => switch (widget.publishedMatchId) {
        final id? => matchPageLink(id),
        null => null,
      };

  Future<void> _shareLink(String link) async {
    final setup = widget.state.setup;
    setState(() => _sharing = true);
    try {
      await ref
          .read(deviceFilesProvider)
          .shareText(matchLinkText(widget.state, link), subject: '${setup.teamA.name} v ${setup.teamB.name}');
    } on Object catch (e) {
      if (mounted) showMessage(context, 'Could not share: $e', isError: true);
    }
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) => SheetBody(
        title: 'Share scorecard',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RepaintBoundary(key: _card, child: ScorecardCard(state: widget.state)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sharing ? null : _share,
              icon: const Icon(Icons.share_rounded),
              label: const Text('Share'),
            ),
            if (_link case final link?) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _sharing ? null : () => _shareLink(link),
                icon: const Icon(Icons.link_rounded),
                label: const Text('Share a link to the match'),
              ),
              const SizedBox(height: 8),
              Text(
                'Anyone can open the link in a browser and follow every ball, without the app.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      );
}

/// The picture that gets shared, so it stays branded wherever it is posted.
class ScorecardCard extends StatelessWidget {
  const ScorecardCard({super.key, required this.state});

  final MatchState state;

  @override
  Widget build(BuildContext context) {
    final setup = state.setup;
    final venue = setup.venue;
    final best = playerOfTheMatch(state);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.neon.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LogoMark(size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'BNP Scorer',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: scoreStyle(16, color: Colors.white),
                ),
              ),
            ],
          ),
          if (venue != null) ...[
            const SizedBox(height: 4),
            Text(
              venue,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          for (final innings in state.innings) _InningsLine(setup: setup, innings: innings),
          const SizedBox(height: 8),
          Text(
            matchStatus(state),
            style: scoreStyle(20, color: AppColors.neon),
          ),
          if (best != null) ...[
            const SizedBox(height: 6),
            Text(
              'Player of the Match: ${playerName(setup, best)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

class _InningsLine extends StatelessWidget {
  const _InningsLine({required this.setup, required this.innings});

  final MatchSetup setup;
  final InningsState innings;

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(color: Colors.white70, fontSize: 12);
    final highlights = inningsHighlights(setup, innings);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  setup.teamById(innings.battingTeamId).name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Text(scoreLine(innings), style: scoreStyle(20, color: Colors.white)),
              Text(' (${innings.oversText})', style: small),
            ],
          ),
          if (highlights.isNotEmpty)
            Text(highlights, maxLines: 2, overflow: TextOverflow.ellipsis, style: small),
        ],
      ),
    );
  }
}
