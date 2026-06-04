// =========================================================
//  lock_screen.dart — Écran de verrouillage à l'ouverture
// =========================================================
//  Affiche par main.dart AVANT le `MaterialApp` si le reglage
//  "Verrouiller a l'ouverture" est active OU si le flavor exige
//  biometricMandatory (Red Room).
//
//  L'utilisateur a DEUX chemins pour entrer :
//
//    1) Empreinte biometrique systeme. Auto-declenchee au boot,
//       re-declenchable via le bouton "Empreinte digitale".
//       Bypass si l'OS n'a pas de PIN/schema configure ET aucun
//       capteur biometrique (local_auth retourne true direct).
//
//    2) Code a 4 chiffres GERE PAR L'APP (AppPinSettings).
//       Par defaut "0000" sur une install fraiche, modifiable
//       dans Reglages > Securite. Ce chemin marche TOUJOURS,
//       independamment de la config Android — important pour
//       les capteurs sous-ecran qui n'arrivent pas a registrer
//       le doigt (cas vecu par l'utilisateur sur sa premiere
//       install Red Room).
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/branding/verified_badge.dart';
import '../../../core/flavor/flavor.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/app_pin_settings.dart';
import '../data/biometric_auth.dart';

class LockScreen extends StatefulWidget {
  /// Callback appele une fois que l'auth a reussi (biometrie ou PIN).
  final VoidCallback onUnlocked;

  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _authenticating = false;
  // PIN tape par l'utilisateur. On utilise un TextEditingController
  // plutot qu'un setState a chaque keystroke pour la perf et pour
  // pouvoir clear() le champ apres une tentative ratee.
  final TextEditingController _pinCtrl = TextEditingController();
  String? _pinError;
  // Le PIN est-il encore le defaut "0000" ? Si oui, on affiche un
  // helper pour le faire savoir au user (utile sur premiere install).
  bool _isDefaultPin = false;

  @override
  void initState() {
    super.initState();
    // Auto-declenche le prompt biometrique au boot, comme une app
    // bancaire. Si ca echoue (capteur HS, annulation), le user a
    // toujours le PIN comme parachute.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    AppPinSettings.instance.isUsingDefault().then((bool isDefault) {
      if (mounted) setState(() => _isDefaultPin = isDefault);
    });
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);
    final bool ok = await BiometricAuth.instance.authenticate(
      reason: context.l10n.lockUnlockReason(FlavorConfig.current.appName),
    );
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    setState(() => _authenticating = false);
  }

  Future<void> _tryPin() async {
    final String pin = _pinCtrl.text.trim();
    if (pin.length < 4) {
      setState(() => _pinError = context.l10n.lockPinTooShort);
      return;
    }
    final bool ok = await AppPinSettings.instance.verify(pin);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _pinError = context.l10n.lockPinWrong;
      _pinCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Sur l'ecran de lock, on cache la status bar pour que l'ecran
    // soit pleinement immersif (style verrouillage bancaire).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 32,
              vertical: 24,
            ),
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
                    // BLACK7 ROYAL uniquement.
                    if (FlavorConfig.current.flavor == Flavor.sevenMotion) ...[
                      const SizedBox(width: 8),
                      const VerifiedBadge.large(),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.lockAppLocked,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 36),

                // ===== BOUTON BIOMETRIE =====
                ElevatedButton.icon(
                  onPressed: _authenticating ? null : _tryBiometric,
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
                      ? context.l10n.lockAuthenticating
                      : context.l10n.lockFingerprint),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                    textStyle: AppTextStyles.button,
                    minimumSize: const Size(220, 48),
                  ),
                ),

                // ===== SEPARATEUR "OU" =====
                const SizedBox(height: 24),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Divider(
                        color: AppColors.textTertiary.withValues(alpha: 0.3),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'OU',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: AppColors.textTertiary.withValues(alpha: 0.3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ===== CHAMP PIN =====
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: TextField(
                    controller: _pinCtrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 8,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headlineMedium.copyWith(
                      letterSpacing: 8,
                    ),
                    autofocus: false,
                    onSubmitted: (_) => _tryPin(),
                    decoration: InputDecoration(
                      hintText: '••••',
                      hintStyle: AppTextStyles.headlineMedium.copyWith(
                        color: AppColors.textTertiary,
                        letterSpacing: 8,
                      ),
                      counterText: '',
                      errorText: _pinError,
                      filled: true,
                      fillColor: AppColors.surfaceHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _tryPin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceOverlay,
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                    minimumSize: const Size(220, 44),
                  ),
                  child: Text(context.l10n.lockValidateCode),
                ),

                // ===== HELPER PIN PAR DEFAUT =====
                if (_isDefaultPin) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      context.l10n.lockDefaultPin(AppPinSettings.defaultPin),
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
      ),
    );
  }
}
