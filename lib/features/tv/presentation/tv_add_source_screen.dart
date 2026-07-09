// =========================================================
//  tv_add_source_screen.dart — « J'ajoute ma propre liste » (Xtream)
// =========================================================
//  The Few NE VEND PAS de liste : le client a le DROIT d'apporter la
//  sienne. Le client CHOISIT un serveur (ceux configurés dans le panel,
//  GET /api/servers) et tape JUSTE son code (identifiant + mot de passe).
//  L'URL du serveur reste cachée. Repli « URL manuelle » s'il en a une à lui.
//
//  SAISIE : de VRAIS champs texte → fonctionnent avec le clavier de l'appli
//  TÉLÉCOMMANDE du TÉLÉPHONE (Android TV Remote…), un clavier physique, l'IME
//  de la box, et le COPIER-COLLER. Plus besoin de taper lettre par lettre.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../playlists/data/default_servers.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/source_link_utils.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';

const String _kManual = '__manual__';
const String _kM3u = '__m3u__';

class TvAddSourceScreen extends StatefulWidget {
  const TvAddSourceScreen({super.key});
  @override
  State<TvAddSourceScreen> createState() => _TvAddSourceScreenState();
}

class _TvAddSourceScreenState extends State<TvAddSourceScreen> {
  final TextEditingController _serverC = TextEditingController();
  final TextEditingController _userC = TextEditingController();
  final TextEditingController _passC = TextEditingController();
  final TextEditingController _m3uC = TextEditingController();

  List<DefaultServer> _servers = const <DefaultServer>[];
  String _choice = _kManual; // id du serveur choisi, _kManual ou _kM3u
  bool _busy = false;
  String? _error;

  bool get _manual => _choice == _kManual;
  bool get _isM3u => _choice == _kM3u;
  String get _serverUrl => _manual
      ? _serverC.text.trim()
      : (_servers
          .firstWhere((DefaultServer s) => s.id == _choice,
              orElse: () => const DefaultServer(id: '', label: '', url: ''))
          .url);

  @override
  void initState() {
    super.initState();
    DefaultServersApi.fetch().then((List<DefaultServer> list) {
      if (!mounted) return;
      final List<DefaultServer> ok =
          list.where((DefaultServer s) => s.url.isNotEmpty).toList();
      setState(() {
        _servers = ok;
        _choice = ok.isNotEmpty ? ok.first.id : _kManual;
      });
    });
  }

  @override
  void dispose() {
    _serverC.dispose();
    _userC.dispose();
    _passC.dispose();
    _m3uC.dispose();
    super.dispose();
  }

