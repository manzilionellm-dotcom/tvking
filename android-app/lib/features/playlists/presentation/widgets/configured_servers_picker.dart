import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../data/default_servers.dart';

/// Suggestions facultatives du panel. Aucune sélection automatique et aucune
/// connexion : seule l'adresse visible change après un geste du client.
class ConfiguredServersPicker extends StatefulWidget {
  const ConfiguredServersPicker({
    super.key,
    required this.serverController,
    this.enabled = true,
    this.normalizeUrl,
  });

  final TextEditingController serverController;
  final bool enabled;
  final String Function(String)? normalizeUrl;

  @override
  State<ConfiguredServersPicker> createState() =>
      _ConfiguredServersPickerState();
}

class _ConfiguredServersPickerState extends State<ConfiguredServersPicker> {
  bool _manual = false;

  @override
  void initState() {
    super.initState();
    // Un ancien serveur sans catalogue laisse le formulaire manuel intact.
    unawaited(DefaultServersApi.fetch(forceRefresh: true));
  }

  String _url(DefaultServer server) =>
      widget.normalizeUrl?.call(server.url) ?? server.url;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<List<DefaultServer>>(
        valueListenable: DefaultServersApi.current,
        builder: (context, servers, _) {
          if (servers.isEmpty) return const SizedBox.shrink();
          return ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.serverController,
            builder: (context, value, _) {
              final selected = _manual
                  ? ''
                  : servers
                          .where((server) => _url(server) == value.text.trim())
                          .map((server) => server.id)
                          .firstOrNull ??
                      '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DropdownButtonFormField<String>(
                  key: ValueKey<String>('configured-servers-$selected'),
                  initialValue: selected,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: context.l10n.tvChooseServer),
                  items: <DropdownMenuItem<String>>[
                    DropdownMenuItem(
                        value: '', child: Text(context.l10n.tvManualServer)),
                    for (final server in servers)
                      DropdownMenuItem(
                          value: server.id,
                          child: Text(
                              server.label.isEmpty
                                  ? Uri.parse(server.url).host
                                  : server.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: !widget.enabled
                      ? null
                      : (id) {
                          if (id == null) return;
                          setState(() => _manual = id.isEmpty);
                          if (id.isEmpty) return;
                          final server = servers
                              .where((item) => item.id == id)
                              .firstOrNull;
                          if (server == null) return;
                          final url = _url(server);
                          widget.serverController.value = TextEditingValue(
                              text: url,
                              selection:
                                  TextSelection.collapsed(offset: url.length));
                        },
                ),
              );
            },
          );
        },
      );
}
