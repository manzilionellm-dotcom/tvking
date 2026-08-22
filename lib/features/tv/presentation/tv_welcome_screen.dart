// =========================================================
//  tv_welcome_screen.dart — Accueil chaleureux du 1er lancement
// =========================================================
//  Demande client (photo « Aucune chaîne dans ce groupe ») : quelqu'un qui
//  installe l'app sur sa TV SANS lien ne doit JAMAIS tomber sur un écran
//  vide ou un simple formulaire froid. Il doit être ACCUEILLI :
//
//    • à DROITE : le QR d'appairage DÉJÀ OUVERT — il scanne avec son
//      téléphone, saisit son lien M3U ou ses codes Xtream sur un VRAI
//      clavier, et la TV se connecte toute seule (PairingService, le
//      circuit « zéro frappe » existant) ;
//    • à GAUCHE : le mot de bienvenue, l'ESSAI DE 3 SEMAINES mis en
//      avant, le PRIX de l'application, et les autres portes d'entrée
//      (saisie à la télécommande, activation d'un abonnement payé).
//
//  DEUX VARIANTES par build :
//    • build DIRECT (revendeur) : tout est visible (essai, prix,
//      activation par code) ;
//    • build STORE (Amazon/Play, kIsPlayBuild) : lecteur PUR « apporte ta
//      playlist » (dossier Amazon 21688197501) — NI prix, NI essai, NI
//      parcours revendeur : seulement le QR d'appairage et la saisie
//      manuelle (le contenu vient de l'utilisateur, jamais de nous).
//
//  Quand l'appairage aboutit, l'import passe par PlaylistRepository →
//  le flux de chaînes notifie TvGate (tv_app.dart) → l'accueil s'ouvre
//  TOUT SEUL. Aucun pop nécessaire quand cet écran est la racine du gate.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/update/build_flags.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../device/data/device_identity.dart';
import '../../playlists/data/pairing_service.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_activation_screen.dart';
import 'tv_components.dart';
import 'tv_shell.dart';
import 'tv_smart_add_screen.dart';

class TvWelcomeScreen extends StatefulWidget {
  const TvWelcomeScreen({super.key});

  @override
  State<TvWelcomeScreen> createState() => _TvWelcomeScreenState();
}

enum _PairPhase { opening, waiting, importing, expired, unavailable }

class _TvWelcomeScreenState extends State<TvWelcomeScreen> {
  static const Duration _pollEvery = Duration(seconds: 2);

  _PairPhase _phase = _PairPhase.opening;
  PairingSession? _session;
  Timer? _poll;
  String? _error;

