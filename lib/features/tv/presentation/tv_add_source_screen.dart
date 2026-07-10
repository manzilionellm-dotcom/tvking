// =========================================================
//  tv_add_source_screen.dart — « J'ajoute ma propre liste » (Xtream)
// =========================================================
//  The Few NE VEND PAS de liste : le client a le DROIT d'apporter la
//  sienne. Le client CHOISIT un serveur (ceux configurés dans le panel,
//  GET /api/servers) et tape JUSTE son code (identifiant + mot de passe).
//  L'URL du serveur reste cachée. Repli « URL manuelle » s'il en a une à lui.
//
//  SAISIE 100 % TÉLÉCOMMANDE : clavier D-pad INTÉGRÉ (TvUrlKeyboard) —
//  flèches + OK suffisent, sur TOUTES les télécommandes. Les VRAIS
//  TextField restent là en parallèle (bouton ⌨ : IME de la box, clavier
//  physique/USB, appli télécommande du téléphone, copier-coller) mais ne
//  sont JAMAIS obligatoires.
//
//  PRÉ-VOL : « Tester et ajouter » vérifie le compte AVANT d'écrire quoi
//  que ce soit (verifyCredentials), montre les corrections apportées à
//  l'adresse (confiance), puis un import VIVANT : étapes ✓, compteur de
//  chaînes qui monte, catégorie en cours — jamais un spinner muet.
// =========================================================
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/i18n/l10n_extension.dart';
import '../../playlists/data/default_servers.dart';
import '../../playlists/data/iptv_http.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/source_input_normalizer.dart';
import '../../playlists/data/source_link_utils.dart';
import '../../playlists/data/source_preflight.dart';
import '../../playlists/data/xtream_client.dart';
import '../../playlists/domain/playlist.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';
import 'tv_import_progress.dart';
import 'tv_url_keyboard.dart';

const String _kManual = '__manual__';

/// Champ actuellement CIBLE du clavier intégré.
enum _Field { server, user, pass }

class TvAddSourceScreen extends StatefulWidget {
  const TvAddSourceScreen({
    super.key,
    this.initialServer,
    this.initialUsername,
    this.initialPassword,
  });

  /// Pré-remplissage (venant de l'aiguillage intelligent : un lien
  /// get.php?username=… collé donne déjà les 3 champs). Null = vide.
  final String? initialServer;
  final String? initialUsername;
  final String? initialPassword;

  @override
  State<TvAddSourceScreen> createState() => _TvAddSourceScreenState();
}

class _TvAddSourceScreenState extends State<TvAddSourceScreen> {
  final TextEditingController _serverC = TextEditingController();
  final TextEditingController _userC = TextEditingController();
  final TextEditingController _passC = TextEditingController();

  List<DefaultServer> _servers = const <DefaultServer>[];
  String _choice = _kManual; // id du serveur choisi, ou _kManual
  _Field _target = _Field.server;
  bool _showPass = false;

  bool _busy = false;
  bool _cancelled = false;
  http.Client? _client; // client du test en cours → close() = annuler
  final TvImportProgress _progress = TvImportProgress();

  String? _error;
  String? _fixNote; // « On a corrigé l'adresse : … » (confiance)

  // Récap final (« ✓ 8 412 chaînes prêtes · 143 catégories »).
  bool _success = false;
  int _doneChannels = 0;
  int _doneCategories = 0;

  bool get _manual => _choice == _kManual;
  String get _serverUrl => _manual
      ? _serverC.text.trim()
      : (_servers
          .firstWhere((DefaultServer s) => s.id == _choice,
              orElse: () => const DefaultServer(id: '', label: '', url: ''))
          .url);

