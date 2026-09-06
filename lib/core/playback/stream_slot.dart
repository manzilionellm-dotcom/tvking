// =========================================================
//  stream_slot.dart — UN SEUL flux réseau à la fois, garanti
// =========================================================
//  LE BUG (terrain, photo client du 17/08) : « je quitte un film, je lance
//  une chaîne → un autre flux est déjà en cours ». Beaucoup de comptes
//  Xtream n'autorisent QU'UNE connexion simultanée ; il suffit qu'un
//  consommateur réseau traîne une milliseconde de trop pour que le panel
//  refuse le suivant.
//
//  Chaque coupable, pris isolément, avait pourtant l'air correct :
//    • le lecteur plein écran libère bien son ExoPlayer en quittant… mais
//      RIEN ne garantissait que la socket soit fermée AVANT que le suivant
//      n'ouvre la sienne ;
//    • l'aperçu d'accueil se mettait en PAUSE entre deux chaînes — or un
//      lecteur en pause GARDE sa connexion ouverte ;
//    • la file de téléchargements Cinéma repartait à la milliseconde où on
//      quittait le lecteur (`setPlaybackHold(false)`), donc pile au moment
//      où l'utilisateur allait lancer une chaîne.
//
//  Corriger chacun dans son coin ne tient pas : à chaque nouvel écran, le
//  bug revient. On centralise donc la règle, une fois pour toutes.
//
//  PRINCIPE — un créneau, un détenteur. Tout ce qui ouvre une connexion au
//  panel (lecteur plein écran, aperçu, multi-vue, téléchargements) doit
//  RÉCLAMER le créneau. Réclamer DÉMONTE d'abord le détenteur courant, et
//  ATTEND que son démontage soit terminé — c'est cette attente qui manquait.
//
//  Le multi-vue est l'exception assumée : ses tuiles partagent un `group`,
//  donc elles coexistent (l'exploitant SAIT qu'il lui faut un compte
//  multi-connexions pour ça) tout en démontant l'aperçu et les
//  téléchargements comme n'importe quel autre détenteur.
//
//  Tout est fail-open : un démontage qui échoue ou traîne ne doit JAMAIS
//  empêcher la lecture suivante (mieux vaut un refus serveur qu'un écran
//  noir définitif). D'où le plafond [_kTeardownBudget].
// =========================================================
import 'dart:async';

import 'package:flutter/foundation.dart';

/// Démontage d'un détenteur : doit fermer ses connexions réseau et ne
/// revenir qu'une fois le travail réellement fait.
typedef StreamTeardown = Future<void> Function();

class _Holder {
  _Holder(this.owner, this.group, this.teardown, this.label,
      {this.isHandOff = false});

  /// Détenteur de TRANSITION (fermeture d'un lecteur quitté) : droit à un
  /// budget de démontage plus long, cf. _kHandOffBudget.
  final bool isHandOff;
  final Object owner;
  final String group;
  final StreamTeardown teardown;
  final String label;
}

class StreamSlot {
  StreamSlot._();
  static final StreamSlot instance = StreamSlot._();

  /// Groupe par défaut : « je suis seul à jouer ». Deux détenteurs de ce
  /// groupe ne peuvent jamais coexister.
  static const String groupSolo = 'solo';

  /// Multi-vue : ses tuiles se tolèrent entre elles.
  static const String groupMultiview = 'multiview';

  /// File de téléchargements : détenteur de plus BASSE priorité, démonté
  /// par n'importe quelle lecture.
  static const String groupDownloads = 'downloads';

  /// Plafond d'attente d'un démontage. Au-delà, on ouvre quand même : un
  /// démontage bloqué ne doit pas condamner l'écran.
  static const Duration _kTeardownBudget = Duration(milliseconds: 1200);

