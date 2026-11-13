import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../features/device/data/device_identity.dart';
import '../network/api_config.dart';

/// Keystore/Keychain, not SharedPreferences. Fail closed for WS auth if the
/// secure store is unavailable; the existing HTTP fallback still works.
abstract final class DeviceSession {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static Future<String>? _key;
  static Future<Map<String, String>> headers() async {
    try {
      final String key = await (_key ??= _loadKey());
      return <String, String>{
        ...kNoCacheHeaders,
        'X-Device-Key': key,
        'X-Device-Id': await DeviceIdentity.instance.androidId(),
      };
    } catch (_) {
      return kNoCacheHeaders;
    }
  }

  static Future<String> _loadKey() async {
    final String? existing = await _storage.read(key: 'atlas.installation-key');
    if (existing != null) return existing;
    final Random random = Random.secure();
    final String value = List<String>.generate(
            32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    await _storage.write(key: 'atlas.installation-key', value: value);
    return value;
  }

  static Future<void> accept(Map<String, dynamic> body) async {
    final Object? token = body['device_token'];
    if (token is! String || token.isEmpty) return;
    try {
      await _storage.write(key: 'atlas.device-token', value: token);
    } catch (_) {/* no insecure fallback */}
  }

  static Future<String?> token() async {
    try {
      return await _storage.read(key: 'atlas.device-token');
    } catch (_) {
      return null;
    }
  }
}
