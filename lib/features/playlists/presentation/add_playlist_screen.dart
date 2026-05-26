// =========================================================
//  add_playlist_screen.dart — Écran d'ajout de playlist
// =========================================================
//  Écran avec 2 onglets (M3U / Xtream Codes), formulaires
//  propres, validation côté client + côté serveur, et
//  feedback visuel (loader pendant la sync, message d'erreur
//  clair en cas de problème).
//
//  À la fin d'un ajout réussi → on referme l'écran et le
//  Stream du repository fait remonter les nouvelles chaînes
//  sur HomeScreen automatiquement.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/playlist_repository.dart';
import '../domain/playlist.dart';

class AddPlaylistScreen extends StatefulWidget {
  const AddPlaylistScreen({super.key});

  @override
  State<AddPlaylistScreen> createState() => _AddPlaylistScreenState();
}

class _AddPlaylistScreenState extends State<AddPlaylistScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Formulaire M3U
  final TextEditingController _m3uNameCtrl =
      TextEditingController(text: 'Ma playlist');
  final TextEditingController _m3uUrlCtrl = TextEditingController();
  final TextEditingController _m3uEpgCtrl = TextEditingController();

  // Formulaire Xtream
  final TextEditingController _xtNameCtrl =
      TextEditingController(text: 'Mon Xtream');
  final TextEditingController _xtServerCtrl = TextEditingController();
  final TextEditingController _xtUserCtrl = TextEditingController();
  final TextEditingController _xtPassCtrl = TextEditingController();

  // Formulaire Bulk M3U
  final TextEditingController _bulkPrefixCtrl =
      TextEditingController(text: 'Playlist');
  final TextEditingController _bulkUrlsCtrl = TextEditingController();
  int _bulkProgressCurrent = 0;
  int _bulkProgressTotal = 0;
  List<BatchImportResult> _bulkResults = <BatchImportResult>[];

  bool _busy = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _m3uNameCtrl.dispose();
    _m3uUrlCtrl.dispose();
    _m3uEpgCtrl.dispose();
    _xtNameCtrl.dispose();
    _xtServerCtrl.dispose();
    _xtUserCtrl.dispose();
    _xtPassCtrl.dispose();
    _bulkPrefixCtrl.dispose();
    _bulkUrlsCtrl.dispose();
    super.dispose();
  }

  // ============================================================
  //  Soumissions
  // ============================================================

  Future<void> _submitM3u() async {
    final String name = _m3uNameCtrl.text.trim();
    final String url = _m3uUrlCtrl.text.trim();
    final String epgUrl = _m3uEpgCtrl.text.trim();

    if (name.isEmpty) {
      _setError('Donne un nom à ta playlist (ex : "Mon abonnement").');
      return;
    }
    if (url.isEmpty || (!url.startsWith('http://') && !url.startsWith('https://'))) {
      _setError('URL invalide. Elle doit commencer par http:// ou https://');
      return;
    }
    if (epgUrl.isNotEmpty &&
        !epgUrl.startsWith('http://') &&
        !epgUrl.startsWith('https://')) {
      _setError(
          'URL EPG invalide. Laisse vide si tu n\'en as pas, ou commence par http(s)://');
      return;
    }

    _setBusy(true);
    try {
      final Playlist saved = await PlaylistRepository.instance.addM3uPlaylist(
        name: name,
        url: url,
        epgUrl: epgUrl.isEmpty ? null : epgUrl,
      );
      if (!mounted) return;
      _onSuccess(saved);
    } on Exception catch (e) {
      _setError(_humanReadable(e));
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _submitBulk() async {
    final String prefix = _bulkPrefixCtrl.text.trim();
    final String raw = _bulkUrlsCtrl.text;

    if (prefix.isEmpty) {
      _setError('Donne un préfixe (ex: "Mes playlists").');
      return;
    }

    // Extraction des URLs : une par ligne, vide ignorée
    final List<String> urls = raw
        .split('\n')
        .map((String l) => l.trim())
        .where((String l) =>
            l.isNotEmpty &&
            (l.startsWith('http://') || l.startsWith('https://')))
        .toList();

    if (urls.isEmpty) {
      _setError(
        'Colle une URL par ligne (chacune doit commencer par http:// ou https://).',
      );
      return;
    }
    if (urls.length > 10) {
      _setError(
        'Max 10 URLs à la fois (tu en as ${urls.length}). Découpe en plusieurs lots.',
      );
      return;
    }

    final List<({String name, String url})> entries = <({String name, String url})>[
      for (int i = 0; i < urls.length; i++)
        (name: '$prefix #${i + 1}', url: urls[i]),
    ];

    _setBusy(true);
    setState(() {
      _bulkProgressCurrent = 0;
      _bulkProgressTotal = entries.length;
      _bulkResults = <BatchImportResult>[];
    });

    final List<BatchImportResult> results =
        await PlaylistRepository.instance.addM3uPlaylistsBatch(
      entries: entries,
      onProgress: (int index, int total, String name, BatchImportResult? r) {
        if (!mounted) return;
        setState(() {
          _bulkProgressCurrent = index;
          _bulkProgressTotal = total;
          if (r != null) _bulkResults = <BatchImportResult>[..._bulkResults, r];
        });
      },
    );

    _setBusy(false);

    final int ok = results.where((BatchImportResult r) => r.ok).length;
    final int fail = results.where((BatchImportResult r) => !r.ok).length;

    if (!mounted) return;
    if (ok > 0 && fail == 0) {
      // Toutes les playlists ont marché → on ferme
      Navigator.of(context).pop();
    } else if (ok == 0) {
      _setError('Aucune playlist n\'a pu être importée. Vérifie les URLs.');
    } else {
      _setError(
        '$ok importée(s), $fail en erreur. Tu peux fermer ou réessayer.',
      );
    }
  }

  Future<void> _submitXtream() async {
    final String name = _xtNameCtrl.text.trim();
    final String server = _xtServerCtrl.text.trim();
    final String user = _xtUserCtrl.text.trim();
    final String pass = _xtPassCtrl.text;

    if (name.isEmpty) {
      _setError('Donne un nom à ta playlist (ex : "Mon Xtream").');
      return;
    }
    if (server.isEmpty || (!server.startsWith('http://') && !server.startsWith('https://'))) {
      _setError(
        'Serveur invalide. Format attendu : http://server.com:8080',
      );
      return;
    }
    if (user.isEmpty || pass.isEmpty) {
      _setError('Username et mot de passe sont obligatoires.');
      return;
    }

    _setBusy(true);
    try {
      final Playlist saved =
          await PlaylistRepository.instance.addXtreamPlaylist(
        name: name,
        serverUrl: server,
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
    // On retire le préfixe "Exception:" pour un message plus propre.
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
        title: const Text('Ajouter une playlist'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.accentPink,
          labelColor: AppColors.accentPink,
          unselectedLabelColor: Colors.white60,
          tabs: const <Widget>[
            Tab(text: 'M3U / URL'),
            Tab(text: 'Xtream Codes'),
            Tab(text: 'M3U en lot'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: <Widget>[
            _buildM3uForm(),
            _buildXtreamForm(),
            _buildBulkForm(),
          ],
        ),
      ),
    );
  }

  Widget _buildM3uForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _intro(
            'Colle l\'URL de ton fichier .m3u ou .m3u8.\n'
            'Ton fournisseur IPTV te la donne (souvent un lien type '
            'http://serveur.com/get.php?username=X&password=Y).',
          ),
          const SizedBox(height: 24),
          _label('Nom de la playlist'),
          _textField(
            controller: _m3uNameCtrl,
            hint: 'Mon abonnement',
            icon: Icons.label_outline,
          ),
          const SizedBox(height: 16),
          _label('URL de la playlist M3U'),
          _textField(
            controller: _m3uUrlCtrl,
            hint: 'http://serveur.com/get.php?username=...',
            icon: Icons.link,
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          _label('URL EPG XMLTV (optionnel)'),
          _textField(
            controller: _m3uEpgCtrl,
            hint: 'http://serveur.com/xmltv.php?username=...',
            icon: Icons.event_note_rounded,
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Optionnel · Active le guide TV et les programmes en cours.',
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (_errorMessage != null) _errorBanner(_errorMessage!),
          const SizedBox(height: 8),
          _primaryButton(
            label: _busy ? 'Téléchargement en cours...' : 'Charger la playlist',
            icon: _busy ? null : Icons.download_rounded,
            onPressed: _busy ? null : _submitM3u,
          ),
        ],
      ),
    );
  }

  Widget _buildXtreamForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _intro(
            'Renseigne les 3 infos que ton fournisseur t\'a données : '
            'l\'URL du serveur (avec le port), ton identifiant et ton mot de passe. '
            'On vérifie les identifiants avant de tout télécharger.',
          ),
          const SizedBox(height: 24),
          _label('Nom de la playlist'),
          _textField(
            controller: _xtNameCtrl,
            hint: 'Mon Xtream',
            icon: Icons.label_outline,
          ),
          const SizedBox(height: 16),
          _label('Serveur'),
          _textField(
            controller: _xtServerCtrl,
            hint: 'http://serveur.com:8080',
            icon: Icons.dns_rounded,
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          _label('Username'),
          _textField(
            controller: _xtUserCtrl,
            hint: 'identifiant',
            icon: Icons.person_outline,
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          _label('Mot de passe'),
          _textField(
            controller: _xtPassCtrl,
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
            onPressed: _busy ? null : _submitXtream,
          ),
        ],
      ),
    );
  }

  Widget _buildBulkForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _intro(
            'Colle jusqu\'à 10 URLs M3U d\'un coup, une par ligne. '
            'L\'app va les télécharger en série et créer une playlist '
            'séparée pour chacune (renommée "Préfixe #1", "Préfixe #2"...).',
          ),
          const SizedBox(height: 24),
          _label('Préfixe des noms'),
          _textField(
            controller: _bulkPrefixCtrl,
            hint: 'Mes playlists',
            icon: Icons.label_outline,
          ),
          const SizedBox(height: 16),
          _label('URLs M3U (une par ligne, max 10)'),
          TextField(
            controller: _bulkUrlsCtrl,
            enabled: !_busy,
            keyboardType: TextInputType.multiline,
            maxLines: 8,
            minLines: 4,
            autocorrect: false,
            style: AppTextStyles.bodyLarge.copyWith(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'http://serveur1.com/get.php?...\n'
                  'http://serveur2.com/playlist.m3u\n'
                  'https://example.com/list.m3u8',
              hintStyle: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
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
          ),
          const SizedBox(height: 18),

          // Barre de progression pendant l'import
          if (_busy && _bulkProgressTotal > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Import : $_bulkProgressCurrent / $_bulkProgressTotal',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.accentCyan,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _bulkProgressTotal == 0
                          ? null
                          : _bulkProgressCurrent / _bulkProgressTotal,
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.accentPink),
                    ),
                  ),
                ],
              ),
            ),

          // Résultats individuels
          if (_bulkResults.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: _bulkResults
                    .map((BatchImportResult r) => _bulkResultLine(r))
                    .toList(),
              ),
            ),

          if (_errorMessage != null) _errorBanner(_errorMessage!),
          const SizedBox(height: 8),
          _primaryButton(
            label: _busy
                ? 'Import en cours...'
                : 'Importer toutes les playlists',
            icon: _busy ? null : Icons.cloud_download_rounded,
            onPressed: _busy ? null : _submitBulk,
          ),
        ],
      ),
    );
  }

  Widget _bulkResultLine(BatchImportResult r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Icon(
            r.ok ? Icons.check_circle : Icons.cancel,
            color: r.ok ? AppColors.success : AppColors.live,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              r.ok
                  ? '${r.name} — ${r.channelCount} chaînes'
                  : '${r.name} — ${r.error ?? "échec"}',
              style: AppTextStyles.bodyMedium.copyWith(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