  /// Anti-empilement des relèves (même verrou que tv_pair_screen : sur un
  /// Wi-Fi lent une relève peut durer 12 s alors que le timer bat à 2 s).
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    // Le QR s'ouvre TOUT SEUL : zéro clic avant de pouvoir scanner.
    // ignore: discarded_futures
    _startPairing();
    // Code appareil : affiché dans la carte « Contact » (le revendeur en a
    // besoin pour activer / pousser la source).
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = DeviceIdentity.stripPrefix(m));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _startPairing() async {
    _poll?.cancel();
    setState(() {
      _phase = _PairPhase.opening;
      _error = null;
    });
    final PairingSession? s = await PairingService.instance.open();
    if (!mounted) return;
    if (s == null) {
      // Backend injoignable : pas de cul-de-sac — la saisie manuelle reste
      // le chemin principal, et « Nouveau code » permet de retenter.
      setState(() => _phase = _PairPhase.unavailable);
      return;
    }
    setState(() {
      _session = s;
      _phase = _PairPhase.waiting;
    });
    _poll = Timer.periodic(_pollEvery, (_) => _tick());
  }

  Future<void> _tick() async {
    final PairingSession? s = _session;
    if (s == null || _phase != _PairPhase.waiting || _polling) return;
    _polling = true;
    final PairingPoll r;
    try {
      r = await PairingService.instance.poll(s.token);
    } finally {
      _polling = false;
    }
    if (!mounted || _phase != _PairPhase.waiting) return;
    if (r.status == PairingStatus.expired) {
      _poll?.cancel();
      setState(() => _phase = _PairPhase.expired);
      return;
    }
    if (r.status == PairingStatus.ready && r.source != null) {
      _poll?.cancel();
      await _import(r.source!);
    }
  }

  /// Import par les MÊMES points d'entrée que la saisie manuelle (zéro
  /// chemin parallèle). Succès → le flux de chaînes réveille TvGate qui
  /// remplace cet écran par l'accueil ; si l'écran a été POUSSÉ (depuis un
  /// autre parcours), on referme proprement.
  Future<void> _import(PairedSource src) async {
    setState(() => _phase = _PairPhase.importing);
    try {
      if (src.isXtream) {
        await PlaylistRepository.instance.addXtreamPlaylist(
          name: src.name,
          serverUrl: src.server!,
          username: src.username!,
          password: src.password!,
        );
      } else {
        await PlaylistRepository.instance.addM3uPlaylistSmart(
          name: src.name,
          url: src.m3uUrl!,
        );
      }
      if (!mounted) return;
      final NavigatorState nav = Navigator.of(context);
      if (nav.canPop()) nav.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _PairPhase.expired;
        _error = e.toString();
      });
    }
  }

  /// Code de CET appareil (MAC nue, sans le préfixe « MK: » que les panels
  /// ajoutent déjà) : c'est le code que le client donne à son revendeur.
  String _mac = '…';

  /// Appareil DÉJÀ actif (payé ou essai en cours) : il repasse par ici
  /// uniquement parce qu'il n'a plus AUCUNE chaîne (source supprimée) —
  /// on l'accueille sans lui re-vendre essai/prix/activation.
  bool get _alreadyActive {
    final SubscriptionStatus s = SubscriptionState.instance.status;
    return s == SubscriptionStatus.paid || s == SubscriptionStatus.trialActive;
  }

  void _openScreen(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TvShell(child: screen)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Même recette d'échelle que l'écran d'activation : le design est pensé
    // à taille fixe puis FittedBox = jamais de débordement, 720p → 4K,
    // overscan compris ; textScale système neutralisé (box qui poussent 1.3).
    return MediaQuery.withNoTextScaling(
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 1120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SizedBox(width: 620, child: _heroColumn(context)),
                const SizedBox(width: 52),
                SizedBox(width: 420, child: _pairPane(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Colonne gauche : bienvenue + essai + prix + portes d'entrée ----
  Widget _heroColumn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const TvLogo(width: 210),
        const SizedBox(height: 26),
        Text(context.l10n.tvWelcomeTitle,
            style: TvTokens.display(42, color: TvTokens.text)),
        const SizedBox(height: 10),
        Text(context.l10n.tvWelcomeSub,
            style: TvTokens.ui(18, color: TvTokens.muted)),

        // ===== ESSAI 3 SEMAINES + PRIX — builds DIRECTS uniquement =====
        // (build store : lecteur pur, aucune offre commerciale — dossier
        //  Amazon 21688197501 + règles de facturation des stores.)
        // Et JAMAIS pour un appareil DÉJÀ ACTIF (payé/essai en cours) qui
        // repasse ici après avoir supprimé sa source : on ne vend pas un
        // essai à un client déjà chez nous — QR + saisie suffisent.
        if (!kIsPlayBuild && !_alreadyActive) ...<Widget>[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TvTokens.rCard),
              border: Border.all(color: TvTokens.gold, width: 1.4),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[
                  TvTokens.sel,
                  TvTokens.sel.withValues(alpha: 0.0),
                ],
              ),
            ),
            child: Row(
              children: <Widget>[
                const Text('🎁', style: TextStyle(fontSize: 34)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(context.l10n.tvWelcomeTrialTitle,
                          style: TvTokens.ui(21,
                              weight: FontWeight.w800,
                              color: TvTokens.goldBright)),
                      const SizedBox(height: 3),
                      Text(context.l10n.tvWelcomeTrialSub,
                          style: TvTokens.ui(14, color: TvTokens.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Le PRIX, dit franchement (même pastille que l'activation —
          // une seule vérité tarifaire dans l'app).
          TvPricePill(label: context.l10n.tvLifetime, amount: '9,99 \$'),
        ],

        const SizedBox(height: 26),
        // ----- Portes d'entrée -----
        TvCtaButton(
          label: '⌨  ${context.l10n.tvWelcomeManualBtn}',
          onSelect: () => _openScreen(const TvSmartAddScreen()),
        ),
        if (!kIsPlayBuild && !_alreadyActive) ...<Widget>[
          const SizedBox(height: 12),
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => _openScreen(const TvActivationScreen()),
            builder: (BuildContext context, bool focused) => Container(
              alignment: Alignment.center,
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(TvTokens.rButton),
                border: Border.all(
                    color: focused ? TvTokens.gold : TvTokens.line),
                color: focused ? TvTokens.sel : Colors.transparent,
              ),
              child: Text('🔓  ${context.l10n.tvWelcomeActivateBtn}',
                  style: TvTokens.ui(19,
                      weight: FontWeight.w600,
                      color:
                          focused ? TvTokens.goldBright : TvTokens.muted)),
            ),
          ),
        ],

        // ===== CODE DE L'APPAREIL + CONTACT (retour client du 21/08) =====
        // « Le client ne sait pas comment mettre le Xtream et le code » : la
        // vraie porte de sortie pour lui, c'est SON REVENDEUR. On lui met
        // donc sous les yeux (a) le code à donner, (b) un QR qui ouvre la
        // conversation WhatsApp avec le code DÉJÀ écrit dans le message.
        const SizedBox(height: 20),
        _DeviceAndContactCard(mac: _mac),
      ],
    );
  }

  // ---- Colonne droite : QR d'appairage DÉJÀ ouvert ----
  Widget _pairPane(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(context.l10n.tvWelcomeScanTitle,
            textAlign: TextAlign.center,
            style: TvTokens.ui(21,
                weight: FontWeight.w800, color: TvTokens.text)),
        const SizedBox(height: 6),
        SizedBox(
          width: 360,
          child: Text(context.l10n.tvWelcomeScanSub,
              textAlign: TextAlign.center,
              style: TvTokens.ui(14, color: TvTokens.mutedDim)),
        ),
        const SizedBox(height: 18),
        ..._pairBody(context),
      ],
    );
  }

  List<Widget> _pairBody(BuildContext context) {
    switch (_phase) {
      case _PairPhase.opening:
      case _PairPhase.importing:
        return <Widget>[
          const SizedBox(height: 60),
          const SizedBox(
            width: 30,
            height: 30,
            child:
                CircularProgressIndicator(strokeWidth: 3, color: TvTokens.gold),
          ),
          const SizedBox(height: 14),
          Text(context.l10n.tvPairConnecting,
              style: TvTokens.ui(15, color: TvTokens.muted)),
          const SizedBox(height: 60),
        ];
      case _PairPhase.unavailable:
      case _PairPhase.expired:
        return <Widget>[
          const SizedBox(height: 40),
          Text(
            _phase == _PairPhase.unavailable
                ? context.l10n.tvPairUnavailable
                : (_error ?? context.l10n.tvPairExpired),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TvTokens.ui(15, color: const Color(0xFFE0746A)),
          ),
          const SizedBox(height: 16),
          TvCtaButton(
              label: context.l10n.tvPairNewCode, onSelect: _startPairing),
          const SizedBox(height: 40),
        ];
      case _PairPhase.waiting:
        final PairingSession s = _session!;
        return <Widget>[
          // QR sur carte blanche cerclée d'or — le « scanne-moi » évident.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(TvTokens.rCard),
              border: Border.all(color: TvTokens.gold, width: 2),
            ),
            child: QrImageView(
              data: s.url,
              version: QrVersions.auto,
              size: 250,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square, color: Color(0xFF0B0B0B)),
              dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF0B0B0B)),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text('${context.l10n.tvPairCodeIs}  ',
                  style: TvTokens.ui(14, color: TvTokens.muted)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: TvTokens.sel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: TvTokens.gold),
                ),
                child: Text(s.code,
                    style: TvTokens.mono(24, color: TvTokens.goldBright)
                        .copyWith(letterSpacing: 5)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: TvTokens.mutedDim),
              ),
              const SizedBox(width: 10),
              Text(context.l10n.tvPairWaiting,
                  style: TvTokens.ui(13, color: TvTokens.mutedDim)),
            ],
          ),
        ];
    }
  }
}

