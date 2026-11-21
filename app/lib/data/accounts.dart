import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// A scorer signed in with Google. Only signed-in scorers publish matches.
class Scorer {
  const Scorer({required this.uid, required this.name, this.phone});

  /// The account id: stored on published matches as their owner.
  final String uid;

  /// Shown to watchers as who is scoring.
  final String name;

  /// The mobile number confirmed by SMS, in E.164 form, or null. It claims
  /// the player profile under that number and is never published.
  final String? phone;

  @override
  bool operator ==(Object other) =>
      other is Scorer && other.uid == uid && other.name == name && other.phone == phone;

  @override
  int get hashCode => Object.hash(uid, name, phone);
}

/// An SMS code on its way to [phone], waiting to be typed in.
class PhoneCodeRequest {
  const PhoneCodeRequest({required this.phone, required this.verificationId, this.resendToken});

  final String phone;
  final String verificationId;

  /// Lets "Send again" reuse the same verification.
  final int? resendToken;
}

/// Thrown when sign-in fails for a reason other than the scorer cancelling.
/// The message is written for scorers.
class AccountsException implements Exception {
  const AccountsException(this.message);

  final String message;

  @override
  String toString() => 'AccountsException: $message';
}

/// Who is signed in. Behind an interface so tests and builds without the
/// cloud never touch Firebase.
abstract interface class Accounts {
  /// False in a build without the cloud set up: sign-in is not offered.
  bool get available;

  Scorer? get current;

  /// The scorer after every sign-in and sign-out, starting with [current].
  Stream<Scorer?> get changes;

  /// Opens Google sign-in. Null when the scorer cancels; throws
  /// [AccountsException] when it fails.
  Future<Scorer?> signIn();

  Future<void> signOut();

  /// Texts a code to [e164] to confirm the signed-in scorer owns it. Null
  /// when the phone confirmed the number by itself and it is already on the
  /// account; otherwise pass the request to [linkPhone] with the code. Pass
  /// [resend] to send the same code again. Throws [AccountsException].
  Future<PhoneCodeRequest?> requestPhoneCode(String e164, {PhoneCodeRequest? resend});

  /// Puts the number on the account once [code] matches, replacing any
  /// number already there. Throws [AccountsException].
  Future<void> linkPhone(PhoneCodeRequest request, String code);
}

/// For builds without `google-services.json`, and the default in tests.
class LocalOnlyAccounts implements Accounts {
  const LocalOnlyAccounts();

  @override
  bool get available => false;

  @override
  Scorer? get current => null;

  @override
  Stream<Scorer?> get changes => Stream.value(null);

  @override
  Future<Scorer?> signIn() async =>
      throw const AccountsException('Signing in is not set up in this build.');

  @override
  Future<void> signOut() async {}

  @override
  Future<PhoneCodeRequest?> requestPhoneCode(String e164, {PhoneCodeRequest? resend}) async =>
      throw const AccountsException('Signing in is not set up in this build.');

  @override
  Future<void> linkPhone(PhoneCodeRequest request, String code) async =>
      throw const AccountsException('Signing in is not set up in this build.');
}

/// Google sign-in through Firebase Auth.
class FirebaseAccounts implements Accounts {
  FirebaseAccounts(this._auth);

  final FirebaseAuth _auth;
  Future<void>? _googleReady;

  @override
  bool get available => true;

  @override
  Scorer? get current => _scorerOf(_auth.currentUser);

  /// `userChanges`, not `authStateChanges`: only the first fires when a
  /// number is linked. It also fires on token refreshes, hence `distinct`.
  @override
  Stream<Scorer?> get changes => _auth.userChanges().map(_scorerOf).distinct();

  @override
  Future<Scorer?> signIn() async {
    try {
      // On Android the web client id comes from google-services.json, through
      // the Google Services Gradle plugin, so none is passed here.
      await (_googleReady ??= GoogleSignIn.instance.initialize());
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw const AccountsException('Google did not confirm the account. Try again.');
      final result = await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      return _scorerOf(result.user);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw AccountsException('Could not sign in with Google (${e.description ?? e.code.name}).');
    } on FirebaseAuthException catch (e) {
      throw AccountsException('Could not sign in (${e.message ?? e.code}).');
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await GoogleSignIn.instance.signOut();
    } on Object {
      // Firebase is signed out, which is what matters; the next sign-in shows
      // the account picker either way.
    }
  }

