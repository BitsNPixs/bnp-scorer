import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/format.dart';
import '../ui/motion.dart';
import 'avatars.dart';
import 'score_header.dart';

/// The floodlit summary at the top of a scorecard: every innings, the result
/// or the state of play, and the Player of the Match.
class ResultHero extends StatelessWidget {
  const ResultHero({super.key, required this.state, this.focusInnings});

  final MatchState state;

  /// The innings number whose tab is open. Its line gets a neon marker.
  final int? focusInnings;

  @override
  Widget build(BuildContext context) {
    final setup = state.setup;
    final text = Theme.of(context).textTheme;
    const muted = Color(0x99FFFFFF);
    final winner = state.result?.winnerTeamId;
    final best = playerOfTheMatch(state);
    final meta = ['${setup.rules.oversPerInnings} overs', ?setup.venue].join(' · ');

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.neon.withValues(alpha: 0.18)),
        boxShadow: AppColors.glow(AppColors.night, strength: 0.3),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.9, -0.9),
                  radius: 1,
                  colors: [AppColors.neon.withValues(alpha: 0.14), AppColors.neon.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (state.isCompleted)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.neon.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'RESULT',
                          style: TextStyle(
                            color: AppColors.neon,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 1.2,
                          ),
                        ),
                      )
                    else
                      const LivePill(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        meta,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium?.copyWith(color: muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                for (final inn in state.innings)
                  _InningsLine(
                    team: setup.teamById(inn.battingTeamId),
                    innings: inn,
                    won: winner == inn.battingTeamId,
                    focused: inn.number == focusInnings,
                  ),
                const SizedBox(height: 10),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.10)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (state.isCompleted) ...[
                      const PopIn(child: Icon(Icons.emoji_events_rounded, size: 22, color: AppColors.four)),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        matchStatus(state),
                        style: text.titleMedium?.copyWith(
                          color: state.isCompleted ? AppColors.neon : Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                if (best != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.four.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.star_rounded, size: 20, color: AppColors.four),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PLAYER OF THE MATCH',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.labelSmall?.copyWith(color: muted, letterSpacing: 1.2),
                              ),
                              Text(
                                playerName(setup, best),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InningsLine extends StatelessWidget {
  const _InningsLine({required this.team, required this.innings, required this.won, required this.focused});

  final Team team;
  final InningsState innings;
  final bool won;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    const muted = Color(0x99FFFFFF);
    final started = innings.legalBalls > 0 || innings.runs > 0 || innings.isComplete;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              color: focused ? AppColors.neon : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          PlayerAvatar(name: team.name, radius: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              team.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: won || focused ? Colors.white : const Color(0xCCFFFFFF),
                    fontWeight: won ? FontWeight.w800 : FontWeight.w600,
                  ),
            ),
          ),
          if (started) ...[
            Text(
              scoreLine(innings),
              style: scoreStyle(30, color: won ? Colors.white : const Color(0xD9FFFFFF), weight: FontWeight.w800),
            ),
            const SizedBox(width: 6),
            Text(
              '(${innings.oversText})',
              style: const TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ] else
            const Text('Yet to bat', style: TextStyle(color: muted, fontSize: 12)),
        ],
      ),
    );
  }
}