  @override
  void initState() {
    super.initState();
    _serverC.text = widget.initialServer ?? '';
    _userC.text = widget.initialUsername ?? '';
    _passC.text = widget.initialPassword ?? '';
    // Cible initiale logique : le premier champ encore vide.
    _target = _serverC.text.isEmpty
        ? _Field.server
        : (_userC.text.isEmpty ? _Field.user : _Field.pass);
    final bool prefilled = (widget.initialServer ?? '').isNotEmpty;
    DefaultServersApi.fetch().then((List<DefaultServer> list) {
      if (!mounted) return;
      final List<DefaultServer> ok =
          list.where((DefaultServer s) => s.url.isNotEmpty).toList();
      setState(() {
        _servers = ok;
        // Un serveur déjà pré-rempli (lien collé) GAGNE sur les serveurs
        // du panel : on ne remplace pas ce que le client a apporté.
        if (!prefilled) _choice = ok.isNotEmpty ? ok.first.id : _kManual;
      });
    });
  }

  @override
  void dispose() {
    _serverC.dispose();
    _userC.dispose();
    _passC.dispose();
    _progress.dispose();
    _client?.close();
    super.dispose();
  }

  // ---- Cible du clavier intégré ----

  TextEditingController get _targetC {
    switch (_effectiveTarget) {
      case _Field.server:
        return _serverC;
      case _Field.user:
        return _userC;
      case _Field.pass:
        return _passC;
    }
  }

  /// Le champ serveur n'existe qu'en mode manuel : si un serveur du panel
  /// est choisi, la cible retombe sur l'identifiant.
  _Field get _effectiveTarget =>
      (!_manual && _target == _Field.server) ? _Field.user : _target;

  String _targetLabel(BuildContext context) {
    switch (_effectiveTarget) {
      case _Field.server:
        return context.l10n.tvFieldServer;
      case _Field.user:
        return context.l10n.tvFieldUser;
      case _Field.pass:
        return context.l10n.tvFieldPass;
    }
  }

  // ---- Pré-vol + import vivant ----

  Future<void> _testAndAdd() async {
    final String errFill = context.l10n.tvAddListError;
    String server;
    String user = SourceLinkUtils.cleanInput(_userC.text);
    String pass = SourceLinkUtils.cleanInput(_passC.text);
    final List<String> fixes = <String>[];

    if (_manual) {
      // TOLÉRANCE AUX FAUTES : virgules → points, htp:// → http://,
      // espaces purgés… et on retient ce qui a été réparé pour le dire.
      final NormalizedInput n = SourceInputNormalizer.normalizeUrl(_serverUrl);
      server = n.value;
      fixes.addAll(n.fixes);
      // Lien COMPLET (get.php?username=…) collé dans le champ serveur
      // alors que identifiant/mot de passe sont vides → on extrait tout.
      if (user.isEmpty || pass.isEmpty) {
        final ({String server, String username, String password})? ex =
            SourceLinkUtils.tryExtractXtreamCredentials(server);
        if (ex != null) {
          server = ex.server;
          user = user.isEmpty ? ex.username : user;
          pass = pass.isEmpty ? ex.password : pass;
          fixes.add(context.l10n.tvSourceFixCredsFromLink);
        }
      }
    } else {
      server = SourceLinkUtils.ensureScheme(_serverUrl);
    }

    if (server.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() => _error = errFill);
      return;
    }

