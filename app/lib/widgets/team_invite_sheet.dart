import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/cloud_teams.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import 'scoring_sheets.dart';

/// A shared team's invite: the join code, a QR code players scan at the
/// ground, and a button that sends the invite on WhatsApp.
Future<void> showTeamInviteSheet(BuildContext context, {required String teamId, required String teamName}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _TeamInviteSheet(teamId: teamId, teamName: teamName),
    );

class _TeamInviteSheet extends ConsumerWidget {
  const _TeamInviteSheet({required this.teamId, required this.teamName});

  final String teamId;
  final String teamName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = joinCodeOf(teamId);
    final text = Theme.of(context).textTheme;
    return SheetBody(
      title: 'Invite to $teamName',
      subtitle: 'Players scan this or type the code under Teams, Join a team. You add them when they ask.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            // Dark squares on white whatever the theme, so every camera reads it.
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: QrImageView(
                key: const ValueKey('invite-qr'),
                data: joinPageLink(code),
                size: 200,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.night),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppColors.night,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: SelectableText(
              code,
              style: scoreStyle(36, color: Theme.of(context).colorScheme.primary).copyWith(letterSpacing: 4),
            ),
          ),
          Center(child: Text('Join code', style: text.labelMedium)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              try {
                await ref
                    .read(deviceFilesProvider)
                    .shareText(teamInviteText(teamName, code), subject: 'Join $teamName');
              } on Object catch (e) {
                if (context.mounted) showMessage(context, 'Could not open sharing: $e', isError: true);
              }
            },
            icon: const Icon(Icons.send_rounded),
            label: const Text('Send invite'),
          ),
        ],
      ),
    );
  }
}