  Future<void> _validate() async {
    final String errFill = context.l10n.tvAddListError;

    // ----- Mode M3U : un seul champ (lien direct), pipeline COMPLET
    //       (addM3uPlaylistSmart : DoH pour les domaines bloqués par le
    //       FAI, repli get.php→API Xtream si 503/refus ou fichier > 60 Mo).
    if (_isM3u) {
      final String url = SourceLinkUtils.ensureScheme(_m3uC.text);
      if (url.isEmpty) {
        setState(() => _error = errFill);
        return;
      }
      setState(() { _busy = true; _error = null; });
      try {
        await PlaylistRepository.instance
            .addM3uPlaylistSmart(name: 'Ma liste', url: url);
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        // Vrai message (indice DNS opérateur, statut HTTP…), comme sur
        // téléphone — plus de générique qui masque la cause.
        if (mounted) {
          setState(() {
            _busy = false;
            _error = e.toString().replaceFirst('Exception: ', '');
          });
        }
      }
      return;
    }

    // On accepte le lien même sans « http:// » tapé (le revendeur/
    // fournisseur donne souvent juste le domaine, ex. « serveur.com:8080 »).
    String server = SourceLinkUtils.ensureScheme(_serverUrl);
    String user = _userC.text.trim();
    String pass = _passC.text.trim();
    // Beaucoup de fournisseurs ne donnent qu'UN SEUL lien complet (celui
    // pour VLC/Smarters) au lieu de 3 informations séparées. Si c'est ce
    // qui a été tapé/collé dans le champ « serveur » et que utilisateur/
    // mot de passe sont vides, on les en extrait tout seul.
    if (_manual && (user.isEmpty || pass.isEmpty)) {
      final ({String server, String username, String password})? extracted =
          SourceLinkUtils.tryExtractXtreamCredentials(_serverUrl);
      if (extracted != null) {
        server = extracted.server;
        user = user.isEmpty ? extracted.username : user;
        pass = pass.isEmpty ? extracted.password : pass;
      }
    }
    if (server.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() => _error = errFill);
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await PlaylistRepository.instance.addXtreamPlaylist(
        name: _manual
            ? 'Ma liste'
            : (_servers
                .firstWhere((DefaultServer s) => s.id == _choice,
                    orElse: () => const DefaultServer(id: '', label: 'Ma liste', url: ''))
                .label),
        serverUrl: server,
        username: user,
        password: pass,
      );
      if (mounted) Navigator.of(context).pop(); // le gate ouvre l'app
    } catch (e) {
      // Vrai message (indice DNS opérateur, statut HTTP…) — même
      // diagnostic que sur téléphone, plus de « Erreur de connexion »
      // générique qui masquait la cause.
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
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

              // ----- Choix de la source : serveurs du panel + « URL
              //       manuelle » (Xtream) + « M3U » (lien direct). Toujours
              //       affiché → le mode M3U est atteignable même sans serveur.
              Text(
                  (_servers.isNotEmpty
                          ? context.l10n.tvChooseServer
                          : 'Choisis ta source')
                      .toUpperCase(),
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
                  _ServerChip(
                    label: 'M3U',
                    selected: _isM3u,
                    onSelect: () => setState(() => _choice = _kM3u),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ----- Champs texte (clavier téléphone / physique + coller) -----
              if (_isM3u) ...<Widget>[
                // Mode M3U : UN seul champ, le lien direct.
                _TextField(
                  controller: _m3uC,
                  label: 'URL M3U',
                  hint: 'http://serveur.com/get.php?username=…',
                  autofocus: true,
                  keyboardType: TextInputType.url,
                ),
              ] else ...<Widget>[
                if (_manual) ...<Widget>[
                  _TextField(
                    controller: _serverC,
                    label: context.l10n.tvFieldServer,
                    hint: 'http://serveur.com:8080',
                    autofocus: true,
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 10),
                ],
                _TextField(
                  controller: _userC,
                  label: context.l10n.tvFieldUser,
                  autofocus: !_manual,
                ),
                const SizedBox(height: 10),
                _TextField(
                  controller: _passC,
                  label: context.l10n.tvFieldPass,
                  obscure: true,
                ),
              ],

              const SizedBox(height: 10),
              Text(context.l10n.tvKeyboardHint,
                  style: TvTokens.ui(12, color: TvTokens.mutedDim)),

              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(_error!, style: TvTokens.ui(14, color: const Color(0xFFE0746A))),
              ],
              const SizedBox(height: 20),

              TvCtaButton(
                label: _busy ? context.l10n.tvConnecting : context.l10n.tvAddListValidate,
                onSelect: _busy ? null : _validate,
              ),
              // Pendant l'import, un message d'attente HONNÊTE : sans lui,
              // « Connexion… » figé donnait l'impression que rien ne se
              // passait (les liens get.php passent par l'API Xtream en
              // quelques secondes ; le repli M3U brut peut prendre ~1 min).
              if (_busy) ...<Widget>[
                const SizedBox(height: 10),
                Text(context.l10n.tvConnectingHint,
                    textAlign: TextAlign.center,
                    style: TvTokens.ui(13, color: TvTokens.mutedDim)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Champ texte Maison Noir. C'est un VRAI TextField : il accepte le clavier
/// de l'appli télécommande du téléphone, un clavier USB/Bluetooth, l'IME de
/// la box, et le copier-coller (appui long / Ctrl+V).
class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.autofocus = false,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final bool autofocus;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(TvTokens.rButton),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: obscure,
      keyboardType: keyboardType,
      autocorrect: false,
      enableSuggestions: false,
      cursorColor: TvTokens.gold,
      style: TvTokens.ui(18, weight: FontWeight.w500, color: TvTokens.text),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TvTokens.ui(13, color: TvTokens.muted),
        hintStyle: TvTokens.ui(14, color: TvTokens.mutedDim),
        floatingLabelStyle: TvTokens.ui(13, color: TvTokens.goldBright),
        filled: true,
        fillColor: TvTokens.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        enabledBorder: border(TvTokens.line, 1),
        focusedBorder: border(TvTokens.gold, 2),
      ),
    );
  }
}

class _ServerChip extends StatelessWidget {
  const _ServerChip({required this.label, required this.selected, required this.onSelect});
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
            color: focused ? TvTokens.gold : (selected ? TvTokens.sel : Colors.transparent),
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