  @override
  Future<PhoneCodeRequest?> requestPhoneCode(String e164, {PhoneCodeRequest? resend}) async {
    if (_auth.currentUser == null) throw const AccountsException('Sign in with Google first.');
    final sent = Completer<PhoneCodeRequest?>();
    void fail(FirebaseAuthException e) {
      // Firebase's own words go to the log; the player sees plain advice.
      debugPrint('Sending a phone code failed: ${e.code}: ${e.message}');
      if (!sent.isCompleted) sent.completeError(AccountsException(phoneErrorMessage(e.code)));
    }

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: e164,
        forceResendingToken: resend?.resendToken,
        // Android read the SMS itself, or confirmed the number without one.
        // After the code screen is up this links in the background, and the
        // screen sees the number arrive on the scorer.
        verificationCompleted: (credential) async {
          try {
            await _attach(credential);
            if (!sent.isCompleted) sent.complete(null);
          } on FirebaseAuthException catch (e) {
            if (sent.isCompleted) {
              debugPrint('Linking the number by itself failed: ${e.code}');
            } else {
              fail(e);
            }
          }
        },
        verificationFailed: fail,
        codeSent: (verificationId, resendToken) {
          if (sent.isCompleted) return;
          sent.complete(PhoneCodeRequest(phone: e164, verificationId: verificationId, resendToken: resendToken));
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } on FirebaseAuthException catch (e) {
      fail(e);
    }
    return sent.future;
  }

  @override
  Future<void> linkPhone(PhoneCodeRequest request, String code) async {
    final user = _auth.currentUser;
    if (user == null) throw const AccountsException('Sign in with Google first.');
    // The phone may have read the SMS and linked it already.
    if (user.phoneNumber == request.phone) return;
    try {
      await _attach(PhoneAuthProvider.credential(verificationId: request.verificationId, smsCode: code.trim()));
    } on FirebaseAuthException catch (e) {
      debugPrint('Linking a phone number failed: ${e.code}: ${e.message}');
      throw AccountsException(phoneErrorMessage(e.code));
    }
  }

  /// Links the number, or swaps it for the one already on the account, then
  /// refreshes the token so the cloud rules see the new number at once.
  Future<void> _attach(PhoneAuthCredential credential) async {
    final user = _auth.currentUser;
    if (user == null) throw FirebaseAuthException(code: 'user-not-found');
    if (user.phoneNumber == null) {
      await user.linkWithCredential(credential);
    } else {
      await user.updatePhoneNumber(credential);
    }
    await _auth.currentUser?.getIdToken(true);
    await _auth.currentUser?.reload();
  }

  static Scorer? _scorerOf(User? user) {
    if (user == null) return null;
    final phone = user.phoneNumber;
    return Scorer(
      uid: user.uid,
      name: publicScorerName(user.displayName),
      phone: phone == null || phone.isEmpty ? null : phone,
    );
  }
}

/// What to tell a player when confirming their number fails, by Firebase
/// error code.
String phoneErrorMessage(String code) => switch (code) {
      'invalid-verification-code' => 'That code is not right. Check the SMS and try again.',
      'session-expired' || 'code-expired' => 'The code has expired. Send a new one.',
      'credential-already-in-use' || 'account-exists-with-different-credential' =>
        'This number is already on another BNP Scorer account. Sign in with that Google '
            'account, or remove the number there first.',
      'invalid-phone-number' => 'That does not look like a mobile number.',
      'too-many-requests' || 'quota-exceeded' => 'Too many tries. Wait a while before trying again.',
      'network-request-failed' => 'No internet. Connect and try again.',
      // Setup problems: the code says which one, for whoever fixes it.
      'app-not-authorized' || 'missing-client-identifier' || 'operation-not-allowed' || 'billing-not-enabled' =>
        'Confirming numbers is not set up yet ($code). Try again after the next update.',
      _ => 'Could not confirm the number ($code).',
    };

/// The name published with a scorer's matches: their Google display name, or
/// "Scorer". Never the email address, which stays private, even when an
/// account uses it as its display name.
String publicScorerName(String? displayName) {
  final name = displayName?.trim() ?? '';
  return name.isEmpty || name.contains('@') ? 'Scorer' : name;
}
