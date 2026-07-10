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

import '../../playlists/data/source_input_normalizer.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_add_m3u_screen.dart';
import 'tv_add_source_screen.dart';
import 'tv_components.dart';
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
        _error = 'Colle ou tape ton lien pour commencer.';
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
          : 'On a corrigé l\'adresse : ${a.fixes.join(' · ')}';
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
                Text('Ajouter une source',
                    style: TvTokens.display(34, color: TvTokens.text)),
                const SizedBox(height: 6),
                Text(
                    'Colle ou tape le lien donné par ton fournisseur — '
                    'on reconnaît tout seul de quel type de liste il s\'agit.',
                    style: TvTokens.ui(16, color: TvTokens.mutedDim)),
                const SizedBox(height: 18),

                TvKeyboardField(
                  controller: _linkC,
                  label: 'Colle ou tape ton lien',
                  hint: 'http://serveur.com:8080/get.php?username=…',
                  autofocus: true,
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

                TvCtaButton(label: 'Continuer', onSelect: _continue),

                // ----- Question simple quand on ne peut pas deviner -----
                if (_pendingChoice != null) ...<Widget>[
                  const SizedBox(height: 18),
                  Text('Dernière question : qu\'est-ce que ton fournisseur '
                      't\'a donné avec ce lien ?',
                      style: TvTokens.ui(15,
                          weight: FontWeight.w600, color: TvTokens.text)),
                  const SizedBox(height: 10),
                  _ChoiceCard(
                    icon: Icons.badge_outlined,
                    title: 'Un identifiant et un mot de passe',
                    subtitle: 'On garde ton lien comme adresse du serveur, '
                        'tu ajoutes tes codes.',
                    autofocus: true,
                    onSelect: () => _push(TvAddSourceScreen(
                        initialServer: _pendingChoice!.url)),
                  ),
                  const SizedBox(height: 10),
                  _ChoiceCard(
                    icon: Icons.playlist_play_rounded,
                    title: 'Juste ce lien, rien d\'autre',
                    subtitle: 'On le traite comme une liste M3U directe.',
                    onSelect: () =>
                        _push(TvAddM3uScreen(initialUrl: _pendingChoice!.url)),
                  ),
                ],

                // ----- Raccourcis pour ceux qui savent -----
                const SizedBox(height: 24),
                Text('OU DIRECTEMENT',
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
                      label: 'Code Xtream (serveur + identifiants)',
                      onSelect: () => _push(const TvAddSourceScreen()),
                    ),
                    _ShortcutChip(
                      icon: Icons.playlist_add_rounded,
                      label: 'Lien M3U',
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
              fieldLabel: 'Ton lien',
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
