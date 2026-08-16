// =========================================================
//  tv_smart_add_screen.dart — « Colle ou tape ton lien » (aiguillage)
// =========================================================
//  LE point d'entrée unique de l'ajout de source. Le client ne doit PAS
//  savoir ce que veut dire « Xtream » ou « M3U » : il colle/tape le lien
//  que son fournisseur lui a donné, et l'app AIGUILLE toute seule :
//
//    • get.php?username=X&password=Y  → écran Xtream, 3 champs PRÉ-REMPLIS
//    • …/liste.m3u ou .m3u8           → écran M3U, URL pré-remplie
//    • portail Xtream sans identifiants → écran Xtream, serveur pré-rempli
//    • indécidable (domaine seul)     → on pose UNE question simple,
//      champs déjà pré-remplis dans les deux cas.
//
//  Saisie 100 % télécommande (TvUrlKeyboard, chips http:// / .m3u / …) ;
//  les fautes de frappe sont réparées (SourceInputNormalizer) et la
//  correction est MONTRÉE (« server,com → server.com ») — confiance.
//  Ceux qui savent ce qu'ils font ont des raccourcis directs en bas.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../playlists/data/source_input_normalizer.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_add_m3u_screen.dart';
import 'tv_add_source_screen.dart';
import 'tv_components.dart';
import 'tv_pair_screen.dart';
import 'tv_shell.dart';
import 'tv_url_keyboard.dart';

class TvSmartAddScreen extends StatefulWidget {
  const TvSmartAddScreen({super.key});

  @override
  State<TvSmartAddScreen> createState() => _TvSmartAddScreenState();
}

class _TvSmartAddScreenState extends State<TvSmartAddScreen> {
  final TextEditingController _linkC = TextEditingController();

  String? _error;
  String? _fixNote;

  /// Analyse « indécidable » en attente : on pose la question M3U/Xtream.
  SourceInputAnalysis? _pendingChoice;

  @override
  void dispose() {
    _linkC.dispose();
    super.dispose();
  }

