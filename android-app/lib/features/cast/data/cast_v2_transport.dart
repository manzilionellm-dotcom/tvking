import 'dart:async';

import '../domain/cast_device.dart';
import 'cast_transport.dart';
import 'cast_v2_client.dart';
import 'cast_v2_codec.dart';
import 'dlna_profiles.dart';
import 'local_cast_server.dart';

/// Émetteur Chromecast PC. Android garde son transport SDK natif existant.
class CastV2Transport implements CastTransport {
  CastV2Transport(this.device);
  final CastDevice device;
  CastV2Client? _client;
  String? _relayUrl;
  bool _stopped = false;
  bool _playbackStarted = false;
  String? originalUpstreamUrl;
  String? contentType;
  void Function(String)? onPlayerState;
  void Function()? onDisconnected;

  void _clearRelay() {
    final String? relay = _relayUrl;
    _relayUrl = null;
    if (relay != null) LocalCastServer.instance.clearRelay(relay);
  }

  @override
  Future<void> playStream(
      {required String streamUrl,
      String title = 'ZUNO',
      String? imageUrl}) async {
    if (_stopped) throw StateError('Cast cancelled');
    final String lower = Uri.parse(streamUrl).path.toLowerCase();
    String mime = castV2ContentType(streamUrl, contentType);
    String url = originalUpstreamUrl ?? streamUrl;
    try {
      // Le récepteur standard ne lit pas le TS live brut : réutiliser le
      // segmenteur HLS/serveur HTTP Dart existant, sans proxy cloud.
      if (mime.toLowerCase().contains('mp2t') || lower.endsWith('.ts')) {
        final String? relay = await LocalCastServer.instance.registerRelay(
            upstreamUrl: url,
            profile: DlnaProfiles.select(url: url, finalMime: mime),
            receiverHost: device.host,
            wrapInHls: true);
        if (relay == null) {
          throw StateError('Cast relay unavailable on this LAN');
        }
        _relayUrl = relay;
        url = relay;
        mime = 'application/x-mpegURL';
      }
      if (_stopped) throw StateError('Cast cancelled');
      final CastV2Client client = CastV2Client(onPlayerState: (String state) {
        if (state == 'PLAYING') _playbackStarted = true;
        if (state == 'IDLE' && _playbackStarted) _clearRelay();
        onPlayerState?.call(state);
      }, onDisconnected: () {
        _clearRelay();
        onDisconnected?.call();
      });
      _client = client;
      await client.open(device.host, device.port > 0 ? device.port : 8009);
      await client.load(
          url: url,
          contentType: mime,
          title: title,
          imageUrl: imageUrl,
          live: !lower.endsWith('.mp4') &&
              !lower.endsWith('.mkv') &&
              !lower.contains('/movie/') &&
              !lower.contains('/series/'));
    } on Object {
      _client?.close();
      _clearRelay();
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    final CastV2Client? client = _client;
    if (client == null) throw StateError('Cast disconnected');
    await client.command('PAUSE');
  }

  @override
  Future<void> resume() async {
    final CastV2Client? client = _client;
    if (client == null) throw StateError('Cast disconnected');
    await client.command('PLAY');
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    final CastV2Client? client = _client;
    try {
      if (client != null) {
        await client.command('STOP').timeout(const Duration(seconds: 3));
      }
    } on Object {
      /* Closing a lost/connecting receiver remains safe. */
    } finally {
      client?.close();
      _clearRelay();
      _client = null;
    }
  }
}
