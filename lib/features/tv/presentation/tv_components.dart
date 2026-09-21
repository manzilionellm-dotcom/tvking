// =========================================================
//  tv_components.dart — Composants « Maison Noir » réutilisables
// =========================================================
//  Logo (vrai asset), Card (filet or), Button (CTA or), Pill (prix),
//  EmptyState. Tout référence TvTokens — zéro couleur en dur.
// =========================================================
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../vod/data/vod_novelty_service.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

/// Nom produit affiché PARTOUT.
const String kAppName = 'The Few TV';
// Logo « naturel » sur fond TRANSPARENT (pas le carré noir, qui se voyait
// comme un rectangle plus sombre sur les surfaces gris foncé de l'app).
// Le carré noir reste UNIQUEMENT pour l'icône de lancement (cf. yaml dédié),
// où un fond est normal.
const String _kLogoAsset = 'assets/branding/thefew_logo.png';

/// Numéro WhatsApp business (format international, sans + ni espaces).
const String kWhatsAppPhone = '18077888909';

/// Construit le lien wa.me avec un message pré-rempli (code MAC inclus).
String tvWhatsAppUrl(String mac) {
  final String code = (mac == '…' || mac.isEmpty) ? '' : mac;
  final String msg = Uri.encodeComponent(
      'Bonjour, je souhaite activer The Few TV.'
      '${code.isEmpty ? '' : ' Mon code : $code'}');
  return 'https://wa.me/$kWhatsAppPhone?text=$msg';
}

/// Panneau QR « Scanne-moi » → WhatsApp du revendeur, MAC pré-remplie.
/// Réutilisé sur l'écran d'activation ET sur l'accueil (quand aucune chaîne).
class TvWhatsAppQr extends StatelessWidget {
  const TvWhatsAppQr({super.key, required this.mac, this.size = 220});
  final String mac;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // QR sur fond clair (un QR se scanne en sombre-sur-clair).
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(TvTokens.rCard),
            border: Border.all(color: TvTokens.gold, width: 2),
          ),
          child: QrImageView(
            data: tvWhatsAppUrl(mac),
            version: QrVersions.auto,
            size: size,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square, color: Color(0xFF0B0B0B)),
            dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF0B0B0B)),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.qr_code_scanner_rounded,
                color: TvTokens.goldBright, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Text(context.l10n.tvScanToActivate,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.ui(18,
                      weight: FontWeight.w700, color: TvTokens.goldBright)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: size + 40,
          child: Text(context.l10n.tvScanHelp,
              textAlign: TextAlign.center,
              style: TvTokens.ui(13, color: TvTokens.mutedDim)),
        ),
      ],
    );
  }
}

/// Logo réel « The Few » (or sur noir).
class TvLogo extends StatelessWidget {
  const TvLogo({super.key, this.width = 180});
  final double width;

  @override
  Widget build(BuildContext context) {
    return Image.asset(_kLogoAsset, width: width, fit: BoxFit.contain);
  }
}

/// Carte sombre avec filet d'accent or en haut.
class TvCard extends StatelessWidget {
  const TvCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Filet d'accent or (1px) en haut.
          const SizedBox(
            height: 1,
            child: DecoratedBox(decoration: BoxDecoration(gradient: TvTokens.goldHairline)),
          ),
          Padding(padding: padding ?? const EdgeInsets.all(24), child: child),
        ],
      ),
    );
  }
}

/// Libellé de section : Inter 600, letterspaced, majuscules, gris.
class TvSectionLabel extends StatelessWidget {
  const TvSectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TvTokens.ui(10.5, weight: FontWeight.w600, color: TvTokens.mutedDim, spacing: 2.8),
      );
}

/// Bandeau de LANGUE au-dessus d'une rangée du Cinéma : « Français »,
/// « Türkçe », « العربية · Arabe »…
///
/// DEMANDE DU PROPRIÉTAIRE (20/09/2026) : « que les langues soient
/// différentes… facile surtout pour les gens âgés. » D'où le parti pris :
///  • GRAND (plus gros que tout le reste de la page hors la vedette),
///    en blanc plein — un client âgé le lit depuis son canapé sans
///    chercher ;
///  • une BARRE braise devant, et un FILET qui court sur toute la largeur
///    dessous : la coupure entre deux langues se voit même de loin, quand
///    on fait défiler vite ;
///  • ni focusable, ni cliquable : la télécommande passe par-dessus, le
///    parcours des rangées ne change pas d'un cran.
///
/// Le texte vient de `vod/domain/pays_cinema.dart` (une seule source, deux
/// écrans). Ici, on ne fait que dessiner.
class TvLangueBandeau extends StatelessWidget {
  const TvLangueBandeau(this.libelle, {super.key});
  final String libelle;

