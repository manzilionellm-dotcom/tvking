// =========================================================
//  tv_sources_screen.dart — « Mes sources » (gérer M3U / Xtream)
// =========================================================
//  Le client gère SES sources : en ajouter (Xtream ou M3U), les activer /
//  désactiver, ou les supprimer.
//
//  TV = MODE FUSION : PLUSIEURS sources actives EN MÊME TEMPS, sans limite de
//  nombre — leurs chaînes arrivent ensemble dans Direct (et leurs films /
//  séries dans Cinéma). « Désactiver » retire une source de l'affichage sans
//  la supprimer ; « Activer » la remet instantanément (chaînes gardées en base).
//
//  IDENTIFICATION (demande du propriétaire 27/09/2026) : chaque ligne affiche
//  l'identifiant (username) et le serveur de la source — le revendeur voit
//  d'un coup d'œil QUEL abonnement est installé sur la box. Le mot de passe
//  n'est JAMAIS affiché.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/app/novatube_tv_edition.dart';

import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../../playlists/domain/open_source_input.dart';
import '../../playlists/domain/playlist.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import '../core/tv_app_tokens.dart';
import 'tv_add_source_screen.dart';
import 'novatube_max_m3u_batch.dart';
import 'tv_shell.dart';
import 'tv_source_error_text.dart';

class TvSourcesScreen extends StatelessWidget {
  const TvSourcesScreen({super.key});

  void _open(BuildContext context, OpenEntryMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvShell(child: TvAddSourceScreen(initialMode: mode)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
            Text(
              context.l10n.tvMySources,
              style: TextStyle(
                fontSize: TvDimens.displayS,
                fontWeight: FontWeight.w800,
                color: TvAppTokens.of(context).text,
              ),
            ),
            if (!kNovatubeMax) const Spacer(),
            _Pill(
              icon: Icons.add_rounded,
              label: context.l10n.tvAddXtream,
              autofocus: true,
              onSelect: () => _open(context, OpenEntryMode.xtream),
            ),
            if (!kNovatubeMax) const SizedBox(width: 12),
            _Pill(
              icon: Icons.playlist_add_rounded,
              label: context.l10n.tvAddM3u,
              onSelect: () => _open(context, OpenEntryMode.m3u),
            ),
            if (kNovatubeMax) _Pill(
              icon: Icons.library_add_rounded, label: context.l10n.novaBatchTitle,
              onSelect: () => showDialog<void>(context: context, barrierDismissible: false,
                builder: (_) => const MaxM3uBatchDialog()),
            ),
            if (!kNovatubeMax) const SizedBox(width: 12),
            _Pill(
              icon: Icons.play_circle_outline_rounded,
              label: OpenSourceInput.playerLabel,
              onSelect: () => _open(context, OpenEntryMode.player),
            ),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (kNovatubeMax)
          Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center,
              children: actions)
        else
          Row(children: actions),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<List<Playlist>>(
            stream: PlaylistRepository.instance.playlistsStream,
            initialData: PlaylistRepository.instance.currentPlaylists,
            builder:
                (BuildContext context, AsyncSnapshot<List<Playlist>> snap) {
                  final List<Playlist> items = snap.data ?? const <Playlist>[];
                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        context.l10n.tvSourcesEmpty,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: TvDimens.body,
                          color: TvAppTokens.of(context).mutedDim,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(right: 6, bottom: 8),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int i) =>
                        _SourceRow(playlist: items[i]),
                  );
                },
          ),
        ),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.playlist});
  final Playlist playlist;

  bool get _xtream => playlist.type == PlaylistType.xtream;

  /// Mode fusion (TV) : « active » = non désactivée. Sinon (historique) :
  /// la source unique marquée active.
  bool get _merge => PlaylistRepository.mergeAllPlaylists;
  bool get _on => _merge ? !playlist.hidden : playlist.isActive;

  Future<void> _edit(BuildContext context) async {
    String name = playlist.name;
    String address = '';
    bool busy = false;
    String? error;
    await showDialog<void>(context: context, builder: (dialog) => StatefulBuilder(
      builder: (ctx, update) => PopScope(canPop: !busy, child: AlertDialog(
        title: Text(ctx.l10n.tvMySources),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(initialValue: name, enabled: !busy,
            decoration: InputDecoration(labelText: ctx.l10n.tvFieldNameOptional),
            onChanged: (value) => name = value),
          TextField(enabled: !busy, obscureText: true, enableSuggestions: false,
            autocorrect: false, keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: ctx.l10n.tvFieldM3uUrl,
              hintText: playlist.reference.host),
            onChanged: (value) => address = value.trim()),
          if (error != null) Text(sourceErrorText(ctx, error!)),
          if (busy) const LinearProgressIndicator(),
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: Text(ctx.l10n.buttonCancel)),
          TextButton(onPressed: busy ? null : () async {
            if (address.isNotEmpty && !OpenSourceInput.playlistLink(address).isValid) {
              update(() => error = OpenSourceInput.errNeedUrl);
              return;
            }
            update(() {busy = true; error = null;});
            try {
              await RemoteSourceRepository.runUserImport(() =>
                PlaylistRepository.instance.editSource(playlist,
                  name: name.trim().isEmpty ? playlist.name : name.trim(),
                  address: address.isEmpty ? null : address));
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (failure) {
              if (ctx.mounted) update(() {busy = false; error = sourceFailureCode(failure);});
            }
          }, child: Text(ctx.l10n.buttonSave)),
        ],
      )),
    ));
  }

  Future<void> _refresh(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(context.l10n.libraryRefreshRunning)));
    try {
      final done = await RemoteSourceRepository.runUserImport(() =>
          PlaylistRepository.instance.refreshPlaylist(playlist));
      if (!done) throw StateError('source');
      if (context.mounted) messenger.hideCurrentSnackBar();
    } catch (failure) {
      if (context.mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(content: Text(sourceErrorText(context, sourceFailureCode(failure)))));
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    // Le choix local est définitif, y compris pour une liste venue du panel.
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: TvAppTokens.of(context).card,
        title: Text(
          context.l10n.tvDeleteQuestion,
          style: TextStyle(color: TvAppTokens.of(context).text),
        ),
        content: Text(
          context.l10n.tvDeleteSourceConfirm(playlist.name),
          style: TextStyle(color: TvAppTokens.of(context).muted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              context.l10n.tvCancel,
              style: TextStyle(color: TvAppTokens.of(context).muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.l10n.tvDelete,
              style: TextStyle(color: TvAppTokens.of(context).live),
            ),
          ),
        ],
      ),
    );
    if (ok != true || playlist.id == null) return;
    // Suppression locale durable ; retrait serveur tenté ensuite pour les
    // listes personnelles. Une simple synchronisation ne les rétablit pas.
    final bool done = await RemoteSourceRepository.deleteFromTv(playlist);
    if (!done && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.l10n.tvDeleteSourceFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Deux ors, pas un bleu étranger au reste de la Maison Noir.
    final Color badge = _xtream
        ? TvAppTokens.of(context).accent
        : TvAppTokens.of(context).accentBright;
    final ({String? user, String? host}) ref = playlist.reference;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: TvAppTokens.of(context).panel,
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(
          color: _on
              ? TvAppTokens.of(context).accent
              : TvAppTokens.of(context).lineSoft,
          width: _on ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badge.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              _xtream ? 'XTREAM' : 'M3U',
              style: TvAppTokens.of(context).ui(
                TvDimens.caption,
                weight: FontWeight.w700,
                spacing: 0.5,
                color: badge,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TvDimens.title,
                    fontWeight: FontWeight.w700,
                    color: TvAppTokens.of(context).text,
                  ),
                ),
                if (ref.user != null || ref.host != null) ...<Widget>[
                  const SizedBox(height: 4),
                  _Reference(user: kNovatubeTv ? null : ref.user, host: ref.host),
                ],
                const SizedBox(height: 4),
                Text(
                  '${context.l10n.tvSourceChannels(playlist.channelCount)}'
                  '  ·  '
                  '${_on ? '✓ ${context.l10n.tvSourceActive}' : context.l10n.tvSourceInactive}',
                  style: TextStyle(
                    fontSize: TvDimens.label,
                    color: _on
                        ? TvAppTokens.of(context).accent
                        : TvAppTokens.of(context).mutedDim,
                  ),
                ),
              ],
            ),
          ),
          if (playlist.id != null && _merge) ...<Widget>[
            // Bascule indépendante : les autres sources ne bougent pas.
            _Pill(
              icon: _on
                  ? Icons.pause_circle_outline_rounded
                  : Icons.play_arrow_rounded,
              label: _on ? context.l10n.tvDeactivate : context.l10n.tvActivate,
              onSelect: () => PlaylistRepository.instance.setPlaylistHidden(
                playlist.id!,
                _on,
              ),
            ),
            const SizedBox(width: 10),
          ] else if (!playlist.isActive && playlist.id != null) ...<Widget>[
            _Pill(
              icon: Icons.play_arrow_rounded,
              label: context.l10n.tvActivate,
              onSelect: () =>
                  PlaylistRepository.instance.setActivePlaylist(playlist.id!),
            ),
            const SizedBox(width: 10),
          ],
          if (kNovatubeTv) ...[
            Tooltip(message: context.l10n.tvRename, child: _IconBtn(
              icon: Icons.edit_outlined, onSelect: () => _edit(context))),
            Tooltip(message: context.l10n.tvRefresh, child: _IconBtn(
              icon: Icons.refresh_rounded, onSelect: () => _refresh(context))),
          ],
          _IconBtn(
            icon: Icons.delete_outline_rounded,
            onSelect: () => _delete(context),
          ),
        ],
      ),
    );
  }
}

