// =========================================================
//  xtream_login_form.dart — Formulaire de connexion Xtream / M3U
// =========================================================
//  Le CŒUR de la connexion, réutilisé à deux endroits :
//    1. l'écran d'activation (bouton « J'ai un code Xtream ») ;
//    2. la feuille `xtream_login_sheet.dart`.
//
//  Deux modes au choix via un sélecteur (même pattern que la feuille
//  « Source perso » m3u_login_sheet.dart) :
//    - Xtream (défaut) : le LIEN du serveur + IDENTIFIANT + MOT DE
//      PASSE (Xtream Codes) ;
//    - M3U : on colle DIRECTEMENT le lien M3U/M3U8 donné par le
//      revendeur — un seul champ, chargement immédiat.
//
//  Conforme AGENTS.md règle n°2 : aucune URL de flux n'est écrite EN
//  DUR dans le code — c'est l'utilisateur qui fournit la sienne.
//  Aucune dépendance au cast.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/update/build_flags.dart';
import '../../../demo/data/demo_mode.dart';
import '../../data/import_progress.dart';
import '../../data/playlist_repository.dart';
import '../../data/source_link_utils.dart';
import '../../domain/playlist.dart';
import '../import_progress_screen.dart';

class XtreamLoginForm extends StatefulWidget {
  const XtreamLoginForm({
    super.key,
    this.onConnected,
    this.showCancel = false,
  });

  /// Appelé après une connexion RÉUSSIE. La feuille s'en sert pour se
  /// fermer ; l'accueil le laisse `null` (il se reconstruit tout seul
  /// dès que le flux de chaînes émet la nouvelle playlist).
  final VoidCallback? onConnected;

  /// Affiche un bouton « Annuler » (utile dans la feuille, inutile sur
  /// l'écran d'accueil vide où il n'y a rien à annuler).
  final bool showCancel;

  @override
  State<XtreamLoginForm> createState() => _XtreamLoginFormState();
}

class _XtreamLoginFormState extends State<XtreamLoginForm> {
  final TextEditingController _serverCtrl = TextEditingController();
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _m3uCtrl = TextEditingController();

  /// 'xtream' (défaut : le flux revendeur classique) ou 'm3u' (on colle
  /// directement le lien M3U).
  String _mode = 'xtream';

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _m3uCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // On capture le messenger AVANT le `await` (le contexte peut être
    // démonté si le parent — une feuille — se ferme via onConnected).
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    // ----- Accès examinateur (Google Play) : le code AVANT tout réseau -----
    // Le relecteur tape [kReviewAccessCode] comme identifiant (ou comme lien
    // M3U) : on entre en Mode démo — bouquet fictif embarqué dans l'APK,
    // aucun appel serveur, aucune activation revendeur. Conforme AGENTS.md
    // règle n°2 : ce chemin ne charge AUCUNE URL de flux, uniquement la démo.
    // BUILD APP STORE iOS : pas de code examinateur ni de bouquet démo —
    // le playbook iOS (docs/ios-app-store-playbook.md) interdit tout
    // contenu préchargé dans le binaire ; le reviewer Apple reçoit une
    // M3U libre et légale dans les notes de review, jamais dans l'app.
    final String maybeCode =
        (_mode == 'm3u' ? _m3uCtrl.text : _userCtrl.text).trim().toUpperCase();
    if (!kIsIosStoreBuild && maybeCode == kReviewAccessCode) {
      setState(() {
        _busy = true;
        _error = null;
      });
      await DemoMode.instance.enter();
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            context.l10n.loginConnected,
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
      widget.onConnected?.call();
      return;
    }

    // ----- Mode M3U : un seul champ, le lien direct -----
    if (_mode == 'm3u') {
      // On accepte le lien même sans « http:// » tapé (le revendeur
      // donne parfois juste le domaine) — on le complète.
      final String url = SourceLinkUtils.ensureScheme(_m3uCtrl.text);
      if (url.isEmpty) {
        setState(() => _error = context.l10n.loginInvalidUrl);
        return;
      }
      // « Smart » : si get.php est refusé (503, signatures bloquées)
      // mais que le lien porte des identifiants Xtream, le MÊME compte
      // est importé via l'API player_api — comme IBO/Smarters.
      await _run(
          messenger,
          (ImportProgressCallback op) => PlaylistRepository.instance
              .addM3uPlaylistSmart(
                  name: context.l10n.playlistDefaultSubscription, url: url, onProgress: op));
      return;
    }

    // ----- Mode Xtream : serveur + identifiant + mot de passe -----
    String server = SourceLinkUtils.ensureScheme(_serverCtrl.text);
    String user = _userCtrl.text.trim();
    String pass = _passCtrl.text.trim();

