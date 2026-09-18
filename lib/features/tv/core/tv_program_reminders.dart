// =========================================================
//  tv_program_reminders.dart — « Ça commence bientôt » (rappels EPG favoris)
// =========================================================
//  LE manque n°1 documenté chez les lecteurs IPTV concurrents (aucun rappel
//  d'émission chez IBO Player Pro, rien de proactif chez TiviMate) : ici,
//  quand une émission DÉMARRE BIENTÔT sur une chaîne FAVORITE, une bannière
//  discrète l'annonce — où qu'on soit dans l'app.
//
//  DESIGN « TECHNOLOGIE CALME » (Calm Tech, 2024) : l'information passe par
//  la périphérie — une bannière en haut, 12 secondes, qui ne vole JAMAIS le
//  focus D-pad (IgnorePointer), ne bloque rien, ne culpabilise pas. Pas de
//  son. Un rappel par émission (dédupliqué), favoris uniquement (c'est
//  l'utilisateur qui a choisi ces chaînes — pas un algorithme pousse-clic).
//
//  COÛT : un balayage toutes les 5 min de l'EPG LOCAL (SQLite) des 12
//  premiers favoris — zéro réseau, négligeable même sur petite box.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../channels/domain/channel.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/domain/epg_program.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import 'tv_dimens.dart';
import 'tv_logo.dart';
import 'tv_tokens.dart';

/// Un rappel prêt à afficher.
class TvReminder {
  const TvReminder({
    required this.channel,
    required this.program,
    required this.minutesLeft,
  });
  final Channel channel;
  final EpgProgram program;
  final int minutesLeft;
}

class TvProgramReminders extends ChangeNotifier {
  TvProgramReminders._();
  static final TvProgramReminders instance = TvProgramReminders._();

  /// Rappel actuellement affiché (null = bannière repliée).
  TvReminder? current;

  /// Fenêtre d'annonce : émissions qui commencent dans 0 à 10 minutes.
  static const Duration kWindow = Duration(minutes: 10);

  /// Un rappel par (chaîne, horaire) — jamais deux fois la même annonce.
  final Set<String> _announced = <String>{};

  Timer? _scanTimer;
  Timer? _hideTimer;

  /// Le PREMIER balayage, 20 s après l'ouverture. Il était créé sans être
  /// gardé : impossible de l'annuler, il partait donc même si le balayage
  /// venait d'être arrêté. Un lecteur SQLite + favoris qui démarre 20 s
  /// après qu'on a tout éteint, c'est exactement le genre de réveil
  /// inexplicable qu'on traque.
  Timer? _firstScanTimer;
  bool _started = false;

