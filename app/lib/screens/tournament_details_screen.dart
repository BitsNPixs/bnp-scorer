import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/feedback.dart';
import '../ui/inputs.dart';
import '../widgets/surface_panel.dart';

/// What the organiser filled in on [TournamentDetailsScreen].
typedef TournamentDetails = ({List<Prize> prizes, int? entryFee, String? rules});

/// Prizes, the entry fee and house rules, edited together. Pops with the new
/// [TournamentDetails], or nothing if the organiser backs out.
class TournamentDetailsScreen extends StatefulWidget {
  const TournamentDetailsScreen({super.key, required this.tournament});

  final Tournament tournament;

  static const missingTitle = 'Give each prize a name, like Winner or Best bowler';

  @override
  State<TournamentDetailsScreen> createState() => _TournamentDetailsScreenState();
}

class _TournamentDetailsScreenState extends State<TournamentDetailsScreen> {
  final _prizes = <({TextEditingController title, TextEditingController reward})>[];
  late final _fee = TextEditingController(text: widget.tournament.entryFee?.toString() ?? '');
  late final _rules = TextEditingController(text: widget.tournament.rules ?? '');

  @override
  void initState() {
    super.initState();
    final existing = widget.tournament.prizes;
    if (existing.isEmpty) {
      // The prizes nearly every cup has, ready to fill in.
      _addPrize('Winner');
      _addPrize('Runner-up');
    } else {
      for (final prize in existing) {
        _addPrize(prize.title, prize.reward);
      }
    }
  }

  void _addPrize([String title = '', String reward = '']) => _prizes.add((
        title: TextEditingController(text: title),
        reward: TextEditingController(text: reward),
      ));

  @override
  void dispose() {
    for (final row in _prizes) {
      row.title.dispose();
      row.reward.dispose();
    }
    _fee.dispose();
    _rules.dispose();
    super.dispose();
  }

  /// Rows without a reward are left out: a prize is what is won.
  void _save() {
    final prizes = <Prize>[];
    for (final row in _prizes) {
      final reward = row.reward.text.trim();
      if (reward.isEmpty) continue;
      final title = row.title.text.trim();
      if (title.isEmpty) {
        showMessage(context, TournamentDetailsScreen.missingTitle, isError: true);
        return;
      }
      prizes.add(Prize(title: title, reward: reward));
    }
    final fee = int.tryParse(_fee.text.trim());
    final TournamentDetails details = (prizes: prizes, entryFee: fee == 0 ? null : fee, rules: _rules.text);
    Navigator.of(context).pop(details);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Text('Prizes, fee and rules'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Prizes'),
                const SizedBox(height: 4),
                Text(
                  'Write each prize as you would announce it. The first one is the winner\'s.',
                  style: text.bodySmall?.copyWith(color: muted),
                ),
                for (final (i, row) in _prizes.indexed) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: ValueKey('prize-title-$i'),
                          controller: row.title,
                          textCapitalization: TextCapitalization.words,
                          decoration: fieldDecoration(context, 'Prize, e.g. Best bowler'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove prize',
                        onPressed: () {
                          setState(() => _prizes.removeAt(i));
                          // Its fields leave the screen in this frame; free them after it.
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            row.title.dispose();
                            row.reward.dispose();
                          });
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: ValueKey('prize-reward-$i'),
                    controller: row.reward,
                    decoration: fieldDecoration(context, 'What it is, e.g. ₹10,000 + trophy',
                        icon: Icons.emoji_events_outlined),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(_addPrize),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add prize'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Entry fee per team'),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('entry-fee'),
                  controller: _fee,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
                  decoration: fieldDecoration(context, 'None', icon: Icons.currency_rupee_rounded),
                ),
                const SizedBox(height: 6),
                Text(
                  'Track who has paid on the Prizes tab. Payments stay on this phone.',
                  style: text.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Rules and notes'),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('rules'),
                  controller: _rules,
                  minLines: 3,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: fieldDecoration(context, 'Ball, timings, fees not refundable...'),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Save'),
          ),
        ),
      ),
    );
  }
}