    // Beaucoup de fournisseurs ne donnent qu'UN SEUL lien complet (celui
    // pour VLC/Smarters) au lieu de 3 informations séparées. Si c'est ce
    // qui a été collé dans le champ « serveur » et que utilisateur/mot de
    // passe sont vides, on les en extrait tout seul.
    if (user.isEmpty || pass.isEmpty) {
      final ({String server, String username, String password})? extracted =
          SourceLinkUtils.tryExtractXtreamCredentials(_serverCtrl.text);
      if (extracted != null) {
        server = extracted.server;
        user = user.isEmpty ? extracted.username : user;
        pass = pass.isEmpty ? extracted.password : pass;
      }
    }

    if (server.isEmpty) {
      setState(() => _error = context.l10n.loginServerRequired);
      return;
    }
    if (user.isEmpty || pass.isEmpty) {
      setState(() => _error = context.l10n.loginCredsRequired);
      return;
    }
    await _run(
        messenger,
        (ImportProgressCallback op) =>
            PlaylistRepository.instance.addXtreamPlaylist(
              name: context.l10n.playlistDefaultSubscription,
              serverUrl: server,
              username: user,
              password: pass,
              onProgress: op,
            ));
  }

  /// Exécute l'ajout (M3U ou Xtream) via le plein-écran d'import VIVANT
  /// (barre + compteur de chaînes + chrono) au lieu d'un spinner figé.
  Future<void> _run(
    ScaffoldMessengerState messenger,
    Future<Playlist> Function(ImportProgressCallback onProgress) task,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ImportOutcome<Playlist> outcome =
        await runImportWithProgress<Playlist>(
      context,
      title: 'IMPORT DE TA SOURCE',
      task: task,
    );
    if (!mounted) return;

    if (!outcome.ok) {
      final Object? e = outcome.error;
      setState(() {
        _busy = false;
        _error = e == null
            ? null
            : (e is Exception
                ? e.toString().replaceFirst('Exception: ', '')
                : context.l10n.errorWithMessage('$e'));
      });
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          context.l10n.loginConnected,
          style: AppTextStyles.bodyMedium,
        ),
      ),
    );
    widget.onConnected?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.vpn_key_rounded, color: AppColors.accent, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Text(context.l10n.loginTitle,
                  style: AppTextStyles.headlineLarge.copyWith(fontSize: 22)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          // BUILD APP STORE iOS : les intros classiques disent « le code
          // que ton revendeur t'a donné » — mention à éviter devant Apple
          // (5.2.3, facilitation). On affiche une phrase neutre à la place.
          kIsIosStoreBuild
              ? context.l10n.activateChannelsSectionDesc
              : (_mode == 'm3u'
                  ? context.l10n.loginM3uIntro
                  : context.l10n.loginXtreamIntro),
          style: AppTextStyles.bodyMedium.copyWith(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        // ----- Sélecteur Xtream / M3U (ajout M3U DIRECT depuis la
        // feuille de connexion — même pattern que « Source perso »).
        Row(
          children: <Widget>[
            _modeButton('Xtream', 'xtream'),
            const SizedBox(width: 10),
            _modeButton('M3U', 'm3u'),
          ],
        ),
        const SizedBox(height: 16),
        if (_mode == 'm3u') ...<Widget>[
          // Lien M3U direct : UN seul champ.
          _label(context.l10n.loginUrlM3u),
          TextField(
            controller: _m3uCtrl,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'http://serveur.com/get.php?username=…',
            ),
          ),
        ] else ...<Widget>[
          // Lien du serveur (URL).
          _label(context.l10n.loginServer),
          TextField(
            controller: _serverCtrl,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'http://exemple.com:8080',
            ),
          ),
          const SizedBox(height: 12),
          // Identifiant.
          _label(context.l10n.loginUsername),
          TextField(controller: _userCtrl, autocorrect: false),
          const SizedBox(height: 12),
          // Mot de passe.
          _label(context.l10n.loginPassword),
          TextField(
              controller: _passCtrl, obscureText: true, autocorrect: false),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.live.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.live.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.error_outline_rounded,
                    color: AppColors.live, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: AppTextStyles.bodyMedium.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded, size: 20),
            label: Text(_busy
                ? context.l10n.loginVerifying
                : context.l10n.loginLoadChannels),
          ),
        ),
        if (widget.showCancel) ...<Widget>[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Text(context.l10n.buttonCancel),
            ),
          ),
        ],
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
            letterSpacing: 1.2,
          ),
        ),
      );

  /// Bouton du sélecteur de mode (même style que m3u_login_sheet.dart).
  Widget _modeButton(String label, String value) {
    final bool selected = _mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: _busy ? null : () => setState(() => _mode = value),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.15)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.bodyLarge.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
