// =========================================================
//  xtream_login_form.dart — Formulaire de connexion Xtream
// =========================================================
//  Le CŒUR de la connexion Xtream, extrait pour être réutilisé à
//  deux endroits :
//    1. l'écran d'accueil VIDE (mobile) — affiché directement, ouvert ;
//    2. la feuille `xtream_login_sheet.dart` (bouton « Ajouter »).
//
//  Conforme AGENTS.md règle n°2 : aucune URL de flux en dur. Les
//  serveurs proposés (« Serveur 1 »…) viennent du Worker via
//  `GET /api/servers` (cf. default_servers.dart). Le client choisit un
//  serveur (ou il est prédéfini s'il n'y en a qu'un) puis saisit son
//  CODE Xtream (identifiant + mot de passe). L'URL réelle reste cachée.
//
//  Aucune dépendance au cast.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/default_servers.dart';
import '../../data/playlist_repository.dart';

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
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();

  /// Serveurs proposés (chargés depuis le Worker). `null` = en cours de
  /// chargement, liste vide = aucun serveur configuré / réseau KO.
  List<DefaultServer>? _servers;

  /// Identifiant du serveur sélectionné (par défaut le premier).
  String? _selectedServerId;

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadServers();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadServers() async {
    final List<DefaultServer> servers = await DefaultServersApi.fetch();
    if (!mounted) return;
    setState(() {
      _servers = servers;
      _selectedServerId = servers.isNotEmpty ? servers.first.id : null;
    });
  }

  DefaultServer? get _selectedServer {
    final List<DefaultServer>? servers = _servers;
    if (servers == null || _selectedServerId == null) return null;
    for (final DefaultServer s in servers) {
      if (s.id == _selectedServerId) return s;
    }
    return null;
  }

  Future<void> _submit() async {
    // On capture le messenger AVANT le `await` (le contexte peut être
    // démonté si le parent — une feuille — se ferme via onConnected).
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final DefaultServer? server = _selectedServer;
    final String user = _userCtrl.text.trim();
    final String pass = _passCtrl.text.trim();

    if (server == null) {
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
        // Nom interne = libellé du serveur, le client n'a rien à nommer.
        name: server.label,
        serverUrl: server.url,
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
        // Sélecteur affiché seulement s'il y a plusieurs serveurs (ou
        // pendant le chargement). Un seul serveur = prédéfini, le client
        // ne choisit rien.
        if (_servers == null || _servers!.length > 1) ...<Widget>[
          _label(context.l10n.loginServer),
          _buildServerSelector(),
          const SizedBox(height: 12),
        ],
        _label(context.l10n.loginUsername),
        TextField(controller: _userCtrl, autocorrect: false),
        const SizedBox(height: 12),
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
            onPressed: (_busy || _selectedServer == null) ? null : _submit,
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

  /// Sélecteur de serveur. Affiche les libellés (« Serveur 1 »…) —
  /// jamais les URLs. Trois états : chargement, vide (réseau KO ou aucun
  /// serveur configuré côté Worker), liste de choix.
  Widget _buildServerSelector() {
    final List<DefaultServer>? servers = _servers;

    if (servers == null) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              context.l10n.loginLoadingServers,
              style: AppTextStyles.bodyMedium.copyWith(fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (servers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.l10n.loginServersUnavailable,
              style: AppTextStyles.bodyMedium.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                setState(() => _servers = null);
                _loadServers();
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(context.l10n.buttonRetry),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          for (final DefaultServer s in servers)
            RadioListTile<String>(
              value: s.id,
              groupValue: _selectedServerId,
              onChanged: _busy
                  ? null
                  : (String? v) => setState(() => _selectedServerId = v),
              activeColor: AppColors.accent,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              title: Text(
                s.label,
                style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
              ),
            ),
        ],
      ),
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
