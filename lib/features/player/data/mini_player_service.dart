// =========================================================
//  mini_player_service.dart — Lecture réduite (mini-lecteur)
// =========================================================
//  Porté de TV King : « La lecture vous suit » — bouton « Réduire »
//  façon YouTube : la vidéo continue dans une petite fenêtre
//  flottante pendant que l'utilisateur navigue dans l'app, avec
//  tous les contrôles dedans (écouteurs = audio seulement,
//  lecture/pause, chaîne suivante, agrandir, fermer).
//
//  CONCEPTION : le service possède SA PROPRE instance mpv, créée
//  au moment de la réduction (après fermeture du plein écran) et
//  détruite à la fermeture du mini. On ne « déplace » PAS le
//  Player du VideoPlayerScreen : son cycle de vie est soudé au
//  relais local, à l'enregistrement, aux watchdogs et au PiP —
//  l'extraire serait fragile. Ici : une instance simple, lecture
//  DIRECTE de l'URL (pas de relais, pas d'enregistrement).
//
//  Comptes « 1 connexion » : start() attend un court délai avant
//  d'ouvrir, le temps que l'instance du plein écran (disposée par
//  la fermeture de l'écran) libère sa connexion serveur. Et
//  playChannel() ferme le mini avant toute nouvelle lecture.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../channels/domain/channel.dart';
import 'player_settings.dart';

class MiniPlayerService extends ChangeNotifier {
  MiniPlayerService._();
  static final MiniPlayerService instance = MiniPlayerService._();

  Player? _player;
  VideoController? _controller;
  Channel? _channel;
  List<Channel>? _zapPlaylist;
  String? _overrideUrl;
  String? _overrideTitle;
  bool _audioOnly = false;
  // Génération : invalide les starts dépassés par un close/start plus
  // récent (l'ouverture attend ~600 ms, l'utilisateur peut agir entre-temps).
  int _generation = 0;

  bool get isActive => _player != null;
  Player? get player => _player;
  VideoController? get controller => _controller;
  Channel? get channel => _channel;
  List<Channel>? get zapPlaylist => _zapPlaylist;
  String? get overrideUrl => _overrideUrl;
  String? get overrideTitle => _overrideTitle;
  bool get audioOnly => _audioOnly;

  /// Titre affiché dans la fenêtre réduite.
  String get title => _overrideTitle ?? _channel?.cleanName ?? '';

  /// Chaîne suivante de la playlist de zap (null : bouton masqué).
  Channel? get nextChannel {
    final List<Channel>? list = _zapPlaylist;
    final Channel? cur = _channel;
    if (list == null || cur == null || list.length < 2) return null;
    final int i = list.indexWhere((Channel c) => c.id == cur.id);
    if (i < 0) return null;
    return list[(i + 1) % list.length];
  }

  /// Démarre la lecture réduite. [resumePosition] : reprise VOD (ignorée
  /// pour du live, où la durée est nulle). Appelé APRÈS la fermeture du
  /// plein écran — d'où le délai avant open() (libération de connexion).
  Future<void> start({
    required Channel channel,
    List<Channel>? zapPlaylist,
    String? overrideUrl,
    String? overrideTitle,
    Duration? resumePosition,
    bool audioOnly = false,
  }) async {
    await close();
    final int gen = ++_generation;

    _channel = channel;
    _zapPlaylist = zapPlaylist;
    _overrideUrl = overrideUrl;
    _overrideTitle = overrideTitle;
    _audioOnly = audioOnly;

    // Laisse l'instance du plein écran fermer sa connexion serveur
    // (dispose asynchrone côté mpv) avant d'en ouvrir une nouvelle.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (gen != _generation) return; // dépassé par un close()/start()

    final Player player = Player(
      configuration: PlayerConfiguration(
        bufferSize: PlayerSettings.instance.bufferBytes,
        logLevel: MPVLogLevel.warn,
      ),
    );
    _player = player;
    _controller = VideoController(player);
    notifyListeners();

    // Lecture DIRECTE de l'URL (même chemin que le VOD du plein écran).
    // Fail-open : une erreur d'ouverture laisse la fenêtre affichée,
    // l'utilisateur peut agrandir (relance le vrai lecteur) ou fermer.
    try {
      await player.open(
        Media(
          overrideUrl ?? channel.streamUrl,
          httpHeaders: <String, String>{
            'User-Agent': PlayerSettings.instance.userAgent,
          },
        ),
      );
      if (gen == _generation &&
          resumePosition != null &&
          resumePosition > Duration.zero) {
        await player.seek(resumePosition);
      }
    } catch (e) {
      debugPrint('[MiniPlayer] open a échoué : $e');
    }
  }

  /// Bascule écouteurs : le son continue, l'image est remplacée par un
  /// panneau « Audio seulement » (le flux vidéo n'est PAS coupé — même
  /// approche que le mode Écouteurs du plein écran, simplicité d'abord).
  void toggleAudioOnly() {
    if (!isActive) return;
    _audioOnly = !_audioOnly;
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    final Player? p = _player;
    if (p == null) return;
    try {
      await p.playOrPause();
    } catch (_) {
      // best-effort : jamais d'exception vers l'UI pour un play/pause.
    }
  }

  /// Zappe sur la chaîne suivante de la playlist, dans la fenêtre réduite.
  Future<void> playNext() async {
    final Channel? next = nextChannel;
    if (next == null) return;
    final List<Channel>? list = _zapPlaylist;
    final bool keepAudioOnly = _audioOnly;
    await start(
      channel: next,
      zapPlaylist: list,
      audioOnly: keepAudioOnly,
    );
  }

  /// Position courante — transmise au plein écran lors de l'agrandissement.
  Duration get position => _player?.state.position ?? Duration.zero;

  /// Ferme la lecture réduite et libère l'instance mpv. Idempotent.
  Future<void> close() async {
    _generation++;
    final Player? p = _player;
    if (p == null) return;
    _player = null;
    _controller = null;
    _channel = null;
    _zapPlaylist = null;
    _overrideUrl = null;
    _overrideTitle = null;
    _audioOnly = false;
    notifyListeners();
    try {
      await p.dispose();
    } catch (e) {
      debugPrint('[MiniPlayer] dispose a échoué : $e');
    }
  }
}
