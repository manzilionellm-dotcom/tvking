// =========================================================
//  xtream_login_sheet.dart — Saisie Xtream Codes côté client
// =========================================================
//  Bottom sheet appelée depuis l'écran "Tes chaînes arrivent
//  bientôt" pour les utilisateurs qui ont LEUR PROPRE
//  abonnement Xtream et ne veulent pas passer par un revendeur.
//
//  3 champs : Serveur, Utilisateur, Mot de passe.
//  Validation : URL non vide, user non vide, pass non vide.
//  Submit → PlaylistRepository.addXtreamPlaylist (vérifie les
//  credentials côté Xtream avant de polluer la DB locale).
//
//  Pas de M3U manuel proposé ici — uniquement Xtream, comme
//  demandé par l'utilisateur.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../playlists/data/playlist_repository.dart';

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
  final TextEditingController _serverCtrl = TextEditingController();
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String server = _serverCtrl.text.trim();
    final String user = _userCtrl.text.trim();
    final String pass = _passCtrl.text.trim();
    final String name =
        _nameCtrl.text.trim().isEmpty ? 'Mon abonnement' : _nameCtrl.text.trim();

    if (server.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Serveur, utilisateur et mot de passe sont obligatoires.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PlaylistRepository.instance.addXtreamPlaylist(
        name: name,
        serverUrl: server,
        username: user,
        password: pass,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Abonnement ajouté. Tes chaînes arrivent…',
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
                    Text('Xtream Codes',
                        style: AppTextStyles.headlineLarge
                            .copyWith(fontSize: 22)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Saisis les identifiants Xtream que t\'a donnés ton '
                  'fournisseur IPTV. Tes chaînes seront chargées en '
                  'quelques secondes.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                _label('Serveur Xtream'),
                TextField(
                  controller: _serverCtrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: 'http://serveur.com:8080',
                  ),
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                _label('Nom de l\'abonnement (optionnel)'),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Défaut : "Mon abonnement"',
                  ),
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
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 20),
                    label: Text(_busy ? 'Vérification…' : 'Charger mes chaînes'),
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
