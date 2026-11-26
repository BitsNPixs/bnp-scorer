import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/push_messages.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import 'surface_panel.dart';

/// Settings: a switch per kind of push, and a test button. Signed out, it
/// says why signing in matters instead.
class PushSettingsPanel extends ConsumerWidget {
  const PushSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(pushRegistrationProvider).available) return const SizedBox.shrink();
    final signedIn = ref.watch(scorerProvider).value != null;
    final kinds = ref.watch(pushKindsProvider);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SurfacePanel(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: signedIn
            ? Column(
                children: [
                  for (final kind in PushKind.values)
                    SwitchListTile(
                      secondary: Icon(switch (kind) {
                        PushKind.follow => Icons.sports_cricket_rounded,
                        PushKind.team => Icons.groups_rounded,
                        PushKind.cup => Icons.emoji_events_rounded,
                      }),
                      title: Text(kind.title),
                      subtitle: Text(kind.detail),
                      value: kinds.contains(kind),
                      onChanged: (on) async {
                        final result = await ref.read(pushKindsProvider.notifier).set(kind, on);
                        if (context.mounted) reportResult(context, result);
                      },
                    ),
                  if (kinds.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.send_to_mobile_rounded),
                      title: const Text('Send me a test notification'),
                      subtitle: const Text('Checks that updates reach this phone'),
                      onTap: () async {
                        try {
                          await ref.read(pushRegistrationProvider).requestTest();
                          if (context.mounted) showMessage(context, 'Sent. It should arrive in a few seconds.');
                        } on Object catch (e) {
                          if (context.mounted) showMessage(context, 'Could not send it: $e', isError: true);
                        }
                      },
                    ),
                ],
              )
            : ListTile(
                leading: const Icon(Icons.notifications_none_rounded),
                title: const Text('Live updates'),
                subtitle: Text(
                  'Sign in to hear about matches you follow, your teams and your cups.',
                  style: TextStyle(color: muted),
                ),
              ),
      ),
    );
  }
}

/// The bell on a watched match: follow it for its wickets, milestones and
/// result. Hidden where push is not available, on a finished match, and on
/// the scorer's own match. Signed out, it says to sign in.
class FollowMatchButton extends ConsumerWidget {
  const FollowMatchButton({super.key, required this.matchId, required this.ownerUid, required this.finished});

  final String matchId;
  final String ownerUid;
  final bool finished;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(pushMessagesProvider).available && ref.watch(pushDevicesProvider) != null;
    if (!available || finished) return const SizedBox.shrink();
    final scorer = ref.watch(scorerProvider).value;
    if (scorer?.uid == ownerUid) return const SizedBox.shrink();
    final following = ref.watch(followedMatchesProvider).containsKey(matchId);
    return IconButton(
      tooltip: following ? 'Following: tap to stop' : 'Follow this match',
      isSelected: following,
      icon: const Icon(Icons.notifications_none_rounded),
      selectedIcon: const Icon(Icons.notifications_active_rounded, color: AppColors.neon),
      onPressed: () async {
        if (scorer == null) {
          showMessage(context, 'Sign in from Settings to follow matches.');
          return;
        }
        final result = await ref.read(followedMatchesProvider.notifier).toggle(matchId);
        if (!context.mounted || !reportResult(context, result)) return;
        showMessage(
          context,
          following ? 'Stopped following' : "Following: you'll hear about wickets, milestones and the result",
        );
      },
    );
  }
}

