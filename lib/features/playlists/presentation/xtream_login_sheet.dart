// =========================================================
//  xtream_login_sheet.dart — Connexion Xtream côté client
// =========================================================
//  Bottom sheet de connexion. Le client NE saisit PLUS d'URL de
//  serveur : conformément à AGENTS.md règle n°2, aucune URL de flux
//  IPTV n'est en dur dans l'app. À la place, on récupère les
//  serveurs proposés (« Serveur 1 », « Serveur 2 »…) depuis le
//  Worker via `GET /api/servers` (cf. default_servers.dart) et le
//  client n'a qu'à :
//    1. choisir un serveur,
//    2. saisir son CODE Xtream (utilisateur + mot de passe).
//
//  L'URL réelle reste cachée et peut être changée côté serveur sans
//  re-publier l'app.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/default_servers.dart';
import '../data/playlist_repository.dart';

Future<void> showXtreamLoginSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _XtreamLoginSheet(),
  );
}

class _XtreamLoginSheet extends StatefulWidget {
  const _XtreamLoginSheet();

  @override
  State<_XtreamLoginSheet> createState() => _XtreamLoginSheetState();
}

class _XtreamLoginSheetState extends State<_XtreamLoginSheet> {
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();

  /// Serveurs proposés (chargés depuis le Worker). `null` = en cours
  /// de chargement, liste vide = aucun serveur configuré / réseau KO.
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
    final DefaultServer? server = _selectedServer;
    final String user = _userCtrl.text.trim();
    final String pass = _passCtrl.text.trim();

    if (server == null) {
      setState(() => _error = 'Choisis un serveur.');
      return;
    }
    if (user.isEmpty || pass.isEmpty) {
      setState(
          () => _error = 'Utilisateur et mot de passe sont obligatoires.');
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
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Connecté. Tes chaînes arrivent…',
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
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
        _error = 'Erreur : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Icon(Icons.vpn_key_rounded,
                        color: AppColors.accent, size: 22),
                    const SizedBox(width: 10),
                    Text('Connexion',
                        style: AppTextStyles.headlineLarge
                            .copyWith(fontSize: 22)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Choisis ton serveur puis saisis le code que t\'a '
                  'donné ton revendeur (utilisateur + mot de passe). '
                  'Tes chaînes seront chargées en quelques secondes.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                // Sélecteur affiché seulement s'il y a plusieurs serveurs
                // (ou pendant le chargement). Un seul serveur = prédéfini,
                // le client ne choisit rien.
                if (_servers == null || _servers!.length > 1) ...<Widget>[
                  _label('Serveur'),
                  _buildServerSelector(),
                  const SizedBox(height: 12),
                ],
                _label('Utilisateur'),
                TextField(
                  controller: _userCtrl,
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                _label('Mot de passe'),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  autocorrect: false,
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.live.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.live.withValues(alpha: 0.4),
                      ),
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
                            style: AppTextStyles.bodyMedium
                                .copyWith(fontSize: 12),
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
                    onPressed: (_busy || _selectedServer == null)
                        ? null
                        : _submit,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 20),
                    label:
                        Text(_busy ? 'Vérification…' : 'Charger mes chaînes'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Annuler'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Sélecteur de serveur. Affiche les libellés (« Serveur 1 »…) —
  /// jamais les URLs. Trois états : chargement, vide (réseau KO ou
  /// aucun serveur configuré côté Worker), liste de choix.
  Widget _buildServerSelector() {
    final List<DefaultServer>? servers = _servers;

    if (servers == null) {
      // Chargement en cours.
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
              'Chargement des serveurs…',
              style: AppTextStyles.bodyMedium.copyWith(fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (servers.isEmpty) {
      // Aucun serveur dispo (réseau KO au 1er lancement, ou rien de
      // configuré côté Worker). On propose de réessayer.
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
              'Serveurs indisponibles pour le moment.',
              style: AppTextStyles.bodyMedium.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                setState(() => _servers = null);
                _loadServers();
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }

    // Liste de choix (RadioListTile pour le tactile + télécommande TV).
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12),
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
