// =========================================================
//  tv_privacy_screen.dart — « Connexion protégée » (statut VPN + guide)
// =========================================================
//  Affiche EN CLAIR si la connexion du client passe par un VPN. Quand
//  c'est le cas, son fournisseur d'accès Internet ne voit pas ce qu'il
//  regarde (vie privée). Sinon, on explique simplement comment s'en servir.
//
//  IMPORTANT : AUCUN VPN n'est embarqué dans l'app. On se contente de
//  DÉTECTER et de GUIDER — c'est une fonctionnalité de CONFIDENTIALITÉ,
//  pas un outil de contournement. L'état se met à jour en direct (la
//  détection tourne en boucle douce tant que l'écran est ouvert).
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/network/vpn_status.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

class TvPrivacyScreen extends StatefulWidget {
  const TvPrivacyScreen({super.key});

  @override
  State<TvPrivacyScreen> createState() => _TvPrivacyScreenState();
}

class _TvPrivacyScreenState extends State<TvPrivacyScreen> {
  @override
  void initState() {
    super.initState();
    // Démarre la détection en direct (4 s) : le bouclier passe au vert tout
    // seul dès que l'utilisateur active son VPN.
    VpnStatus.instance.start();
  }

  @override
  void dispose() {
    VpnStatus.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool?>(
      valueListenable: VpnStatus.instance.active,
      builder: (BuildContext context, bool? state, _) {
        // Apparence selon l'état (couleurs du design system uniquement) :
        //   protégé → vert (success) ; non protégé → or (chaud, non alarmant) ;
        //   inconnu → gris discret.
        final bool protected = state == true;
        final bool unknown = state == null;
        final Color accent = protected
            ? TvTokens.success
            : (unknown ? TvTokens.mutedDim : TvTokens.gold);
        final IconData icon = protected
            ? Icons.verified_user_rounded
            : (unknown ? Icons.shield_outlined : Icons.gpp_maybe_rounded);
        final String title = protected
            ? 'Ta connexion est protégée'
            : (unknown ? 'Statut non déterminé' : 'Connexion non masquée');
        final String subtitle = protected
            ? 'Un VPN est actif : ton fournisseur d\'accès Internet ne peut pas '
                'voir ce que tu regardes.'
            : (unknown
                ? 'Impossible de vérifier l\'état du VPN sur cet appareil. '
                    'Appuie sur « Revérifier ».'
                : 'Ton activité est visible par ton fournisseur d\'accès. '
                    'Pour une confidentialité totale, active un VPN sur cet appareil.');

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Connexion protégée',
                  style: TextStyle(
                      fontSize: TvDimens.displayM,
                      fontWeight: FontWeight.w800,
                      color: TvTokens.text)),
              const SizedBox(height: 6),
              Text('Confidentialité vis-à-vis de ton fournisseur d\'accès',
                  style:
                      TextStyle(fontSize: TvDimens.body, color: TvTokens.muted)),
              const SizedBox(height: 22),

              // ----- Carte STATUT -----
              Container(
                width: 760,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: TvTokens.card,
                  borderRadius: BorderRadius.circular(TvDimens.panelRadius),
                  border: Border.all(color: accent.withValues(alpha: 0.45)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(TvTokens.rCard),
                      ),
                      child: Icon(icon, color: accent, size: 44),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(title,
                              style: TextStyle(
                                  fontSize: TvDimens.title,
                                  fontWeight: FontWeight.w800,
                                  color: accent)),
                          const SizedBox(height: 8),
                          Text(subtitle,
                              style: TextStyle(
                                  fontSize: TvDimens.body,
                                  height: 1.35,
                                  color: TvTokens.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ----- Bouton « Revérifier » -----
              TvFocusBuilder(
                autofocus: true,
                scale: TvFocusScale.large,
                onSelect: () => VpnStatus.instance.check(),
                builder: (BuildContext context, bool focused) {
                  final Color bg = focused ? TvTokens.gold : TvTokens.sel;
                  final Color fg =
                      focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
                  return Container(
                    decoration: BoxDecoration(
                        color: bg,
                        borderRadius:
                            BorderRadius.circular(TvDimens.cardRadius)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.refresh_rounded, color: fg, size: 24),
                        const SizedBox(width: 10),
                        Text('Revérifier maintenant',
                            style: TextStyle(
                                fontSize: TvDimens.title,
                                fontWeight: FontWeight.w700,
                                color: fg)),
                      ],
                    ),
                  );
                },
              ),

              // ----- Guide (affiché seulement si NON protégé) -----
              if (!protected) ...<Widget>[
                const SizedBox(height: 26),
                Text('Comment activer un VPN ?',
                    style: TextStyle(
                        fontSize: TvDimens.titleS,
                        fontWeight: FontWeight.w700,
                        color: TvTokens.text)),
                const SizedBox(height: 12),
                _Step(
                    n: 1,
                    text: 'Installe une application VPN réputée depuis le '
                        'store de ta TV (Google Play / Amazon Appstore).'),
                _Step(
                    n: 2,
                    text: 'Ouvre l\'app VPN et connecte-toi à un serveur '
                        '(autorise la demande de connexion VPN si elle apparaît).'),
                _Step(
                    n: 3,
                    text: 'Reviens ici : le bouclier passe au vert tout seul '
                        'dès que le VPN est actif.'),
                const SizedBox(height: 18),
                // Note honnête : la confidentialité ≠ blanchiment de contenu.
                Container(
                  width: 760,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: TvTokens.sel,
                    borderRadius: BorderRadius.circular(TvTokens.rCard),
                    border: Border.all(color: TvTokens.lineSoft),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.info_outline_rounded,
                          color: TvTokens.mutedDim, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Un VPN protège ta vie privée. Il ne remplace pas le '
                          'respect des conditions d\'utilisation de tes contenus.',
                          style: TextStyle(
                              fontSize: TvDimens.caption,
                              height: 1.35,
                              color: TvTokens.mutedDim),
                        ),
                      ),
                    ],
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

/// Une étape numérotée du petit guide (pastille or + texte).
class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: 760,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: TvTokens.badgeBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('$n',
                  style: TextStyle(
                      fontSize: TvDimens.caption,
                      fontWeight: FontWeight.w800,
                      color: TvTokens.gold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(text,
                    style: TextStyle(
                        fontSize: TvDimens.body,
                        height: 1.35,
                        color: TvTokens.muted)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
