// =========================================================
//  xtream_login_form.dart — Formulaire de connexion Xtream
// =========================================================
//  Le CŒUR de la connexion Xtream, réutilisé à deux endroits :
//    1. l'écran d'activation (bouton « J'ai un code Xtream ») ;
//    2. la feuille `xtream_login_sheet.dart`.
//
//  Le client saisit LUI-MÊME ses 3 informations Xtream Codes :
//    - le LIEN du serveur (URL) ;
//    - son IDENTIFIANT ;
//    - son MOT DE PASSE.
//
//  Pas de M3U. Conforme AGENTS.md règle n°2 : aucune URL de flux n'est
//  écrite EN DUR dans le code — c'est l'utilisateur qui fournit la sienne.
//  Aucune dépendance au cast.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/playlist_repository.dart';
import '../../data/source_link_utils.dart';

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

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // On capture le messenger AVANT le `await` (le contexte peut être
    // démonté si le parent — une feuille — se ferme via onConnected).
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PlaylistRepository.instance.addXtreamPlaylist(
        // Nom par défaut localisé — figé à la création comme tout nom
        // de playlist (le champ est libre côté données).
        name: context.l10n.playlistDefaultSubscription,
        serverUrl: server,
        username: user,
        password: pass,
      );
      if (!mounted) return;
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
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.l10n.errorWithMessage('$e');
      });
    }
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
          context.l10n.loginXtreamIntro,
          style: AppTextStyles.bodyMedium.copyWith(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
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
        TextField(controller: _passCtrl, obscureText: true, autocorrect: false),
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
}