  /// 2.2 (05/09/2026) — BUDGET D'UN DÉTENTEUR DE TRANSITION ([handOff]).
  ///
  ///  Le démontage ordinaire (un aperçu, une file) tient en 1,2 s. Mais la
  ///  fermeture d'un LECTEUR quitté enchaîne : stop natif (posté sur le
  ///  thread lecteur), fermeture de la session relais, puis
  ///  `awaitNetworkIdle` qui attend jusqu'à 3 s la fermeture RÉELLE de la
  ///  socket. Plafonner cette attente à 1,2 s revenait à la court-
  ///  circuiter systématiquement : le créneau rendait la main AVANT que
  ///  la socket soit fermée, et le prochain écran ouvrait sa connexion
  ///  par-dessus — « limite 1/1 » à chaque film → chaîne un peu lent.
  ///  4 s couvre l'attente native (3 s) plus la marge des deux `await`
  ///  qui la précèdent. Toujours fail-open au-delà.
  static const Duration _kHandOffBudget = Duration(milliseconds: 4000);

  /// Durée de vie MAXIMALE d'un détenteur de transition ([handOff]) dont la
  /// fermeture ne répond pas : au-delà, il se retire tout seul.
  static const Duration _kHandOffLinger = Duration(seconds: 10);

  final Map<Object, _Holder> _holders = <Object, _Holder>{};

  /// Sérialise les réclamations : deux écrans qui réclament en même temps
  /// (pop du lecteur + aperçu qui se ré-arme) doivent passer l'un APRÈS
  /// l'autre, sinon le second démonte ce que le premier vient d'ouvrir.
  Future<void> _chain = Future<void>.value();

  /// Déclare un consommateur de connexion. À appeler à l'initialisation de
  /// l'écran ; [teardown] doit fermer la connexion pour de bon (stop, pas
  /// pause) et n'être tenu de rien d'autre.
  void register(
    Object owner, {
    required StreamTeardown teardown,
    String group = groupSolo,
    String label = '',
  }) {
    _holders[owner] = _Holder(owner, group, teardown, label);
  }

  /// Retire un consommateur (dispose de l'écran). Ne démonte rien : l'écran
  /// qui part a déjà fait son ménage.
  void unregister(Object owner) => _holders.remove(owner);

  /// SORTIE D'ÉCRAN (dispose) : remplace [owner] par un détenteur de
  /// TRANSITION lié à [shutdown], sa fermeture réseau réellement en cours.
  ///
  /// POURQUOI : `dispose()` est synchrone — l'écran ne peut pas y attendre
  /// la fermeture de ses sockets (stop natif posté sur le thread lecteur,
  /// session relais annulée en asynchrone). Avec un simple [unregister], le
  /// PROCHAIN [claim] ne trouvait plus personne à démonter et ouvrait sa
  /// connexion PENDANT que celle de l'écran quitté se fermait encore — sur
  /// une ligne à 1 connexion, le panel refuse la seconde (458). Ici, le
  /// prochain [claim] attend [shutdown] (toujours plafonné par
  /// [_kTeardownBudget], fail-open), et le détenteur de transition se
  /// retire tout seul dès la fermeture terminée.
  /// Dernière SORTIE d'écran de lecture ([handOff]) : borne la fenêtre où
  /// le panel du fournisseur peut encore compter la session FANTÔME de la
  /// lecture quittée (il la libère à l'expiration de SA session, souvent
  /// 15-90 s après la fermeture réelle de la socket). Sert à la pré-attente
  /// mesurée du lecteur (transition cinéma ↔ chaîne « trop fluide », 21/08).
  DateTime? _lastHandOffAt;
  DateTime? get lastHandOffAt => _lastHandOffAt;

