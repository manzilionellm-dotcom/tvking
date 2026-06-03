// =========================================================
//  m3u_login_sheet.dart — Source perso : M3U OU Xtream
// =========================================================
//  Pour les clients qui apportent LEUR PROPRE source (pas le serveur
//  prédéfini du revendeur). Deux modes au choix via un sélecteur :
//    - M3U    : on colle une URL M3U / M3U8.
//    - Xtream : on saisit le serveur (URL complète) + utilisateur +
//               mot de passe (Xtream Codes d'un fournisseur tiers).
//
//  Le parseur sous-jacent est adaptatif (accepte tous les formats
//  M3U ; vérifie les identifiants Xtream avant de charger).
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/playlist_repository.dart';

Future<void> showM3uLoginSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _M3uLoginSheet(),
  );
}

class _M3uLoginSheet extends StatefulWidget {
  const _M3uLoginSheet();

  @override
  State<_M3uLoginSheet> createState() => _M3uLoginSheetState();
}

class _M3uLoginSheetState extends State<_M3uLoginSheet> {
  // 'm3u' ou 'xtream'.
  String _mode = 'm3u';

  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  // Xtream
  final TextEditingController _serverCtrl = TextEditingController();
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String name =
        _nameCtrl.text.trim().isEmpty ? 'Ma source' : _nameCtrl.text.trim();
    setState(() => _error = null);

    if (_mode == 'm3u') {
      final String url = _urlCtrl.text.trim();
      if (url.isEmpty ||
          (!url.startsWith('http://') && !url.startsWith('https://'))) {
        setState(() => _error =
            'URL invalide. Elle doit commencer par http:// ou https://');
        return;
      }
      await _run(() =>
          PlaylistRepository.instance.addM3uPlaylist(name: name, url: url));
    } else {
      final String server = _serverCtrl.text.trim();
      final String user = _userCtrl.text.trim();
      final String pass = _passCtrl.text.trim();
      if (server.isEmpty ||
          (!server.startsWith('http://') && !server.startsWith('https://'))) {
        setState(() => _error =
            'Serveur invalide. Format : http://serveur.com:8080');
        return;
      }
      if (user.isEmpty || pass.isEmpty) {
        setState(() =>
            _error = 'Utilisateur et mot de passe sont obligatoires.');
        return;
      }
      await _run(() => PlaylistRepository.instance.addXtreamPlaylist(
            name: name,
            serverUrl: server,
            username: user,
            password: pass,
          ));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Source ajoutée. Tes chaînes arrivent…',
              style: AppTextStyles.bodyMedium),
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
                    Icon(Icons.link_rounded, color: AppColors.accent, size: 22),
                    const SizedBox(width: 10),
                    Text('Ma source perso',
                        style:
                            AppTextStyles.headlineLarge.copyWith(fontSize: 22)),
                  ],
                ),
                const SizedBox(height: 14),
                // ----- Sélecteur M3U / Xtream -----
                Row(
                  children: <Widget>[
                    _modeButton('M3U', 'm3u'),
                    const SizedBox(width: 10),
                    _modeButton('Xtream', 'xtream'),
                  ],
                ),
                const SizedBox(height: 16),

                if (_mode == 'm3u') ...<Widget>[
                  _label('URL M3U'),
                  TextField(
                    controller: _urlCtrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText: 'http://serveur.com/get.php?username=…',
                    ),
                  ),
                ] else ...<Widget>[
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
                  TextField(controller: _userCtrl, autocorrect: false),
                  const SizedBox(height: 12),
                  _label('Mot de passe'),
                  TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    autocorrect: false,
                  ),
                ],
                const SizedBox(height: 12),
                _label('Nom (optionnel)'),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Défaut : "Ma source"',
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
                          child: Text(_error!,
                              style: AppTextStyles.bodyMedium
                                  .copyWith(fontSize: 12)),
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

  Widget _modeButton(String label, String value) {
    final bool selected = _mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: _busy ? null : () => setState(() => _mode = value),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.accent.withValues(alpha: 0.15) : AppColors.surface,
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
