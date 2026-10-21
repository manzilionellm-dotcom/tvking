import 'package:flutter/material.dart';

import '../../../core/app/zuno_edition.dart';
import '../../cast/data/cast_platform.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';

/// L'identité du panel reste celle de ZUNO. Seul le point d'entrée choisit
/// l'ergonomie : une tablette ne doit pas redevenir une télévision.
bool get isZunoTouch => CastPlatform.zunoEdition == ZunoEdition.touch;

/// En-tête des pages tactiles : retour visible et titre qui peut se replier
/// lorsque le téléphone est étroit ou que le texte système est agrandi.
class TvTouchPageHeader extends StatelessWidget {
  const TvTouchPageHeader({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          if (Navigator.of(context).canPop())
            const BackButton(color: TvTokens.text),
          Expanded(
            child: Text(title, style: TvTokens.display(TvDimens.headline)),
          ),
        ],
      );
}

class TvTouchChoice<T> {
  const TvTouchChoice({required this.value, required this.label, this.icon});
  final T value;
  final String label;
  final IconData? icon;
}

/// Les longs catalogues gardent une liste paresseuse dans une feuille. Sur
/// téléphone, un rail permanent de 300 dp enlèverait toute place au contenu.
class TvTouchMenuButton<T> extends StatelessWidget {
  const TvTouchMenuButton({
    super.key,
    required this.label,
    required this.choices,
    required this.onSelected,
    this.selected,
  });

  final String label;
  final List<TvTouchChoice<T>> choices;
  final T? selected;
  final ValueChanged<T> onSelected;

  Future<void> _open(BuildContext context) async {
    final T? value = await showModalBottomSheet<T>(
      context: context,
      backgroundColor: TvTokens.panel,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheet) => SizedBox(
        height: MediaQuery.sizeOf(sheet).height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(TvDimens.touchSafeH),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.ui(TvDimens.title),
                    ),
                  ),
                  CloseButton(onPressed: () => Navigator.pop(sheet)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: choices.length,
                itemBuilder: (BuildContext context, int index) {
                  final TvTouchChoice<T> choice = choices[index];
                  return ListTile(
                    selected: choice.value == selected,
                    selectedColor: TvTokens.accentBright,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: TvDimens.touchSafeH,
                      vertical: TvDimens.touchGap / 2,
                    ),
                    leading: Icon(
                      choice.value == selected
                          ? Icons.check_rounded
                          : choice.icon ?? Icons.folder_outlined,
                    ),
                    title: Text(
                      choice.label,
                      style: TvTokens.ui(TvDimens.label),
                    ),
                    onTap: () => Navigator.pop(sheet, choice.value),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (value != null && context.mounted) onSelected(value);
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: choices.isEmpty ? null : () => _open(context),
        icon: const Icon(Icons.filter_list_rounded),
        label: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TvTokens.ui(TvDimens.label),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(TvDimens.touchTarget),
          foregroundColor: TvTokens.accentBright,
          padding: const EdgeInsets.all(TvDimens.touchGap),
        ),
      );
}
