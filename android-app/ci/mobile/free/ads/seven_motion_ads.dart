import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// L'emplacement est réservé aux réglages de 7 MOTION. Aucun identifiant
/// utilisateur, URL de playlist ou renseignement sur la lecture ne le traverse.
class SevenMotionAdsBanner extends StatefulWidget {
  const SevenMotionAdsBanner({super.key, this.enabled = true});

  final bool enabled;

  @override
  State<SevenMotionAdsBanner> createState() => _SevenMotionAdsBannerState();
}

class _SevenMotionAdsBannerState extends State<SevenMotionAdsBanner> {
  static const _channel = MethodChannel('7motion/admob');
  bool _requested = false;
  bool _showAd = false;
  bool _showPrivacy = false;
  bool _busy = false;

  Future<void> _update(String method) async {
    if (!mounted || _busy) return;
    // Retirer l'ancienne vue avant de présenter les choix de confidentialité.
    setState(() {
      _busy = true;
      _showAd = false;
    });
    Map<Object?, Object?>? state;
    try {
      state = await _channel.invokeMapMethod<Object?, Object?>(method);
    } on MissingPluginException {
      // La variante sans identifiants AdMob ne contient pas le pont Android.
    } on PlatformException {
      // Une indisponibilité de la publicité ne bloque jamais les réglages.
    }
    if (!mounted) return;
    setState(() {
      _showAd = state?['banner'] == true;
      _showPrivacy = state?['privacy'] == true;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        !(ModalRoute.isCurrentOf(context) ?? true)) {
      return const SizedBox.shrink();
    }
    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.enabled &&
            (ModalRoute.isCurrentOf(context) ?? true)) {
          _update('prepare');
        } else {
          _requested = false;
        }
      });
    }
    if (!_showPrivacy && !_showAd) return const SizedBox.shrink();

    // Le format Google BANNER mesure 320 x 50 dp. Dans une fenêtre plus
    // étroite, garder l'accès aux choix privés et ne pas charger de publicité.
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitsAd = _showAd && constraints.maxWidth >= 320;
        if (!fitsAd && !_showPrivacy) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (fitsAd)
                const SizedBox(
                  width: 320,
                  height: 50,
                  child: AndroidView(viewType: '7motion/admob/banner'),
                ),
              if (_showPrivacy)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextButton(
                    onPressed: _busy ? null : () => _update('privacy'),
                    child: Text(
                      _privacyLabel(
                        Localizations.localeOf(context).languageCode,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _privacyLabel(String language) => switch (language) {
    'fr' => 'Confidentialité des annonces',
    'de' => 'Datenschutz für Anzeigen',
    'sv' => 'Annonsintegritet',
    'pl' => 'Prywatność reklam',
    'es' => 'Privacidad de los anuncios',
    'pt' => 'Privacidade dos anúncios',
    'it' => 'Privacy degli annunci',
    'nl' => 'Advertentieprivacy',
    'tr' => 'Reklam gizliliği',
    'ar' => 'خصوصية الإعلانات',
    'so' => 'Asturnaanta xayeysiisyada',
    _ => 'Ad privacy options',
  };
}
