import 'dart:convert';
import 'dart:math' as math;
import '../services/secure_store.dart';

class AuthSession {
  final String token;
  final String deviceId;
  final String deviceKey;
  final String? phoneNumber;
  final String? password;
  final String? displayName;
  final String? email;
  final String? cookie;
  final bool isPro;
  final bool isLoggedIn;
  final DateTime? savedAt;

  AuthSession({
    required this.token,
    String? deviceId,
    required this.deviceKey,
    this.phoneNumber,
    this.password,
    this.displayName,
    this.email,
    this.cookie,
    this.isPro = false,
    this.isLoggedIn = true,
    DateTime? savedAt,
  })  : deviceId = (deviceId == null || deviceId.trim().isEmpty) ? generateUuid() : deviceId,
        savedAt = savedAt ?? DateTime.now();

  static String generateUuid() {
    final rnd = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant RFC4122
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static bool isDummyToken(String token) {
    return token.contains('VQjKASL57tJCcHIIwY8BPk5du-ltBjvdHg7TgA6i7GeWw4pWJN8ecmEkvIe1XgCYXYJE1w') ||
        token.contains('example') ||
        token.contains('dummy');
  }

  static Map<String, dynamic>? decodeJwtPayload(String token) {
    if (token.trim().isEmpty) return null;
    try {
      final clean = token.startsWith('Bearer ') ? token.substring(7) : token;
      final parts = clean.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decodedBytes = base64.decode(payload);
      final jsonStr = utf8.decode(decodedBytes);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static bool isJwtExpired(String token) {
    if (token.trim().isEmpty || isDummyToken(token)) return true;
    try {
      final map = decodeJwtPayload(token);
      if (map == null || !map.containsKey('exp')) return false;
      final expSeconds = map['exp'] as num;
      final expDate = DateTime.fromMillisecondsSinceEpoch(expSeconds.toInt() * 1000);
      return !DateTime.now().isBefore(expDate);
    } catch (_) {
      return false;
    }
  }

  bool get isValid => isLoggedIn && token.trim().isNotEmpty && !isDummyToken(token) && !isJwtExpired(token);

  Map<String, dynamic> toJson() => {
        'token': token,
        'deviceId': deviceId,
        'deviceKey': deviceKey,
        'phoneNumber': phoneNumber,
        'displayName': displayName,
        'email': email,
        'cookie': cookie,
        'isPro': isPro,
        'isLoggedIn': isLoggedIn,
        'savedAt': savedAt?.toIso8601String(),
      };

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        token: json['token'] ?? '',
        deviceId: json['deviceId'] ?? '',
        deviceKey: json['deviceKey'] ?? '',
        phoneNumber: json['phoneNumber'],
        password: json['password'],
        displayName: json['displayName'],
        email: json['email'],
        cookie: json['cookie'],
        isPro: json['isPro'] == true,
        isLoggedIn: json['isLoggedIn'] != false,
        savedAt: json['savedAt'] != null
            ? DateTime.tryParse(json['savedAt'])
            : null,
      );

  static const String _prefKey = 'br_auth_session';
  static const String _prefPhoneKey = 'br_saved_phone';
  static const String _prefPasswordKey = 'br_saved_password';

  static Future<void> save(AuthSession session) async {
    await SecureStore.write(_prefKey, jsonEncode(session.toJson()));
    if (session.phoneNumber != null && session.phoneNumber!.isNotEmpty) {
      await SecureStore.write(_prefPhoneKey, session.phoneNumber!);
    }
  }

  static Future<void> saveUserCredentials(String phone, [String? password]) async {
    if (phone.isNotEmpty) {
      await SecureStore.write(_prefPhoneKey, phone.trim());
    }
    if (password != null && password.isNotEmpty) {
      await SecureStore.write(_prefPasswordKey, password);
    }
  }

  static Future<Map<String, String>> getSavedUserCredentials() async {
    return {
      'phone': await SecureStore.read(_prefPhoneKey) ?? '',
      'password': await SecureStore.read(_prefPasswordKey) ?? '',
    };
  }

  static Future<void> clearSavedUserCredentials() async {
    await SecureStore.delete(_prefPhoneKey);
    await SecureStore.delete(_prefPasswordKey);
  }

  static Future<AuthSession?> load() async {
    final raw = await SecureStore.read(_prefKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final session = AuthSession.fromJson(map);
      if (isDummyToken(session.token)) {
        await clear();
        return null;
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    await SecureStore.delete(_prefKey);
  }
}
