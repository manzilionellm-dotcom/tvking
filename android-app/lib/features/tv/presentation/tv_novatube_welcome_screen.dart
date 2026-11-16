// =========================================================
//  tv_novatube_welcome_screen.dart — « Bienvenue sur NovaTube »
// =========================================================
//  Premier écran de l'édition NovaTube TV (compilée avec
//  --dart-define=NOVATUBE_TV=true). Il remplace l'écran d'activation Zuno
//  tant que la box n'a ni accès valide ni liste (voir TvGate, tv_app.dart).
//
//  Objectif : une application OUVERTE et SIMPLE. N'importe qui ajoute sa
//  propre liste en deux gestes, même si sa licence n'est pas encore active :
//
//      ┌───────────────────────────────────────────────┐
//      │                 ▶ NovaTube                    │
//      │           Bienvenue sur NovaTube              │
//      │  Ajoutez la liste de votre fournisseur…       │
//      │  [ Ajouter une liste M3U ] [ Xtream Codes ]   │
//      │  Code de l'appareil  MK:XX:XX:XX:XX:XX        │
//      │  ● Licence en attente d'activation            │
//      │  [ Vérifier mon accès ]                       │
//      └───────────────────────────────────────────────┘
//
//  Ce qui n'est PAS fait ici (volontairement) :
//    • aucun téléchargement de liste : les deux boutons ouvrent l'écran
//      d'ajout déjà testé (TvAddSourceScreen → TvSourceEntryForm), qui
//      valide l'adresse HTTP/HTTPS ou les identifiants Xtream ;
//    • aucune décision d'accès : c'est TvGate qui ouvre l'accueil dès qu'une
//      liste existe ET que le serveur ne bloque pas (essai expiré, licence
//      suspendue…). Une liste ajoutée pendant un blocage est conservée ;
//    • aucun nom du panel d'administration, aucune adresse de serveur, aucun
//      identifiant à l'écran : seulement le code appareil `MK:…`, que le
//      client donne à son revendeur ;
//    • aucun paiement : le prix n'est pas affiché tant que le compte marchand
//      n'est pas validé (exigence du propriétaire).
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../device/data/device_identity.dart';
import '../../device/domain/display_mac.dart';
import '../../playlists/domain/open_source_input.dart';
import '../../subscription/data/remote_activation_watch.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_app_tokens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_add_source_screen.dart';
import 'tv_components.dart';
import 'tv_shell.dart';

class TvNovatubeWelcomeScreen extends StatefulWidget {
  const TvNovatubeWelcomeScreen({super.key});

  @override
  State<TvNovatubeWelcomeScreen> createState() =>
      _TvNovatubeWelcomeScreenState();
}

