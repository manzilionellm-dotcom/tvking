// Identité du canal temps réel : même coffre et mêmes noms que le client
// canonique déployé au commit 8b10203 (DeviceSession). Une mise à jour doit
// retrouver la clé déjà liée côté serveur, jamais la dériver de la MAC ni
// convertir le secret legacy. Aucun accès HTTP ni enrôlement dans ce fichier.
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/device/data/device_identity.dart';
import '../../features/subscription/data/device_realtime_channel.dart';

class DeviceSession {
  DeviceSession._()
      : _read = ((key) => _storage.read(key: key)),
        _write = ((key, value) => _storage.write(key: key, value: value)),
        _deviceId = DeviceIdentity.instance.androidId;

  /// Tests isolés : remplace uniquement les entrées/sorties du coffre et du
  /// pont Android. La production utilise exclusivement [instance].
  @visibleForTesting
  DeviceSession.forTesting({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
    required Future<String> Function() deviceId,
  })  : _read = read,
        _write = write,
        _deviceId = deviceId;

  static final DeviceSession instance = DeviceSession._();

  // Options par défaut comme dans 8b10203 : pas de nouveau nom de fichier,
  // de migration EncryptedSharedPreferences ou de remise à zéro sur erreur.
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _installationKey = 'atlas.installation-key';
  static const String _deviceToken = 'atlas.device-token';
  static const Map<String, String> _noCacheHeaders = <String, String>{
    'Accept': 'application/json',
    'Cache-Control': 'no-cache, no-store',
    'Pragma': 'no-cache',
  };
  static final RegExp _validKey = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _invalidId = RegExp(r'[\x00-\x20\x7f]');

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;
  final Future<String> Function() _deviceId;
  Future<String?>? _keyInFlight;

  /// Identifiants stables pour statut → ticket → WebSocket. En cas de coffre
  /// indisponible, clé invalide ou ANDROID_ID absent, aucun secret de repli
  /// n'est inventé. Les clients HTTP legacy restent utilisables séparément.
  Future<DeviceRealtimeCredentials?> credentials() async {
    try {
      final String id = await _deviceId();
      if (id.isEmpty || id.length > 256 || _invalidId.hasMatch(id)) return null;
      final String? key = await _installationKeyValue();
      if (key == null) return null;
      return DeviceRealtimeCredentials(deviceKey: key, deviceId: id);
    } catch (_) {
      // Ne jamais journaliser l'exception du coffre : certains ponts natifs
      // peuvent y inclure la valeur demandée. Une prochaine passe réessaiera.
      return null;
    }
  }

  Future<String?> _installationKeyValue() {
    final Future<String?>? pending = _keyInFlight;
    if (pending != null) return pending;
    final Future<String?> job = _readOrCreateKey();
    _keyInFlight = job;
    return job.whenComplete(() {
      if (identical(_keyInFlight, job)) _keyInFlight = null;
    });
  }

  Future<String?> _readOrCreateKey() async {
    final String? existing = await _read(_installationKey);
    // Même une valeur vide/invalide est une entrée préexistante : on refuse
    // le canal sans la remplacer. Seule une absence réelle autorise la création.
    if (existing != null) return _validKey.hasMatch(existing) ? existing : null;
    final Random random = Random.secure();
    final String value = List<String>.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await _write(_installationKey, value);
    // Une clé uniquement en RAM ne doit jamais être liée au serveur. On relit
    // le coffre après écriture avant d'autoriser son utilisation sur le réseau.
    final String? persisted = await _read(_installationKey);
    return persisted != null && _validKey.hasMatch(persisted)
        ? persisted
        : null;
  }

  /// Contrat canonique utile aux lectures de statut. Aucun jeton, secret
  /// historique ou identifiant d'installation n'apparaît dans les logs.
  Future<Map<String, String>> headers() async {
    final DeviceRealtimeCredentials? identity = await credentials();
    return <String, String>{
      ..._noCacheHeaders,
      if (identity != null) ...<String, String>{
        'X-Device-Key': identity.deviceKey,
        'X-Device-Id': identity.deviceId,
      },
    };
  }

  /// Le statut authentifié peut renouveler le jeton d'une heure. Conserve le
  /// nom de stockage canonique ; un échec n'écrit jamais en SharedPreferences.
  Future<void> accept(Map<String, dynamic> body) async {
    final Object? value = body['device_token'];
    if (value is! String || value.isEmpty) return;
    try {
      await _write(_deviceToken, value);
    } catch (_) {
      // Aucun stockage non chiffré ni affichage du jeton en cas d'échec.
    }
  }

  Future<String?> token() async {
    try {
      return await _read(_deviceToken);
    } catch (_) {
      return null;
    }
  }
}
