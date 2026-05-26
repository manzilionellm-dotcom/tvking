// =========================================================
//  admin_dashboard_screen.dart — Console admin in-app
// =========================================================
//  Permet à l'admin (toi) de gérer ses clients SANS éditer le
//  gist GitHub à la main :
//
//    - Setup : pose le PAT GitHub + l'ID gist (une seule fois)
//    - Liste : tous les clients avec leur MAC + nom + nb playlists
//    - Add  : bouton "+ Nouveau client" → ouvre le sheet de création
//    - Edit : tap sur un client → ouvre le sheet pré-rempli
//    - Delete : long-press sur un client → confirmation puis suppression
//    - Refresh : bouton refresh → re-fetch le gist (au cas où
//      modifié depuis un autre appareil)
//
//  Tous les écrits passent par GistRepository.write() qui
//  reconstruit le JSON et le push sur GitHub via API authentifiée.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/admin_client.dart';
import '../data/admin_credentials.dart';
import '../data/backend_repository.dart';
import 'admin_client_edit_sheet.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<AdminClient> _clients = <AdminClient>[];
  bool _loading = false;
  String? _error;

  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _secretCtrl = TextEditingController();

  /// Quand la connexion Worker est configurée (URL + secret), on
  /// replie la carte de setup pour ne plus voir que la liste des
  /// clients + le FAB. L'utilisateur peut ré-ouvrir via le bouton
  /// "Modifier" du badge "Connecté".
  bool _setupExpanded = false;

  @override
  void initState() {
    super.initState();
    final AdminCredentials cred = AdminCredentials.instance;
    _urlCtrl.text = cred.workerUrl ?? '';
    _secretCtrl.text = cred.adminSecret ?? '';

    _setupExpanded = !cred.canWrite;
    if (cred.canWrite) {
      _load();
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final AdminCredentials cred = AdminCredentials.instance;
    if (!cred.canWrite) {
      setState(() => _error = 'URL serveur ou secret admin manquant.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final BackendReadResult result = await BackendRepository.read(
        baseUrl: cred.workerUrl!,
        adminSecret: cred.adminSecret!,
      );
      if (!mounted) return;
      setState(() {
        _clients = result.clients;
        _loading = false;
      });
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erreur : $e';
        _loading = false;
      });
    }
  }

  Future<void> _saveCredentials() async {
    if (_urlCtrl.text.trim().isEmpty || _secretCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.live,
          content: Text(
            'URL et secret obligatoires.',
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
      return;
    }
    await AdminCredentials.instance.setWorkerUrl(_urlCtrl.text);
    await AdminCredentials.instance.setAdminSecret(_secretCtrl.text);
    if (!mounted) return;
    setState(() => _setupExpanded = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Serveur configuré. Tu peux maintenant ajouter des clients.',
          style: AppTextStyles.bodyMedium,
        ),
      ),
    );
    await _load();
  }

  Future<void> _pushUpsert(AdminClient client) async {
    final AdminCredentials cred = AdminCredentials.instance;
    if (!cred.canWrite) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.live,
          content: Text(
            'Configure d\'abord URL serveur + secret admin.',
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await BackendRepository.upsert(
        baseUrl: cred.workerUrl!,
        adminSecret: cred.adminSecret!,
        client: client,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Client enregistré. Visible côté client à sa prochaine sync.',
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
      await _load();
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.live,
          content: Text(e.message, style: AppTextStyles.bodyMedium),
        ),
      );
    }
  }

  Future<void> _pushDelete(String mac) async {
    final AdminCredentials cred = AdminCredentials.instance;
    if (!cred.canWrite) return;
    setState(() => _loading = true);
    try {
      await BackendRepository.delete(
        baseUrl: cred.workerUrl!,
        adminSecret: cred.adminSecret!,
        mac: mac,
      );
      if (!mounted) return;
      await _load();
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.live,
          content: Text(e.message, style: AppTextStyles.bodyMedium),
        ),
      );
    }
  }

  Future<void> _addClient() async {
    final AdminClient? created = await showModalBottomSheet<AdminClient>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AdminClientEditSheet(),
    );
    if (created == null) return;

    if (_clients.any((AdminClient c) => c.mac == created.mac)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.warning,
          content: Text(
            'Un client avec cette MAC existe déjà. '
            'Modifie-le au lieu d\'en créer un nouveau.',
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
      return;
    }
    await _pushUpsert(created);
  }

  Future<void> _editClient(AdminClient existing) async {
    final AdminClient? edited = await showModalBottomSheet<AdminClient>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AdminClientEditSheet(existing: existing),
    );
    if (edited == null) return;
    await _pushUpsert(edited);
  }

  Future<void> _deleteClient(AdminClient target) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Supprimer ce client ?'),
        content: Text(
          'La MAC ${target.mac} ne recevra plus de playlist. '
          'L\'app cliente videra ses chaînes à la prochaine sync.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.live),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _pushDelete(target.mac);
  }

  Future<void> _copyMac(String mac) async {
    await Clipboard.setData(ClipboardData(text: mac));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('MAC copiée : $mac',
            style: AppTextStyles.bodyMedium),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AdminCredentials cred = AdminCredentials.instance;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Admin'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Recharger',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: cred,
        builder: (BuildContext context, _) {
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: <Widget>[
              _credentialsCard(),
              const SizedBox(height: 18),
              _clientsHeader(cred),
              const SizedBox(height: 10),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_error != null)
                _errorBlock(_error!)
              else if (_clients.isEmpty && cred.hasGistId)
                _emptyBlock()
              else
                ..._clients.map(_clientTile),
            ],
          );
        },
      ),
      floatingActionButton: AdminCredentials.instance.canWrite
          ? FloatingActionButton.extended(
              onPressed: _loading ? null : _addClient,
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.voidSurface,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Nouveau client',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : null,
    );
  }

  // ============================================================
  //  Sections
  // ============================================================

  Widget _credentialsCard() {
    final AdminCredentials cred = AdminCredentials.instance;
    final bool collapsed = !_setupExpanded && cred.canWrite;
    if (collapsed) return _collapsedCredentials(cred);
    return _expandedCredentials();
  }

  /// Carte mini quand tout est OK : badge "✓ Connecté" + bouton modifier.
  Widget _collapsedCredentials(AdminCredentials cred) {
    final Uri? uri = Uri.tryParse(cred.workerUrl ?? '');
    final String host = uri?.host ?? cred.workerUrl ?? '';
    final String displayHost =
        host.length > 32 ? '${host.substring(0, 30)}…' : host;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Serveur connecté',
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  displayHost,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _setupExpanded = true),
            child: const Text('Modifier'),
          ),
        ],
      ),
    );
  }

  /// Carte complète avec les 2 champs — visible quand pas encore
  /// configuré OU quand l'admin tape "Modifier".
  Widget _expandedCredentials() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.dns_rounded,
                  color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              Text('Connexion serveur',
                  style: AppTextStyles.headlineMedium
                      .copyWith(fontSize: 15)),
              const Spacer(),
              if (AdminCredentials.instance.canWrite)
                TextButton(
                  onPressed: () =>
                      setState(() => _setupExpanded = false),
                  child: const Text('Replier'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Setup une seule fois. Déploie ton mini-backend Cloudflare '
            '(15 min, voir cloudflare/README.md), puis colle l\'URL + '
            'ton secret admin ci-dessous.',
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 12,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          _label('URL du serveur'),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'https://seven-motion-backend.X.workers.dev',
            ),
          ),
          const SizedBox(height: 10),
          _label('Secret admin'),
          TextField(
            controller: _secretCtrl,
            obscureText: true,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'Celui défini avec `wrangler secret put ADMIN_SECRET`',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Pas encore déployé ? Suis cloudflare/README.md dans le '
            'repo. Cloudflare Worker est gratuit jusqu\'à 100k req/jour.',
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 11,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saveCredentials,
              child: const Text('Enregistrer et tester'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _clientsHeader(AdminCredentials cred) {
    return Row(
      children: <Widget>[
        Text(
          'CLIENTS',
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${_clients.length}',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _clientTile(AdminClient client) {
    final String displayName = client.name.isNotEmpty
        ? client.name
        : 'Sans nom';
    final int count = client.playlists.length;
    final AdminPlaylist? first =
        client.playlists.isNotEmpty ? client.playlists.first : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _editClient(client),
          onLongPress: () => _deleteClient(client),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                // Pastille avec initiale du nom
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    displayName.substring(0, 1).toUpperCase(),
                    style: AppTextStyles.headlineMedium.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        displayName,
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      GestureDetector(
                        onTap: () => _copyMac(client.mac),
                        child: Text(
                          client.mac,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        first == null
                            ? '$count playlist'
                            : '$count playlist · ${first.type.toUpperCase()} · ${first.name}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyBlock() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(alpha: 0.15),
            ),
            child: Icon(Icons.person_add_alt_1_rounded,
                size: 32, color: AppColors.accent),
          ),
          const SizedBox(height: 14),
          Text(
            'Aucun client pour l\'instant',
            style: AppTextStyles.headlineMedium.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Tape sur le bouton ci-dessous, colle la MAC que ton client '
            't\'a envoyée + son URL M3U. C\'est tout.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 12,
              color: AppColors.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _loading ? null : _addClient,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Ajouter mon premier client',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBlock(String msg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.live.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.live.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline_rounded,
              color: AppColors.live, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg, style: AppTextStyles.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          t,
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textSecondary,
            fontSize: 10,
            letterSpacing: 1.2,
          ),
        ),
      );
}
