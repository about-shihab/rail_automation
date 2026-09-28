import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStore {
  static const _storage = FlutterSecureStorage();

  /// Migrates plaintext values once; never silently falls back to plaintext.
  static Future<String?> read(String key) async {
    final existing = await _storage.read(key: key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (existing != null) {
      await prefs.remove(key);
      return existing;
    }
    final legacy = prefs.getString(key);
    if (legacy != null) {
      await _storage.write(key: key, value: legacy);
      await prefs.remove(key);
    }
    return legacy;
  }

  static Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
    await (await SharedPreferences.getInstance()).remove(key);
  }

  static Future<void> delete(String key) async {
    await _storage.delete(key: key);
    await (await SharedPreferences.getInstance()).remove(key);
  }
}
