// =========================================================
//  add_playlist_screen.dart — Connexion client (Xtream)
// =========================================================
//  Écran de connexion simplifié. Le client NE saisit plus d'URL
//  (ni M3U, ni serveur Xtream libre) : conformément à AGENTS.md
//  règle n°2, aucune URL de flux IPTV n'est en dur dans l'app.
//
//  À la place :
//    1. il choisit un serveur (« Serveur 1 », « Serveur 2 »…),
//       récupéré depuis le Worker via `GET /api/servers`
//       (cf. default_servers.dart) — l'URL reste cachée ;
//    2. il saisit son CODE Xtream (utilisateur + mot de passe).
//
//  Les anciens onglets « M3U / URL », « M3U en lot » et le champ
//  serveur libre ont été retirés : le client n'a plus aucun chemin
//  pour taper une URL lui-même.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/legal_disclaimer.dart';
import '../data/default_servers.dart';
import '../data/playlist_repository.dart';
import '../domain/playlist.dart';

class AddPlaylistScreen extends StatefulWidget {
  const AddPlaylistScreen({super.key});

  @override
  State<AddPlaylistScreen> createState() => _AddPlaylistScreenState();
}

class _AddPlaylistScreenState extends State<AddPlaylistScreen> {
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();

  /// Serveurs proposés (chargés depuis le Worker). `null` = en cours
  /// de chargement, liste vide = aucun serveur dispo / réseau KO.
  List<DefaultServer>? _servers;

  /// Identifiant du serveur sélectionné (par défaut le premier).
  String? _selectedServerId;

  bool _busy = false;
  String? _errorMessage;

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

  // ============================================================
  //  Soumission
  // ============================================================

  Future<void> _submit() async {
    final DefaultServer? server = _selectedServer;
    final String user = _userCtrl.text.trim();
    final String pass = _passCtrl.text;

    if (server == null) {
      _setError('Choisis un serveur.');
      return;
    }
    if (user.isEmpty || pass.isEmpty) {
      _setError('Utilisateur et mot de passe sont obligatoires.');
      return;
    }

    _setBusy(true);
    try {
      final Playlist saved =
          await PlaylistRepository.instance.addXtreamPlaylist(
        // Nom interne = libellé du serveur (le client n'a rien à nommer).
        name: server.label,
        serverUrl: server.url,
        username: user,
        password: pass,
      );
      if (!mounted) return;
      _onSuccess(saved);
    } on Exception catch (e) {
      _setError(_humanReadable(e));
    } finally {
      _setBusy(false);
    }
  }

  void _onSuccess(Playlist saved) {
    Navigator.of(context).pop<Playlist>(saved);
  }

  void _setBusy(bool busy) {
    if (!mounted) return;
    setState(() {
      _busy = busy;
      if (busy) _errorMessage = null;
    });
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
  }

  String _humanReadable(Object error) {
    final String raw = error.toString();
    return raw.startsWith('Exception: ')
        ? raw.substring('Exception: '.length)
        : raw;
  }

  // ============================================================
  //  UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Connexion'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const LegalDisclaimer.compact(),
              const SizedBox(height: 16),
              _intro(
                'Choisis ton serveur, puis saisis le code que t\'a donné '
                'ton revendeur (utilisateur + mot de passe). On vérifie '
                'le code avant de charger tes chaînes.',
              ),
              const SizedBox(height: 24),
              _label('Serveur'),
              _buildServerSelector(),
              const SizedBox(height: 16),
              _label('Utilisateur'),
              _textField(
                controller: _userCtrl,
                hint: 'identifiant',
                icon: Icons.person_outline,
                autocorrect: false,
              ),
              const SizedBox(height: 16),
              _label('Mot de passe'),
              _textField(
                controller: _passCtrl,
                hint: 'mot de passe',
                icon: Icons.lock_outline,
                obscureText: true,
                autocorrect: false,
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null) _errorBanner(_errorMessage!),
              const SizedBox(height: 8),
              _primaryButton(
                label: _busy
                    ? 'Connexion au serveur...'
                    : 'Se connecter et charger',
                icon: _busy ? null : Icons.cloud_download_rounded,
                onPressed:
                    (_busy || _selectedServer == null) ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sélecteur de serveur. N'affiche QUE les libellés (« Serveur 1 »…),
  /// jamais les URLs. Trois états : chargement, vide, liste de choix.
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
              'Chargement des serveurs…',
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
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
              activeColor: AppColors.accentPink,
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

  // ----- Petits composants visuels réutilisés -----

  Widget _intro(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accentCyan.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, color: AppColors.accentCyan, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyMedium.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Text(
        text,
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    bool autocorrect = true,
  }) {
    return TextField(
      controller: controller,
      enabled: !_busy,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autocorrect: autocorrect,
      style: AppTextStyles.bodyLarge,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textMuted,
        ),
        prefixIcon: Icon(icon, color: AppColors.accentCyan, size: 20),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.accentPink.withValues(alpha: 0.8),
            width: 1.6,
          ),
        ),
      ),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.live.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.live.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, color: AppColors.live, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData? icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentPink,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.accentPink.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white70,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: AppTextStyles.bodyLarge.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (_busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else if (icon != null)
              Icon(icon, size: 20),
            const SizedBox(width: 10),
            Text(label),
          ],
        ),
      ),
    );
  }
}
