// =========================================================
//  tv_welcome_screen.dart — Le PREMIER écran, celui qui décide
// =========================================================
//  Cahier des charges du client : « dès que le client ouvre
//  l'application après téléchargement, il doit immédiatement se sentir
//  en confiance, comme s'il utilisait Netflix ou Disney+ ».
//
//  Deux colonnes, parce qu'une box 720p ne laisse que ~640 px utiles en
//  hauteur : tout empiler obligerait à faire défiler dès la première
//  seconde, et un écran qu'on doit faire défiler pour comprendre n'est
//  pas rassurant.
//    • GAUCHE  — l'accueil et le geste : bienvenue, statut, puis les
//                deux méthodes de connexion (Xtream / M3U) ;
//    • DROITE  — les preuves : la fiche du client, le QR du support.
//  En haut une barre d'état, en bas un pied de page discret.
//
//  ─────────────────────────────────────────────────────────────
//  CE QUI EST AFFICHÉ EST VRAI. C'est la règle de cet écran.
//  Le cahier des charges demandait une pastille verte « Abonnement
//  actif » en dur. On ne l'a PAS fait : afficher « actif » à un client
//  gelé, expiré ou jamais activé, c'est le mensonge qui fait perdre la
//  confiance qu'on cherchait à installer. La pastille lit le VRAI
//  statut (SubscriptionState) et change de couleur et de mot.
//  De même, deux champs demandés n'existent nulle part dans le système
//  — nom du client, nombre d'appareils autorisés : ils ne sont pas
//  inventés, ils sont simplement absents (voir les notes plus bas).
//  ─────────────────────────────────────────────────────────────
//
//  SAISIE : les deux onglets ne re-fabriquent PAS de champs de texte.
//  L'app a déjà des écrans de saisie éprouvés (clavier télécommande,
//  correction des fautes de frappe, vérification du serveur) —
//  TvAddSourceScreen et TvAddM3uScreen. Les onglets montrent ce qui
//  sera demandé, et le bouton ouvre le vrai formulaire. Un champ
//  décoratif qui ne saisit rien serait pire que pas de champ du tout.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/flavor/flavor.dart';
import '../../device/data/device_identity.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/source_sync.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_add_m3u_screen.dart';
import 'tv_add_source_screen.dart';
import 'tv_components.dart';
import 'tv_legal_screen.dart';
import 'tv_settings_screen.dart';
import 'tv_shell.dart';

/// Palette de l'écran. AUCUNE couleur inventée ici : tout vient de
/// [TvTokens], le thème de l'app — demande explicite du client, « le
/// thème reste le même que l'app ». Cet alias ne sert qu'à écrire des
/// noms parlants (`accent`, `dim`) au lieu de l'héritage `gold…` qui
/// désigne aujourd'hui le turquoise de la maison.
///
/// Les trois seules couleurs propres à cet écran sont les états
/// d'abonnement (suspendu / bloqué) : le thème n'a pas d'orange ni de
/// rouge d'alerte, et le rouge « direct » signifie autre chose.
class _C {
  static const Color bg = TvTokens.bg;
  static const Color panel = TvTokens.card;
  static const Color panelHi = TvTokens.sel;
  static const Color line = TvTokens.line;
  static const Color text = TvTokens.text;
  static const Color dim = TvTokens.muted;
  static const Color faint = TvTokens.mutedDim;
  static const Color accent = TvTokens.gold; // turquoise de la maison
  static const Color accentSoft = TvTokens.goldBright;
  static const Color accentDeep = TvTokens.goldDeep;
  static const Color onAccent = TvTokens.onGold;
  static const Color ok = TvTokens.success;
  static const Color warn = Color(0xFFD69847);
  static const Color bad = Color(0xFFC9584E);
}

class TvWelcomeScreen extends StatefulWidget {
  const TvWelcomeScreen({super.key, this.onReload});