class _TvNovatubeWelcomeScreenState extends State<TvNovatubeWelcomeScreen> {
  // « … » tant que l'identité n'est pas lue (quelques millisecondes).
  String _mac = '…';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = m);
    });
    // Le statut est lu par la veille unique de l'app (RemoteActivationWatch),
    // avec ses délais progressifs. Cet écran ÉCOUTE seulement : il n'envoie
    // aucune requête en boucle (pas de synchronisation toutes les secondes).
    SubscriptionState.instance.addListener(_onStatus);
  }

  void _onStatus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SubscriptionState.instance.removeListener(_onStatus);
    super.dispose();
  }

  /// Une seule vérification à la demande. Le bouton est désactivé pendant
  /// l'appel : appuyer dix fois ne lance pas dix requêtes.
  Future<void> _checkAccess() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await SubscriptionState.instance.syncWithBackend();
      RemoteActivationWatch.instance.nudge();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Ouvre l'écran d'ajout existant, directement sur le bon formulaire.
  /// Au retour, TvGate réévalue tout seul (il écoute les chaînes).
  void _openEntry(OpenEntryMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvShell(child: TvAddSourceScreen(initialMode: mode)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TvAppTokens t = TvAppTokens.of(context);
    final AppLocalizations l10n = context.l10n;
    final _AccessLine access = _AccessLine.of(l10n);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Deux boutons côte à côte sur une TV, l'un sous l'autre sur un
        // écran étroit (téléphone en portrait, fenêtre réduite).
        final bool wide = constraints.maxWidth >= 720;
        final List<Widget> entries = <Widget>[
          _BigEntryButton(
            key: const ValueKey<String>('novatube-welcome-m3u'),
            icon: Icons.playlist_add_rounded,
            label: l10n.novatubeAddM3u,
            // Le premier bouton reçoit le focus : la télécommande est
            // immédiatement utilisable, sans chercher où l'on se trouve.
            autofocus: true,
            onSelect: () => _openEntry(OpenEntryMode.m3u),
          ),
          _BigEntryButton(
            key: const ValueKey<String>('novatube-welcome-xtream'),
            icon: Icons.vpn_key_rounded,
            label: l10n.novatubeXtreamLogin,
            onSelect: () => _openEntry(OpenEntryMode.xtream),
          ),
        ];
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.hasBoundedHeight
                  ? constraints.maxHeight - 56
                  : 0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const TvLogo(width: 300),
                    const SizedBox(height: 22),
                    Text(
                      l10n.novatubeWelcomeTitle,
                      textAlign: TextAlign.center,
                      style: t.display(34, color: t.text),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.novatubeWelcomeSubtitle,
                      textAlign: TextAlign.center,
                      style: t.ui(18, color: t.muted),
                    ),
                    const SizedBox(height: 28),
                    if (wide)
                      Row(
                        children: <Widget>[
                          Expanded(child: entries[0]),
                          const SizedBox(width: 20),
                          Expanded(child: entries[1]),
                        ],
                      )
                    else ...<Widget>[
                      entries[0],
                      const SizedBox(height: 16),
                      entries[1],
                    ],
                    const SizedBox(height: 30),
                    TvCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 22,
                      ),
                      child: Column(
                        children: <Widget>[
                          TvSectionLabel(l10n.novatubeDeviceCodeLabel),
                          const SizedBox(height: 10),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              // Format complet demandé : MK:XX:XX:XX:XX:XX.
                              displayMac(_mac, showPrefix: true),
                              // Un code reste gauche → droite, même en arabe.
                              textDirection: TextDirection.ltr,
                              style: t.mono(
                                34,
                                color: t.accentBright,
                                spacing: 2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l10n.novatubeDeviceCodeHelp,
                            textAlign: TextAlign.center,
                            style: t.ui(15, color: t.mutedDim),
                          ),
                          const SizedBox(height: 16),
                          _AccessStatus(line: access),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: 360,
                      child: TvCtaButton(
                        label: _busy ? l10n.tvChecking : l10n.novatubeCheckAccess,
                        onSelect: _busy ? null : _checkAccess,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      l10n.novatubePlayerNotice,
                      textAlign: TextAlign.center,
                      style: t.ui(13, color: t.mutedDim),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Grand bouton d'entrée (M3U ou Xtream). Focus télécommande net : fond
/// relevé + bordure turquoise vive, comme la ligne sélectionnée de la
/// capture de référence. Hauteur généreuse : lisible à 3 m.
class _BigEntryButton extends StatelessWidget {
  const _BigEntryButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onSelect,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(TvTokens.rCard);
    return TvFocusBuilder(
      onSelect: onSelect,
      autofocus: autofocus,
      scale: TvFocusScale.small,
      borderRadius: radius,
      builder: (BuildContext context, bool focused) {
        final TvAppTokens t = TvAppTokens.of(context);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 118,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: focused ? t.sel : t.card,
            borderRadius: radius,
            border: Border.all(
              color: focused ? t.accentBright : t.line,
              width: focused ? 2.5 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 40, color: focused ? t.accentBright : t.accent),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.ui(
                    21,
                    weight: FontWeight.w700,
                    color: focused ? t.text : t.muted,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// État de l'accès, en une phrase claire. Les six cas demandés sont
/// distingués : essai actif, licence active, expirée, suspendue, réseau
/// indisponible, et « en attente » (jamais activée). La réassociation
/// d'une installation est gérée par le panel : la box garde son code.
class _AccessLine {
  const _AccessLine(this.text, this.ok);
  final String text;

  /// `true` = accès ouvert (pastille turquoise), `false` = action requise.
  final bool ok;

  static _AccessLine of(AppLocalizations l10n) {
    final SubscriptionState s = SubscriptionState.instance;
    // Une coupure réseau n'est JAMAIS présentée comme une licence perdue.
    if (s.syncHint == 'offline') {
      return _AccessLine(l10n.tvNetworkUnavailableHelp, false);
    }
    return switch (s.status) {
      SubscriptionStatus.paid => _AccessLine(l10n.novatubeStatusActive, true),
      SubscriptionStatus.trialActive =>
        _AccessLine(l10n.novatubeStatusTrial, true),
      SubscriptionStatus.trialExpired =>
        _AccessLine(l10n.novatubeStatusExpired, false),
      SubscriptionStatus.frozen =>
        _AccessLine(l10n.novatubeStatusSuspended, false),
      SubscriptionStatus.banned => _AccessLine(l10n.tvStatusBanned, false),
      SubscriptionStatus.unknown =>
        _AccessLine(l10n.novatubeStatusPending, false),
    };
  }
}

class _AccessStatus extends StatelessWidget {
  const _AccessStatus({required this.line});
  final _AccessLine line;

  @override
  Widget build(BuildContext context) {
    final TvAppTokens t = TvAppTokens.of(context);
    final Color dot = line.ok ? t.accentBright : t.live;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            line.text,
            textAlign: TextAlign.center,
            style: t.ui(17, weight: FontWeight.w600, color: t.text),
          ),
        ),
      ],
    );
  }
}
