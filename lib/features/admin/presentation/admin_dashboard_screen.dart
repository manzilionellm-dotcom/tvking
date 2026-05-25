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
import '../data/gist_repository.dart';
import 'admin_client_edit_sheet.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<AdminClient> _clients = <AdminClient>[];
  String _fileName = 'config.json';
  bool _loading = false;
  String? _error;

  final TextEditingController _patCtrl = TextEditingController();
  final TextEditingController _gistIdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final AdminCredentials cred = AdminCredentials.instance;
    _patCtrl.text = cred.pat ?? '';
    _gistIdCtrl.text = cred.gistId ?? '';
    if (cred.hasGistId) {
      _load();
    }
  }

  @override
  void dispose() {
    _patCtrl.dispose();
    _gistIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final AdminCredentials cred = AdminCredentials.instance;
    if (!cred.hasGistId) {
      setState(() => _error = 'Pas d\'ID gist configuré.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final GistReadResult result = await GistRepository.read(
        gistId: cred.gistId!,
        pat: cred.pat,
      );
      if (!mounted) return;
      setState(() {
        _clients = result.clients;
        _fileName = result.fileName;
        _loading = false;
      });
    } on GistException catch (e) {
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
    await AdminCredentials.instance.setPat(_patCtrl.text);
    await AdminCredentials.instance.setGistId(_gistIdCtrl.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Identifiants enregistrés.',
          style: AppTextStyles.bodyMedium,
        ),
      ),
    );
    await _load();
  }

  Future<void> _pushToGist(List<AdminClient> updated) async {
    final AdminCredentials cred = AdminCredentials.instance;
    if (!cred.canWrite) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.live,
          content: Text(
            'PAT GitHub manquant. Renseigne-le en haut.',
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await GistRepository.write(
        gistId: cred.gistId!,
        fileName: _fileName,
        clients: updated,
        pat: cred.pat!,
      );
      if (!mounted) return;
      setState(() {
        _clients = updated;
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Gist mis à jour. Les clients verront le changement '
            'à leur prochaine sync (max 30 min).',
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
    } on GistException catch (e) {
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

    // Vérifie qu'on n'écrase pas un client existant par erreur
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
    final List<AdminClient> updated = <AdminClient>[
      created,
      ..._clients,
    ];
    await _pushToGist(updated);
  }

  Future<void> _editClient(AdminClient existing) async {
    final AdminClient? edited = await showModalBottomSheet<AdminClient>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AdminClientEditSheet(existing: existing),
    );
    if (edited == null) return;
    final List<AdminClient> updated = _clients
        .map((AdminClient c) => c.mac == existing.mac ? edited : c)
        .toList();
    await _pushToGist(updated);
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
    final List<AdminClient> updated = _clients
        .where((AdminClient c) => c.mac != target.mac)
        .toList();
    await _pushToGist(updated);
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
              Icon(Icons.key_rounded,
                  color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              Text('Connexion GitHub',
                  style: AppTextStyles.headlineMedium
                      .copyWith(fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          _label('ID du gist'),
          TextField(
            controller: _gistIdCtrl,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'ex : abc123def456…',
            ),
          ),
          const SizedBox(height: 10),
          _label('GitHub Personal Access Token (scope `gist`)'),
          TextField(
            controller: _patCtrl,
            obscureText: true,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'ghp_xxxxxxxxxxxxxxxxxxxx',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Crée le PAT sur github.com → Settings → Developer settings → '
            'Personal access tokens → Generate new (classic) → cocher `gist`.',
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
              child: const Text('Enregistrer et charger'),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: <Widget>[
          Icon(Icons.group_outlined,
              size: 36, color: AppColors.textMuted),
          const SizedBox(height: 10),
          Text(
            'Aucun client encore.',
            style: AppTextStyles.bodyLarge.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Tape "Nouveau client" en bas pour en ajouter un.',
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 12,
              color: AppColors.textMuted,
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
