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
  _Holder(this.owner, this.group, this.teardown, this.label);
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

  /// RÉCLAME le créneau pour [owner] : démonte tous les détenteurs d'un
  /// AUTRE groupe et attend qu'ils aient fini. À appeler juste AVANT
  /// d'ouvrir une URL.
  ///
  /// N'échoue jamais : les démontages sont indépendants et plafonnés.
  Future<void> claim(Object owner) {
    final Future<void> next = _chain.then((_) => _claimNow(owner));
    // La chaîne ne doit pas mourir sur une erreur d'un maillon.
    _chain = next.catchError((Object _) {});
    return next;
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
          await h.teardown().timeout(_kTeardownBudget);
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
  }
}
