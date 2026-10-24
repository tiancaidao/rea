import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import '../data/night.dart';

/// Where the app talks to, chosen at build time:
///
///   flutter run                                       # BACKEND=off: local-only (default)
///   flutter run --dart-define=BACKEND=emulator        # Firebase emulators + local API
///   flutter run --dart-define=BACKEND=cloud \
///     --dart-define=API_BASE_URL=https://<run-url> \
///     --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... \
///     --dart-define=FIREBASE_SENDER_ID=... --dart-define=FIREBASE_PROJECT_ID=... \
///     --dart-define=FIREBASE_STORAGE_BUCKET=...
///
/// (`backend/scripts/app_defines.sh <project>` prints the cloud flags.)
class BackendConfig {
  static const mode = String.fromEnvironment('BACKEND', defaultValue: 'off');
  // Android emulator reaches the host machine at 10.0.2.2
  static const emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: '10.0.2.2');
  static const apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: mode == 'emulator' ? 'http://$emulatorHost:8080' : '');

  // the app's own named database (projects may be shared with other apps)
  static const database =
      String.fromEnvironment('FIRESTORE_DATABASE', defaultValue: mode == 'cloud' ? 'sleep-tracker' : '(default)');

  static bool get enabled => mode == 'emulator' || mode == 'cloud';

  static FirebaseOptions get options => mode == 'emulator'
      ? const FirebaseOptions(
          apiKey: 'demo-key',
          appId: '1:1234567890:android:0000000000000000',
          messagingSenderId: '1234567890',
          projectId: 'demo-sleep-tracker',
          storageBucket: 'demo-sleep-tracker.appspot.com',
        )
      : const FirebaseOptions(
          apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
          appId: String.fromEnvironment('FIREBASE_APP_ID'),
          messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
          projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
          storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
        );
}

class BackendException implements Exception {
  final String message;
  BackendException(this.message);
  @override
  String toString() => message;
}

/// Firebase Auth + Firestore sync + the Cloud Run API, behind one facade.
/// Every method is a no-op (or returns null) when the backend is off, so the
/// app keeps working fully offline.
class Backend {
  Backend._();
  static final Backend I = Backend._();