  void handOff(Object owner, Future<void> shutdown, {String label = ''}) {
    _lastHandOffAt = DateTime.now();
    _holders.remove(owner);
    // Les erreurs de fermeture sont avalées : un stop raté ne doit jamais
    // casser la chaîne des réclamations (même règle que _claimNow). Et une
    // fermeture qui ne répond JAMAIS (thread lecteur natif bloqué) ne doit
    // pas laisser un détenteur de transition éternel — qui pénaliserait du
    // budget [_kTeardownBudget] CHAQUE ouverture suivante : au-delà de
    // [_kHandOffLinger], il se retire de lui-même.
    final Future<void> safe =
        shutdown.timeout(_kHandOffLinger).catchError((Object _) {});
    final Object token = Object();
    _holders[token] = _Holder(
      token,
      groupSolo,
      () => safe,
      label.isEmpty ? 'fermeture en cours' : label,
      isHandOff: true,
    );
    unawaited(safe.whenComplete(() => _holders.remove(token)));
  }

  /// Réclamations actuellement en vol : tant que ce compteur n'est pas à
  /// zéro, la chaîne [_chain] n'est pas au repos et un nouvel arrivant doit
  /// se sérialiser derrière elle.
  int _pendingClaims = 0;

  /// RÉCLAME le créneau pour [owner] : démonte tous les détenteurs d'un
  /// AUTRE groupe et attend qu'ils aient fini. À appeler juste AVANT
  /// d'ouvrir une URL.
  ///
  /// N'échoue jamais : les démontages sont indépendants et plafonnés.
  Future<void> claim(Object owner) {
    _pendingClaims++;
    final Future<void> next = _chain.then((_) => _claimNow(owner));
    // La chaîne ne doit pas mourir sur une erreur d'un maillon.
    _chain = next.catchError((Object _) {});
    return next.whenComplete(() => _pendingClaims--);
  }

  /// Variante SANS COÛT quand il n'y a rien à faire : renvoie `null` si
  /// AUCUN autre détenteur n'est à démonter et qu'aucune réclamation n'est
  /// en vol — réclamer serait alors un pur no-op ASYNCHRONE, et ces sauts
  /// de microtâches ont un coût réel : ils ont cassé le contrat « l'aperçu
  /// démarre dans la même frame » (tests widget rouges du 19/08). Sinon,
  /// une vraie réclamation, à attendre.
  Future<void>? claimIfNeeded(Object owner) {
    if (_pendingClaims == 0 && !_hasOthers(owner)) return null;
    return claim(owner);
  }

  /// Y a-t-il un détenteur d'un AUTRE groupe que [owner] à démonter ?
  bool _hasOthers(Object owner) {
    final _Holder? me = _holders[owner];
    final String myGroup = me?.group ?? groupSolo;
    return _holders.values.any((_Holder h) =>
        h.owner != owner &&
        // Même groupe non-solo = cohabitation voulue (multi-vue).
        !(h.group == myGroup && myGroup != groupSolo));
  }

  Future<void> _claimNow(Object owner) async {
    final _Holder? me = _holders[owner];
    final String myGroup = me?.group ?? groupSolo;
    final List<_Holder> others = _holders.values
        .where((_Holder h) =>
            h.owner != owner &&
            // Même groupe non-solo = cohabitation voulue (multi-vue).
            !(h.group == myGroup && myGroup != groupSolo))
        .toList(growable: false);
    if (others.isEmpty) return;

    await Future.wait(
      others.map((_Holder h) async {
        try {
          await h.teardown().timeout(
              h.isHandOff ? _kHandOffBudget : _kTeardownBudget);
          if (kDebugMode) debugPrint('[Slot] démonté: ${h.label}');
        } catch (e) {
          // Fail-open ASSUMÉ : on préfère un refus du panel (message clair,
          // « Réessayer ») à un écran qui ne s'ouvre jamais.
          if (kDebugMode) debugPrint('[Slot] démontage KO (${h.label}): $e');
        }
      }),
    );
  }

  /// Visible pour les tests : qui est déclaré en ce moment.
  @visibleForTesting
  Iterable<String> get holdersForTest =>
      _holders.values.map((_Holder h) => '${h.group}:${h.label}');

  @visibleForTesting
  void resetForTest() {
    _holders.clear();
    _chain = Future<void>.value();
    _pendingClaims = 0;
    _lastHandOffAt = null;
  }
}
