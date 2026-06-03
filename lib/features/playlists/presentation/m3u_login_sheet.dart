// =========================================================
//  m3u_login_sheet.dart — Le client colle SON propre M3U
// =========================================================
//  Pour les clients qui ont leur propre lien M3U / M3U8 (au lieu
//  d'un code Xtream ou d'une activation par MAC). On colle l'URL,
//  on valide côté serveur, puis on charge les chaînes.
//
//  Le parseur sous-jacent (m3u_fetcher + m3u_parser) est ADAPTATIF :
//  il gère les playlists avec ou sans en-tête #EXTM3U, l'UTF-8 et le
//  Latin-1, les attributs tvg-*, group-title, etc. → il « prend tous
//  les M3U ».
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
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String url = _urlCtrl.text.trim();
    final String name =
        _nameCtrl.text.trim().isEmpty ? 'Ma playlist' : _nameCtrl.text.trim();

    if (url.isEmpty ||
        (!url.startsWith('http://') && !url.startsWith('https://'))) {
      setState(() => _error =
          'URL invalide. Elle doit commencer par http:// ou https://');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PlaylistRepository.instance.addM3uPlaylist(name: name, url: url);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Playlist ajoutée. Tes chaînes arrivent…',
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
                    Icon(Icons.link_rounded, color: AppColors.accent, size: 22),
                    const SizedBox(width: 10),
                    Text('Mon M3U',
                        style:
                            AppTextStyles.headlineLarge.copyWith(fontSize: 22)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Colle l\'URL de ta playlist M3U ou M3U8 (le lien que t\'a '
                  'donné ton fournisseur). On accepte tous les formats.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                _label('URL M3U'),
                TextField(
                  controller: _urlCtrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: 'http://serveur.com/get.php?username=…',
                  ),
                ),
                const SizedBox(height: 12),
                _label('Nom (optionnel)'),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Défaut : "Ma playlist"',
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
                            style:
                                AppTextStyles.bodyMedium.copyWith(fontSize: 12),
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
