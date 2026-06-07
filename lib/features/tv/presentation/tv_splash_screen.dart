// =========================================================
//  tv_splash_screen.dart — Écran de démarrage dédié Télévision
// =========================================================
//  POURQUOI cet écran ?
//  ----------------------------------------------------------
//  Sur TV, le client doit communiquer son IDENTIFIANT APPAREIL (la
//  « MAC » virtuelle, format MK:xx:xx:xx:xx:xx) à son fournisseur
//  pour activer son abonnement. Sur un téléphone c'est facile (on
//  copie/colle). Sur une TV, sans clavier ni copier-coller pratique,
//  il faut pouvoir LIRE la MAC en gros — voire la PHOTOGRAPHIER avec
//  son téléphone. D'où cet écran d'accueil dédié, affiché au lancement
//  de la version TV : logo + nom + MAC géante, puis un bouton ENTRER.
//
//  IDENTITÉ VISUELLE : palette « VIOLET ROYAL » (cf. `tv_palette.dart`),
//  calibrée sur des études d'ergonomie (fond presque-noir teinté
//  violet, texte blanc cassé, accent violet réservé au focus/CTA).
//
//  NAVIGATION TÉLÉCOMMANDE :
//   - Le bouton ENTRER reçoit le focus automatiquement (autofocus) :
//     l'utilisateur tape OK et entre dans l'app.
//   - Le bouton « Copier le code » est accessible au D-pad (utile sur
//     Fire TV avec un clavier/souris ou l'app télécommande).
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/branding/brand_logo.dart';
import '../../../core/branding/verified_badge.dart';
import '../../../core/flavor/flavor.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/tv_palette.dart';
import '../../device/data/device_identity.dart';

/// Écran de démarrage TV. `onEnter` est appelé quand l'utilisateur
/// valide le bouton ENTRER (OK de la télécommande) — c'est l'appelant
/// (le routeur dans `main.dart`) qui décide de basculer vers l'accueil.
class TvSplashScreen extends StatefulWidget {
  const TvSplashScreen({super.key, required this.onEnter});

  /// Callback déclenché à la validation du bouton ENTRER.
  final VoidCallback onEnter;

  @override
  State<TvSplashScreen> createState() => _TvSplashScreenState();
}

