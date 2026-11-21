import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/accounts.dart';
import '../data/phone_numbers.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/inputs.dart';
import 'scoring_sheets.dart';

/// Asks for a mobile number and texts a code. Signed in, the number goes on
/// the account; signed out, it signs in with it, and a new account is asked
/// for a name. With [nameOnly], it only asks for the name, for an account
/// that skipped that step. True once done.
Future<bool> showPhoneLinkSheet(BuildContext context, {bool nameOnly = false}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _PhoneLinkSheet(nameOnly: nameOnly),
    ) ??
    false;

class _PhoneLinkSheet extends ConsumerStatefulWidget {
  const _PhoneLinkSheet({required this.nameOnly});

  final bool nameOnly;

  @override
  ConsumerState<_PhoneLinkSheet> createState() => _PhoneLinkSheetState();
}

class _PhoneLinkSheetState extends ConsumerState<_PhoneLinkSheet> {
  static const why = 'We text you a code to check the number is yours. It finds your player profile, '
      'so the runs and wickets captains add under your number become yours. It is never shown to anyone.';

  final _number = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  PhoneCodeRequest? _request;
  String? _error;
  bool _busy = false;
  bool _done = false;

  /// Signed in with a number but no name yet: the last step asks for one.
  late bool _askingName = widget.nameOnly;

  /// Who was signed in when the sheet opened; null means this signs in.
  late final bool _signingIn = ref.read(accountsProvider).current == null;

  @override
  void dispose() {
    _number.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  void _finish() {
    if (_done) return;
    if (ref.read(accountsProvider).current?.needsName ?? false) {
      setState(() {
        _askingName = true;
        _busy = false;
        _error = null;
      });
      return;
    }
    _done = true;
    Navigator.of(context).pop(true);
  }

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isEmpty || name.contains('@')) {
      setState(() => _error = 'Type the name players know you by.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountsProvider).setName(name);
      if (!mounted) return;
      _done = true;
      Navigator.of(context).pop(true);
    } on AccountsException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  Future<void> _send({bool again = false}) async {
    final e164 = again ? _request?.phone : normalizePhone(_number.text);
    if (e164 == null) {
      setState(() => _error = 'Type a 10-digit mobile number, or one with its + code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = await ref.read(accountsProvider).requestPhoneCode(e164, resend: again ? _request : null);
      if (!mounted) return;
      if (request == null) return _finish();
      setState(() {
        _request = request;
        _busy = false;
        _code.clear();
      });
    } on AccountsException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  Future<void> _confirm() async {
    final request = _request!;
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Type the 6-digit code from the SMS.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountsProvider).confirmPhone(request, code);
      if (mounted) _finish();
    } on AccountsException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Android may read the SMS by itself once the code is on its way.
    ref.listen(scorerProvider, (_, next) {
      final request = _request;
      if (request != null && !_askingName && next.value?.phone == request.phone) _finish();
    });
    final request = _request;
    final error = _error;
    final spinner = SizedBox.square(
      dimension: 22,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.night.withValues(alpha: 0.7)),
    );
    if (_askingName) {
      return SheetBody(
        title: 'Your name',
        subtitle: 'Shown as who scores your matches and on your player profile.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('scorer-name'),
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              inputFormatters: [LengthLimitingTextInputFormatter(60)],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveName(),
              decoration: fieldDecoration(context, 'Your name', icon: Icons.person_rounded),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _saveName, child: _busy ? spinner : const Text('Save')),
          ],
        ),
      );
    }
    return SheetBody(
      title: request != null
          ? 'Type the code'
          : _signingIn
              ? 'Sign in with your number'
              : 'Your mobile number',
      subtitle: request == null ? why : 'Sent by SMS to ${request.phone}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (request == null)
            TextField(
              key: const ValueKey('phone-number'),
              controller: _number,
              autofocus: true,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: fieldDecoration(context, '98765 43210', icon: Icons.phone_rounded),
            )
          else
            TextField(
              key: const ValueKey('sms-code'),
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _confirm(),
              decoration: fieldDecoration(context, '6-digit code', icon: Icons.sms_rounded),
            ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : (request == null ? _send : _confirm),
            child: _busy ? spinner : Text(request == null ? 'Send code' : 'Confirm'),
          ),
          if (request != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _busy ? null : () => _send(again: true),
                    child: const Text('Send again'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _request = null;
                              _error = null;
                            }),
                    child: const Text('Change number'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