/// Carte « Mon code + Contact » de l'accueil (retour client du 21/08).
///
/// À GAUCHE : le CODE de l'appareil, en gros et en mono — c'est ce que le
/// client dicte à son revendeur pour être activé / recevoir sa liste. Il
/// n'a alors RIEN à taper lui-même : ni serveur Xtream, ni identifiant.
/// À DROITE : un petit QR « Aide & contact » qui ouvre la conversation
/// WhatsApp avec le message DÉJÀ écrit, code inclus (tvWhatsAppUrl).
class _DeviceAndContactCard extends StatelessWidget {
  const _DeviceAndContactCard({required this.mac});
  final String mac;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(context.l10n.tvDeviceAddress,
                    style: TvTokens.ui(12, color: TvTokens.mutedDim)),
                const SizedBox(height: 6),
                SelectableText(
                  mac,
                  style: TvTokens.mono(26, color: TvTokens.goldBright)
                      .copyWith(letterSpacing: 2),
                ),
                const SizedBox(height: 8),
                Text(context.l10n.tvDeviceAddressHelp,
                    style: TvTokens.ui(13, color: TvTokens.muted)),
              ],
            ),
          ),
          const SizedBox(width: 18),
          // QR CONTACT — petit, discret, mais c'est LA porte de secours du
          // client : il scanne, WhatsApp s'ouvre, le message est déjà écrit
          // avec son code. Zéro saisie, zéro jargon.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: TvTokens.line),
                ),
                child: QrImageView(
                  data: tvWhatsAppUrl(mac),
                  version: QrVersions.auto,
                  size: 108,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square, color: Color(0xFF0B0B0B)),
                  dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF0B0B0B)),
                ),
              ),
              const SizedBox(height: 8),
              Text(context.l10n.tvSettingsHelp,
                  style: TvTokens.ui(13,
                      weight: FontWeight.w700, color: TvTokens.goldBright)),
              Text(context.l10n.tvHelpScanWrite,
                  style: TvTokens.ui(11, color: TvTokens.mutedDim)),
            ],
          ),
        ],
      ),
    );
  }
}
