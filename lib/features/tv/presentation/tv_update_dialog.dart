// =========================================================
//  tv_update_dialog.dart — Mise à jour VIVANTE (cœur de l'app)
// =========================================================
//  Retour client du 21/08 : « le bouton Mise à jour n'est pas cliquable…
//  ça doit montrer que c'est la dernière version ou une recherche VRAIE,
//  pas un bouton décoratif. » La cause : l'ancien flux affichait ses
//  résultats en SnackBar (ScaffoldMessenger) — or les écrans TV n'ont pas
//  de Scaffold → rien ne s'affichait JAMAIS, le bouton semblait mort.
//
//  Ici : un dialogue premium qui VIT sous les yeux du client —
//    1. RECHERCHE : anneau doré qui tourne + « Recherche de mise à jour… »
//    2. À JOUR    : grand ✓ doré + « Tu as déjà la dernière version (x.y) »
//    3. DISPONIBLE: version proposée + « Mettre à jour » (or) / Annuler
//    4. TÉLÉCHARGE: barre de progression réelle (0 → 100 %), puis
//       l'installateur système Android prend le relais.
//    5. ERREUR    : message clair + « Réessayer ».
//
//  Réutilise UpdateService (manifeste + APK avec miroir domaine en
//  secours) — ce dialogue n'invente aucun canal, il rend le circuit
//  VISIBLE. Style aligné sur les cartes premium (showTvConfirm).
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/update/update_service.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

/// Ouvre le dialogue de mise à jour VIVANT (bouton des Réglages).
Future<void> showTvUpdateDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.86),
    // Pas de fermeture par clic-barrière pendant un téléchargement : le
    // PopScope interne gère ça proprement.
    builder: (_) => const _TvUpdateDialog(),
  );
}

enum _Phase { searching, upToDate, available, downloading, error }

class _TvUpdateDialog extends StatefulWidget {
  const _TvUpdateDialog();

  @override
  State<_TvUpdateDialog> createState() => _TvUpdateDialogState();
}

