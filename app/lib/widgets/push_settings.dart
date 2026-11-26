import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/push_messages.dart';
import '../state/providers.dart';
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
