import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/session.dart';

class SessionService {
  static const String _sessionKey = 'user_session';
  static Session? _currentSession;
  static const String _pairingKey = 'is_paired';
  static const String _boatIdKey = 'paired_boat_id';
  static bool _isPaired = false;
  static String? _pairedBoatId;

  static Future<void> init() async {
    await _loadSession();
    await _loadPairingState();
    await _loadStatusInterval();
    await _loadGpsUpdateInterval();
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

    print('SessionService: Loading session from prefs: $sessionJson');

    if (sessionJson != null) {
      try {
        final Map<String, dynamic> sessionMap = jsonDecode(sessionJson);
        _currentSession = Session.fromJson(sessionMap);
        print(
          'SessionService: Session loaded successfully. Token: ${_currentSession?.token}',
        );
      } catch (e) {
        print('SessionService: Error loading session: $e');
        print('SessionService: Clearing invalid session data.');
        await clearSession();
      }
    } else {
      print('SessionService: No session found in prefs.');
    }
  }

  // Fixing the session loading logic is out of scope unless it blocks me.
  // I'll add the pairing logic.

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

  static Future<void> saveSession(Session session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(session.toJson()));
    _currentSession = session;
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    _currentSession = null;
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
