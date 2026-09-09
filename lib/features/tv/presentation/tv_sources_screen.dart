// =========================================================
//  tv_sources_screen.dart — « Mes sources » (gérer M3U / Xtream)
// =========================================================
//  Le client gère SES sources : en ajouter (Xtream ou M3U), en activer une
//  (= celle dont les chaînes s'affichent), ou en supprimer. Modèle « une source
//  active à la fois » (activer une autre = désactiver la précédente).
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/app/device_memory.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../playlists/data/playlist_repository.dart';
import 'tv_components.dart';
import '../../playlists/data/source_opt_outs.dart';
import '../../playlists/domain/playlist.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_shell.dart';
import 'tv_smart_add_screen.dart';

class TvSourcesScreen extends StatelessWidget {
  const TvSourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(context.l10n.tvSourcesTitle,
                style: TextStyle(
                    fontSize: TvDimens.displayS,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.text)),
            const Spacer(),
            // UNE SEULE porte d'entrée : l'aiguillage intelligent devine
            // tout seul si le lien collé est M3U ou Xtream — le client n'a
            // plus à choisir un jargon qu'il ne connaît pas.
            _Pill(
              icon: Icons.add_rounded,
              label: context.l10n.tvSourceAddTitle,
              autofocus: true,
              onSelect: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (_) => const TvShell(child: TvSmartAddScreen()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<List<Playlist>>(
            stream: PlaylistRepository.instance.playlistsStream,
            initialData: PlaylistRepository.instance.currentPlaylists,
            builder: (BuildContext context, AsyncSnapshot<List<Playlist>> snap) {
              final List<Playlist> items = snap.data ?? const <Playlist>[];
              if (items.isEmpty) {
                return Center(
                  child: Text(
                    context.l10n.tvSourcesEmpty,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: TvDimens.body, color: TvTokens.mutedDim),
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

  /// Lien EXACT de la source (serveur Xtream ou URL M3U) — pour le
  /// diagnostic à distance. Vide si absent.
  String get _diagLink {
    if (_xtream) return (playlist.xtreamServer ?? '').trim();
    return (playlist.m3uUrl ?? '').trim();
  }

  /// Identifiant Xtream (username) — vide pour une source M3U.
  String get _diagUser => (playlist.xtreamUsername ?? '').trim();

  /// LE NOMBRE DE CHAÎNES — le VRAI, compté en base à chaque affichage.
  ///
  //  CONSTATÉ PAR LE PROPRIÉTAIRE (09/09/2026), capture à l'appui : sa box
  //  annonçait « 25000 channels » alors que ce n'était pas le compte de son
  //  abonnement.
  //
  //  Il avait raison, et ce n'était pas un problème d'affichage. On lisait
  //  `playlist.channelCount`, une valeur gravée UNE FOIS à l'import. Or
  //  l'import s'arrête au plafond mémoire de l'appareil — 25 000 pile sur
  //  une box de 2 Go (DeviceMemory.channelCap). Le chiffre affiché n'était
  //  donc pas la taille de l'abonnement mais LA LIMITE DE LA BOX, et il ne
  //  bougeait plus jamais, même après un ré-import qui en chargeait plus.
  //
  //  Deux corrections, et la seconde compte autant que la première :
  //
  //   1. ON COMPTE. `countChannelsOf` fait un COUNT sur colonne indexée —
  //      quelques millisecondes. Le chiffre suit désormais la réalité de la
  //      base, ré-import compris.
  //
  //   2. ON SIGNALE LA TRONCATURE. Quand le compte atteint exactement le
  //      plafond de l'appareil, c'est que la liste a été COUPÉE : il y a
  //      « au moins » ce nombre-là, pas « exactement ». On écrit donc un
  //      « + ». Sans lui, on remplacerait un chiffre faux par un autre
  //      chiffre faux, simplement mieux calculé.
  //
  //  Le « + » n'a besoin d'aucune traduction — il se lit pareil dans les
  //  huit langues de l'app.
  Widget _countLine(BuildContext context) {
    final Color couleur = playlist.isActive ? TvTokens.gold : TvTokens.muted;
    final TextStyle style =
        TextStyle(fontSize: TvDimens.label, color: couleur);
    final String suffixeActif =
        playlist.isActive ? '  ·  ${context.l10n.tvSourceActiveSuffix}' : '';

    String rendu(int n) {
      // `>=` et non `==` : un plafond qui changerait (mise à jour de l'app,
      // box remplacée) laisserait sinon passer le cas tronqué en silence.
      final bool tronque = n > 0 && n >= DeviceMemory.channelCap;
      return '${context.l10n.channelCount(n)}${tronque ? ' +' : ''}$suffixeActif';
    }

    final int? id = playlist.id;
    // Playlist pas encore enregistrée : rien à compter, on montre ce qu'on a.
    if (id == null) return Text(rendu(playlist.channelCount), style: style);

    return FutureBuilder<int>(
      // Le compte est relancé à chaque reconstruction de la rangée. C'est
      // volontaire et sans coût mesurable : cet écran affiche une poignée
      // de sources, et un COUNT indexé se paie en millisecondes. En
      // échange, le chiffre est JUSTE juste après un ré-import, sans qu'on
      // ait à inventer un mécanisme d'invalidation.
      future: PlaylistRepository.instance.countChannelsOf(id),
      // Tant que la base répond, on affiche l'ancien chiffre plutôt qu'un
      // vide qui ferait clignoter la ligne.
      initialData: playlist.channelCount,
      builder: (BuildContext _, AsyncSnapshot<int> snap) =>
          Text(rendu(snap.data ?? playlist.channelCount), style: style),
    );
  }

  /// Ligne « icône + valeur » monospace, discrète, lisible à l'écran TV.
  /// Sélectionnable pour pouvoir copier le lien depuis un clavier/souris.
  Widget _diagRow(IconData icon, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 13, color: TvTokens.muted),
        const SizedBox(width: 6),
        Expanded(
          child: SelectableText(
            value,
            maxLines: 2,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.3,
              color: TvTokens.muted,
            ),
          ),
        ),
      ],
    );
  }

  /// RE-IMPORT du contenu de la source (photo client : il n'existait AUCUN
  /// bouton TV qui re-télécharge vraiment le contenu — les « rafraîchir »
  /// existants ne relisaient que la base locale). Ici : le MÊME
  /// `refreshPlaylist()` que le veilleur automatique (remplace les chaînes
  /// en base, l'UI se met à jour via le stream). Voile modal pendant le
  /// travail (pas de double lancement), dialogue en cas d'échec.
  Future<void> _refreshContent(BuildContext context) async {
    if (playlist.id == null) return;
    final NavigatorState nav = Navigator.of(context, rootNavigator: true);
    // ignore: discarded_futures
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: SizedBox(
          width: 46,
          height: 46,
          child: CircularProgressIndicator(strokeWidth: 3, color: TvTokens.gold),
        ),
      ),
    );
    String? error;
    try {
      await PlaylistRepository.instance.refreshPlaylist(playlist);
    } catch (e) {
      error = e.toString();
    }
    if (!context.mounted) return;
    nav.pop(); // ferme le voile de progression
    if (error != null) {
      // Carte premium partagée (plus d'AlertDialog Android nu).
      await showTvInfo(context,
          title: context.l10n.tvSourcesTitle,
          message: context.l10n.errorWithMessage(error));
    }
    // Succès : rien à afficher — le compteur de chaînes de la rangée se met
    // à jour tout seul via playlistsStream (preuve visible du re-import).
  }