    setState(() {
      _busy = true;
      _cancelled = false;
      _error = null;
      _fixNote = fixes.isEmpty
          ? null
          : context.l10n.tvSourceFixedAddress(fixes.join(' · '));
    });
    _progress.reset();
    final http.Client client = createIptvHttpClient();
    _client = client;
    try {
      // 1) PRÉ-VOL : le compte est-il bon ? (rien n'est écrit en base ici)
      _progress.startStage(context.l10n.loginConnecting);
      await XtreamClient(
        serverUrl: server,
        username: user,
        password: pass,
        httpClient: client,
      ).verifyCredentials();
      if (_abortRequested()) return;
      _progress.completeStage(context.l10n.tvSourceListOk);

      // 2) RÉSUMÉ avant validation : le client relit ce qui va être ajouté.
      final bool confirmed = await _confirmSummary(server, user, pass);
      if (_abortRequested()) return;
      if (!confirmed) {
        setState(() => _busy = false);
        _progress.reset();
        return;
      }

      // 3) IMPORT VIVANT : compteur de chaînes + catégorie en cours.
      _progress.startStage(context.l10n.tvSourceDownloadingChannels);
      final Playlist saved =
          await PlaylistRepository.instance.addXtreamPlaylist(
        name: _manual
            ? context.l10n.tvSourceDefaultListName
            : (_servers
                .firstWhere((DefaultServer s) => s.id == _choice,
                    orElse: () => DefaultServer(
                        id: '',
                        label: context.l10n.tvSourceDefaultListName,
                        url: ''))
                .label),
        serverUrl: server,
        username: user,
        password: pass,
        httpClient: client,
        onProgress: _progress.onImportProgress,
      );
      if (_abortRequested()) return;
      _progress.completeStage(context.l10n.tvSourceDone);
      setState(() {
        _busy = false;
        _success = true;
        _doneChannels = saved.channelCount;
        _doneCategories = _progress.categoriesSeen.length;
      });
    } catch (e) {
      // Annulé au Retour : le repository a déjà retiré la playlist
      // orpheline (son catch) → la base reste propre, on rend la main.
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

  /// Résumé « ce qui va être ajouté » — mot de passe masqué par défaut.
  Future<bool> _confirmSummary(
      String server, String user, String pass) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: TvTokens.card,
        title: Row(
          children: <Widget>[
            const Icon(Icons.check_circle_rounded,
                color: TvTokens.success, size: 26),
            const SizedBox(width: 10),
            Text(ctx.l10n.tvSourceListOk,
                style: TvTokens.ui(20,
                    weight: FontWeight.w700, color: TvTokens.text)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SummaryRow(label: context.l10n.tvFieldServer, value: server),
            _SummaryRow(label: context.l10n.tvFieldUser, value: user),
            _SummaryRow(
                label: context.l10n.tvFieldPass, value: '•' * pass.length),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.tvSourceEditBtn,
                style: TvTokens.ui(15, color: TvTokens.muted)),
          ),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.tvSourceLoadMyList,
                style: TvTokens.ui(15,
                    weight: FontWeight.w700, color: TvTokens.goldBright)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Retour pendant le test/import = ANNULATION propre (pas de sortie
  /// d'écran surprise) : on coupe le client HTTP → l'attente s'interrompt,
  /// le repository nettoie l'éventuelle playlist orpheline.
  void _cancelBusy() {
    _cancelled = true;
    _client?.close();
  }

  /// Après CHAQUE await : si l'annulation est tombée pile entre deux
  /// étapes (l'await a réussi AVANT la coupure du client), on ne doit
  /// surtout pas rester bloqué en `_busy` (Retour serait alors muet).
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

  // ---- Récap final chaleureux + « Regarder maintenant » ----
  Widget _buildSuccess(BuildContext context) {
    final String cats = _doneCategories > 0
        ? ' · ${context.l10n.tvSourceCategoriesCount(tvFormatCount(_doneCategories))}'
        : '';
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
            Text(
              '${context.l10n.tvSourceChannelsReady(tvFormatCount(_doneChannels))}$cats',
              textAlign: TextAlign.center,
              style: TvTokens.display(34, color: TvTokens.text),
            ),
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
        // ----- Colonne gauche : choix serveur + champs + états -----
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(context.l10n.tvAddListTitle,
                    style: TvTokens.display(34, color: TvTokens.text)),
                const SizedBox(height: 6),
                Text(context.l10n.tvAddListSubtitle,
                    style: TvTokens.ui(16, color: TvTokens.mutedDim)),
                const SizedBox(height: 18),

                // ----- Choix du serveur (ceux du panel) + « URL manuelle » -----
                if (_servers.isNotEmpty) ...<Widget>[
                  Text(context.l10n.tvChooseServer.toUpperCase(),
                      style: TvTokens.ui(11,
                          weight: FontWeight.w600,
                          color: TvTokens.mutedDim,
                          spacing: 2)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final DefaultServer s in _servers)
                        _ServerChip(
                          label: s.label,
                          selected: _choice == s.id,
                          onSelect: () => setState(() => _choice = s.id),
                        ),
                      _ServerChip(
                        label: context.l10n.tvManualServer,
                        selected: _manual,
                        onSelect: () => setState(() => _choice = _kManual),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // ----- Champs : OK = cible du clavier intégré ; ⌨ = IME -----
                if (_manual) ...<Widget>[
                  TvKeyboardField(
                    controller: _serverC,
                    label: context.l10n.tvFieldServer,
                    hint: 'http://serveur.com:8080',
                    autofocus: true,
                    active: _effectiveTarget == _Field.server,
                    onActivate: () =>
                        setState(() => _target = _Field.server),
                  ),
                  const SizedBox(height: 10),
                ],
                TvKeyboardField(
                  controller: _userC,
                  label: context.l10n.tvFieldUser,
                  autofocus: !_manual,
                  active: _effectiveTarget == _Field.user,
                  onActivate: () => setState(() => _target = _Field.user),
                ),
                const SizedBox(height: 10),
                TvKeyboardField(
                  controller: _passC,
                  label: context.l10n.tvFieldPass,
                  obscured: !_showPass,
                  onToggleObscure: () =>
                      setState(() => _showPass = !_showPass),
                  active: _effectiveTarget == _Field.pass,
                  onActivate: () => setState(() => _target = _Field.pass),
                ),

                const SizedBox(height: 10),
                Text(context.l10n.tvKeyboardHint,
                    style: TvTokens.ui(12, color: TvTokens.mutedDim)),

                if (_fixNote != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(_fixNote!,
                      style: TvTokens.ui(13, color: TvTokens.gold)),
                ],
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: TvTokens.ui(14, color: const Color(0xFFE0746A))),
                ],
                const SizedBox(height: 12),
                TvImportProgressView(progress: _progress),
                if (_busy) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(context.l10n.tvSourcePressBackToCancel,
                      style: TvTokens.ui(12, color: TvTokens.mutedDim)),
                ],
                const SizedBox(height: 14),

                TvCtaButton(
                  label: _busy
                      ? context.l10n.tvChecking
                      : context.l10n.tvSourceTestAndAdd,
                  onSelect: _busy ? null : _testAndAdd,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 22),
        // ----- Colonne droite : clavier D-pad intégré, cible affichée -----
        SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: TvUrlKeyboard(
              controller: _targetC,
              fieldLabel: _targetLabel(context),
              obscured: _effectiveTarget == _Field.pass && !_showPass,
              showUrlChips: _effectiveTarget == _Field.server,
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Text(label, style: TvTokens.ui(14, color: TvTokens.muted)),
          ),
          Expanded(
            child: Text(value,
                style: TvTokens.mono(14, color: TvTokens.text)),
          ),
        ],
      ),
    );
  }
}

class _ServerChip extends StatelessWidget {
  const _ServerChip(
      {required this.label, required this.selected, required this.onSelect});
  final String label;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.medium,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final bool hl = focused || selected;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: focused
                ? TvTokens.gold
                : (selected ? TvTokens.sel : Colors.transparent),
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: Border.all(color: hl ? TvTokens.gold : TvTokens.line),
          ),
          child: Text(label,
              style: TvTokens.ui(15,
                  weight: FontWeight.w600,
                  color: focused
                      ? const Color(0xFF1A1206)
                      : (selected ? TvTokens.goldBright : TvTokens.muted))),
        );
      },
    );
  }
}