/// Ligne de référence : 👤 identifiant   ·   🌐 serveur (sobre, lisible à 3 m).
class _Reference extends StatelessWidget {
  const _Reference({required this.user, required this.host});
  final String? user;
  final String? host;

  @override
  Widget build(BuildContext context) {
    final TextStyle st = TextStyle(
      fontSize: TvDimens.label,
      fontWeight: FontWeight.w600,
      color: TvAppTokens.of(context).text,
    );
    return Row(
      children: <Widget>[
        if (user != null) ...<Widget>[
          Icon(
            Icons.person_outline_rounded,
            size: 18,
            color: TvAppTokens.of(context).muted,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              user!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: st,
            ),
          ),
        ],
        if (user != null && host != null) const SizedBox(width: 16),
        if (host != null) ...<Widget>[
          Icon(
            Icons.dns_outlined,
            size: 18,
            color: TvAppTokens.of(context).muted,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              host!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: st.copyWith(
                fontWeight: FontWeight.w400,
                color: TvAppTokens.of(context).muted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.onSelect,
    this.autofocus = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.medium,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused
            ? TvAppTokens.of(context).onAccent
            : TvAppTokens.of(context).accentBright;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: focused
                ? TvAppTokens.of(context).accent
                : TvAppTokens.of(context).sel,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 19, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: TvDimens.titleS,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onSelect});
  final IconData icon;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: focused ? TvAppTokens.of(context).live : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 24,
            color: focused ? Colors.white : TvAppTokens.of(context).muted,
          ),
        );
      },
    );
  }
}
