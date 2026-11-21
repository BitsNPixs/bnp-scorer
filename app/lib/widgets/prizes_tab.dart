import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/tournament_details_screen.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import '../ui/inputs.dart';
import 'avatars.dart';
import 'surface_panel.dart';

/// A tournament's prizes, house rules and entry fees, with who has paid.
/// Payments are the organiser's own record and never leave this phone. When
/// [watching] someone else's tournament, it only shows what they published.
class PrizesTab extends ConsumerWidget {
  const PrizesTab({super.key, required this.tournament, this.watching = false});

  final Tournament tournament;
  final bool watching;

  static const noneListed = 'No prizes or rules listed yet.';

  static const privateNote = 'Only on this phone. Never published.';

  Future<void> _save(BuildContext context, WidgetRef ref, Tournament changed) async {
    try {
      await ref.read(tournamentRepositoryProvider).save(changed);
    } on Object catch (e) {
      if (context.mounted) showMessage(context, 'Could not save it: $e', isError: true);
      return;
    }
    if (context.mounted) ref.invalidate(tournamentsProvider);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final details = await Navigator.of(context).push<TournamentDetails>(
      MaterialPageRoute(builder: (_) => TournamentDetailsScreen(tournament: tournament)),
    );
    if (details == null || !context.mounted) return;
    await _save(
      context,
      ref,
      tournament.withDetails(prizes: details.prizes, entryFee: details.entryFee, rules: details.rules),
    );
  }

  Future<void> _recordPayment(BuildContext context, WidgetRef ref, Team team) async {
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => _PaymentDialog(team: team, fee: tournament.entryFee!, paid: tournament.paidBy(team.id)),
    );
    if (amount == null || !context.mounted) return;
    await _save(context, ref, tournament.withPaid(team.id, amount));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fee = tournament.entryFee;
    final rules = tournament.rules;
    final nothingYet = tournament.prizes.isEmpty && fee == null && rules == null;
    if (nothingYet && watching) return const Center(child: Text(noneListed));
    if (nothingYet) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SurfacePanel(
            child: Column(
              children: [
                const Icon(Icons.emoji_events_rounded, size: 44, color: AppColors.four),
                const SizedBox(height: 12),
                Text(
                  'Add the prizes, an entry fee and house rules, so every team knows what they '
                  'are playing for.',
                  textAlign: TextAlign.center,
                  style: text.bodyLarge,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _edit(context, ref),
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Add details'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final collected = tournament.teams.fold(0, (sum, t) => sum + tournament.paidBy(t.id));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (tournament.prizes.isNotEmpty) ...[
          const SectionTitle('Prizes'),
          const SizedBox(height: 10),
          SurfacePanel(
            child: Column(
              children: [
                for (final (i, prize) in tournament.prizes.indexed) ...[
                  if (i > 0) const Divider(height: 24),
                  Row(
                    children: [
                      SizedBox(
                        width: 30,
                        child: Icon(
                          Icons.emoji_events_rounded,
                          color: i == 0 ? AppColors.four : scheme.onSurfaceVariant,
                          size: i == 0 ? 30 : 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(prize.title.toUpperCase(),
                                style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 1.2)),
                            const SizedBox(height: 2),
                            Text(prize.reward, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (rules != null) ...[
          const SectionTitle('Rules and notes'),
          const SizedBox(height: 10),
          SurfacePanel(child: Text(rules, style: text.bodyLarge)),
          const SizedBox(height: 20),
        ],
        if (fee != null && watching) ...[
          const SectionTitle('Entry fee'),
          const SizedBox(height: 4),
          Text('${rupees(fee)} a team', style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
        ],
        if (fee != null && !watching) ...[
          const SectionTitle('Entry fees'),
          const SizedBox(height: 4),
          Text(
            '${rupees(fee)} a team · ${rupees(collected)} of ${rupees(fee * tournament.teams.length)} collected',
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(child: Text(privateNote, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
            ],
          ),
          const SizedBox(height: 10),
          SurfacePanel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final team in tournament.teams)
                  _PaymentRow(team: team, tournament: tournament, onTap: () => _recordPayment(context, ref, team)),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (!watching)
          OutlinedButton.icon(
            onPressed: () => _edit(context, ref),
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Edit prizes, fee and rules'),
          ),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.team, required this.tournament, required this.onTap});

  final Team team;
  final Tournament tournament;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final paid = tournament.paidBy(team.id);
    final due = tournament.dueFrom(team.id) ?? 0;
    final (status, color) = switch ((paid, due)) {
      (_, 0) => ('Paid', scheme.primary),
      (0, _) => ('Not paid', scheme.error),
      _ => ('${rupees(paid)} of ${rupees(tournament.entryFee!)}', AppColors.four),
    };
    return ListTile(
      onTap: onTap,
      leading: TeamBadge(name: team.name, size: 36, logoUrl: team.logoUrl),
      title: Text(team.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(status, style: text.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w800)),
    );
  }
}

/// Asks what a team has paid in total so far. Pops with the amount.
class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.team, required this.fee, required this.paid});

  final Team team;
  final int fee;
  final int paid;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final _amount = TextEditingController(text: widget.paid == 0 ? '' : '${widget.paid}');

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _done(int amount) => Navigator.of(context).pop(amount);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.team.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paid so far, of ${rupees(widget.fee)}'),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('paid-amount'),
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
              decoration: fieldDecoration(context, '0', icon: Icons.currency_rupee_rounded),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(label: const Text('Paid in full'), onPressed: () => _done(widget.fee)),
                ActionChip(label: const Text('Not paid'), onPressed: () => _done(0)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => _done(int.tryParse(_amount.text.trim()) ?? 0),
            child: const Text('Save'),
          ),
        ],
      );
}
