// =========================================================
//  tv_add_source_screen.dart — « J'ajoute ma propre liste » (Xtream)
// =========================================================
//  The Few NE VEND PAS de liste : le client a le DROIT d'apporter la
//  sienne. Le client CHOISIT un serveur (ceux configurés dans le panel,
//  GET /api/servers) et tape JUSTE son code (identifiant + mot de passe).
//  L'URL du serveur reste cachée. Repli « URL manuelle » s'il en a une à lui.
//  → on charge via PlaylistRepository → l'app s'ouvre.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../playlists/data/default_servers.dart';
import '../../playlists/data/playlist_repository.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';

const String _kManual = '__manual__';

class TvAddSourceScreen extends StatefulWidget {
  const TvAddSourceScreen({super.key});
  @override
  State<TvAddSourceScreen> createState() => _TvAddSourceScreenState();
}

class _TvAddSourceScreenState extends State<TvAddSourceScreen> {
  List<DefaultServer> _servers = const <DefaultServer>[];
  String _choice = _kManual; // id du serveur choisi, ou _kManual
  // Valeurs : serveur (manuel), identifiant, mot de passe.
  String _manualUrl = '';
  String _user = '';
  String _pass = '';
  // Champ actif : 0=serveur(manuel), 1=identifiant, 2=mot de passe.
  int _active = 1;
  bool _busy = false;
  String? _error;

  bool get _manual => _choice == _kManual;
  String get _serverUrl => _manual
      ? _manualUrl
      : (_servers
          .firstWhere((DefaultServer s) => s.id == _choice,
              orElse: () => const DefaultServer(id: '', label: '', url: ''))
          .url);

  static const List<String> _keys = <String>[
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    '.', ':', '/', '-', '_', '@',
  ];

  @override
  void initState() {
    super.initState();
    DefaultServersApi.fetch().then((List<DefaultServer> list) {
      if (!mounted) return;
      final List<DefaultServer> ok =
          list.where((DefaultServer s) => s.url.isNotEmpty).toList();
      setState(() {
        _servers = ok;
        // S'il y a des serveurs du panel → on en sélectionne un par défaut
        // (le client n'a plus qu'à taper son code). Sinon → saisie manuelle.
        if (ok.isNotEmpty) {
          _choice = ok.first.id;
          _active = 1; // identifiant
        } else {
          _choice = _kManual;
          _active = 0; // serveur
        }
      });
    });
  }

  void _type(String c) {
    setState(() {
      if (_active == 0) {
        _manualUrl += c;
      } else if (_active == 1) {
        _user += c;
      } else {
        _pass += c;
      }
    });
  }

  void _back() {
    setState(() {
      if (_active == 0 && _manualUrl.isNotEmpty) {
        _manualUrl = _manualUrl.substring(0, _manualUrl.length - 1);
      } else if (_active == 1 && _user.isNotEmpty) {
        _user = _user.substring(0, _user.length - 1);
      } else if (_active == 2 && _pass.isNotEmpty) {
        _pass = _pass.substring(0, _pass.length - 1);
      }
    });
  }

  void _clearActive() {
    setState(() {
      if (_active == 0) {
        _manualUrl = '';
      } else if (_active == 1) {
        _user = '';
      } else {
        _pass = '';
      }
    });
  }

  Future<void> _validate() async {
    final String errFill = context.l10n.tvAddListError;
    final String errConn = context.l10n.tvConnectError;
    final String server = _serverUrl.trim();
    if (server.isEmpty || _user.trim().isEmpty || _pass.trim().isEmpty) {
      setState(() => _error = errFill);
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await PlaylistRepository.instance.addXtreamPlaylist(
        name: _manual ? 'Ma liste' : (_servers
            .firstWhere((DefaultServer s) => s.id == _choice,
                orElse: () => const DefaultServer(id: '', label: 'Ma liste', url: ''))
            .label),
        serverUrl: server,
        username: _user.trim(),
        password: _pass.trim(),
      );
      if (mounted) Navigator.of(context).pop(); // le gate ouvre l'app
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = errConn; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
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
                      weight: FontWeight.w600, color: TvTokens.mutedDim, spacing: 2)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final DefaultServer s in _servers)
                    _ServerChip(
                      label: s.label,
                      selected: _choice == s.id,
                      onSelect: () => setState(() {
                        _choice = s.id;
                        _active = 1; // → identifiant
                      }),
                    ),
                  _ServerChip(
                    label: context.l10n.tvManualServer,
                    selected: _manual,
                    onSelect: () => setState(() {
                      _choice = _kManual;
                      _active = 0; // → serveur
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // ----- Champs (serveur seulement si manuel) -----
            if (_manual) ...<Widget>[
              _Field(
                label: context.l10n.tvFieldServer,
                value: _manualUrl,
                active: _active == 0,
                onSelect: () => setState(() => _active = 0),
              ),
              const SizedBox(height: 10),
            ],
            _Field(
              label: context.l10n.tvFieldUser,
              value: _user,
              active: _active == 1,
              onSelect: () => setState(() => _active = 1),
            ),
            const SizedBox(height: 10),
            _Field(
              label: context.l10n.tvFieldPass,
              value: '•' * _pass.length,
              active: _active == 2,
              onSelect: () => setState(() => _active = 2),
            ),

            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_error!, style: TvTokens.ui(14, color: const Color(0xFFE0746A))),
            ],
            const SizedBox(height: 16),

            // ----- Clavier -----
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                for (final String k in _keys) _Key(label: k, onTap: () => _type(k)),
                _Key(label: '⌫', onTap: _back),
                _Key(label: '✕', onTap: _clearActive),
              ],
            ),
            const SizedBox(height: 22),

            TvCtaButton(
              label: _busy ? context.l10n.tvConnecting : context.l10n.tvAddListValidate,
              onSelect: _busy ? null : _validate,
            ),
          ],
        ),
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

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, required this.active, required this.onSelect});
  final String label;
  final String value;
  final bool active;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.large,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: TvTokens.card,
          borderRadius: BorderRadius.circular(TvTokens.rButton),
          border: Border.all(color: (active || focused) ? TvTokens.gold : TvTokens.line),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 160,
              child: Text(label.toUpperCase(),
                  style: TvTokens.ui(11, weight: FontWeight.w600, color: TvTokens.mutedDim, spacing: 2)),
            ),
            Expanded(
              child: Text(value.isEmpty ? '—' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.ui(18, weight: FontWeight.w500, color: TvTokens.text)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 50,
      child: TvFocusBuilder(
        scale: TvFocusScale.small,
        onSelect: onTap,
        builder: (BuildContext context, bool focused) => Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : TvTokens.sel,
            borderRadius: BorderRadius.circular(TvTokens.rSmall),
          ),
          child: Text(label,
              style: TvTokens.ui(20,
                  weight: FontWeight.w600,
                  color: focused ? const Color(0xFF1A1206) : TvTokens.text)),
        ),
      ),
    );
  }
}