  /// Pousse l'écran suivant ; s'il se termine par un ajout réussi
  /// (pop(true)), on referme AUSSI cet aiguillage — le client retombe
  /// directement sur ses sources / son accueil.
  Future<void> _push(Widget screen) async {
    final bool? added = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => TvShell(child: screen)),
    );
    if (added == true && mounted) Navigator.of(context).pop(true);
  }

  void _continue() {
    final SourceInputAnalysis a = SourceInputNormalizer.analyze(_linkC.text);
    if (a.url.isEmpty) {
      setState(() {
        _error = context.l10n.tvSmartAddEmptyError;
        _pendingChoice = null;
      });
      return;
    }
    setState(() {
      _error = null;
      _pendingChoice = null;
      // Montre discrètement ce qu'on a réparé — le client comprend que
      // l'app travaille AVEC lui, pas contre lui.
      _fixNote = a.fixes.isEmpty
          ? null
          : context.l10n.tvSourceFixedAddress(a.fixes.join(' · '));
    });

    switch (a.kind) {
      case SourceInputKind.xtream:
        _push(TvAddSourceScreen(
          initialServer: a.xtreamServer,
          initialUsername: a.xtreamUsername,
          initialPassword: a.xtreamPassword,
        ));
      case SourceInputKind.m3u:
        _push(TvAddM3uScreen(initialUrl: a.url));
      case SourceInputKind.unknown:
        // On ne force personne à connaître le jargon : UNE question,
        // formulée avec des mots simples, champs déjà pré-remplis.
        setState(() => _pendingChoice = a);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // ----- Colonne gauche : la zone intelligente + aiguillage -----
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(context.l10n.tvSourceAddTitle,
                    style: TvTokens.display(34, color: TvTokens.text)),
                const SizedBox(height: 6),
                Text(context.l10n.tvSmartAddSubtitle,
                    style: TvTokens.ui(16, color: TvTokens.mutedDim)),
                const SizedBox(height: 18),

                // VOIE ROYALE, EN PREMIER (et pré-focalisée) : appairage par
                // QR. Taper un serveur Xtream à la télécommande est le pire
                // moment de la vie d'un client ; on lui propose d'abord de
                // le faire sur son téléphone. La saisie manuelle reste juste
                // en dessous pour ceux qui préfèrent.
                _ChoiceCard(
                  icon: Icons.qr_code_2_rounded,
                  title: context.l10n.tvPairEntry,
                  subtitle: context.l10n.tvPairEntrySub,
                  autofocus: true,
                  onSelect: () => _push(const TvPairScreen()),
                ),
                const SizedBox(height: 18),

                TvKeyboardField(
                  controller: _linkC,
                  label: context.l10n.tvSmartAddFieldLabel,
                  hint: 'http://serveur.com:8080/get.php?username=…',
                  // PAS d'autofocus ici : la carte d'appairage ci-dessus le
                  // prend (voie recommandée). Deux autofocus dans la même
                  // route = focus indéterminé au premier rendu — bug typique
                  // « la télécommande ne répond pas » sur box.
                  autofocus: false,
                  active: true,
                  onActivate: () {},
                ),

                if (_fixNote != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(_fixNote!, style: TvTokens.ui(13, color: TvTokens.gold)),
                ],
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: TvTokens.ui(14, color: const Color(0xFFE0746A))),
                ],
                const SizedBox(height: 16),

                TvCtaButton(
                    label: context.l10n.buttonContinue, onSelect: _continue),

                // ----- Question simple quand on ne peut pas deviner -----
                if (_pendingChoice != null) ...<Widget>[
                  const SizedBox(height: 18),
                  Text(context.l10n.tvSmartAddLastQuestion,
                      style: TvTokens.ui(15,
                          weight: FontWeight.w600, color: TvTokens.text)),
                  const SizedBox(height: 10),
                  _ChoiceCard(
                    icon: Icons.badge_outlined,
                    title: context.l10n.tvSmartAddChoiceCredsTitle,
                    subtitle: context.l10n.tvSmartAddChoiceCredsSubtitle,
                    autofocus: true,
                    onSelect: () => _push(TvAddSourceScreen(
                        initialServer: _pendingChoice!.url)),
                  ),
                  const SizedBox(height: 10),
                  _ChoiceCard(
                    icon: Icons.playlist_play_rounded,
                    title: context.l10n.tvSmartAddChoiceLinkTitle,
                    subtitle: context.l10n.tvSmartAddChoiceLinkSubtitle,
                    onSelect: () =>
                        _push(TvAddM3uScreen(initialUrl: _pendingChoice!.url)),
                  ),
                ],

                // ----- Raccourcis pour ceux qui savent -----
                const SizedBox(height: 24),
                Text(context.l10n.tvSmartAddOrDirectly,
                    style: TvTokens.ui(11,
                        weight: FontWeight.w600,
                        color: TvTokens.mutedDim,
                        spacing: 2)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    _ShortcutChip(
                      icon: Icons.vpn_key_rounded,
                      label: context.l10n.tvSmartAddShortcutXtream,
                      onSelect: () => _push(const TvAddSourceScreen()),
                    ),
                    _ShortcutChip(
                      icon: Icons.playlist_add_rounded,
                      label: context.l10n.tvSmartAddShortcutM3u,
                      onSelect: () => _push(const TvAddM3uScreen()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 22),
        // ----- Colonne droite : clavier D-pad intégré -----
        SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: TvUrlKeyboard(
              controller: _linkC,
              fieldLabel: context.l10n.tvSmartAddYourLink,
            ),
          ),
        ),
      ],
    );
  }
}

/// Grande carte de choix (question M3U / Xtream) : lisible de loin,
/// focusable, une seule idée par carte.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onSelect,
    this.autofocus = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused ? const Color(0xFF1A1206) : TvTokens.text;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rCard),
            border:
                Border.all(color: focused ? TvTokens.gold : TvTokens.line),
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 28, color: focused ? fg : TvTokens.gold),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title,
                        style: TvTokens.ui(17,
                            weight: FontWeight.w700, color: fg)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TvTokens.ui(13,
                            color: focused
                                ? const Color(0xB31A1206)
                                : TvTokens.muted)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip(
      {required this.icon, required this.label, required this.onSelect});
  final IconData icon;
  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused ? const Color(0xFF1A1206) : TvTokens.muted;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border:
                Border.all(color: focused ? TvTokens.gold : TvTokens.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(label,
                  style:
                      TvTokens.ui(14, weight: FontWeight.w600, color: fg)),
            ],
          ),
        );
      },
    );
  }
}
