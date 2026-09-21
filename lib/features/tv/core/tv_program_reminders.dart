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
import '../../channels/data/recently_watched_repository.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../subscription/data/now_playing.dart';
import '../data/display_settings.dart';
import 'tv_dimens.dart';
import 'tv_event_priority.dart';
import 'tv_logo.dart';
import 'tv_tokens.dart';

/// Un rappel prêt à afficher.
class TvReminder {
  const TvReminder({
    required this.channel,
    required this.program,
    required this.minutesLeft,
    this.type = TypeEvenement.ordinaire,
    this.etape = EtapeRappel.tot,
  });
  final Channel channel;
  final EpgProgram program;
  final int minutesLeft;

  /// Match / journal / ordinaire — décide de l'icône et du ton du texte.
  final TypeEvenement type;

  /// Rappel tôt (30 / 10 min) ou DERNIER APPEL à 5 min (21/09/2026).
  final EtapeRappel etape;

  /// Clé de déduplication : une annonce par (chaîne, horaire, étape).
  String get cle => cleRappel(channel.id, program.startTime, etape);
}

/// La clé d'une annonce. L'ÉTAPE en fait partie : le rappel tôt et le
/// dernier appel de la même émission sont deux annonces distinctes,
/// chacune passe une fois.
String cleRappel(String channelId, int startTime, EtapeRappel etape) =>
    '$channelId@$startTime${etape == EtapeRappel.dernierAppel ? '#5' : ''}';

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

  /// DERNIERS APPELS ARMÉS À LA MINUTE PRÈS. Le balayage passe toutes
  /// les 5 minutes : à lui seul, il annoncerait « dans 5 min » n'importe
  /// où entre 5 et 0 minutes — parfois « dans 0 min », trop tard pour
  /// changer de chaîne. Alors dès qu'un match ou un journal est repéré
  /// (au rappel tôt), on arme une minuterie EXACTE pour l'instant
  /// « début − 5 min ». Une par émission, annulée avec stop(). Le
  /// balayage reste le filet : si la minuterie n'a pas tiré (app en
  /// pause au mauvais moment), il rattrape le dernier appel au passage.
  final Map<String, Timer> _derniersAppels = <String, Timer>{};

  // =========================================================
  //  « QUE CE SOIT PAS GÊNANT » (21/09/2026) — les quatre règles
  // =========================================================
  //  Ce que disent les guides (Material « Android notifications »,
  //  Android TV app quality, Fire TV multimedia requirements, guides UX
  //  des toasts) tient en une phrase : une annonce non demandée n'est
  //  tolérée que si elle est RARE, COURTE, PERTINENTE et sous CONTRÔLE
  //  du client. D'où :
  //
  //   1. PERTINENTE — jamais pour la chaîne qu'on regarde DÉJÀ. Annoncer
  //      « le match commence sur beIN » à quelqu'un qui est sur beIN,
  //      c'est le cas d'école de la bannière inutile. On compare au
  //      porte-état NowPlaying que le lecteur remplit.
  //   2. RARE — pas plus d'une bannière toutes les 3 minutes, hors
  //      dernier appel (lui, on ne le retient pas : à 5 minutes du
  //      match, c'est précisément l'information qu'on attend).
  //   3. COURTE — le dernier appel reste 8 secondes, pas 12 : il n'a
  //      rien à apprendre, il rappelle. (Les guides UX disent 2 à 6 s
  //      pour un toast ; à trois mètres d'une télé on lit plus lentement
  //      qu'au téléphone, d'où un peu plus.)
  //   4. SOUS CONTRÔLE — Réglages → Affichage → Rappels d'émissions :
  //      tous / matchs et journaux / aucun (DisplaySettings.rappels).
  // =========================================================

  /// Écart minimal entre deux bannières « tôt ».
  static const Duration kEcartMinimal = Duration(minutes: 3);

  /// Instant de la dernière bannière affichée (pour l'écart minimal).
  DateTime? _derniereBanniere;

  /// Règle 1 : la chaîne du rappel est-elle celle qu'on regarde ?
  static bool _dejaDessus(Channel ch) {
    final String enCours = NowPlaying.instance.current;
    return enCours.isNotEmpty && enCours == ch.cleanName.trim();
  }

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
    for (final Timer t in _derniersAppels.values) {
      t.cancel();
    }
    _derniersAppels.clear();
    _started = false;
  }

  /// Les chaînes qu'on surveille : les FAVORIES **et** celles que le
  /// client REGARDE vraiment.
  ///
  ///  POURQUOI CE CHANGEMENT (18/09/2026). On ne regardait que les
  ///  favoris. Or presque personne ne met France 24 en favori — on la
  ///  regarde, c'est tout. Un client qui suit l'info tous les soirs
  ///  n'était donc jamais prévenu du journal, et la fonctionnalité
  ///  paraissait morte alors qu'elle tournait.
  ///
  ///  Les favoris passent DEVANT (c'est un choix explicite du client,
  ///  pas une déduction), puis l'historique récent. Sans doublon, et la
  ///  même borne de coût qu'avant.
  List<String> _chainesSurveillees() {
    final List<String> ordre = <String>[];
    final Set<String> vus = <String>{};
    for (final String id in FavoritesRepository.instance.current) {
      if (vus.add(id)) ordre.add(id);
    }
    for (final String id in RecentlyWatchedRepository.instance.current) {
      if (vus.add(id)) ordre.add(id);
    }
    return ordre;
  }

  Future<void> _scan() async {
    if (current != null) return; // une bannière à la fois
    // Règle 4 : le client a coupé les rappels → on ne lit même pas l'EPG.
    final ModeRappels mode = DisplaySettings.instance.rappels;
    if (mode == ModeRappels.aucun) return;
    final List<String> surveillees = _chainesSurveillees();
    if (surveillees.isEmpty) return;
    final Map<String, Channel> byId = <String, Channel>{
      for (final Channel c in PlaylistRepository.instance.currentChannels)
        c.id: c,
    };
    final DateTime now = DateTime.now();
    int checked = 0;
    // On ne s'arrête plus au PREMIER trouvé : on retient le MEILLEUR.
    // Sinon, une émission quelconque sur le favori n°1 passait devant la
    // finale qui commence sur le favori n°4 — et le client ratait le
    // match en ayant été prévenu d'autre chose.
    TvReminder? meilleur;
    int meilleurRang = -1;
    for (final String id in surveillees) {
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
      // LA FENÊTRE DÉPEND DE CE QUI COMMENCE. Un match se prévient 30 min
      // avant (demande du propriétaire), le reste 10 min comme avant —
      // puis DERNIER APPEL à 5 min pour match et journal (21/09/2026).
      // Le jugement (quelle étape, maintenant ?) vit dans
      // tv_event_priority.dart, testé sans box ni EPG.
      final TypeEvenement type = classerEvenement(next.title);
      // Règle 4 : en mode « importants », l'ordinaire ne passe pas.
      if (mode == ModeRappels.importants && type == TypeEvenement.ordinaire) {
        continue;
      }
      // Règle 1 : on est déjà sur cette chaîne → rien à annoncer.
      if (_dejaDessus(ch)) continue;
      final EtapeRappel? etape = etapeAAnnoncer(
        type,
        untilStart,
        totDejaAnnonce: _announced
            .contains(cleRappel(ch.id, next.startTime, EtapeRappel.tot)),
        dernierAppelDejaAnnonce: _announced.contains(
            cleRappel(ch.id, next.startTime, EtapeRappel.dernierAppel)),
      );
      if (etape == null) continue;
      final int rang = rangRappel(type, etape);
      if (rang <= meilleurRang) continue;
      meilleurRang = rang;
      meilleur = TvReminder(
        channel: ch,
        program: next,
        minutesLeft: _minutesRestantes(untilStart),
        type: type,
        etape: etape,
      );
      // Le dernier appel d'un match : rien ne passe devant, on s'arrête.
      if (rang == rangMaximal) break;
    }
    if (meilleur != null) {
      // Règle 2 : un rappel TÔT attend son tour si une bannière vient de
      // passer ; on ne le marque pas annoncé, le balayage suivant le
      // reprendra. Le dernier appel, lui, passe toujours.
      final DateTime? derniere = _derniereBanniere;
      final bool tropTot = meilleur.etape == EtapeRappel.tot &&
          derniere != null &&
          now.difference(derniere) < kEcartMinimal;
      // On ne marque QU'À L'AFFICHAGE : une émission écartée parce
      // qu'un match passait devant doit pouvoir être annoncée au
      // balayage suivant, si le match est déjà passé.
      if (!tropTot) _annoncer(meilleur);
    }
    // Ménage : la liste des annonces ne grandit pas à l'infini.
    if (_announced.length > 200) _announced.clear();
  }

  /// Minutes restantes ARRONDIES AU-DESSUS : à 4 min 40 s on dit
  /// « dans 5 min », pas « dans 4 » — et jamais « dans 0 min » à 30 s du
  /// début, ce qui se lisait comme une erreur.
  static int _minutesRestantes(Duration d) =>
      (d.inSeconds / 60).ceil().clamp(0, 30);

  /// Affiche un rappel, le marque annoncé, et — pour un rappel tôt d'un
  /// match ou d'un journal — arme le dernier appel à la minute près.
  void _annoncer(TvReminder r) {
    _announced.add(r.cle);
    _show(r);
    if (r.etape == EtapeRappel.tot && aDroitAuDernierAppel(r.type)) {
      _armerDernierAppel(r);
    }
  }

  /// Minuterie exacte pour « début − 5 min ». Idempotente par émission.
  void _armerDernierAppel(TvReminder r) {
    final String cle = cleRappel(
        r.channel.id, r.program.startTime, EtapeRappel.dernierAppel);
    if (_derniersAppels.containsKey(cle) || _announced.contains(cle)) return;
    final Duration delai =
        r.program.startDateTime.difference(DateTime.now()) - fenetreDernierAppel;
    // Déjà à moins de 5 min : le balayage courant l'a annoncé ou va le
    // faire ; pas de minuterie dans le passé.
    if (delai <= Duration.zero) return;
    _derniersAppels[cle] = Timer(delai, () {
      _derniersAppels.remove(cle);
      if (!_started || _announced.contains(cle)) return;
      // Règle 4 : les rappels ont pu être coupés entre-temps.
      if (DisplaySettings.instance.rappels == ModeRappels.aucun) return;
      // Règle 1 : le client est déjà sur la chaîne → on marque annoncé
      // (le balayage ne le redira pas) et on se tait.
      if (_dejaDessus(r.channel)) {
        _announced.add(cle);
        return;
      }
      // Le dernier appel REMPLACE une bannière en cours : à 5 minutes du
      // match, c'est lui le plus urgent — on ne le fait pas attendre
      // douze secondes derrière un rappel ordinaire.
      _annoncer(TvReminder(
        channel: r.channel,
        program: r.program,
        minutesLeft: fenetreDernierAppel.inMinutes,
        type: r.type,
        etape: EtapeRappel.dernierAppel,
      ));
    });
  }

  void _show(TvReminder r) {
    current = r;
    _derniereBanniere = DateTime.now();
    notifyListeners();
    _hideTimer?.cancel();
    // Règle 3 : le dernier appel est plus court (8 s) que le rappel tôt
    // (12 s) — il rappelle, il n'apprend rien.
    final Duration duree = r.etape == EtapeRappel.dernierAppel
        ? const Duration(seconds: 8)
        : const Duration(seconds: 12);
    _hideTimer = Timer(duree, () {
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
                      //  L'ICÔNE DIT DE QUOI IL S'AGIT, AVANT LA LECTURE.
                      //  Sur une TV, à trois mètres, le pictogramme arrive
                      //  à l'œil une demi-seconde avant le texte : un
                      //  ballon se reconnaît sans lire.
                      Icon(
                        switch (r.type) {
                          TypeEvenement.match => Icons.sports_soccer_rounded,
                          TypeEvenement.journal => Icons.podcasts_rounded,
                          TypeEvenement.ordinaire => Icons.star_rounded,
                        },
                        color: TvTokens.gold,
                        size: 20,
                      ),
                      // DERNIER APPEL : une cloche en plus du pictogramme.
                      // Le client a déjà vu ce match annoncé une demi-heure
                      // avant ; la cloche dit « cette fois c'est tout de
                      // suite », sans rien lire.
                      if (r.etape == EtapeRappel.dernierAppel) ...<Widget>[
                        const SizedBox(width: 4),
                        const Icon(Icons.notifications_active_rounded,
                            color: TvTokens.emberBright, size: 18),
                      ],
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
                            //  LE MOT « MATCH » EN TOUTES LETTRES.
                            //  « Dans 30 min » ne dit pas pourquoi on
                            //  dérange. « Le match commence dans 30 min »
                            //  se comprend depuis le canapé, sans lever
                            //  les yeux du téléphone.
                            Text(
                                switch ((r.type, r.minutesLeft <= 0)) {
                                  (TypeEvenement.match, true) =>
                                    'Le match commence · ${r.channel.cleanName}',
                                  (TypeEvenement.match, false) =>
                                    'Le match commence dans ${r.minutesLeft} min · ${r.channel.cleanName}',
                                  (TypeEvenement.journal, true) =>
                                    'Le journal commence · ${r.channel.cleanName}',
                                  (TypeEvenement.journal, false) =>
                                    'Le journal commence dans ${r.minutesLeft} min · ${r.channel.cleanName}',
                                  (TypeEvenement.ordinaire, true) =>
                                    'Commence maintenant · ${r.channel.cleanName}',
                                  (TypeEvenement.ordinaire, false) =>
                                    'Dans ${r.minutesLeft} min · ${r.channel.cleanName}',
                                },
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