  /// Rappel « Recharger ma source » — fourni par l'accueil quand une
  /// source EST enregistrée mais ne contient aucune chaîne. `null` =
  /// aucune source, on propose alors d'en ajouter une.
  final Future<void> Function()? onReload;

  @override
  State<TvWelcomeScreen> createState() => _TvWelcomeScreenState();
}

class _TvWelcomeScreenState extends State<TvWelcomeScreen> {
  String _mac = '…';
  String _version = '';
  int _tab = 0; // 0 = Xtream, 1 = M3U
  bool _reloading = false;

  @override
  void initState() {
    super.initState();
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = DeviceIdentity.stripPrefix(m));
    }).catchError((Object _) {});
    PackageInfo.fromPlatform().then((PackageInfo p) {
      if (mounted) setState(() => _version = p.version);
    }).catchError((Object _) {});
    SubscriptionState.instance.addListener(_onSub);
  }

  @override
  void dispose() {
    SubscriptionState.instance.removeListener(_onSub);
    super.dispose();
  }

  void _onSub() {
    if (mounted) setState(() {});
  }

  // =========================================================
  //  Le statut RÉEL — jamais une pastille verte de décoration
  // =========================================================
  ({String label, Color color, String subtitle}) get _status {
    final SubscriptionState s = SubscriptionState.instance;
    switch (s.status) {
      case SubscriptionStatus.paid:
        final int? d = s.subscriptionDaysLeft;
        return (
          label: 'Abonnement actif',
          color: _C.ok,
          subtitle: d == null
              ? 'Ton abonnement est actif et prêt à être utilisé.'
              : 'Ton abonnement est actif — encore $d jour${d > 1 ? 's' : ''}.',
        );
      case SubscriptionStatus.trialActive:
        final int d = s.trialDaysRemaining;
        return (
          label: 'Essai en cours',
          color: _C.accent,
          subtitle: 'Ton essai est actif — encore $d jour${d > 1 ? 's' : ''}.',
        );
      case SubscriptionStatus.trialExpired:
        return (
          label: 'Essai terminé',
          color: _C.warn,
          subtitle: 'Ton essai est terminé. Contacte ton revendeur pour '
              'activer ton abonnement.',
        );
      case SubscriptionStatus.frozen:
        return (
          label: 'Compte suspendu',
          color: _C.warn,
          subtitle: 'Ton accès est suspendu. Contacte ton revendeur.',
        );
      case SubscriptionStatus.banned:
        return (
          label: 'Compte bloqué',
          color: _C.bad,
          subtitle: 'Ton accès est bloqué. Contacte ton revendeur.',
        );
      case SubscriptionStatus.unknown:
        return (
          label: 'En attente d\'activation',
          color: _C.faint,
          subtitle: 'Donne le code ci-contre à ton revendeur pour activer '
              'cet appareil.',
        );
    }
  }

  /// Nom lisible du forfait. `plan` vient du serveur — on ne traduit que
  /// ce qu'on connaît, le reste passe tel quel plutôt qu'inventé.
  String get _planLabel {
    final String p = SubscriptionState.instance.remote.plan;
    switch (p) {
      case 'lifetime':
        return 'À vie';
      case 'trial':
        return 'Essai';
      case 'paid':
      case 'custom':
        return 'Premium';
      case '1y':
        return 'Premium 12 mois';
      case 'expired':
        return 'Expiré';
      case 'frozen':
        return 'Suspendu';
      case 'banned':
        return 'Bloqué';
      case '':
      case 'unknown':
        return '—';
      default:
        return p;
    }
  }

  String get _expiryLabel {
    final SubscriptionState s = SubscriptionState.instance;
    if (s.isLifetime) return 'Jamais (à vie)';
    final DateTime? until = s.paidUntil;
    if (until != null) return _date(until);
    final int trial = s.remote.trialUntil;
    if (trial > 0) {
      return _date(DateTime.fromMillisecondsSinceEpoch(trial));
    }
    return '—';
  }

  static String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  // =========================================================
  //  Actions
  // =========================================================
  Future<void> _openXtream() => _open(const TvAddSourceScreen());
  Future<void> _openM3u() => _open(const TvAddM3uScreen());

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => TvShell(child: screen)),
    );
  }

  Future<void> _reload() async {
    if (_reloading) return;
    setState(() => _reloading = true);
    final Future<void> Function()? cb = widget.onReload;
    if (cb != null) {
      await cb();
    } else {
      await SourceSync.run();
    }
    if (mounted) setState(() => _reloading = false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        // Une box d'entrée de gamme peut sortir sous le 720p. Rien n'a
        // de taille fixe : tout se resserre plutôt que de déborder.
        final bool tight = c.maxHeight < 640;
        final double gap = tight ? 20 : 32;
        final double padH = tight ? 28 : 52;
        return Container(
          color: _C.bg,
          child: Padding(
            padding: EdgeInsets.fromLTRB(padH, tight ? 14 : 22, padH, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _header(tight),
                SizedBox(height: gap),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // GAUCHE : l'accueil et le geste.
                      Expanded(flex: 62, child: _left(tight)),
                      SizedBox(width: gap),
                      // DROITE : les preuves.
                      Expanded(flex: 38, child: _right(tight)),
                    ],
                  ),
                ),
                _footer(tight),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------
  //  1. Barre du haut : marque, connexion, sécurité
  // ---------------------------------------------------------
  Widget _header(bool tight) {
    final bool online = SubscriptionState.instance.remote.exists;
    return Row(
      children: <Widget>[
        // Le logo PORTE DÉJÀ le nom « 7 MOTION ». Écrire le nom à côté
        // l'affichait deux fois de suite — repéré sur le rendu avant
        // build. On laisse donc parler le logo, en plus grand.
        _BreathingLogo(width: tight ? 168 : 210),
        const Spacer(),
        // Le point vert ne ment pas non plus : il dit si le serveur nous
        // a répondu, pas « tout va bien » par principe.
        _Pill(
          dotColor: online ? _C.ok : _C.faint,
          label: online ? 'Connecté' : 'Hors ligne',
          tight: tight,
        ),
        SizedBox(width: tight ? 8 : 12),
        _Pill(
          icon: Icons.lock_rounded,
          label: 'Connexion sécurisée',
          tight: tight,
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  //  2 + 4. Bienvenue, statut, et les deux méthodes
  // ---------------------------------------------------------
  Widget _left(bool tight) {
    final ({String label, Color color, String subtitle}) st = _status;
    // Une source enregistrée mais vide : le bon geste n'est pas
    // « ajouter », c'est « recharger ». L'accueil nous le dit.
    final bool reloadMode = widget.onReload != null;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // NOM DU CLIENT : le cahier des charges demandait « Bienvenue
          // [Nom] ». L'app ne demande AUCUN compte et ne connaît donc
          // aucun nom — c'est un choix produit assumé (rien à saisir).
          // On ne fabrique pas un prénom : on accueille sans mentir.
          Text(
            'Bienvenue',
            style: TextStyle(
              color: _C.text,
              fontSize: tight ? 34 : 44,
              fontWeight: FontWeight.w800,
              height: 1.05,
              letterSpacing: -0.5,
            ),
          ),
          SizedBox(height: tight ? 8 : 12),
          Row(
            children: <Widget>[
              _StatusChip(label: st.label, color: st.color, tight: tight),
            ],
          ),
          SizedBox(height: tight ? 8 : 12),
          Text(
            st.subtitle,
            style: TextStyle(
              color: _C.dim,
              fontSize: tight ? 15 : 17,
              height: 1.45,
            ),
          ),
          SizedBox(height: tight ? 18 : 28),
          if (reloadMode) ...<Widget>[
            _bigButton(
              icon: Icons.sync_rounded,
              label: _reloading ? 'Rechargement…' : 'Recharger ma source',
              help: 'Ta source est enregistrée mais ne contient aucune '
                  'chaîne pour l\'instant.',
              autofocus: true,
              tight: tight,
              onSelect: () => unawaited(_reload()),
            ),
            SizedBox(height: tight ? 14 : 20),
          ],
          _tabs(tight),
          SizedBox(height: tight ? 12 : 18),
          _tabBody(tight, autofocus: !reloadMode),
        ],
      ),
    );
  }

  Widget _tabs(bool tight) {
    return Row(
      children: <Widget>[
        _TabButton(
          label: 'Xtream Codes',
          badge: 'Recommandé',
          selected: _tab == 0,
          tight: tight,
          onSelect: () => setState(() => _tab = 0),
        ),
        SizedBox(width: tight ? 8 : 12),
        _TabButton(
          label: 'Playlist M3U',
          selected: _tab == 1,
          tight: tight,
          onSelect: () => setState(() => _tab = 1),
        ),
      ],
    );
  }

  Widget _tabBody(bool tight, {required bool autofocus}) {
    final bool xtream = _tab == 0;
    return Container(
      padding: EdgeInsets.all(tight ? 16 : 22),
      decoration: BoxDecoration(
        color: _C.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _C.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Ce qui sera demandé — pas des champs décoratifs : la saisie
          // se fait dans l'écran dédié, avec le clavier télécommande.
          if (xtream) ...<Widget>[
            _FieldPreview(
                label: 'Adresse du serveur', hint: 'http://…', tight: tight),
            _FieldPreview(
                label: 'Nom d\'utilisateur',
                hint: 'fourni par ton revendeur',
                tight: tight),
            _FieldPreview(
                label: 'Mot de passe', hint: '••••••••', tight: tight),
          ] else ...<Widget>[
            _FieldPreview(
                label: 'Lien M3U', hint: 'http://….m3u', tight: tight),
            _FieldPreview(
                label: 'Lien EPG (facultatif)',
                hint: 'guide des programmes',
                tight: tight),
          ],
          SizedBox(height: tight ? 12 : 18),
          _bigButton(
            icon: xtream ? Icons.vpn_key_rounded : Icons.playlist_add_rounded,
            label: xtream ? 'Se connecter' : 'Charger la playlist',
            help: xtream
                ? 'Méthode recommandée — guide des programmes et cinéma '
                    'automatiques.'
                : 'Compatible avec tous les lecteurs.',
            autofocus: autofocus,
            tight: tight,
            onSelect: () => unawaited(xtream ? _openXtream() : _openM3u()),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  //  3 + 5. La fiche du client, et le support
  // ---------------------------------------------------------
  Widget _right(bool tight) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: EdgeInsets.all(tight ? 14 : 20),
            decoration: BoxDecoration(
              color: _C.panelHi,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _C.accent.withValues(alpha: 0.28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'TON APPAREIL',
                  style: TextStyle(
                    color: _C.faint,
                    fontSize: tight ? 11 : 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
                SizedBox(height: tight ? 8 : 12),
                // L'identifiant client ET l'adresse MAC sont la MÊME
                // chose dans ce système : il n'y a pas de compte, la MAC
                // EST le numéro de dossier que le revendeur cherche dans
                // son panel. On l'affiche donc une fois, en grand, au
                // lieu de dupliquer la même valeur sous deux étiquettes.
                Text(
                  _mac,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _C.accentSoft,
                    fontSize: tight ? 24 : 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.2,
                  ),
                ),
                Text(
                  'Adresse MAC · ton identifiant client',
                  style: TextStyle(color: _C.faint, fontSize: tight ? 11 : 12),
                ),
                SizedBox(height: tight ? 12 : 16),
                Divider(color: _C.line, height: 1),
                SizedBox(height: tight ? 10 : 14),
                _InfoRow(label: 'Forfait', value: _planLabel, tight: tight),
                _InfoRow(
                    label: 'Expiration', value: _expiryLabel, tight: tight),
                _InfoRow(
                  label: 'Sources',
                  value:
                      '${PlaylistRepository.instance.currentPlaylists.length}',
                  tight: tight,
                ),
              ],
            ),
          ),
          SizedBox(height: tight ? 12 : 18),
          // SUPPORT : le QR porte déjà le code de l'appareil dans le
          // message — le client n'a rien à recopier, il scanne et écrit.
          Container(
            padding: EdgeInsets.all(tight ? 12 : 18),
            decoration: BoxDecoration(
              color: _C.panel,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _C.line),
            ),
            child: Column(
              children: <Widget>[
                TvWhatsAppQr(mac: _mac, size: tight ? 118 : 150),
                SizedBox(height: tight ? 8 : 12),
                Text(
                  'Besoin d\'aide ? Notre équipe est disponible 24 h/24.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _C.dim,
                    fontSize: tight ? 12 : 13,
                    height: 1.35,
                  ),
                ),
                SizedBox(height: tight ? 6 : 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.shield_rounded,
                        size: tight ? 13 : 15, color: _C.ok),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Tes identifiants restent sur cet appareil.',
                        style: TextStyle(
                          color: _C.faint,
                          fontSize: tight ? 11 : 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  //  6. Pied de page
  // ---------------------------------------------------------
  Widget _footer(bool tight) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tight ? 8 : 14),
      child: Row(
        children: <Widget>[
          Text(
            _version.isEmpty ? '' : 'Version $_version',
            style: TextStyle(color: _C.faint, fontSize: tight ? 11 : 12),
          ),
          const Spacer(),
          _FooterLink(
            label: 'Conditions d\'utilisation',
            tight: tight,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TvLegalScreen()),
            ),
          ),
          Text(' · ', style: TextStyle(color: _C.faint, fontSize: 12)),
          _FooterLink(
            label: 'Réglages',
            tight: tight,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TvSettingsScreen()),
            ),
          ),
          const Spacer(),
          Text(
            'Powered by ${FlavorConfig.current.appName}',
            style: TextStyle(color: _C.faint, fontSize: tight ? 11 : 12),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  //  Le grand bouton d'action
  // ---------------------------------------------------------
  Widget _bigButton({
    required IconData icon,
    required String label,
    required String help,
    required bool autofocus,
    required bool tight,
    required VoidCallback onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TvFocusBuilder(
          autofocus: autofocus,
          scale: TvFocusScale.medium,
          onSelect: onSelect,
          builder: (BuildContext context, bool focused) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              curve: Curves.easeOut,
              padding: EdgeInsets.symmetric(
                horizontal: tight ? 22 : 30,
                vertical: tight ? 13 : 17,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: focused
                      ? const <Color>[_C.accentSoft, _C.accent]
                      : const <Color>[_C.accent, _C.accentDeep],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: focused
                    ? <BoxShadow>[
                        BoxShadow(
                          color: _C.accent.withValues(alpha: 0.45),
                          blurRadius: 26,
                          spreadRadius: 1,
                        ),
                      ]
                    : const <BoxShadow>[],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, color: _C.onAccent, size: tight ? 19 : 22),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: _C.onAccent,
                      fontSize: tight ? 16 : 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        SizedBox(height: tight ? 6 : 9),
        Text(
          help,
          style: TextStyle(
            color: _C.faint,
            fontSize: tight ? 12 : 13,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

// =========================================================
//  Petites pièces
// =========================================================

/// Le logo qui RESPIRE : il s'efface presque complètement, puis revient.
///
/// Demande du client : « il disparaît, il revient, genre il montre juste
/// qu'il est là ». La raison est juste — le logo est ORANGE, le thème est
/// turquoise. Un aplat orange posé en permanence en haut à gauche tire
/// l'œil et écrase la palette de tout l'écran. En le faisant respirer, la
/// marque se rappelle au souvenir sans jamais dominer.
///
/// Choix d'exécution :
///   • cycle LENT (5,2 s aller-retour) — un clignotement rapide serait
///     une alarme, pas une signature ;
///   • on descend à 0,10 et pas à 0 : le logo s'efface, il ne « saute »
///     pas hors de l'écran ;
///   • FadeTransition, donc AUCUN recalcul de mise en page à chaque
///     image — sur une box modeste, une opacité animée ne coûte rien,
///     là où une taille animée ferait tressauter toute la barre du haut.
class _BreathingLogo extends StatefulWidget {
  const _BreathingLogo({required this.width});

  final double width;

  @override
  State<_BreathingLogo> createState() => _BreathingLogoState();
}

class _BreathingLogoState extends State<_BreathingLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  late final Animation<double> _fade = Tween<double>(
    begin: 1.0,
    end: 0.10,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOutSine));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: TvLogo(width: widget.width),
    );
  }
}

/// Pastille d'en-tête : un point de couleur ou une icône, puis un mot.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.tight,
    this.dotColor,
    this.icon,
  });

  final String label;
  final bool tight;
  final Color? dotColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tight ? 10 : 14,
        vertical: tight ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: _C.panel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _C.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (dotColor != null)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                      color: dotColor!.withValues(alpha: 0.7), blurRadius: 8),
                ],
              ),
            )
          else
            Icon(icon, size: tight ? 13 : 15, color: _C.dim),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: _C.dim,
              fontSize: tight ? 12 : 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastille de statut d'abonnement — la couleur suit la vérité.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    required this.tight,
  });

  final String label;
  final Color color;
  final bool tight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tight ? 12 : 16,
        vertical: tight ? 6 : 9,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: tight ? 13 : 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Onglet de méthode de connexion.
