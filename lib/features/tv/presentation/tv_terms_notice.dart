// =========================================================
//  tv_terms_notice.dart — Les conditions, SANS bloquer la télé
// =========================================================
//  Demande du client : « les conditions qui ne bloquent pas la télé.
//  Juste un petit message comme un chat. Il faut accepter que
//  l'application ne vend pas de contenu, mais que ça vienne un petit
//  message, tip top. Genre, que ça ne dérange pas, mais il doit dire
//  oui ou non. »
//
//  Sur TÉLÉPHONE, les conditions restent une PORTE : `ConsentScreen`
//  barre l'entrée tant qu'on n'a pas accepté (c'est ce que les boutiques
//  attendent d'une app installée à la main). Sur une TÉLÉVISION, cette
//  même porte est vécue comme une panne : un mur de texte à lire à trois
//  mètres, à la télécommande, avant d'avoir vu la moindre image.
//
//  Ici, l'accueil s'affiche NORMALEMENT et une bulle vient se poser en
//  bas à droite, quelques secondes après. Elle dit l'essentiel en deux
//  lignes et attend un OUI ou un NON :
//    • OUI  → c'est noté (même clé que le téléphone : `ConsentState`),
//             la bulle ne revient plus jamais ;
//    • NON  → on ouvre les conditions en entier pour qu'il lise, et
//             rien n'est enregistré : la bulle reviendra au prochain
//             lancement. À AUCUN MOMENT la télé ne s'arrête.
//
//  Le focus va sur OUI : un seul appui sur OK et la bulle disparaît.
//  C'est le geste le moins dérangeant possible — sans ça, sur une box
//  sans écran tactile, la bulle serait tout simplement inatteignable.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../onboarding/data/consent_state.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_legal_screen.dart';

class TvTermsNotice extends StatefulWidget {
  const TvTermsNotice({super.key, this.delay = const Duration(seconds: 3)});

  /// Délai avant l'apparition. On laisse l'accueil se poser et le bouquet
  /// arriver : une bulle qui surgit pendant le chargement est perçue
  /// comme une erreur, pas comme une politesse.
  final Duration delay;

  @override
  State<TvTermsNotice> createState() => _TvTermsNoticeState();
}

class _TvTermsNoticeState extends State<TvTermsNotice> {
  /// `null` tant qu'on n'a pas lu la préférence — on ne montre rien.
  bool? _accepted;
  bool _visible = false;
  Timer? _appear;

  @override
  void initState() {
    super.initState();
    ConsentState.instance.hasAccepted().then((bool ok) {
      if (!mounted) return;
      setState(() => _accepted = ok);
      if (ok) return;
      _appear = Timer(widget.delay, () {
        if (mounted) setState(() => _visible = true);
      });
    }).catchError((Object _) {
      // Préférence illisible : on ne harcèle pas, on ne bloque rien.
      if (mounted) setState(() => _accepted = true);
    });
  }

  @override
  void dispose() {
    _appear?.cancel();
    super.dispose();
  }

  void _yes() {
    unawaited(ConsentState.instance.markAccepted());
    setState(() {
      _accepted = true;
      _visible = false;
    });
  }

  void _no() {
    // NON ne coupe rien : on referme la bulle et on ouvre le texte
    // complet. Rien n'est enregistré — la question se reposera au
    // prochain lancement, mais la télé, elle, continue.
    setState(() => _visible = false);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TvLegalScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted != false || !_visible) return const SizedBox.shrink();
    return Align(
      alignment: const Alignment(0.97, 0.94),
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.4),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 420),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
              decoration: BoxDecoration(
                color: TvTokens.surface3.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: TvTokens.gold.withValues(alpha: 0.4)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x88000000),
                    blurRadius: 28,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.chat_bubble_outline_rounded,
                          color: TvTokens.goldBright, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Un mot, vite fait',
                        style: TvTokens.ui(17,
                            weight: FontWeight.w700,
                            color: TvTokens.goldBright),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Cette application est un LECTEUR. Elle ne vend, ne '
                    'fournit et n\'héberge aucune chaîne : tu apportes ta '
                    'propre source. D\'accord ?',
                    style: TvTokens.ui(15, color: TvTokens.text)
                        .copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  // Wrap et non Row : selon la police réellement chargée
                  // et la langue, les deux libellés peuvent dépasser la
                  // largeur de la bulle. Ils passent alors à la ligne au
                  // lieu de déborder.
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      _NoticeButton(
                        label: 'Non, lire les conditions',
                        onSelect: _no,
                      ),
                      _NoticeButton(
                        label: 'Oui, j\'ai compris',
                        primary: true,
                        autofocus: true,
                        onSelect: _yes,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeButton extends StatelessWidget {
  const _NoticeButton({
    required this.label,
    required this.onSelect,
    this.primary = false,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onSelect;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = primary
            ? TvTokens.onGold
            : (focused ? TvTokens.goldBright : TvTokens.text);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: primary
                ? TvTokens.gold
                : (focused
                    ? TvTokens.gold.withValues(alpha: 0.18)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focused
                  ? TvTokens.goldBright
                  : TvTokens.gold.withValues(alpha: 0.3),
              width: focused ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TvTokens.ui(14, weight: FontWeight.w700, color: fg),
          ),
        );
      },
    );
  }
}
