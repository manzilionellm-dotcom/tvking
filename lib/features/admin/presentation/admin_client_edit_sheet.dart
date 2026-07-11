// =========================================================
//  admin_client_edit_sheet.dart — Formulaire ajout/modif client
// =========================================================
//  Bottom sheet plein écran avec un formulaire :
//    - MAC (en mode ajout)
//    - Nom du client (optionnel, libellé humain)
//    - Type playlist : M3U ou Xtream
//      → M3U : URL + URL EPG (optionnelle)
//      → Xtream : serveur + username + password
//    - Nom de la playlist
//
//  Pour cette première version : 1 client = 1 playlist. Les
//  clients qui ont DÉJÀ plusieurs playlists ne perdent rien
//  (on conserve telles quelles, on n'édite que la 1ère).
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../playlists/data/source_link_utils.dart';
import '../data/admin_client.dart';

class AdminClientEditSheet extends StatefulWidget {
  const AdminClientEditSheet({super.key, this.existing});

  /// Si `null` → mode "Ajouter". Sinon → mode "Modifier".
  final AdminClient? existing;

  @override
  State<AdminClientEditSheet> createState() => _AdminClientEditSheetState();
}

class _AdminClientEditSheetState extends State<AdminClientEditSheet> {
  final TextEditingController _macCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _playlistNameCtrl = TextEditingController();
  final TextEditingController _m3uUrlCtrl = TextEditingController();
  final TextEditingController _epgUrlCtrl = TextEditingController();
  final TextEditingController _serverCtrl = TextEditingController();
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  String _type = 'm3u'; // 'm3u' | 'xtream'
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final AdminClient? c = widget.existing;
    if (c != null) {
      _macCtrl.text = c.mac;
      _nameCtrl.text = c.name;
      if (c.playlists.isNotEmpty) {
        final AdminPlaylist p = c.playlists.first;
        _playlistNameCtrl.text = p.name;
        _type = p.type;
        _m3uUrlCtrl.text = p.url ?? '';
        _epgUrlCtrl.text = p.epgUrl ?? '';
        _serverCtrl.text = p.server ?? '';
        _usernameCtrl.text = p.username ?? '';
        _passwordCtrl.text = p.password ?? '';
      }
    }
  }

  @override
  void dispose() {
    _macCtrl.dispose();
    _nameCtrl.dispose();
    _playlistNameCtrl.dispose();
    _m3uUrlCtrl.dispose();
    _epgUrlCtrl.dispose();
    _serverCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String? _validate() {
    final String mac = _macCtrl.text.trim().toUpperCase();
    if (!RegExp(r'^MK(?::[0-9A-F]{2}){5}$').hasMatch(mac)) {
      return context.l10n.adminMacInvalid;
    }
    // Le nom de playlist est optionnel — on met "Abonnement IPTV"
    // par défaut si vide. Permet à l'admin de juste taper MAC + URL.
    if (_type == 'm3u') {
      if (_m3uUrlCtrl.text.trim().isEmpty) {
        return context.l10n.adminM3uRequired;
      }
    } else {
      if (_serverCtrl.text.trim().isEmpty ||
          _usernameCtrl.text.trim().isEmpty ||
          _passwordCtrl.text.trim().isEmpty) {
        return context.l10n.adminXtreamFieldsRequired;
      }
    }
    return null;
  }

  /// Nettoie les liens AVANT validation/enregistrement — ESSENTIEL ici :
  /// ce panel POUSSE directement la config vers les appareils clients
  /// (cf. RemoteSourceRepository). Un lien mal formé ici cassait
  /// silencieusement chez le client, des jours plus tard, sans le moindre
  /// message d'erreur visible pour l'admin.
  ///   - complète http:// si seul le domaine a été donné ;
  ///   - si le fournisseur n'a donné qu'UN lien complet (get.php?username=
  ///     …&password=…) et qu'il a été collé dans le champ « serveur »
  ///     alors que utilisateur/mot de passe sont vides, on les en extrait.
  void _normalizeInputs() {
    if (_type == 'm3u') {
      _m3uUrlCtrl.text = SourceLinkUtils.ensureScheme(_m3uUrlCtrl.text);
      final String epg = _epgUrlCtrl.text.trim();
      if (epg.isNotEmpty) {
        _epgUrlCtrl.text = SourceLinkUtils.ensureScheme(epg);
      }
      return;
    }
    final String rawServer = _serverCtrl.text;
    _serverCtrl.text = SourceLinkUtils.ensureScheme(rawServer);
    if (_usernameCtrl.text.trim().isEmpty || _passwordCtrl.text.trim().isEmpty) {
      final ({String server, String username, String password})? extracted =
          SourceLinkUtils.tryExtractXtreamCredentials(rawServer);
      if (extracted != null) {
        _serverCtrl.text = extracted.server;
        if (_usernameCtrl.text.trim().isEmpty) {
          _usernameCtrl.text = extracted.username;
        }
        if (_passwordCtrl.text.trim().isEmpty) {
          _passwordCtrl.text = extracted.password;
        }
      }
    }
  }

  void _save() {
    _normalizeInputs();
    final String? err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.live,
          content: Text(err, style: AppTextStyles.bodyMedium),
        ),
      );
      return;
    }
    setState(() => _saving = true);

    final String pName = _playlistNameCtrl.text.trim().isEmpty
        ? context.l10n.adminDefaultPlaylistName
        : _playlistNameCtrl.text.trim();

    final AdminPlaylist playlist = AdminPlaylist(
      name: pName,
      type: _type,
      url: _type == 'm3u' ? _m3uUrlCtrl.text.trim() : null,
      epgUrl:
          _type == 'm3u' && _epgUrlCtrl.text.trim().isNotEmpty
              ? _epgUrlCtrl.text.trim()
              : null,
      server: _type == 'xtream' ? _serverCtrl.text.trim() : null,
      username: _type == 'xtream' ? _usernameCtrl.text.trim() : null,
      password: _type == 'xtream' ? _passwordCtrl.text.trim() : null,
    );

    // Si le client existait, on garde ses anciennes playlists et on
    // remplace seulement la 1ère. Sinon liste = [playlist].
    List<AdminPlaylist> playlists;
    if (widget.existing != null && widget.existing!.playlists.length > 1) {
      playlists = <AdminPlaylist>[
        playlist,
        ...widget.existing!.playlists.skip(1),
      ];
    } else {
      playlists = <AdminPlaylist>[playlist];
    }

    final AdminClient result = AdminClient(
      mac: _macCtrl.text.trim().toUpperCase(),
      name: _nameCtrl.text.trim(),
      addedAt: widget.existing?.addedAt ??
          DateTime.now().millisecondsSinceEpoch,
      playlists: playlists,
    );

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (BuildContext context, ScrollController controller) {
          return Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
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
                Text(
                  _isEdit
                      ? context.l10n.adminEditClientTitle
                      : context.l10n.adminNewClient,
                  style: AppTextStyles.headlineLarge.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 16),
                _label(context.l10n.adminClientMacLabel),
                TextField(
                  controller: _macCtrl,
                  enabled: !_isEdit, // MAC immuable en modif
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: <TextInputFormatter>[
                    UpperCaseTextFormatter(),
                  ],
                  decoration: const InputDecoration(
                    hintText: 'MK:AA:BB:CC:DD:EE',
                  ),
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 14),
                _label(context.l10n.adminClientNameLabel),
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    hintText: context.l10n.adminClientNameHint,
                  ),
                ),
                const SizedBox(height: 20),
                _SectionDivider(label: context.l10n.adminPlaylistSection),
                const SizedBox(height: 12),
                _typeSwitcher(),
                const SizedBox(height: 14),
                _label(context.l10n.adminPlaylistNameLabel),
                TextField(
                  controller: _playlistNameCtrl,
                  decoration: InputDecoration(
                    hintText: context.l10n.adminPlaylistNameHint,
                  ),
                ),
                const SizedBox(height: 14),
                if (_type == 'm3u') ...<Widget>[
                  _label(context.l10n.loginUrlM3u),
                  TextField(
                    controller: _m3uUrlCtrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText:
                          'http://serveur.com/get.php?username=…&type=m3u_plus',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _label(context.l10n.adminEpgUrlLabel),
                  TextField(
                    controller: _epgUrlCtrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText: 'http://serveur.com/xmltv.php?…',
                    ),
                  ),
                ] else ...<Widget>[
                  _label(context.l10n.loginServerXtream),
                  TextField(
                    controller: _serverCtrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText: 'http://serveur.com:8080',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _label(context.l10n.loginUsername),
                  TextField(
                    controller: _usernameCtrl,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                  _label(context.l10n.loginPassword),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    autocorrect: false,
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: Icon(_isEdit
                        ? Icons.save_rounded
                        : Icons.check_rounded),
                    label: Text(
                      _isEdit
                          ? context.l10n.buttonSave
                          : context.l10n.buttonAdd,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.l10n.buttonCancel),
                  ),
                ),
              ],
            ),
          );
        },
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

  Widget _typeSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _typeButton('M3U', 'm3u'),
          ),
          Expanded(
            child: _typeButton(context.l10n.playlistTypeXtream, 'xtream'),
          ),
        ],
      ),
    );
  }

  Widget _typeButton(String label, String value) {
    final bool selected = _type == value;
    return GestureDetector(
      onTap: () => setState(() => _type = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTextStyles.bodyLarge.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected
                ? AppColors.voidSurface
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: Divider(color: AppColors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textTertiary,
              fontSize: 10,
              letterSpacing: 1.6,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppColors.border)),
      ],
    );
  }
}
