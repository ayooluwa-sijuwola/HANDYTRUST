/// Q-3 (approved): one password rule for every NEW or CHANGED password —
/// at least 8 characters, one uppercase letter and one number. Existing
/// passwords are never re-validated at sign-in, so no user is forced to
/// change a password just to sign in.
abstract final class PasswordPolicy {
  static const minLength = 8;

  static const summary = 'At least 8 characters, with an uppercase letter and a number.';

  /// Null when [value] satisfies the policy; otherwise the first problem.
  static String? validate(String? value) {
    final v = value ?? '';
    if (v.length < minLength) return 'Password must be at least $minLength characters';
    if (!v.contains(RegExp(r'[A-Z]'))) return 'Include at least one uppercase letter';
    if (!v.contains(RegExp(r'[0-9]'))) return 'Include at least one number';
    return null;
  }

  /// Per-rule status, for a live checklist under the field.
  static List<(String, bool)> checklist(String value) => [
        ('At least $minLength characters', value.length >= minLength),
        ('One uppercase letter', value.contains(RegExp(r'[A-Z]'))),
        ('One number', value.contains(RegExp(r'[0-9]'))),
      ];
}
