import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/session.dart';
import '../models/user.dart';
import 'package:boatnode/services/log_service.dart';

class SessionService {
  static const String _sessionKey = 'user_session';
  static Session? _currentSession;
  static const String _pairingKey = 'is_paired';
  static const String _boatIdKey = 'paired_boat_id';
  static bool _isPaired = false;
  static String? _pairedBoatId;
  static const String _journeyKey = 'is_journey_active';
  static bool _journeyActive = false;

  static Future<void> init() async {
    await _loadSession();
    await _loadUser();
    await _loadPairingState();
    await _loadStatusInterval();
    await _loadGpsUpdateInterval();
    await _loadJourneyState();
  }

  static const String _statusIntervalKey = 'status_interval';
  static int _statusInterval = 5;

  static const String _gpsUpdateIntervalKey = 'gps_update_interval';
  static int _gpsUpdateInterval = 30;

  static Future<void> _loadStatusInterval() async {
    final prefs = await SharedPreferences.getInstance();
    _statusInterval = prefs.getInt(_statusIntervalKey) ?? 5;
  }

  static Future<void> _loadGpsUpdateInterval() async {
    final prefs = await SharedPreferences.getInstance();
    _gpsUpdateInterval = prefs.getInt(_gpsUpdateIntervalKey) ?? 30;
  }

  static Future<void> saveStatusInterval(int interval) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_statusIntervalKey, interval);
    _statusInterval = interval;
  }

  static Future<void> saveGpsUpdateInterval(int interval) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_gpsUpdateIntervalKey, interval);
    _gpsUpdateInterval = interval;
  }

  static int get statusInterval => _statusInterval;
  static int get gpsUpdateInterval => _gpsUpdateInterval;

  static Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionJson = prefs.getString(_sessionKey);

    LogService.d('SessionService: Loading session from prefs: $sessionJson');

    if (sessionJson != null) {
      try {
        final Map<String, dynamic> sessionMap = jsonDecode(sessionJson);
        _currentSession = Session.fromJson(sessionMap);
        LogService.i(
          'SessionService: Session loaded successfully. Token: ${_currentSession?.token}',
        );
      } catch (e) {
        LogService.e('SessionService: Error loading session', e);
        LogService.w('SessionService: Clearing invalid session data.');
        await clearSession();
      }
    } else {
      LogService.i('SessionService: No session found in prefs.');
    }
  }

  // --- User Persistence ---
  static const String _userKey = 'user_profile';
  static User? _currentUser;

  static Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    if (userJson != null) {
      try {
        _currentUser = User.fromJson(jsonDecode(userJson));
        LogService.i(
          'SessionService: User loaded: ${_currentUser?.displayName}',
        );
      } catch (e) {
        LogService.e('SessionService: Error loading user', e);
      }
    }
  }

  static Future<void> saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
    await prefs.setString(
      'user_id_cache',
      user.id,
    ); // Valid for BackgroundService
    _currentUser = user;
  }

  static Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove('user_id_cache');
    _currentUser = null;
  }

  static User? get currentUser => _currentUser;

  // --- Pairing ---

  static Future<void> _loadPairingState() async {
    final prefs = await SharedPreferences.getInstance();
    _isPaired = prefs.getBool(_pairingKey) ?? false;
    _pairedBoatId = prefs.getString(_boatIdKey);
  }

  static Future<void> savePairingState(bool isPaired, String? boatId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pairingKey, isPaired);
    if (boatId != null) {
      await prefs.setString(_boatIdKey, boatId);
    } else {
      await prefs.remove(_boatIdKey);
    }
    _isPaired = isPaired;
    _pairedBoatId = boatId;
  }

  static Future<void> clearPairingState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pairingKey);
    await prefs.remove(_boatIdKey);
    _isPaired = false;
    _pairedBoatId = null;
  }

  static bool get isPaired => _isPaired;
  static String? get pairedBoatId => _pairedBoatId;

  // --- Journey Mode ---

  static Future<void> _loadJourneyState() async {
    final prefs = await SharedPreferences.getInstance();
    _journeyActive = prefs.getBool(_journeyKey) ?? false;
  }

  static Future<void> saveJourneyState(bool isActive) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_journeyKey, isActive);
    _journeyActive = isActive;
  }

  static bool get isJourneyActive => _journeyActive;

  static Future<void> saveSession(Session session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(session.toJson()));
    _currentSession = session;
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    _currentSession = null;
    await clearUser(); // Also clear user data
  }

  static Session? get currentSession {
    if (_currentSession != null && _currentSession!.isExpired) {
      clearSession();
      return null;
    }
    return _currentSession;
  }

  static bool get isLoggedIn => currentSession != null;
}
