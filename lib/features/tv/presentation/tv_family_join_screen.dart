// =========================================================
//  tv_family_join_screen.dart — « J'ai un code famille » (TV)
// =========================================================
//  L'enfant/le proche tape ici le code à 6 CHIFFRES généré par le
//  propriétaire. Si le code est bon, le worker RATTACHE cet appareil à
//  l'abonnement famille → l'écran d'activation (qui re-vérifie toutes
//  les 5 s) débloque l'app toute seule dans la foulée.
// =========================================================
import 'package:flutter/material.dart';

import '../../device/data/device_identity.dart';
import '../../subscription/data/family_backend.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

class TvFamilyJoinScreen extends StatefulWidget {
  const TvFamilyJoinScreen({super.key});

  @override
  State<TvFamilyJoinScreen> createState() => _TvFamilyJoinScreenState();
}

class _TvFamilyJoinScreenState extends State<TvFamilyJoinScreen> {
  String _code = '';
  bool _busy = false;
  String? _message; // erreur ou succès (doux, en clair)
  bool _joined = false;

  void _type(String d) {
    if (_busy || _joined || _code.length >= 6) return;
    setState(() {
      _code += d;
      _message = null;
    });
    if (_code.length == 6) _submit();
  }

  void _backspace() {
    if (_busy || _joined || _code.isEmpty) return;
    setState(() => _code = _code.substring(0, _code.length - 1));
  }

  Future<void> _submit() async {
    if (_busy || _code.length != 6) return;
    setState(() => _busy = true);
    final String mac = await DeviceIdentity.instance.mac;
    final Map<String, dynamic>? r = await FamilyBackend.join(mac, _code);
    if (!mounted) return;
    if (r == null) {
      setState(() {
        _busy = false;
        _message = 'Connexion impossible. Vérifie le réseau et réessaie.';
      });
      return;
    }
    if (r['ok'] == true) {
      setState(() {
        _busy = false;
        _joined = true;
        _message =
            '🎉 C\'est fait ! Cet appareil est rattaché à l\'abonnement '
            'famille ${r['owner'] ?? ''}. L\'app se débloque dans quelques '
            'secondes…';
      });
      // Pousse le rafraîchissement tout de suite (sans attendre le poll 5 s).
      await SubscriptionState.instance.syncWithBackend();
      return;
    }
    final String err = (r['error'] ?? '').toString();
    setState(() {
      _busy = false;
      _code = '';
      _message = switch (err) {
        'code_invalid' => 'Code invalide ou expiré. Redemande un code.',
        'family_full' => 'Cette famille est complète (5 appareils max).',
        'owner_not_paid' =>
          'L\'abonnement du propriétaire n\'est plus actif.',
        'own_code' => 'C\'est ton propre code 🙂 — il est pour tes proches.',
        _ => 'Impossible pour le moment. Réessaie plus tard.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    // Affichage « 4 8 1 · · · » du code en cours de saisie.
    final String shown = List<String>.generate(
      6,
      (int i) => i < _code.length ? _code[i] : '·',
    ).join(' ');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'J\'ai un code famille',
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: TvTokens.text),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tape le code à 6 chiffres affiché sur l\'appareil de ton '
              'proche (Réglages → Abonnement Famille).',
              style: TextStyle(fontSize: 15, color: TvTokens.muted),
            ),
            const SizedBox(height: 24),
            // ----- Code en cours -----
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
              decoration: BoxDecoration(
                color: TvTokens.card,
                borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                border: Border.all(
                    color: _joined ? TvTokens.success : TvTokens.gold),
              ),
              child: Text(
                shown,
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 6,
                  color: _joined ? TvTokens.success : TvTokens.goldBright,
                ),
              ),
            ),
            if (_message != null) ...<Widget>[
              const SizedBox(height: 14),
              Text(
                _message!,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _joined ? TvTokens.success : TvTokens.muted,
                ),
              ),
            ],
            const SizedBox(height: 24),
            // ----- Pavé de chiffres (D-pad) -----
            if (!_joined)
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (int d = 1; d <= 9; d++)
                    _key('$d', autofocus: d == 1, onSelect: () => _type('$d')),
                  _key('0', onSelect: () => _type('0')),
                  _key('⌫', onSelect: _backspace),
                ],
              ),
            if (_busy) ...<Widget>[
              const SizedBox(height: 18),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: TvTokens.gold),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _key(String label,
      {required VoidCallback onSelect, bool autofocus = false}) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused ? TvTokens.gold : TvTokens.sel;
        final Color fg = focused ? const Color(0xFF1A1206) : TvTokens.text;
        return Container(
          width: 64,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: fg)),
        );
      },
    );
  }
}