  /// Démarre le balayage périodique (idempotent — appelé par la bannière).
  void start() {
    if (_started) return;
    _started = true;
    _scanTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(_scan());
    });
    // Premier balayage rapide après l'ouverture (le temps que tout charge).
    _firstScanTimer =
        Timer(const Duration(seconds: 20), () => unawaited(_scan()));
  }

  /// Arrête le balayage. AJOUTÉ le 28/08 — il n'existait pas.
  ///
  /// Sans cette méthode, ouvrir la bannière de rappels UNE seule fois
  /// lançait un balayage EPG (lecture SQLite + parcours des favoris)
  /// toutes les 5 minutes pour TOUT le reste de la session, sans aucun
  /// moyen de l'éteindre — y compris application en arrière-plan, box
  /// censée être au repos. C'est une des « petites fuites bizarres »
  /// signalées : rien ne plante, mais la box travaille pour rien.
  ///
  /// `start()` reste idempotent après un `stop()` : on peut relancer.
  void stop() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _firstScanTimer?.cancel();
    _firstScanTimer = null;
    _hideTimer?.cancel();
    _hideTimer = null;
    _started = false;
  }

  Future<void> _scan() async {
    if (current != null) return; // une bannière à la fois
    final Set<String> favIds = FavoritesRepository.instance.current;
    if (favIds.isEmpty) return;
    final Map<String, Channel> byId = <String, Channel>{
      for (final Channel c in PlaylistRepository.instance.currentChannels)
        c.id: c,
    };
    final DateTime now = DateTime.now();
    int checked = 0;
    for (final String id in favIds) {
      if (checked >= 12) break; // borne de coût (petites box)
      final Channel? ch = byId[id];
      if (ch == null) continue;
      checked++;
      EpgProgram? next;
      try {
        next = await EpgRepository.instance.nextProgram(ch.id);
      } catch (_) {
        continue; // pas d'EPG pour cette chaîne → suivante
      }
      if (next == null) continue;
      final Duration untilStart = next.startDateTime.difference(now);
      if (untilStart.isNegative || untilStart > kWindow) continue;
      final String key = '${ch.id}@${next.startTime}';
      if (!_announced.add(key)) continue; // déjà annoncé
      _show(TvReminder(
        channel: ch,
        program: next,
        minutesLeft: untilStart.inMinutes.clamp(0, 10),
      ));
      return; // une annonce, puis on laisse l'écran tranquille
    }
    // Ménage : la liste des annonces ne grandit pas à l'infini.
    if (_announced.length > 200) _announced.clear();
  }

  void _show(TvReminder r) {
    current = r;
    notifyListeners();
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 12), () {
      current = null;
      notifyListeners();
    });
  }
}

/// Bannière « Ça commence bientôt » — à poser en haut de la racine TV
/// (même patron que AdminMessageBanner). IgnorePointer : zéro impact D-pad.
class TvReminderBanner extends StatefulWidget {
  const TvReminderBanner({super.key});

  @override
  State<TvReminderBanner> createState() => _TvReminderBannerState();
}

class _TvReminderBannerState extends State<TvReminderBanner> {
  @override
  void initState() {
    super.initState();
    TvProgramReminders.instance.addListener(_onChange);
    TvProgramReminders.instance.start();
  }

  @override
  void dispose() {
    TvProgramReminders.instance.removeListener(_onChange);
    //  ⚠ MANQUAIT (corrigé le 28/08). On retirait bien l'écouteur, mais
    //  on n'arrêtait PAS le balayage lancé par `start()` juste au-dessus.
    //  Résultat : ouvrir cette bannière une seule fois déclenchait un
    //  balayage EPG (lecture SQLite + parcours des favoris) toutes les
    //  5 minutes pour tout le reste de la session — plus personne pour
    //  l'écouter, et aucun moyen de l'éteindre.
    //
    //  Une paire `start()`/`stop()` doit être aussi symétrique qu'une
    //  paire `addListener()`/`removeListener()`. Elle ne l'était pas.
    TvProgramReminders.instance.stop();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final TvReminder? r = TvProgramReminders.instance.current;
    return IgnorePointer(
      child: AnimatedSlide(
        offset: r == null ? const Offset(0, -1.4) : Offset.zero,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: r == null ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          child: r == null
              ? const SizedBox.shrink()
              : Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: TvTokens.card.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(color: TvTokens.gold),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: TvTokens.gold.withValues(alpha: 0.25),
                        blurRadius: 22,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.star_rounded,
                          color: TvTokens.gold, size: 20),
                      const SizedBox(width: 10),
                      TvChannelLogo(
                          logoUrl: r.channel.logoUrl,
                          label: r.channel.name,
                          size: 34,
                          radius: 8),
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(r.program.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TvTokens.ui(TvDimens.body,
                                    weight: FontWeight.w800,
                                    color: TvTokens.text)),
                            Text(
                                r.minutesLeft <= 0
                                    ? 'Commence maintenant · ${r.channel.cleanName}'
                                    : 'Dans ${r.minutesLeft} min · ${r.channel.cleanName}',
                                style: TvTokens.ui(TvDimens.caption,
                                    color: TvTokens.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
