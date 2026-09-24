// =========================================================
//  admin_pin_screen.dart — Code admin (création / vérification)
// =========================================================
//  Si aucun PIN n'est défini → mode "Création" : saisie + confirm.
//  Si un PIN existe → mode "Vérification" : 1 seule saisie.
//
//  Layout sobre Maison Noir : pavé numérique XL, dots discrets
//  d'avancement, message d'erreur ember quand mauvais code,
//  reset après 3 tentatives ratées (lockout temporaire).
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/branding/brand_logo.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/admin_credentials.dart';
import 'admin_dashboard_screen.dart';

class AdminPinScreen extends StatefulWidget {
  const AdminPinScreen({super.key});

  @override
  State<AdminPinScreen> createState() => _AdminPinScreenState();
}

class _AdminPinScreenState extends State<AdminPinScreen> {
  static const int _pinLength = 4;

  String _entered = '';
  String? _firstPass; // pour le mode création (1ère saisie)
  bool _confirming = false;
  String? _error;
  int _failCount = 0;

  bool get _isCreating => !AdminCredentials.instance.hasPin;

  String get _title {
    if (_isCreating) {
      return _confirming ? 'Confirme ton code' : 'Crée ton code admin';
    }
    return 'Code admin';
  }

  String get _hint {
    if (_isCreating && !_confirming) {
      return '$_pinLength chiffres. Personne d\'autre n\'aura cet accès.';
    }
    if (_isCreating && _confirming) {
      return 'Retape le même code pour confirmer.';
    }
    return 'Entre ton code pour accéder au mode admin.';
  }

  Future<void> _onDigit(int digit) async {
    if (_entered.length >= _pinLength) return;
    setState(() {
      _entered += digit.toString();
      _error = null;
    });
    if (_entered.length == _pinLength) {
      await _handleComplete();
    }
  }

  void _onBack() {
    if (_entered.isEmpty) return;
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = null;
    });
  }

  Future<void> _handleComplete() async {
    if (_isCreating) {
      if (!_confirming) {
        // 1ère saisie OK → demande de confirmation
        setState(() {
          _firstPass = _entered;
          _entered = '';
          _confirming = true;
        });
      } else {
        // 2e saisie : compare
        if (_entered == _firstPass) {
          await AdminCredentials.instance.setPin(_entered);
          if (!mounted) return;
          await HapticFeedback.lightImpact();
          _enterDashboard();
        } else {
          await HapticFeedback.heavyImpact();
          setState(() {
            _error = 'Les deux codes ne correspondent pas.';
            _entered = '';
            _firstPass = null;
            _confirming = false;
          });
        }
      }
    } else {
      // Mode vérification
      final bool ok =
          await AdminCredentials.instance.verifyPin(_entered);
      if (!mounted) return;
      if (ok) {
        await HapticFeedback.lightImpact();
        _enterDashboard();
      } else {
        await HapticFeedback.heavyImpact();
        _failCount++;
        setState(() {
          _error = _failCount >= 3
              ? 'Trop de tentatives. Reviens dans une minute.'
              : 'Code incorrect.';
          _entered = '';
        });
      }
    }
  }

  void _enterDashboard() {
    Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => const AdminDashboardScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Accès admin'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: <Widget>[
                  const Spacer(),
                  const BrandLogo.medium(),
                  const SizedBox(height: 24),
                  Text(
                    _title,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headlineLarge.copyWith(
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _hint,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ----- Dots d'avancement -----
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<Widget>.generate(_pinLength, (int i) {
                      final bool filled = i < _entered.length;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: filled
                                ? AppColors.accent
                                : AppColors.surfaceHigh,
                            border: Border.all(
                              color: filled
                                  ? AppColors.accent
                                  : AppColors.border,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 12,
                        color: AppColors.live,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),

                  // ----- Pavé numérique -----
                  _Numpad(
                    onDigit: _onDigit,
                    onBackspace: _onBack,
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Numpad extends StatelessWidget {
  const _Numpad({required this.onDigit, required this.onBackspace});

  final void Function(int) onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int row = 0; row < 3; row++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                for (int col = 0; col < 3; col++)
                  _NumKey(
                    label: '${row * 3 + col + 1}',
                    onTap: () => onDigit(row * 3 + col + 1),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              const SizedBox(width: 72, height: 72),
              _NumKey(label: '0', onTap: () => onDigit(0)),
              SizedBox(
                width: 72,
                height: 72,
                child: IconButton(
                  iconSize: 28,
                  onPressed: onBackspace,
                  icon: const Icon(
                    Icons.backspace_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NumKey extends StatelessWidget {
  const _NumKey({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: AppTextStyles.headlineLarge.copyWith(
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
