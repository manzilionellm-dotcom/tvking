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
      reason: 'Déverrouille 7 MOTION',
    );
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() => _authenticating = false);
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
              Text('7 MOTION', style: AppTextStyles.headlineLarge),
              const SizedBox(height: 4),
              Text(
                'Application verrouillée',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 48),

              // Bouton de déverrouillage manuel — affiché seulement
              // si l'auto-prompt a déjà tenté et failed/cancelled.
              if (_attempted && !_authenticating)
                ElevatedButton.icon(
                  onPressed: _unlock,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Déverrouiller'),
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
              if (_authenticating)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
