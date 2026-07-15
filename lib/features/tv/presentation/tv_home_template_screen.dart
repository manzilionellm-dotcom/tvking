// =========================================================
//  tv_home_template_screen.dart — « Changer les templates » (sélecteur)
// =========================================================
//  L'utilisateur choisit la disposition de son accueil, avec un APERÇU
//  visuel de chaque template. Application immédiate + persistance
//  (TvHomeTemplateRepository). 100 % télécommande.
// =========================================================
import 'package:flutter/material.dart';

import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_home_template.dart';
import '../core/tv_tokens.dart';
import 'tv_shell.dart';

class TvHomeTemplateScreen extends StatelessWidget {
  const TvHomeTemplateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TvShell(
      child: ListenableBuilder(
        listenable: TvHomeTemplateRepository.instance,
        builder: (BuildContext context, Widget? _) {
          final TvHomeTemplate current =
              TvHomeTemplateRepository.instance.template;
          final List<TvHomeTemplate> all = TvHomeTemplate.values;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Changer les templates',
                  style: TvTokens.ui(TvDimens.displayS, weight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'Choisis la disposition de ton accueil — appliquée tout de suite.',
                style: TvTokens.ui(TvDimens.body, color: TvTokens.muted),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (int i = 0; i < all.length; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                              right: i == all.length - 1 ? 0 : 18),
                          child: _TemplateCard(
                            template: all[i],
                            selected: all[i] == current,
                            autofocus: all[i] == current,
                            onSelect: () async {
                              await TvHomeTemplateRepository.instance
                                  .setTemplate(all[i]);
                              if (context.mounted) {
                                Navigator.of(context).maybePop();
                              }
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.autofocus,
    required this.onSelect,
  });
  final TvHomeTemplate template;
  final bool selected;
  final bool autofocus;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color border = focused
            ? TvTokens.goldBright
            : selected
                ? TvTokens.gold
                : TvTokens.hairline;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: focused ? TvTokens.sel : TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rCard),
            border: Border.all(color: border, width: focused || selected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: _TemplatePreview(template: template)),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(template.label,
                        style: TvTokens.ui(TvDimens.title,
                            weight: FontWeight.w700, color: TvTokens.text)),
                  ),
                  if (selected)
                    const Icon(Icons.check_circle_rounded,
                        color: TvTokens.gold, size: 24),
                ],
              ),
              const SizedBox(height: 4),
              Text(template.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.ui(TvDimens.caption, color: TvTokens.muted)),
            ],
          ),
        );
      },
    );
  }
}

/// Aperçu miniature (mock) de la disposition, dessiné en simples blocs.
class _TemplatePreview extends StatelessWidget {
  const _TemplatePreview({required this.template});
  final TvHomeTemplate template;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: TvTokens.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: TvTokens.line),
        ),
        child: _mockFor(template),
      ),
    );
  }

  Widget _mockFor(TvHomeTemplate t) {
    switch (t) {
      case TvHomeTemplate.launcher:
        return _launcherMock();
      case TvHomeTemplate.rails:
        return _railsMock();
      case TvHomeTemplate.classic:
        return _classicMock();
    }
  }

  // Rails : barre haute + héro/colonne + rangée d'icônes + rail bas.
  Widget _railsMock() {
    Widget iconRow(int n) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < n; i++) ...<Widget>[
              Expanded(child: _box()),
              if (i != n - 1) const SizedBox(width: 4),
            ],
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 8,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Spacer(flex: 6),
              Expanded(flex: 3, child: _box(color: _accent)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          flex: 4,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(flex: 66, child: _box(color: _accent)),
              const SizedBox(width: 6),
              Expanded(
                flex: 32,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: _box()),
                    const SizedBox(height: 4),
                    Expanded(child: _box()),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(height: 12, child: iconRow(5)),
        const SizedBox(height: 6),
        Expanded(flex: 2, child: iconRow(4)),
      ],
    );
  }

  Widget _box({Color? color, double radius = 4}) => Container(
        decoration: BoxDecoration(
          color: color ?? TvTokens.card,
          borderRadius: BorderRadius.circular(radius),
        ),
      );

  Color get _accent => TvTokens.gold.withValues(alpha: 0.55);

  // Classique : barre haute (pastilles) + grand contenu.
  Widget _classicMock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 10,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(flex: 3, child: _box(color: _accent)),
              const Spacer(flex: 5),
              Expanded(flex: 4, child: _box()),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _box()),
      ],
    );
  }

  // Lanceur : héro + cluster 2×2 + colonne de boutons.
  Widget _launcherMock() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(flex: 5, child: _box(color: _accent)),
        const SizedBox(width: 6),
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: _box()),
                    const SizedBox(width: 6),
                    Expanded(child: _box()),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: _box()),
                    const SizedBox(width: 6),
                    Expanded(child: _box()),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _box()),
              const SizedBox(height: 6),
              Expanded(child: _box()),
              const SizedBox(height: 6),
              Expanded(child: _box()),
            ],
          ),
        ),
      ],
    );
  }
}
