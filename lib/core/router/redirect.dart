import '../../features/auth/domain/auth_repository.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const configError = '/config-error';
  static const onboarding = '/onboarding';
  static const signIn = '/auth/sign-in';
  static const signUp = '/auth/sign-up';
  static const verifyEmail = '/auth/verify-email';
  static const policy = '/policy';
  static const terms = '/terms';
  static const setupProfile = '/setup/profile';
  static const home = '/home';
  static const nearby = '/nearby';
  static const chats = '/chats';
  static const trips = '/trips';
  static const me = '/me';
  static const meEdit = '/me/edit';
  static const tripNew = '/trip/new';
  static const tripOptions = '/trip/new/options';
  static const tripConfirm = '/trip/new/confirm';
  static const nearbyRequests = '/nearby/requests';
  static const candidatePattern = '/nearby/:candidateTripId';
  static const matchPattern = '/matches/:matchId';
  static const chatPattern = '/chats/:matchId';
  static const tripDetailPattern = '/trips/:tripId';
  /// Round 6: the one ride screen (UnifiedRideScreen). Must be registered before `/trips/:tripId`.
  static const tripActiveNow = '/trips/active';
  static const tripActivePattern = '/trips/:tripId/active';
  static const tripArrivedPattern = '/trips/:tripId/arrived';
  static const tripSharePattern = '/trips/:tripId/share';
  static const sos = '/sos';
  static const safety = '/safety';
  static const safetyContacts = '/safety/contacts';
  static const safetyContactEdit = '/safety/contacts/edit';
  static const reportPattern = '/report/:userId';
  static const settings = '/me/settings';
  static const settingsPrivacy = '/me/settings/privacy';
  static const settingsNotifications = '/me/settings/notifications';
  static const settingsDeleteAccount = '/me/settings/delete-account';
  static const settingsGender = '/me/settings/gender';
  static const settingsTheme = '/me/settings/theme';
  static const blocked = '/me/blocked';
  static const vehicle = '/me/vehicle';
  static const driverRegister = '/me/driver/register';
  static const pickupPattern = '/matches/:matchId/pickup';
  // Round 5
  static const mePhoto = '/me/photo';
  static const mePlaces = '/me/places';
  static const mePlacePattern = '/me/places/:kind';
  static String mePlace(String kind) => '/me/places/$kind';
  static const nearbyListView = '/nearby?view=list';
  static const meReviews = '/me/reviews';
  static const reportPhotoPattern = '/report/photo/:userId';
  static const livePattern = '/matches/:matchId/live';
  static const reviewPattern = '/matches/:matchId/review';
  static const reviewDonePattern = '/matches/:matchId/review/done';
  static String live(String matchId) => '/matches/$matchId/live';
  static String review(String matchId) => '/matches/$matchId/review';
  static String reviewDone(String matchId) => '/matches/$matchId/review/done';
  static String reportPhoto(String userId, {String? matchId, String? name}) => Uri(
        path: '/report/photo/$userId',
        queryParameters: {'match': ?matchId, 'name': ?name},
      ).toString();
  static String candidate(String tripId) => '/nearby/$tripId';
  static String match(String matchId) => '/matches/$matchId';
  static String pickup(String matchId) => '/matches/$matchId/pickup';

  /// `/me/vehicle`, optionally with an in-app path to return to (create-trip gate).
  static String vehicleFor({String? returnTo}) =>
      Uri(path: vehicle, queryParameters: {'returnTo': ?returnTo}).toString();
  /// `/me/driver/register`, optionally with an in-app path to return to (create-trip detour).
  static String driverRegisterFor({String? returnTo}) =>
      Uri(path: driverRegister, queryParameters: {'returnTo': ?returnTo}).toString();
  static String chat(String matchId) => '/chats/$matchId';
  static String tripDetail(String id) => '/trips/$id';
  /// Kept for old call sites: `/trips/:id/active` redirects to [tripActiveNow].
  static String tripActive(String id) => tripActiveNow;
  static String tripArrived(String id) => '/trips/$id/arrived';
  static String tripShare(String id) => '/trips/$id/share';
  static String sosFor({String? tripId, bool fromChat = false}) => Uri(
        path: sos,
        queryParameters: {'trip': ?tripId, if (fromChat) 'source': 'chat'},
      ).toString();
  static String report(String userId, {String? matchId, String? name}) => Uri(
        path: '/report/$userId',
        queryParameters: {'match': ?matchId, 'name': ?name},
      ).toString();
  static String contactEdit({String? id}) =>
      Uri(path: safetyContactEdit, queryParameters: {'id': ?id}).toString();
}

class RedirectState {
  const RedirectState({
    required this.configReady,
    required this.booting,
    required this.onboardingDone,
    required this.user,
    required this.profileSetupDone,
  });

  final bool configReady;

  /// Splash minimum time or session restore still running.
  final bool booting;
  final bool onboardingDone;
  final AuthUser? user;
  final bool profileSetupDone;
}

/// Guard order follows design-spec section 2.3. Returns null to stay.
String? computeRedirect(String location, RedirectState s) {
  if (!s.configReady) {
    return location == Routes.configError ? null : Routes.configError;
  }
  if (location == Routes.configError) return Routes.splash;
  if (s.booting) return location == Routes.splash ? null : Routes.splash;

  final isLegal = location == Routes.policy || location == Routes.terms;
  final isAuth = location.startsWith('/auth/');
  final user = s.user;

  if (user == null) {
    final entry = s.onboardingDone ? Routes.signIn : Routes.onboarding;
    if (location == Routes.splash) return entry;
    if (location == Routes.onboarding) return s.onboardingDone ? Routes.signIn : null;
    if (isAuth || isLegal) return null;
    return entry;
  }

  // Signed in: email must be confirmed first (P-4), then profile setup.
  if (!user.emailConfirmed) {
    return location == Routes.verifyEmail || isLegal ? null : Routes.verifyEmail;
  }
  if (!s.profileSetupDone) {
    return location == Routes.setupProfile || isLegal ? null : Routes.setupProfile;
  }
  final isEntry = location == Routes.splash ||
      location == Routes.onboarding ||
      location == Routes.setupProfile ||
      isAuth;
  return isEntry ? Routes.home : null;
}
