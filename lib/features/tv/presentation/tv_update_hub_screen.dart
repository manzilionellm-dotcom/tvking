// =========================================================
//  tv_update_hub_screen.dart — LE bouton « Mise à jour » de l'accueil
// =========================================================
//  DEMANDE CLIENT : « que ce soit un vrai, très fort bouton […] si tu
//  appuies, il te demande : tu veux la mise à jour des applications, des
//  mots de passe ou des listes de chaînes ? »
//
//  Avant, le bouton de l'accueil ne savait faire qu'UNE chose : chercher
//  une nouvelle version de l'APK. Les deux autres gestes que le client fait
//  réellement — re-télécharger ses chaînes, réparer un compte dont le
//  fournisseur a changé le mot de passe — existaient bien dans l'app, mais
//  enterrés dans les Réglages, à cinq appuis de télécommande. C'est cet
//  écran qui les met tous les trois au même endroit.
//
//  CE QUI EST VRAIMENT FAIT (aucune entrée décorative) :
//    • Application    → checkForUpdatesInteractive : cherche, télécharge,
//                       installe PAR-DESSUS (rien n'est effacé).
//    • Listes de chaînes → PlaylistRepository.refreshAll() : re-télécharge
//                       TOUTES les sources, avec le compte rendu réel
//                       (« 2 sources sur 3 »), jamais un faux succès.
//    • Mots de passe  → sous-menu : identifiants du fournisseur (réparation
//                       EN PLACE, la source garde son id) ou code parental.
//
//  10-FOOT : trois grandes lignes, une par geste, titre + explication en
//  clair. Pas de jargon : « listes de chaînes », pas « playlists » ;
//  « identifiants du fournisseur », pas « credentials Xtream ».
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/update/update_prompt.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/domain/playlist.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_add_source_screen.dart';
import 'tv_parental_screen.dart';
import 'tv_shell.dart';

class TvUpdateHubScreen extends StatefulWidget {
  const TvUpdateHubScreen({super.key});

  @override
  State<TvUpdateHubScreen> createState() => _TvUpdateHubScreenState();
}

class _TvUpdateHubScreenState extends State<TvUpdateHubScreen> {
  /// Rafraîchissement des chaînes en cours : la ligne se verrouille et
  /// montre son propre indicateur. On NE bloque PAS l'écran entier — le
  /// client peut encore redescendre sur « Mots de passe ».
  bool _refreshingChannels = false;

  /// Compte rendu de la dernière opération, affiché SOUS la ligne
  /// concernée. Une box n'a pas de barre de notification : un SnackBar qui
  /// passe en 3 s se rate à 3 mètres de l'écran.
  String? _channelsReport;
  bool _channelsFailed = false;