  @override
  Widget build(BuildContext context) => Padding(
        // De l'air AU-DESSUS (on quitte la langue précédente) et juste ce
        // qu'il faut dessous : le titre de la première rangée suit.
        padding: const EdgeInsets.only(top: 18, bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 5,
                  height: 30,
                  decoration: BoxDecoration(
                    color: TvTokens.ember,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    libelle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.ui(26,
                        weight: FontWeight.w800,
                        color: TvTokens.text,
                        spacing: 0.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(height: 1, color: TvTokens.line),
          ],
        ),
      );
}

/// PASTILLE « N NOUVEAUTÉS » sur la tuile Films de l'accueil (21/09/2026).
///
/// Le petit chiffre rouge d'un badge d'app : il dit « il y a du neuf pour
/// toi » avant même d'entrer. Le nombre vient de VodNoveltyService, tel
/// que le dernier passage au Cinéma l'a établi (films apparus au
/// catalogue depuis 14 jours). Rien à afficher = rien de construit : pas
/// de « 0 », pas de pastille vide.
class TvNouveautesBadge extends StatefulWidget {
  const TvNouveautesBadge({super.key});

  @override
  State<TvNouveautesBadge> createState() => _TvNouveautesBadgeState();
}

class _TvNouveautesBadgeState extends State<TvNouveautesBadge> {
  int _n = 0;

  @override
  void initState() {
    super.initState();
    VodNoveltyService.instance
        .freshMovieCount(nowMs: DateTime.now().millisecondsSinceEpoch)
        .then((int n) {
      if (mounted && n != _n) setState(() => _n = n);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_n <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: TvTokens.ember,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        // Au-delà de 99, « 99+ » : le chiffre exact n'apporte plus rien.
        _n > 99 ? '99+' : '$_n',
        style: TvTokens.ui(11, weight: FontWeight.w900, color: TvTokens.onEmber),
      ),
    );
  }
}

/// Pastille prix : « À VIE » + montant or.
class TvPricePill extends StatelessWidget {
  const TvPricePill({super.key, required this.label, required this.amount});
  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: BoxDecoration(
        gradient: TvTokens.pillGradient,
        border: Border.all(color: TvTokens.line),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label.toUpperCase(),
              style: TvTokens.ui(15, weight: FontWeight.w600, color: TvTokens.gold, spacing: 2)),
          const SizedBox(width: 12),
          Text(amount,
              style: TvTokens.display(26, weight: FontWeight.w600, color: TvTokens.goldBright)),
        ],
      ),
    );
  }
}

/// CTA principal : dégradé or, texte sombre, ombre. Focusable (or au focus).
class TvCtaButton extends StatelessWidget {
  const TvCtaButton({
    super.key,
    required this.label,
    required this.onSelect,
    this.autofocus = false,
    this.expand = true,
  });
  final String label;
  final VoidCallback? onSelect;
  final bool autofocus;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.large,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return Container(
          width: expand ? double.infinity : null,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          decoration: BoxDecoration(
            gradient: TvTokens.ctaGradient,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: focused ? Border.all(color: TvTokens.text, width: 2) : null,
            boxShadow: <BoxShadow>[
              BoxShadow(
                // Lueur du CTA : TOUJOURS la couleur d'accent du design system
                // (l'ancien or 0xFFCCB089 était codé en dur ici — il aurait
                // survécu, orphelin, au passage au thème « Verre Noir »).
                color: TvTokens.gold.withValues(alpha: focused ? 0.55 : 0.35),
                blurRadius: focused ? 36 : 24,
                spreadRadius: -10,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TvTokens.ui(TvDimens.title,
                  weight: FontWeight.w600, color: const Color(0xFF1A1206))),
        );
      },
    );
  }
}

/// État vide soigné : carré or léger + titre Oswald + sous-texte gris.
class TvEmptyState extends StatelessWidget {
  const TvEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              gradient: TvTokens.pillGradient,
              border: Border.all(color: TvTokens.line),
              borderRadius: BorderRadius.circular(TvTokens.rButton),
            ),
            child: Icon(icon, color: TvTokens.gold, size: 38),
          ),
          const SizedBox(height: 22),
          Text(title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TvTokens.display(34, color: TvTokens.text)),
          const SizedBox(height: 10),
          SizedBox(
            width: 460,
            child: Text(subtitle,
                textAlign: TextAlign.center,
                style: TvTokens.ui(16, color: TvTokens.mutedDim)),
          ),
        ],
      ),
    );
  }
}

// =========================================================
//  SQUELETTES « RESPIRANTS » — chargement sans roue qui tourne
// =========================================================
//  Une roue de chargement dit « attends » ; une silhouette de contenu dit
//  « ça arrive ». Pendant le chargement d'un catalogue (Films/Séries), on
//  dessine la STRUCTURE de la page (vedette + rangées d'affiches) en
//  surfaces sombres qui « respirent » (opacité 0.45 ↔ 0.9, 1.4 s).
//  GPU-léger : une seule animation d'opacité pour tout le squelette.
//  Respecte « réduire les animations » (statique si demandé par l'OS).
class TvSkeletonRails extends StatefulWidget {
  const TvSkeletonRails({super.key, this.withHero = true, this.rails = 2});