  bool get enabled => BackendConfig.enabled && _ready;
  bool _ready = false;
  String? lastError;

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: BackendConfig.database);
  User? get user => enabled ? _auth.currentUser : null;
  Stream<User?> get authChanges => enabled ? _auth.authStateChanges() : const Stream.empty();

  Future<void> init() async {
    if (!BackendConfig.enabled) return;
    try {
      await Firebase.initializeApp(options: BackendConfig.options);
      if (BackendConfig.mode == 'emulator') {
        await _auth.useAuthEmulator(BackendConfig.emulatorHost, 9099);
        _db.useFirestoreEmulator(BackendConfig.emulatorHost, 8085);
      }
      _ready = true;
    } catch (e) {
      lastError = 'Backend unavailable: $e';
    }
  }

  // ── auth ──────────────────────────────────────────────────────────────────

  Future<User> signIn(String email, String password) =>
      _authCall(() => _auth.signInWithEmailAndPassword(email: email, password: password));

  Future<User> signUp(String email, String password) =>
      _authCall(() => _auth.createUserWithEmailAndPassword(email: email, password: password));

  /// Sign in with Apple (iOS), through Firebase Auth's Apple provider.
  Future<User> signInWithApple() =>
      _authCall(() => _auth.signInWithProvider(AppleAuthProvider()..addScope('email')));

  Future<User> _authCall(Future<UserCredential> Function() f) async {
    try {
      final c = await f();
      return c.user!;
    } on FirebaseAuthException catch (e) {
      throw BackendException(switch (e.code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' => 'Wrong email or password.',
        'email-already-in-use' => 'An account with this email already exists. Log in instead.',
        'weak-password' => 'Choose a password with at least 6 characters.',
        'invalid-email' => 'That email address doesn\'t look right.',
        _ => e.message ?? e.code,
      });
    }
  }

  Future<void> sendPasswordReset() async {
    final e = user?.email;
    if (e != null) await _auth.sendPasswordResetEmail(email: e);
  }

  Future<void> signOut() async {
    if (enabled) await _auth.signOut();
  }

  // ── Firestore sync ────────────────────────────────────────────────────────

  DocumentReference<Map<String, dynamic>>? get _userDoc => user == null ? null : _db.doc('users/${user!.uid}');

  String nightId(Night n) => '${n.wentToBed.millisecondsSinceEpoch}';

  Future<void> saveProfile(Map<String, dynamic> profile) async {
    final d = _userDoc;
    if (d == null) return;
    await d.set({...profile, 'email': user!.email, 'updatedAt': DateTime.now().millisecondsSinceEpoch},
        SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> loadProfile() async => (await _userDoc?.get())?.data();

  Future<void> saveNight(Night n) async {
    final d = _userDoc;
    if (d == null) return;
    await d.collection('nights').doc(nightId(n)).set({...n.toJson(), 'wokeUp': n.wokeUp.millisecondsSinceEpoch});
  }

  Future<void> deleteNight(Night n) async {
    await _userDoc?.collection('nights').doc(nightId(n)).delete();
  }

  Future<List<Night>> loadNights() async {
    final d = _userDoc;
    if (d == null) return [];
    final q = await d.collection('nights').orderBy('wokeUp').get();
    return [for (final doc in q.docs) Night.fromJson(doc.data())];
  }

  // ── Cloud Run API ─────────────────────────────────────────────────────────

  Future<dynamic> _api(String method, String path, {Map<String, dynamic>? body, bool auth = true}) async {
    if (!enabled || BackendConfig.apiBaseUrl.isEmpty) return null;
    final headers = <String, String>{'content-type': 'application/json'};
    if (auth) {
      final token = await user?.getIdToken();
      if (token == null) return null;
      headers['authorization'] = 'Bearer $token';
    }
    final uri = Uri.parse('${BackendConfig.apiBaseUrl}$path');
    final r = await (method == 'POST'
            ? http.post(uri, headers: headers, body: jsonEncode(body ?? {}))
            : http.get(uri, headers: headers))
        .timeout(const Duration(seconds: 20));
    final j = r.body.isEmpty ? null : jsonDecode(r.body);
    if (r.statusCode >= 400) {
      throw BackendException((j is Map ? j['error'] : null)?.toString() ?? 'HTTP ${r.statusCode}');
    }
    return j;
  }

  Future<Map<String, dynamic>?> config() async =>
      (await _api('GET', '/v1/config', auth: false)) as Map<String, dynamic>?;

  Future<Map<String, dynamic>?> sleepAidCatalog() async =>
      (await _api('GET', '/v1/sleep-aid/catalog')) as Map<String, dynamic>?;

  Future<Map<String, dynamic>?> weeklyReport(DateTime weekStartLocal) async {
    final d = weekStartLocal;
    final iso = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final tz = DateTime.now().timeZoneOffset.inMinutes;
    return (await _api('GET', '/v1/insights/weekly?weekStart=$iso&tzOffsetMin=$tz')) as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>?> weather(double lat, double lon) async =>
      (await _api('GET', '/v1/weather?lat=$lat&lon=$lon')) as Map<String, dynamic>?;

  /// Asks the API to re-read this account's subscription from RevenueCat
  /// right after a purchase or restore (the webhook may lag behind).
  Future<Map<String, dynamic>?> syncPurchases() async =>
      (await _api('POST', '/v1/billing/sync')) as Map<String, dynamic>?;

  Future<Map<String, dynamic>?> recommendations({int? goalMinutes}) async {
    final tz = DateTime.now().timeZoneOffset.inMinutes;
    return (await _api(
            'GET', '/v1/insights/recommendations?tzOffsetMin=$tz${goalMinutes == null ? '' : '&goalMin=$goalMinutes'}'))
        as Map<String, dynamic>?;
  }

  Future<void> saveConsent({required bool storage, required bool sounds, required bool product}) async =>
      _api('POST', '/v1/consent', body: {'storage': storage, 'sounds': sounds, 'product': product});

  Future<void> saveProperties(Map<String, String> properties) async =>
      _api('POST', '/v1/user/properties', body: properties);

  Future<void> registerDevice(String token, String platform) async =>
      _api('POST', '/v1/devices/register', body: {'token': token, 'platform': platform});

  /// Server-recorded trial (once per account); the reminder is local.
  Future<Map<String, dynamic>?> startTrial(String productId) async =>
      (await _api('POST', '/v1/trial/start', body: {'productId': productId})) as Map<String, dynamic>?;

  /// The paywall for [placement] (see backend /v1/paywall); null offline.
  Future<Map<String, dynamic>?> paywall(String placement, String installId, {String? variant}) async =>
      (await _api(
              'GET',
              '/v1/paywall?placement=$placement&installId=$installId${variant == null ? '' : '&variant=$variant'}',
              auth: user != null)) as Map<String, dynamic>?;

  /// Two gift codes to share after buying from the gift-card paywall.
  Future<List<String>> issueGiftCards() async =>
      [for (final c in ((await _api('POST', '/v1/giftcards/issue')) as Map?)?['codes'] ?? const []) c as String];

  Future<Map<String, dynamic>?> redeemGiftCard(String code) async =>
      (await _api('POST', '/v1/giftcards/redeem', body: {'code': code})) as Map<String, dynamic>?;

  Future<void> eraseData() async => _api('POST', '/v1/account/erase-data');

  Future<void> deleteAccount() async {
    await _api('POST', '/v1/account/delete');
    await signOut();
  }
}
