// =========================================================
//  tv_add_m3u_screen.dart — Ajouter une liste M3U (URL)
// =========================================================
//  Le client colle/tape l'URL de son fichier .m3u (+ EPG optionnelle),
//  100 % à la télécommande : clavier D-pad intégré (TvUrlKeyboard) avec
//  chips d'insertion rapide (http://, .m3u…). Les vrais TextField restent
//  disponibles via le bouton ⌨ (IME, clavier physique, copier-coller).
//
//  PRÉ-VOL avant l'ajout : on télécharge SEULEMENT LE DÉBUT du fichier
//  (anti-OOM) pour vérifier que c'est une vraie liste, puis import VIVANT
//  (étapes ✓, compteur de chaînes qui monte) — jamais un spinner muet.
// =========================================================
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/i18n/l10n_extension.dart';
import '../../playlists/data/iptv_http.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/source_input_normalizer.dart';
import '../../playlists/data/source_link_utils.dart';
import '../../playlists/data/source_preflight.dart';
import '../../playlists/domain/playlist.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';
import 'tv_import_progress.dart';
import 'tv_url_keyboard.dart';

/// Champ actuellement CIBLE du clavier intégré.
enum _Field { name, url, epg }

class TvAddM3uScreen extends StatefulWidget {
  const TvAddM3uScreen({super.key, this.initialUrl, this.initialName});

  /// Pré-remplissage (venant de l'aiguillage intelligent). Null = vide.
  final String? initialUrl;
  final String? initialName;

  @override
  State<TvAddM3uScreen> createState() => _TvAddM3uScreenState();
}

class _TvAddM3uScreenState extends State<TvAddM3uScreen> {
  final TextEditingController _nameC = TextEditingController();
  final TextEditingController _urlC = TextEditingController();
  final TextEditingController _epgC = TextEditingController();

  _Field _target = _Field.url;
  bool _busy = false;
  bool _cancelled = false;
  http.Client? _client; // client du test en cours → close() = annuler
  final TvImportProgress _progress = TvImportProgress();

  String? _error;
  String? _fixNote; // « On a corrigé l'adresse : … »

  bool _success = false;
  int _doneChannels = 0;

  @override
  void initState() {
    super.initState();
    _urlC.text = widget.initialUrl ?? '';
    _nameC.text = widget.initialName ?? '';
  }

  @override
  void dispose() {
    _nameC.dispose();
    _urlC.dispose();
    _epgC.dispose();
    _progress.dispose();
    _client?.close();
    super.dispose();
  }

  TextEditingController get _targetC {
    switch (_target) {
      case _Field.name:
        return _nameC;
      case _Field.url:
        return _urlC;
      case _Field.epg:
        return _epgC;
    }
  }

  String get _targetLabel {
    switch (_target) {
      case _Field.name:
        return context.l10n.tvSourceFieldName;
      case _Field.url:
        return context.l10n.loginUrlM3u;
      case _Field.epg:
        return context.l10n.tvSourceFieldEpgUrl;
    }
  }

  Future<void> _testAndAdd() async {
    // TOLÉRANCE AUX FAUTES : espaces, virgules, htp://… réparés AVANT le
    // réseau, et on retient ce qui a été corrigé pour le dire (confiance).
    final NormalizedInput n = SourceInputNormalizer.normalizeUrl(_urlC.text);
    final String url = n.value;
    if (url.isEmpty) {
      setState(() => _error = context.l10n.tvSourceEnterValidM3u);
      return;
    }
    setState(() {
      _busy = true;
      _cancelled = false;
      _error = null;
      _fixNote = n.fixes.isEmpty
          ? null
          : context.l10n.tvSourceFixedAddress(n.fixes.join(' · '));
    });
    _progress.reset();
    final http.Client client = createIptvHttpClient();
    _client = client;
    try {
      // 1) PRÉ-VOL : le DÉBUT du fichier seulement (anti-OOM) — est-ce
      //    bien une liste de chaînes ? Rien n'est écrit en base ici.
      _progress.startStage(context.l10n.tvSourceTestingLink);
      await SourcePreflight.probeM3u(url, httpClient: client);
      if (_abortRequested()) return;
      _progress.completeStage(context.l10n.tvSourceListOk);

      // 2) IMPORT VIVANT : téléchargement complet + compteur qui monte.
      _progress.startStage(context.l10n.tvSourceDownloadingChannels);
      final String epg = SourceLinkUtils.cleanInput(_epgC.text);
      final Playlist saved = await PlaylistRepository.instance.addM3uPlaylist(
        name: _nameC.text.trim().isEmpty
            ? context.l10n.tvSourceDefaultM3uName
            : _nameC.text.trim(),
        url: url,
        epgUrl: epg.isEmpty ? null : SourceLinkUtils.ensureScheme(epg),
        httpClient: client,
        onProgress: _progress.onImportProgress,
      );
      if (_abortRequested()) return;
      _progress.completeStage(context.l10n.tvSourceDone);
      setState(() {
        _busy = false;
        _success = true;
        _doneChannels = saved.channelCount;
      });
    } catch (e) {
      // Annulé au Retour : le repository a déjà retiré la playlist
      // orpheline (son catch) → la base reste propre.
      if (!mounted) return;
      _progress.reset();
      setState(() {
        _busy = false;
        _error = _cancelled
            ? context.l10n.tvSourceAddCancelled
            : SourcePreflight.humanize(e);
      });
    } finally {
      _client = null;
      client.close();
    }
  }