  /// Dessine le grand bloc « vedette » au-dessus des rangées.
  final bool withHero;

  /// Nombre de rangées d'affiches suggérées.
  final int rails;

  @override
  State<TvSkeletonRails> createState() => _TvSkeletonRailsState();
}

class _TvSkeletonRailsState extends State<TvSkeletonRails>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduce = MediaQuery.of(context).disableAnimations;
    final Widget bones = _bones();
    if (reduce) return Opacity(opacity: 0.7, child: bones);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 0.9).animate(
          CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: bones,
    );
  }

  Widget _bones() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (widget.withHero) ...<Widget>[
            _box(width: double.infinity, height: 210, radius: TvTokens.rCard),
            const SizedBox(height: 26),
          ],
          for (int r = 0; r < widget.rails; r++) ...<Widget>[
            _box(width: 180 + (r.isEven ? 40 : 0), height: 20, radius: 6),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                for (int i = 0; i < 6; i++) ...<Widget>[
                  _box(
                      width: TvDimens.posterW,
                      height: TvDimens.posterH,
                      radius: TvTokens.rSmall),
                  const SizedBox(width: 12),
                ],
              ],
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _box(
      {required double width, required double height, required double radius}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: TvTokens.tileBorder),
      ),
    );
  }
}

// =========================================================
//  Dialogues PREMIUM partagés (jamais d'AlertDialog Android nu)
// =========================================================
//  Retour client du 21/08 (« on dirait un téléphone chinois ») : tout
//  dialogue TV passe par ces cartes — fond sombre profond, filet doré,
//  boutons pill focusables à la télécommande. Même langage visuel que le
//  dialogue de sortie du template classique (tv_app._ExitDialog).

/// Confirmation à DEUX choix. Renvoie true (confirmer), false/null (annuler).
/// [danger] : action destructrice → le bouton de confirmation vire au rouge.
/// [content] : remplace [message] par un contenu riche (résumé de source…).
Future<bool?> showTvConfirm(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? message,
  Widget? content,
  String? cancelLabel,
  bool danger = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.86),
    builder: (BuildContext ctx) => Center(
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: TvTokens.card,
          borderRadius: BorderRadius.circular(TvTokens.rCard),
          border: Border.all(color: TvTokens.line),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TvTokens.display(24, color: TvTokens.text)),
              if (message != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(message,
                    textAlign: TextAlign.center,
                    style: TvTokens.ui(15, color: TvTokens.mutedDim)),
              ],
              if (content != null) ...<Widget>[
                const SizedBox(height: 14),
                content,
              ],
              const SizedBox(height: 24),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _TvDialogButton(
                      label: cancelLabel ?? ctx.l10n.buttonCancel,
                      // L'ANNULATION prend le focus d'entrée : un OK
                      // réflexe ne détruit jamais rien.
                      autofocus: true,
                      onSelect: () => Navigator.of(ctx).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TvDialogButton(
                      label: confirmLabel,
                      danger: danger,
                      primary: !danger,
                      onSelect: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Message d'information à UN bouton (erreurs, confirmations simples).
Future<void> showTvInfo(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.86),
    builder: (BuildContext ctx) => Center(
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: TvTokens.card,
          borderRadius: BorderRadius.circular(TvTokens.rCard),
          border: Border.all(color: TvTokens.line),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TvTokens.display(24, color: TvTokens.text)),
              const SizedBox(height: 10),
              Text(message,
                  textAlign: TextAlign.center,
                  style: TvTokens.ui(15, color: TvTokens.mutedDim)),
              const SizedBox(height: 24),
              _TvDialogButton(
                label: ctx.l10n.buttonOk,
                autofocus: true,
                primary: true,
                onSelect: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Bouton pill des dialogues premium : repos discret (filet), focus plein —
/// or pour les actions normales, ROUGE pour les destructrices.
class _TvDialogButton extends StatelessWidget {
  const _TvDialogButton({
    required this.label,
    required this.onSelect,
    this.autofocus = false,
    this.primary = false,
    this.danger = false,
  });
  final String label;
  final VoidCallback onSelect;
  final bool autofocus;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    const Color red = Color(0xFFD0453A);
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color accent = danger ? red : TvTokens.gold;
        final Color bg = focused ? accent : Colors.transparent;
        final Color fg = focused
            ? (danger ? Colors.white : TvTokens.onGold)
            : (danger
                ? red
                : (primary ? TvTokens.goldBright : TvTokens.muted));
        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: Border.all(color: focused ? accent : TvTokens.line),
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TvTokens.ui(16, weight: FontWeight.w700, color: fg)),
        );
      },
    );
  }
}
