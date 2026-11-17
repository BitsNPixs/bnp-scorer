import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// A scorer signed in with Google. Only signed-in scorers publish matches.
class Scorer {
  const Scorer({required this.uid, required this.name});

  /// The account id: stored on published matches as their owner.
  final String uid;

  /// Shown to watchers as who is scoring.
  final String name;
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

  @override
  Stream<Scorer?> get changes => _auth.authStateChanges().map(_scorerOf);

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

  static Scorer? _scorerOf(User? user) {
    if (user == null) return null;
    return Scorer(uid: user.uid, name: publicScorerName(user.displayName));
  }
}

/// The name published with a scorer's matches: their Google display name, or
/// "Scorer". Never the email address, which stays private, even when an
/// account uses it as its display name.
String publicScorerName(String? displayName) {
  final name = displayName?.trim() ?? '';
  return name.isEmpty || name.contains('@') ? 'Scorer' : name;
}
