// Import volontaire, séquentiel. Les URL saisies restent dans la session
// d'import et les résultats ne contiennent que l'hôte et un numéro local.
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../playlists/data/playlist_repository.dart';

class MaxM3uBatchDialog extends StatefulWidget {
  const MaxM3uBatchDialog({super.key});

  static List<({String name, String url})> entries(String text, Set<String> saved) {
    final seen = <String>{...saved};
    final entries = <({String name, String url})>[];
    for (final line in text.split('\n')) {
      final url = line.trim();
      if (url.isEmpty) continue;
      final uri = Uri.tryParse(url);
      if (uri == null || !{'https', 'http'}.contains(uri.scheme) ||
          uri.host.isEmpty || url.contains(RegExp(r'\s'))) {
        throw const FormatException();
      }
      if (seen.add(url)) {
        entries.add((name: '${uri.host} · ${entries.length + 1}', url: url));
      }
    }
    return entries;
  }

  @override
  State<MaxM3uBatchDialog> createState() => _MaxM3uBatchDialogState();
}

class _MaxM3uBatchDialogState extends State<MaxM3uBatchDialog> {
  final _input = TextEditingController();
  bool _busy = false;
  String? _error;
  int _current = 0;
  int _total = 0;
  List<BatchImportResult> _results = [];

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_busy) return;
    final repo = PlaylistRepository.instance;
    final known = <String>{
      for (final p in repo.currentPlaylists)
        if (p.m3uUrl != null) p.m3uUrl!,
    };
    late final List<({String name, String url})> entries;
    try {
      entries = MaxM3uBatchDialog.entries(_input.text, known);
    } on FormatException {
      setState(() => _error = context.l10n.tvAddM3uInvalidUrl);
      return;
    }
    if (entries.isEmpty) {
      setState(() => _error = _input.text.trim().isEmpty ?
          context.l10n.tvAddM3uInvalidUrl : context.l10n.novaBatchAlready);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; _current = 0; _total = entries.length; });
    try {
      final results = await repo.addM3uPlaylistsBatch(entries: entries,
          onProgress: (index, total, name, result) {
            if (mounted && result != null) setState(() => _current = index);
          });
      if (mounted) {
        // Ne garder dans le champ que les adresses qui restent à réessayer.
        final failed = <String>[for (int i = 0; i < results.length; i++)
          if (!results[i].ok) entries[i].url];
        _input.text = failed.join('\n');
        setState(() => _results = results);
      }
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.tvAddM3uFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PopScope(canPop: !_busy, child: AlertDialog(
      title: Text(l.novaBatchTitle),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: _input, enabled: !_busy, minLines: 2, maxLines: 5,
            keyboardType: TextInputType.multiline, autocorrect: false, enableSuggestions: false,
            decoration: InputDecoration(labelText: l.novaBatchHint, errorText: _error,
              border: const OutlineInputBorder())),
          if (_busy) ...[const SizedBox(height: 8),
            LinearProgressIndicator(value: _total == 0 ? null : _current / _total),
            Text('$_current / $_total')],
          for (final row in _results)
            ListTile(dense: true, leading: Icon(row.ok ? Icons.check_circle : Icons.error_outline),
              title: Text(row.name), subtitle: Text(row.ok ? l.channelCount(row.channelCount) : l.tvAddM3uFailed)),
        ],
      ))),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(l.tvClose)),
        FilledButton(onPressed: _busy ? null : _import, child: Text(l.tvAddM3u)),
      ],
    ));
  }
}
