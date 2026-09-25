abstract final class Routes {
  static const splash = '/';
  static const language = '/language';
  static const signIn = '/sign-in';
  static const consent = '/consent';
  static const profileSetup = '/profile-setup';

  /// OAuth deep link path (com.askmedi.askmedi://login-callback). supabase_flutter
  /// consumes the URI itself; go_router also sees it and needs a route for it.
  static const loginCallback = '/login-callback';

  static const home = '/home';
  static const history = '/history';
  static const hospitals = '/hospitals';
  static const profile = '/profile';

  static const preApp = {
    splash,
    language,
    signIn,
    consent,
    profileSetup,
    loginCallback,
  };
}
