String getFriendlyError(String code) {
  switch (code) {
    case 'user-not-found':
      return 'No account found for this email.';
    case 'wrong-password':
      return 'Incorrect password. Please try again.';
    case 'email-already-in-use':
      return 'This email is already registered.';
    case 'weak-password':
      return 'Password should be at least 6 characters.';
    case 'invalid-email':
      return 'Please enter a valid email address.';
    case 'user-disabled':
      return 'This user account has been disabled.';
    case 'operation-not-allowed':
      return 'This operation is not allowed.';
    case 'invalid-credential':
    case 'invalid-verification-code':
    case 'invalid-verification-id':
    case 'expired-action-code':
      return 'There was a problem signing you in. Please try again.';
    default:
      return 'Something went wrong. Please try again.';
  }
}