class _TvUpdateDialogState extends State<_TvUpdateDialog> {
  _Phase _phase = _Phase.searching;
  UpdateInfo? _info;
  String? _remoteVersion;
  String? _error;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _phase = _Phase.searching;
      _error = null;
    });
    final UpdateCheckResult res = await UpdateService.instance.checkDetailed();
    if (!mounted) return;
    setState(() {
      _remoteVersion = res.versionName;
      switch (res.status) {
        case UpdateAvailability.available:
          _info = res.info;
          _phase = _Phase.available;
        case UpdateAvailability.upToDate:
          _phase = _Phase.upToDate;
        case UpdateAvailability.unavailable:
          _error = null;
          _phase = _Phase.error;
      }
    });
  }

  Future<void> _install() async {
    final UpdateInfo? info = _info;
    if (info == null) return;
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
    });
    final bool ok = await UpdateService.instance.downloadAndInstall(
      info,
      onProgress: (double p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    if (ok) {
      // L'installateur système Android est ouvert par-dessus : on referme
      // notre carte, le client confirme l'installation là-bas.
      Navigator.of(context).pop();
    } else {
      setState(() {
        _phase = _Phase.error;
        _error = context.l10n.updateDownloadFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Retour pendant le téléchargement : on laisse finir (quelques
      // secondes) — fermer au milieu laisserait un APK à moitié écrit.
      canPop: _phase != _Phase.downloading,
      child: Center(
        child: Container(
          width: 560,
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rCard),
            border: Border.all(color: TvTokens.gold, width: 1.2),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: TvTokens.gold.withValues(alpha: 0.16),
                blurRadius: 44,
                spreadRadius: 2,
              ),
            ],
          ),
          // Material transparent OBLIGATOIRE : sans ancêtre Material, chaque
          // Text sort avec le double soulignement jaune (photo client).
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _body(context),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    switch (_phase) {
      case _Phase.searching:
        return <Widget>[
          const SizedBox(height: 8),
          const Center(
            child: SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: TvTokens.gold),
            ),
          ),
          const SizedBox(height: 18),
          Text(context.l10n.updateSearching,
              textAlign: TextAlign.center,
              style: TvTokens.ui(17,
                  weight: FontWeight.w600, color: TvTokens.text)),
          const SizedBox(height: 8),
        ];

      case _Phase.upToDate:
        final String? v = _remoteVersion;
        return <Widget>[
          const Icon(Icons.verified_rounded,
              size: 52, color: TvTokens.goldBright),
          const SizedBox(height: 14),
          Text(
            (v != null && v.isNotEmpty)
                ? context.l10n.updateUpToDateVersion(v)
                : context.l10n.updateUpToDate,
            textAlign: TextAlign.center,
            style: TvTokens.display(22, color: TvTokens.text),
          ),
          const SizedBox(height: 22),
          _Btn(
            label: context.l10n.buttonOk,
            primary: true,
            autofocus: true,
            onSelect: () => Navigator.of(context).pop(),
          ),
        ];

      case _Phase.available:
        final UpdateInfo info = _info!;
        return <Widget>[
          Text(context.l10n.updateAvailableTitle,
              textAlign: TextAlign.center,
              style: TvTokens.display(24, color: TvTokens.goldBright)),
          const SizedBox(height: 10),
          Text(
            info.versionName.isNotEmpty
                ? context.l10n.updateBodyVersion(info.versionName)
                : context.l10n.updateBodyGeneric,
            textAlign: TextAlign.center,
            style: TvTokens.ui(15, color: TvTokens.mutedDim),
          ),
          const SizedBox(height: 24),
          _Btn(
            label: context.l10n.updateNow,
            primary: true,
            autofocus: true,
            icon: Icons.system_update_rounded,
            onSelect: () {
              // ignore: discarded_futures
              _install();
            },
          ),
          if (!info.mandatory) ...<Widget>[
            const SizedBox(height: 10),
            _Btn(
              label: context.l10n.buttonCancel,
              onSelect: () => Navigator.of(context).pop(),
            ),
          ],
        ];

      case _Phase.downloading:
        final int pct = (_progress * 100).round();
        return <Widget>[
          Text(context.l10n.updateAvailableTitle,
              textAlign: TextAlign.center,
              style: TvTokens.display(22, color: TvTokens.text)),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              minHeight: 8,
              backgroundColor: TvTokens.sel,
              color: TvTokens.gold,
            ),
          ),
          const SizedBox(height: 12),
          Text('$pct %',
              textAlign: TextAlign.center,
              style: TvTokens.mono(18, color: TvTokens.goldBright)),
          const SizedBox(height: 6),
        ];

      case _Phase.error:
        return <Widget>[
          const Icon(Icons.cloud_off_rounded,
              size: 44, color: Color(0xFFE0746A)),
          const SizedBox(height: 12),
          Text(
            _error ?? context.l10n.updateCheckFailed,
            textAlign: TextAlign.center,
            style: TvTokens.ui(15, color: TvTokens.text),
          ),
          const SizedBox(height: 22),
          _Btn(
            label: context.l10n.buttonRetry,
            primary: true,
            autofocus: true,
            icon: Icons.refresh_rounded,
            onSelect: () {
              // Échec de TÉLÉCHARGEMENT (une MAJ était trouvée) → on
              // retente l'installation ; sinon on relance la recherche.
              if (_info != null && _error != null) {
                // ignore: discarded_futures
                _install();
              } else {
                // ignore: discarded_futures
                _search();
              }
            },
          ),
          const SizedBox(height: 10),
          _Btn(
            label: context.l10n.buttonCancel,
            onSelect: () => Navigator.of(context).pop(),
          ),
        ];
    }
  }
}

/// Bouton pill du dialogue — repos discret, focus OR PLEIN + halo chaud
/// (langage « bijou » demandé par le propriétaire).
class _Btn extends StatelessWidget {
  const _Btn({
    required this.label,
    required this.onSelect,
    this.icon,
    this.primary = false,
    this.autofocus = false,
  });
  final String label;
  final VoidCallback onSelect;
  final IconData? icon;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused
            ? TvTokens.onGold
            : (primary ? TvTokens.goldBright : TvTokens.muted);
        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: focused
                    ? TvTokens.gold
                    : (primary ? TvTokens.gold : TvTokens.line)),
            boxShadow: focused
                ? <BoxShadow>[
                    BoxShadow(
                      color: TvTokens.gold.withValues(alpha: 0.35),
                      blurRadius: 26,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 19, color: fg),
                const SizedBox(width: 9),
              ],
              Text(label,
                  style: TvTokens.ui(16, weight: FontWeight.w700, color: fg)),
            ],
          ),
        );
      },
    );
  }
}
