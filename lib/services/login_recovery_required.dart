/// Recovery failed, but the user can explicitly open a fresh Railway login.
/// This never triggers the incorrect-credentials automatic redirect.
class LoginRecoveryRequired implements Exception {
  const LoginRecoveryRequired(this.message);
  final String message;
  @override
  String toString() => message;
}
