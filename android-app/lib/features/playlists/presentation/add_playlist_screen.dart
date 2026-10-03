// =========================================================
//  add_playlist_screen.dart — Connexion ouverte (téléphone)
// =========================================================
//  Plus de choix « Serveur 1 / Serveur 2 ». La personne écrit :
//    • un compte Xtream (adresse, nom, mot de passe) ;
//    • une adresse M3U / M3U8 ;
//    • un lien de lecteur get.php.
//  N'importe quel fournisseur. Plusieurs sources : chaque validation
//  en ajoute une, sans effacer les précédentes.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/legal_disclaimer.dart';
import '../data/playlist_repository.dart';
import '../domain/open_source_input.dart';
import '../domain/playlist.dart';

class AddPlaylistScreen extends StatefulWidget {
  const AddPlaylistScreen({super.key});

  @override
  State<AddPlaylistScreen> createState() => _AddPlaylistScreenState();
}

class _AddPlaylistScreenState extends State<AddPlaylistScreen> {
  final TextEditingController _serverCtrl = TextEditingController();
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _linkCtrl = TextEditingController();

  OpenEntryMode _mode = OpenEntryMode.xtream;
  bool _busy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final OpenSourceParse parsed = switch (_mode) {
      OpenEntryMode.xtream => OpenSourceInput.xtream(
          server: _serverCtrl.text,
          username: _userCtrl.text,
          password: _passCtrl.text,
        ),
      OpenEntryMode.m3u => OpenSourceInput.playlistLink(_linkCtrl.text),
      OpenEntryMode.player => OpenSourceInput.playerLink(_linkCtrl.text),
    };
    if (!parsed.isValid || parsed.draft == null) {
      _setError(parsed.error ?? OpenSourceInput.errNeedUrl);
      return;
    }
    final OpenSourceDraft draft = parsed.draft!;
    _setBusy(true);
    try {
      final Playlist saved = draft.kind == OpenSourceKind.xtream
          ? await PlaylistRepository.instance.addXtreamPlaylist(
              name: context.l10n.tvMyListHint,
              serverUrl: draft.serverUrl!,
              username: draft.username!,
              password: draft.password!,
            )
          : await PlaylistRepository.instance.addM3uPlaylist(
              name: context.l10n.tvMyListHint,
              url: draft.m3uUrl!,
            );
      if (!mounted) return;
      Navigator.of(context).pop<Playlist>(saved);
    } on Exception catch (e) {
      if (!mounted) return;
      final String raw = e.toString().replaceFirst('Exception: ', '');
      final String lower = raw.toLowerCase();
      _setError(
        raw.isEmpty ||
                lower.contains('http://') ||
                lower.contains('https://') ||
                lower.contains('password')
            ? context.l10n.tvConnectError
            : raw,
      );
    } finally {
      _setBusy(false);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(context.l10n.loginTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const LegalDisclaimer.compact(),
              const SizedBox(height: 16),
              Text(
                'Ajoute ta source : lien M3U, compte Xtream, ou lien lecteur. '
                'N\'importe quel fournisseur.',
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _modeChip(context.l10n.playlistTypeXtream, OpenEntryMode.xtream),
                  _modeChip(context.l10n.playlistTypeM3u, OpenEntryMode.m3u),
                  _modeChip(OpenSourceInput.playerLabel, OpenEntryMode.player),
                ],
              ),
              const SizedBox(height: 16),
              if (_mode == OpenEntryMode.xtream) ...<Widget>[
                _label(context.l10n.loginServer),
                _textField(
                  controller: _serverCtrl,
                  hint: 'http://exemple.test:8080',
                  icon: Icons.dns_outlined,
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 16),
                _label(context.l10n.loginUsername),
                _textField(
                  controller: _userCtrl,
                  hint: context.l10n.loginUsernameHint,
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 16),
                _label(context.l10n.loginPassword),
                _textField(
                  controller: _passCtrl,
                  hint: context.l10n.loginPasswordHint,
                  icon: Icons.lock_outline,
                  obscureText: true,
                ),
              ] else ...<Widget>[
                _label(_mode == OpenEntryMode.player
                    ? OpenSourceInput.playerLabel
                    : context.l10n.loginUrlM3u),
                _textField(
                  controller: _linkCtrl,
                  hint: _mode == OpenEntryMode.player
                      ? 'http://exemple.test/get.php?username=…&password=…'
                      : 'http://exemple.test/liste.m3u',
                  icon: Icons.link_rounded,
                  keyboardType: TextInputType.url,
                ),
              ],
              const SizedBox(height: 24),
              if (_errorMessage != null) ...<Widget>[
                Text(
                  _errorMessage!,
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.live),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy
                      ? context.l10n.loginConnecting
                      : context.l10n.loginConnectLoad),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeChip(String label, OpenEntryMode mode) {
    final bool on = _mode == mode;
    return ChoiceChip(
      label: Text(label),
      selected: on,
      onSelected: _busy
          ? null
          : (_) => setState(() {
                _mode = mode;
                _errorMessage = null;
              }),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Text(
        text,
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
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
  }) {
    return TextField(
      controller: controller,
      enabled: !_busy,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: false,
      style: AppTextStyles.bodyLarge,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.accent, size: 20),
      ),
    );
  }
}