  Future<void> _delete(BuildContext context) async {
    // Confirmation premium partagée — action DESTRUCTRICE → bouton rouge,
    // focus d'entrée sur Annuler (un OK réflexe ne supprime jamais rien).
    final bool? ok = await showTvConfirm(
      context,
      title: context.l10n.tvSourceDeleteConfirmTitle,
      message: context.l10n.tvSourceDeleteConfirmBody(playlist.name),
      confirmLabel: context.l10n.buttonDelete,
      danger: true,
    );
    if (ok != true || playlist.id == null) return;
    try {
      // SUPPRESSION DÉFINITIVE (retour client : « au redémarrage,
      // l'abonnement est toujours là ») : on pose l'empreinte AVANT le
      // delete — la provision automatique par MAC ne la re-importera plus.
      // Récupération : le revendeur re-pousse depuis le panel.
      await SourceOptOuts.markDeleted(playlist);
      await PlaylistRepository.instance.deletePlaylist(playlist.id!);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final Color badge = _xtream ? TvTokens.gold : const Color(0xFF5AA0E8);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: TvTokens.panel,
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(
            color: playlist.isActive ? TvTokens.gold : TvTokens.lineSoft,
            width: playlist.isActive ? 1.5 : 1),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badge.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(_xtream ? 'XTREAM' : 'M3U',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: badge)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: TvDimens.title,
                        fontWeight: FontWeight.w700,
                        color: TvTokens.text)),
                const SizedBox(height: 2),
                _countLine(context),
                // Lien + identifiant EXACTS de la source — indispensables
                // pour diagnostiquer à distance le problème d'un client
                // (« quel serveur / quel username tu vois ? »). Le mot de
                // passe n'est JAMAIS affiché.
                if (_diagLink.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 5),
                  _diagRow(Icons.link_rounded, _diagLink),
                ],
                if (_diagUser.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  _diagRow(Icons.person_outline_rounded, _diagUser),
                ],
              ],
            ),
          ),
          if (!playlist.isActive && playlist.id != null) ...<Widget>[
            _Pill(
                icon: Icons.play_arrow_rounded,
                label: context.l10n.tvSourceActivate,
                onSelect: () =>
                    PlaylistRepository.instance.setActivePlaylist(playlist.id!)),
            const SizedBox(width: 10),
          ],
          if (playlist.id != null) ...<Widget>[
            _Pill(
                icon: Icons.refresh_rounded,
                label: context.l10n.navRefresh,
                onSelect: () => _refreshContent(context)),
            const SizedBox(width: 10),
          ],
          _IconBtn(
              icon: Icons.delete_outline_rounded,
              onSelect: () => _delete(context)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(
      {required this.icon,
      required this.label,
      required this.onSelect,
      this.autofocus = false});
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
        final Color fg = focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : TvTokens.sel,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 19, color: fg),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: TvDimens.titleS,
                      fontWeight: FontWeight.w700,
                      color: fg)),
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
            color: focused ? TvTokens.live : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              size: 24, color: focused ? Colors.white : TvTokens.muted),
        );
      },
    );
  }
}