  /// Retour pendant le test/import = ANNULATION propre : on coupe le
  /// client HTTP, l'attente s'interrompt, la base reste propre.
  void _cancelBusy() {
    _cancelled = true;
    _client?.close();
  }

  /// Après CHAQUE await : si l'annulation est tombée pile entre deux
  /// étapes, ne jamais rester bloqué en `_busy`.
  bool _abortRequested() {
    if (!mounted) return true;
    if (!_cancelled) return false;
    _progress.reset();
    setState(() {
      _busy = false;
      _error = context.l10n.tvSourceAddCancelled;
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop && _busy) _cancelBusy();
      },
      child: _success ? _buildSuccess(context) : _buildForm(context),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Icon(Icons.check_circle_rounded,
                size: 64, color: TvTokens.success),
            const SizedBox(height: 18),
            Text(context.l10n.tvSourceChannelsReady(tvFormatCount(_doneChannels)),
                textAlign: TextAlign.center,
                style: TvTokens.display(34, color: TvTokens.text)),
            const SizedBox(height: 8),
            Text(context.l10n.tvSourceListLoaded,
                textAlign: TextAlign.center,
                style: TvTokens.ui(16, color: TvTokens.muted)),
            const SizedBox(height: 26),
            TvCtaButton(
              label: context.l10n.tvSourceWatchNow,
              autofocus: true,
              onSelect: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // ----- Colonne gauche : champs + états -----
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(context.l10n.tvSourceAddM3uTitle,
                    style: TextStyle(
                        fontSize: TvDimens.displayS,
                        fontWeight: FontWeight.w800,
                        color: TvTokens.text)),
                const SizedBox(height: 6),
                Text(context.l10n.tvSourceAddM3uSubtitle,
                    style: TextStyle(
                        fontSize: TvDimens.body, color: TvTokens.muted)),
                const SizedBox(height: 20),
                TvKeyboardField(
                  controller: _urlC,
                  label: context.l10n.loginUrlM3u,
                  hint: 'http://serveur.com/playlist.m3u',
                  autofocus: true,
                  active: _target == _Field.url,
                  onActivate: () => setState(() => _target = _Field.url),
                ),
                const SizedBox(height: 10),
                TvKeyboardField(
                  controller: _nameC,
                  label: context.l10n.loginNameOptional,
                  hint: context.l10n.tvSourceDefaultListName,
                  active: _target == _Field.name,
                  onActivate: () => setState(() => _target = _Field.name),
                ),
                const SizedBox(height: 10),
                TvKeyboardField(
                  controller: _epgC,
                  label: context.l10n.tvSourceFieldEpgOptional,
                  hint: 'http://serveur.com/xmltv.php',
                  active: _target == _Field.epg,
                  onActivate: () => setState(() => _target = _Field.epg),
                ),

                if (_fixNote != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(_fixNote!, style: TvTokens.ui(13, color: TvTokens.gold)),
                ],
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: TextStyle(
                          fontSize: TvDimens.label,
                          fontWeight: FontWeight.w600,
                          color: TvTokens.live)),
                ],
                const SizedBox(height: 12),
                TvImportProgressView(progress: _progress),
                if (_busy) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(context.l10n.tvSourcePressBackToCancel,
                      style: TvTokens.ui(12, color: TvTokens.mutedDim)),
                ],
                const SizedBox(height: 16),
                TvCtaButton(
                  label: _busy
                      ? context.l10n.tvSourceTesting
                      : context.l10n.tvSourceTestAndAdd,
                  expand: false,
                  onSelect: _busy ? null : _testAndAdd,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 22),
        // ----- Colonne droite : clavier D-pad intégré -----
        SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: TvUrlKeyboard(
              controller: _targetC,
              fieldLabel: _targetLabel,
              // Chips URL partout sauf pour le nom de la liste.
              showUrlChips: _target != _Field.name,
            ),
          ),
        ),
      ],
    );
  }
}
