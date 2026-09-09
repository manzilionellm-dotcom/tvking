// =========================================================
//  foreground_sync.dart — se remettre à jour AU RÉVEIL
// =========================================================
//  POURQUOI CE FICHIER EXISTE (09/09/2026).
//
//  Le même jour, on a fait descendre les ordres du panel (« retirer cette
//  liste ») en 60 secondes au lieu de 5 minutes. Ça suppose qu'un
//  minuteur tourne. Or sur une box, cette supposition est fausse une
//  bonne partie de la journée :
//
//    UNE BOX NE SE FERME JAMAIS, ELLE S'ENDORT. Elle passe la nuit et les
//    journées en veille. Android suspend alors les minuteurs de l'app —
//    ce n'est pas un bug, c'est ce qui économise la batterie et le CPU.
//    Au réveil, le minuteur repart, mais il faut attendre son prochain
//    tour. Le client rallume sa télé et voit, pendant ce délai, une liste
//    que le revendeur a supprimée la veille.
//
//  ÉTAT AVANT CE FICHIER, mesuré :
//    - la box     : AUCUN observateur de cycle de vie. Rien au réveil.
//    - le mobile  : un observateur existait, mais il ne vérifiait que les
//                   mises à jour de l'app — jamais les sources.
//
//  Le moment du réveil est justement celui où la remise à jour compte le
//  plus : c'est l'instant précis où quelqu'un regarde l'écran.
//
//  UNE SEULE IMPLÉMENTATION, TROIS APPELANTS (box, mobile, PC) — même
//  règle que `core/i18n/locale_resolver.dart` ou `cloudflare/
//  app_versions.js`. Trois copies auraient fini par dériver, et c'est
//  celle qui synchronise le moins bien qui aurait laissé passer le bug.
// =========================================================

import 'package:flutter/widgets.dart';

import '../../features/playlists/data/remote_source_repository.dart';

class ForegroundSync with WidgetsBindingObserver {
  ForegroundSync._();
  static final ForegroundSync instance = ForegroundSync._();

  bool _started = false;
  DateTime? _derniere;

  /// GARDE-FOU ANTI-RAFALE. Passer d'une app à l'autre, ou ouvrir puis
  /// fermer un menu système, produit plusieurs `resumed` d'affilée. Sans
  /// ce seuil, chaque aller-retour déclencherait un appel réseau — et sur
  /// un parc entier, ça fait beaucoup de requêtes pour rien.
  ///
  /// 20 s : assez court pour qu'un vrai réveil (télé rallumée après des
  /// heures) passe toujours, assez long pour absorber les rafales.
  static const Duration _seuil = Duration(seconds: 20);

  /// À appeler UNE FOIS au démarrage de chaque plateforme.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On ne synchronise QUE quand l'app est réellement à l'écran. En
    // arrière-plan, l'ordre du panel peut attendre : personne ne le
    // regarde, et une requête de plus ne ferait qu'user la box.
    if (state != AppLifecycleState.resumed) return;
    syncNow();
  }

  /// Resynchronise, sauf si on vient déjà de le faire.
  ///
  /// Exposée séparément pour que l'appelant puisse la déclencher lui-même
  /// (retour depuis un écran de réglages, par exemple) sans dupliquer la
  /// règle anti-rafale.
  void syncNow() {
    final DateTime maintenant = DateTime.now();
    if (_derniere != null && maintenant.difference(_derniere!) < _seuil) {
      return;
    }
    _derniere = maintenant;
    // Best-effort et NON bloquant : `sync()` ne lève jamais (elle rend un
    // RemoteSyncResult), et le réveil de l'app ne doit rien attendre.
    // Cette synchro porte AUSSI les ordres du panel — c'est le même appel
    // réseau qui rapporte les sources et les suppressions à appliquer.
    RemoteSourceRepository.sync();
  }
}
