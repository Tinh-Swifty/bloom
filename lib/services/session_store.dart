import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// What this phone remembers between launches.
class SessionStore {
  SessionStore._(this._prefs);

  final SharedPreferences _prefs;

  static Future<SessionStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('deviceId') == null) {
      final rnd = Random.secure();
      final id = List.generate(
        8,
        (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await prefs.setString('deviceId', id);
    }
    return SessionStore._(prefs);
  }

  String get deviceId => _prefs.getString('deviceId')!;

  String? get code => _prefs.getString('code');
  String get name => _prefs.getString('name') ?? '';
  bool get sharing => _prefs.getBool('sharing') ?? true;

  Future<void> savePairing({required String code, required String name}) async {
    await _prefs.setString('code', code);
    await _prefs.setString('name', name);
    await _prefs.setBool('sharing', true);
  }

  Future<void> setSharing(bool value) => _prefs.setBool('sharing', value);

  Future<void> clearPairing() => _prefs.remove('code');
}