class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.tight,
    required this.onSelect,
    this.badge,
  });

  final String label;
  final String? badge;
  final bool selected;
  final bool tight;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = selected || focused ? _C.text : _C.dim;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(
            horizontal: tight ? 14 : 20,
            vertical: tight ? 9 : 12,
          ),
          decoration: BoxDecoration(
            color: selected ? _C.panelHi : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focused
                  ? _C.accent
                  : (selected ? _C.line : Colors.transparent),
              width: focused ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: tight ? 14 : 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (badge != null) ...<Widget>[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _C.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      color: _C.accentSoft,
                      fontSize: tight ? 9 : 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Ce qui sera demandé dans l'écran de saisie. Volontairement NON
/// focusable : ce n'est pas un champ, c'est une annonce. Un faux champ
/// qu'on sélectionne sans pouvoir y écrire serait pire que rien.
class _FieldPreview extends StatelessWidget {
  const _FieldPreview({
    required this.label,
    required this.hint,
    required this.tight,
  });

  final String label;
  final String hint;
  final bool tight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: tight ? 8 : 11),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tight ? 12 : 16,
          vertical: tight ? 9 : 12,
        ),
        decoration: BoxDecoration(
          color: _C.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _C.line),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: tight ? 132 : 168,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _C.dim,
                  fontSize: tight ? 12 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _C.faint, fontSize: tight ? 12 : 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ligne « étiquette → valeur » de la fiche client.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.tight,
  });

  final String label;
  final String value;
  final bool tight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: tight ? 7 : 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: _C.faint, fontSize: tight ? 12 : 14),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: _C.text,
              fontSize: tight ? 13 : 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lien discret du pied de page — focusable, sinon inatteignable à la
/// télécommande.
class _FooterLink extends StatelessWidget {
  const _FooterLink({
    required this.label,
    required this.tight,
    required this.onSelect,
  });

  final String label;
  final bool tight;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            label,
            style: TextStyle(
              color: focused ? _C.accentSoft : _C.faint,
              fontSize: tight ? 11 : 12,
              fontWeight: focused ? FontWeight.w700 : FontWeight.w500,
              decoration: focused ? TextDecoration.underline : null,
              decorationColor: _C.accentSoft,
            ),
          ),
        );
      },
    );
  }
}
