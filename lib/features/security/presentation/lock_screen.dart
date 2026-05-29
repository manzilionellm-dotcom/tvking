// =========================================================
//  lock_screen.dart — Écran de verrouillage à l'ouverture
// =========================================================
//  Affiché par main.dart AVANT le `MaterialApp` si le réglage
//  "Verrouiller à l'ouverture" est activé. L'utilisateur doit
//  s'authentifier (empreinte ou PIN système) pour accéder à l'app.
//
//  Design : très sobre, dark, avec le logo 7 MOTION centré et un
//  bouton "Déverrouiller" qui déclenche le prompt biométrique.
//  Si le user annule ou foire son auth, il peut retenter ; pas
//  de "kill the app" — Android lui-même propose le PIN fallback.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/branding/verified_badge.dart';
import '../../../core/flavor/flavor.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/biometric_auth.dart';

class LockScreen extends StatefulWidget {
  /// Callback appelé une fois que l'auth a réussi.
  final VoidCallback onUnlocked;

  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _authenticating = false;
  bool _attempted = false;
  // Nombre d'echecs / annulations consecutifs. Au-dela de 2, on
  // affiche un message de secours pour debloquer l'utilisateur qui
  // n'a pas de PIN systeme configure ou dont le capteur sous l'ecran
  // ne repond pas. C'est la difference entre un utilisateur frustre
  // qui desinstalle l'app et un utilisateur qui sait quoi faire.
  int _failures = 0;

  @override
  void initState() {
    super.initState();
    // Auto-déclenche le prompt biométrique dès que l'écran est
    // affiché, sans que l'user ait à tap "Déverrouiller" la première
    // fois. UX d'app bancaire : un seul geste = empreinte au boot.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _attempted = true;
    });
    final bool ok = await BiometricAuth.instance.authenticate(
      reason: 'Déverrouille ${FlavorConfig.current.appName}',
    );
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() {
        _authenticating = false;
        _failures++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sur l'écran de lock, on cache la status bar pour que l'écran
    // soit pleinement immersif (style verrouillage bancaire).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Logo / marque
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accent, width: 2),
                ),
                child: const Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    FlavorConfig.current.appName,
                    style: AppTextStyles.headlineLarge,
                  ),
                  // Le badge verifie est l'identite visuelle de
                  // 7 MOTION uniquement ; il n'apparait pas pour
                  // Red Room (ou un futur flavor) qui a sa propre
                  // marque.
                  if (FlavorConfig.current.flavor == Flavor.sevenMotion) ...[
                    const SizedBox(width: 8),
                    const VerifiedBadge.large(),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Application verrouillée',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 48),

              // Bouton de déverrouillage manuel — affiche SI on a
              // deja tente. On garde le bouton visible pendant
              // _authenticating (avec un spinner integre) au lieu
              // de le cacher : si le prompt systeme ne s'affiche
              // pas (capteur sous l'ecran qui ne registre rien, OS
              // qui ignore le dialog), l'utilisateur ne se retrouve
              // pas devant un ecran vide en attente.
              if (_attempted)
                ElevatedButton.icon(
                  onPressed: _authenticating ? null : _unlock,
                  icon: _authenticating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black54,
                          ),
                        )
                      : const Icon(Icons.fingerprint),
                  label: Text(_authenticating
                      ? 'Authentification...'
                      : 'Déverrouiller'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                    textStyle: AppTextStyles.button,
                  ),
                ),

              // Conseil de secours apres 2 echecs/annulations : on
              // explique a l'utilisateur que SI sa biometrie ne
              // repond pas, c'est probablement parce qu'aucun PIN
              // n'est configure cote OS. local_auth ne peut pas
              // proposer un fallback PIN si l'OS lui-meme n'en a
              // pas. Le message est minimaliste pour ne pas
              // distraire si tout fonctionne normalement.
              if (_failures >= 2) ...[
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    "Empreinte indisponible ?\n"
                    "Configure un verrou d'écran (PIN / schéma) dans "
                    "Réglages Android → Sécurité, puis reviens et "
                    "retape Déverrouiller.",
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
