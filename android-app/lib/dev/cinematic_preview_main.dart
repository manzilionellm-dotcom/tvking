// Aperçu LOCAL de l'accueil. Pas le point d'entrée de la box
// (`lib/main_tv.dart`). Aucune affiche tierce : les cartes sans URL
// montrent un monogramme. La touche Droite passe de l'ancien accueil
// (tuiles) à « Ce soir ».
//
//   flutter run -t lib/dev/cinematic_preview_main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app/box_memory_budget.dart';
import '../core/theme/bundled_fonts.dart';
import '../features/channels/domain/channel.dart';
import '../features/followed/domain/show_clock.dart';
import '../features/tv/core/tv_app_tokens.dart';
import '../features/tv/core/tv_dimens.dart';
import '../features/tv/core/tv_ghost.dart';
import '../features/tv/core/tv_tokens.dart';
import '../features/tv/presentation/tv_starfield.dart';
import '../features/tv/presentation/tv_cinematic_home.dart';
import '../features/tv/presentation/tv_shell.dart';
import '../features/tv/presentation/tv_tonight.dart';
import '../l10n/generated/app_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureTvFontLoading();
  // L'aperçu montre le reflet. Les box ≤ 2 Go ne le jouent pas :
  // le test tv_ghost_test le verrouille.
  BoxMemoryBudget.tier = BoxRamTier.roomy;
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const CinematicPreviewApp());
}

class CinematicPreviewApp extends StatelessWidget {
  const CinematicPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: TvTokens.bg,
        extensions: const <ThemeExtension<dynamic>>[TvAppTokens()],
      ),
      home: const _Stage(),
    );
  }
}

class _Stage extends StatefulWidget {
  const _Stage();
  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> {
  bool _after = false;

  @override
  void initState() {
    super.initState();
    // La capture « avant » a le temps de se faire, puis l'accueil
    // bascule tout seul (la touche n'arrive pas toujours à l'émulateur).
    Future<void>.delayed(const Duration(seconds: 8), () {
      if (mounted) setState(() => _after = true);
    });
  }

  TonightBoard get _board {
    Channel ch(String id, String name) => Channel(
          id: id,
          name: name,
          category: 'Général',
          streamUrl: 'http://example.test/$id',
          isLive: true,
        );
    return composeTonight(
      watching: const [],
      favorites: <Channel>[ch('a', 'Info'), ch('b', 'Sport'), ch('c', 'Cinéma')],
      popular: <Channel>[ch('d', 'Docu'), ch('e', 'Musique'), ch('f', 'Jeunesse')],
      resume: const [],
      guide: <GuideSlot>[
        GuideSlot(
          channelId: 'a',
          channelName: 'Info',
          title: 'Journal du soir',
          startMs: 0,
          stopMs: 3600000,
          catchupDeclared: false,
        ),
      ],
      reminders: const [],
      also: const [],
      nowMs: 1000,
      channelsById: <String, Channel>{'a': ch('a', 'Info')},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: _after
          ? Theme(
              data: Theme.of(context).copyWith(
                extensions: const <ThemeExtension<dynamic>>[
                  TvAppTokens(ghost: true),
                ],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const ColoredBox(color: TvGhost.bg),
                  const Positioned.fill(
                    child: GhostStarfield(animate: true),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 28,
                    ),
                    child: TvCinematicHome(
                      board: _board,
                      blur: false,
                      onPlay: (_) {},
                      onLive: () {},
                      onFilms: () {},
                      onSeries: () {},
                      onServer: () {},
                      onSettings: () {},
                    ),
                  ),
                ],
              ),
            )
          : const TvShell(child: _PreviousTiles()),
    );
  }
}

/// L'accueil d'avant : cinq tuiles or, centrées. Pas une copie pixel
/// à pixel, la disposition que la maquette remplace.
class _PreviousTiles extends StatelessWidget {
  const _PreviousTiles();

  @override
  Widget build(BuildContext context) {
    const List<IconData> icons = <IconData>[
      Icons.live_tv_rounded,
      Icons.movie_rounded,
      Icons.video_library_rounded,
      Icons.dns_rounded,
      Icons.settings_rounded,
    ];
    const List<String> labels = <String>[
      'Direct',
      'Films',
      'Séries',
      'Serveur',
      'Réglages',
    ];
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < icons.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Container(
                width: 150,
                height: 150,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == 0 ? TvTokens.accent : TvTokens.card,
                  borderRadius: BorderRadius.circular(TvTokens.rCard),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      icons[i],
                      size: 42,
                      color: i == 0 ? TvTokens.onAccent : TvTokens.accent,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: TvDimens.label,
                        fontWeight: FontWeight.w700,
                        color: i == 0 ? TvTokens.onAccent : TvTokens.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
