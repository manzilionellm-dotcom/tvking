// =========================================================
//  fake_playback_proof.dart — preuve de rendu, PAS une entrée produit
// =========================================================
//  Écran minimal : une SurfaceView native (le même plugin que Zuno) et
//  un flux PUBLIC de test (Big Buck Bunny, H.264, pas une playlist IPTV).
//  Sert à photographier l'image sur émulateur. On ne l'embarque pas
//  dans les builds TV / mobile.
//
//    flutter build apk --debug --target=lib/fake_playback_proof.dart
// =========================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:native_video_player/native_video_player.dart';

/// Flux public Mux (Big Buck Bunny, H.264 dans un HLS). Le seau Google
/// « gtv-videos-bucket » répond 403 au User-Agent VLC du lecteur, donc
/// il ne peut pas servir de preuve. Remplaçable par
/// `--dart-define=PROOF_URL=https://...`.
const String _kPublicStream = String.fromEnvironment(
  'PROOF_URL',
  defaultValue: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final NativeVideoController controller = NativeVideoController(
    initialUrl: _kPublicStream,
    openAsVod: true,
  );
  controller.addListener(() {
    debugPrint(
      'PROOF first=${controller.firstFrame} playing=${controller.isPlaying} '
      'buffering=${controller.isBuffering} error=${controller.hasError} '
      'engine=${controller.imageEngineWire} contrast=${controller.contrastReason} '
      'decoder=${controller.videoDecoderName}',
    );
  });
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: NativeVideoView(controller: controller),
      ),
    ),
  );
}