  Future<void> _refreshChannels() async {
    if (_refreshingChannels) return;
    setState(() {
      _refreshingChannels = true;
      _channelsReport = null;
      _channelsFailed = false;
    });
    // Nombre de sources AVANT, pour dire « 2 sur 3 » plutôt qu'un « 2 »
    // qui ne veut rien dire.
    final int total =
        (await PlaylistRepository.instance.getAllPlaylists()).length;
    int ok = 0;
    Object? failure;
    try {
      ok = await PlaylistRepository.instance.refreshAll();
    } catch (e) {
      failure = e;
    }
    if (!mounted) return;
    setState(() {
      _refreshingChannels = false;
      if (failure != null) {
        _channelsFailed = true;
        _channelsReport = 'Échec de la mise à jour des chaînes. '
            'Vérifiez la connexion de la box, puis réessayez.';
      } else if (total == 0) {
        // Cas honnête : rien à rafraîchir, ce n'est pas un succès.
        _channelsFailed = true;
        _channelsReport =
            'Aucune source enregistrée. Ajoutez d\'abord une liste de '
            'chaînes dans Réglages → Mes sources.';
      } else if (ok == 0) {
        _channelsFailed = true;
        _channelsReport = 'Aucune source n\'a pu être mise à jour '
            '(0 sur $total). Le compte est peut-être expiré : essayez '
            '« Mots de passe ».';
      } else {
        _channelsFailed = ok < total;
        _channelsReport = ok == total
            ? (total == 1
                ? 'Chaînes à jour.'
                : 'Chaînes à jour · $total sources.')
            : 'Mise à jour partielle : $ok source(s) sur $total. '
                'Les autres n\'ont pas répondu.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Mise à jour',
          style: TextStyle(
            fontSize: TvDimens.displayS,
            fontWeight: FontWeight.w800,
            color: TvTokens.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Que voulez-vous mettre à jour ?',
          style: TextStyle(fontSize: TvDimens.body, color: TvTokens.muted),
        ),
        const SizedBox(height: 22),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(right: 6, bottom: 12),
            children: <Widget>[
              TvUpdateChoiceRow(
                icon: Icons.system_update_rounded,
                title: 'L\'application',
                subtitle: 'Chercher une nouvelle version et l\'installer '
                    'par-dessus. Vos sources et vos favoris sont conservés.',
                autofocus: true,
                onSelect: () =>
                    unawaited(checkForUpdatesInteractive(context)),
              ),
              const SizedBox(height: 12),
              TvUpdateChoiceRow(
                icon: Icons.live_tv_rounded,
                title: 'Les listes de chaînes',
                subtitle: 'Re-télécharger toutes vos sources : nouvelles '
                    'chaînes, chaînes retirées, catégories.',
                busy: _refreshingChannels,
                busyLabel: 'Mise à jour des chaînes en cours…',
                report: _channelsReport,
                reportIsError: _channelsFailed,
                onSelect: () => unawaited(_refreshChannels()),
              ),
              const SizedBox(height: 12),
              TvUpdateChoiceRow(
                icon: Icons.key_rounded,
                title: 'Les mots de passe',
                subtitle: 'Identifiants de votre fournisseur (si vos chaînes '
                    'ne passent plus) ou code parental.',
                onSelect: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const TvShell(child: TvPasswordsHubScreen()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =========================================================
//  SOUS-MENU « MOTS DE PASSE »
// =========================================================
//  Deux mots de passe très différents cohabitent dans l'app, et les
//  confondre coûte cher au support :
//    • celui du FOURNISSEUR (compte Xtream) — quand il change, les chaînes
//      tombent en 401/403 et l'écran devient vide ;
//    • le CODE PARENTAL de la box — 4 chiffres, protège l'app.
//  D'où deux entrées nommées par leur effet, jamais par leur technologie.
// =========================================================
class TvPasswordsHubScreen extends StatelessWidget {
  const TvPasswordsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Mots de passe',
          style: TextStyle(
            fontSize: TvDimens.displayS,
            fontWeight: FontWeight.w800,
            color: TvTokens.text,
          ),
        ),
        const SizedBox(height: 22),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(right: 6, bottom: 12),
            children: <Widget>[
              TvUpdateChoiceRow(
                icon: Icons.vpn_key_rounded,
                title: 'Identifiants du fournisseur',
                subtitle: 'Votre abonnement a changé de mot de passe et les '
                    'chaînes ne passent plus ? Corrigez-le ici : la source '
                    'est réparée sur place, rien n\'est supprimé.',
                autofocus: true,
                onSelect: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const TvShell(child: TvRepairSourceScreen()),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TvUpdateChoiceRow(
                icon: Icons.lock_rounded,
                title: 'Code parental',
                subtitle: 'Changer les 4 chiffres qui protègent l\'app et '
                    'les chaînes réservées aux adultes.',
                onSelect: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TvShell(child: TvParentalScreen()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =========================================================
//  CHOIX DE LA SOURCE À RÉPARER
// =========================================================
//  Une seule source (le cas courant) : on n'inflige pas un écran de
//  sélection à un seul élément, mais on l'affiche quand même — le client
//  doit VOIR laquelle il s'apprête à toucher avant de taper un mot de
//  passe. Les sources M3U sont listées en grisé : elles n'ont pas de
//  couple identifiant/mot de passe à réparer, c'est leur lien qu'il faut
//  changer.
// =========================================================
class TvRepairSourceScreen extends StatelessWidget {
  const TvRepairSourceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Quelle source réparer ?',
          style: TextStyle(
            fontSize: TvDimens.displayS,
            fontWeight: FontWeight.w800,
            color: TvTokens.text,
          ),
        ),
        const SizedBox(height: 22),
        Expanded(
          child: StreamBuilder<List<Playlist>>(
            stream: PlaylistRepository.instance.playlistsStream,
            initialData: PlaylistRepository.instance.currentPlaylists,
            builder:
                (BuildContext context, AsyncSnapshot<List<Playlist>> snap) {
              final List<Playlist> all = snap.data ?? const <Playlist>[];
              final List<Playlist> xtream = all
                  .where((Playlist p) => p.type == PlaylistType.xtream)
                  .toList();
              if (xtream.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      all.isEmpty
                          ? 'Aucune source enregistrée.'
                          : 'Vos sources sont des liens M3U : elles n\'ont '
                              'pas d\'identifiant à corriger. C\'est le lien '
                              'lui-même qu\'il faut remplacer, dans '
                              'Réglages → Mes sources.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: TvDimens.body,
                        color: TvTokens.mutedDim,
                      ),
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.only(right: 6, bottom: 12),
                itemCount: xtream.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (BuildContext context, int i) {
                  final Playlist p = xtream[i];
                  return TvUpdateChoiceRow(
                    icon: Icons.dns_rounded,
                    title: p.name,
                    subtitle: <String>[
                      if ((p.xtreamUsername ?? '').isNotEmpty)
                        'Identifiant : ${p.xtreamUsername}',
                      if (p.channelCount > 0) '${p.channelCount} chaînes',
                    ].join(' · '),
                    autofocus: i == 0,
                    onSelect: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TvShell(
                          child: TvAddSourceScreen(
                            // Réparation EN PLACE : la source garde son id,
                            // ses chaînes sont re-téléchargées avec le
                            // compte corrigé (cf. updateXtreamCredentials).
                            replacePlaylistId: p.id,
                            initialServer: p.xtreamServer,
                            initialUsername: p.xtreamUsername,
                            initialPassword: p.xtreamPassword,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// =========================================================
//  LA GRANDE LIGNE DE CHOIX (partagée par les trois écrans)
// =========================================================
//  Haute, contrastée, lisible à 3 mètres : titre en gras, explication en
//  dessous. À l'état occupé, elle se verrouille et affiche sa propre
//  progression — un bouton qui ne réagit pas est un bouton qu'on martèle.
// =========================================================
class TvUpdateChoiceRow extends StatelessWidget {
  const TvUpdateChoiceRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onSelect,
    this.autofocus = false,
    this.busy = false,
    this.busyLabel,
    this.report,
    this.reportIsError = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onSelect;
  final bool autofocus;

  /// Opération en cours : la ligne n'accepte plus OK et montre sa barre.
  final bool busy;
  final String? busyLabel;

  /// Compte rendu affiché SOUS la ligne (reste à l'écran, ne s'efface pas
  /// tout seul comme un SnackBar).
  final String? report;
  final bool reportIsError;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      autofocus: autofocus,
      enabled: !busy,
      onSelect: busy ? null : onSelect,
      builder: (BuildContext context, bool focused) => AnimatedContainer(
        duration: TvDimens.focusAnim,
        curve: TvDimens.focusCurve,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        decoration: BoxDecoration(
          color: focused ? TvTokens.sel : TvTokens.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: focused
                ? TvTokens.goldBright
                : TvTokens.line.withValues(alpha: 0.9),
            width: focused ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: TvTokens.badgeBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    size: 28,
                    color: focused ? TvTokens.goldBright : TvTokens.gold,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: TvDimens.title,
                          fontWeight: FontWeight.w800,
                          color: TvTokens.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: TvDimens.body,
                          height: 1.35,
                          color: TvTokens.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!busy)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: focused ? TvTokens.goldBright : TvTokens.mutedDim,
                    size: 30,
                  ),
              ],
            ),
            if (busy) ...<Widget>[
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(TvTokens.gold),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      busyLabel ?? 'En cours…',
                      style: TextStyle(
                        fontSize: TvDimens.body,
                        color: TvTokens.gold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (!busy && report != null) ...<Widget>[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    reportIsError
                        ? Icons.error_outline_rounded
                        : Icons.check_circle_rounded,
                    size: 22,
                    color: reportIsError ? TvTokens.live : TvTokens.gold,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      report!,
                      style: TextStyle(
                        fontSize: TvDimens.body,
                        height: 1.35,
                        color: reportIsError
                            ? TvTokens.text
                            : TvTokens.gold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