class _TvSplashScreenState extends State<TvSplashScreen>
    with TickerProviderStateMixin {
  /// Animation d'entrée : fondu + léger glissement vers le haut.
  /// Discrète (les études déconseillent les effets trop tape-à-l'œil
  /// sur TV) mais donne une sensation soignée au lancement.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  )..forward();

  /// Pulsation lente du halo violet derrière le logo — « respiration »
  /// très lente qui donne vie à l'écran sans distraire.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat(reverse: true);

  late final Animation<double> _fade = CurvedAnimation(
    parent: _entrance,
    curve: Curves.easeOut,
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _entrance.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvRoyal.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: TvRoyal.backgroundGradient),
        child: Stack(
          children: <Widget>[
            // ----- Halo violet diffus, pulsant lentement -----
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (BuildContext context, _) {
                  // Opacité oscillant doucement entre 0.10 et 0.22.
                  final double t = 0.10 + 0.12 * _pulse.value;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.45),
                        radius: 0.9,
                        colors: <Color>[
                          TvRoyal.accent.withValues(alpha: t),
                          TvRoyal.accent.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // ----- Contenu central -----
            SafeArea(
              child: Center(
                child: FadeTransition(
                  opacity: _fade,
                  child: SlideTransition(
                    position: _slide,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          // Logo géant à halo violet (lisible à 3 m).
                          const BrandLogo.hero(glowColor: TvRoyal.accentGlow),
                          const SizedBox(height: 26),

                          // Wordmark + badge vérifié.
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                FlavorConfig.current.appName,
                                style: AppTextStyles.headlineLarge.copyWith(
                                  color: TvRoyal.textPrimary,
                                  fontSize: 34,
                                  letterSpacing: 5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const VerifiedBadge.large(),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            BrandStrings.tagline,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: TvRoyal.textSecondary,
                              fontSize: 16,
                              letterSpacing: 2,
                            ),
                          ),

                          const SizedBox(height: 46),

                          // Carte MAC — l'élément clé de l'écran.
                          const _MacCard(),

                          const SizedBox(height: 40),

                          // Bouton ENTRER — focus automatique (OK télécommande).
                          _TvButton(
                            label: 'ENTRER',
                            icon: Icons.play_arrow_rounded,
                            primary: true,
                            autofocus: true,
                            onPressed: widget.onEnter,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
//  Carte MAC — identifiant appareil en GROS, facile à lire/photographier
// ============================================================

class _MacCard extends StatelessWidget {
  const _MacCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 32),
      decoration: BoxDecoration(
        color: TvRoyal.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: TvRoyal.accent.withValues(alpha: 0.45)),
        boxShadow: TvRoyal.focusGlow(intensity: 0.6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Eyebrow — petit label en capitales au-dessus du code.
          Text(
            'VOTRE IDENTIFIANT APPAREIL',
            style: AppTextStyles.labelSmall.copyWith(
              color: TvRoyal.accentGlow,
              fontSize: 13,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 18),

          // La MAC, en grand, en police à chasse fixe (monospace) pour
          // que chaque caractère soit net et aligné — idéal à recopier
          // ou photographier. On écoute le Future de DeviceIdentity ;
          // `macSync` sert de valeur initiale si déjà préchargée.
          FutureBuilder<String>(
            future: DeviceIdentity.instance.mac,
            initialData: DeviceIdentity.instance.macSync,
            builder: (BuildContext context, AsyncSnapshot<String> snap) {
              final String mac = snap.data ?? DeviceIdentity.instance.macSync;
              return SelectableText(
                mac,
                textAlign: TextAlign.center,
                style: GoogleFonts.robotoMono(
                  color: TvRoyal.textPrimary,
                  fontSize: 44,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 4,
                  height: 1.1,
                ),
              );
            },
          ),

          const SizedBox(height: 18),

          // Consigne — à quoi sert ce code.
          Text(
            'Communiquez ce code à votre fournisseur\npour activer votre abonnement.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: TvRoyal.textSecondary,
              fontSize: 15,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 22),

          // Bouton secondaire « Copier le code » — utile si une
          // télécommande/clavier le permet.
          Builder(
            builder: (BuildContext context) => _TvButton(
              label: 'Copier le code',
              icon: Icons.copy_rounded,
              primary: false,
              autofocus: false,
              onPressed: () async {
                final String mac = await DeviceIdentity.instance.mac;
                if (!context.mounted) return;
                await Clipboard.setData(ClipboardData(text: mac));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text('Identifiant copié.'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
//  Bouton TV focusable — primaire (violet plein) ou secondaire (outline)
// ============================================================
//  On gère le focus à la main pour appliquer le « stack focus » TV
//  recommandé par Google : agrandissement (scale) + halo (glow) +
//  changement de couleur. Le bouton reste un vrai bouton clavier
//  (OK télécommande = activation) via `FilledButton`/`OutlinedButton`.

class _TvButton extends StatefulWidget {
  const _TvButton({
    required this.label,
    required this.icon,
    required this.primary,
    required this.autofocus,
    required this.onPressed,
  });

  final String label;
  final IconData icon;

  /// `true` = pilule violette pleine (CTA principal). `false` = bouton
  /// contour discret (action secondaire).
  final bool primary;
  final bool autofocus;
  final VoidCallback onPressed;

  @override
  State<_TvButton> createState() => _TvButtonState();
}

class _TvButtonState extends State<_TvButton> {
  late final FocusNode _node =
      FocusNode(debugLabel: 'tv-splash-${widget.label}');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChange);
    _node.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() => _focused = _node.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    // Agrandissement léger au focus (1.06×) — repère TV n°1.
    final double scale = _focused ? 1.06 : 1.0;

    // Couleurs selon primaire/secondaire + état focus.
    final Color fill = widget.primary
        ? (_focused ? TvRoyal.accentGlow : TvRoyal.accent)
        : (_focused ? TvRoyal.accentSurface : Colors.transparent);
    final Color foreground = widget.primary
        ? TvRoyal.voidSurface // texte sombre sur pilule violette claire
        : (_focused ? TvRoyal.accentGlow : TvRoyal.textSecondary);
    final Border? border = widget.primary
        ? null
        : Border.all(
            color: _focused ? TvRoyal.accent : TvRoyal.border,
            width: 1.5,
          );

    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(16),
          border: border,
          boxShadow: _focused && widget.primary
              ? TvRoyal.focusGlow(intensity: 1.1)
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            focusNode: _node,
            autofocus: widget.autofocus,
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onPressed,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.primary ? 44 : 28,
                vertical: widget.primary ? 20 : 14,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(widget.icon,
                      color: foreground, size: widget.primary ? 26 : 20),
                  const SizedBox(width: 12),
                  Text(
                    widget.label,
                    style: AppTextStyles.button.copyWith(
                      color: foreground,
                      fontSize: widget.primary ? 18 : 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: widget.primary ? 3 : 1,
                    ),
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
