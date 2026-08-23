// =========================================================
//  team_picker_sheet.dart — Choisir une équipe à suivre (mobile)
// =========================================================
//  Équivalent téléphone du sélecteur d'équipes de la TV. Suivre une
//  ÉQUIPE et suivre un MATCH sont deux besoins différents et
//  complémentaires : l'équipe, c'est « préviens-moi pour tous ses
//  matchs, toute la saison » ; le match, c'est « préviens-moi pour
//  celui-là seulement ». Le coin Sport offre les deux.
//
//  La recherche passe par le Worker (proxy TheSportsDB) et couvre TOUS
//  les sports — on peut y chercher les Lakers ou le Stade Toulousain
//  aussi bien qu'un club de football.
//
//  ANTI-MARTÈLEMENT : on ne lance pas une requête à chaque lettre tapée.
//  Une pause de 400 ms après la dernière frappe suffit à diviser le
//  nombre d'appels par cinq — ça compte sur un forfait mobile, et ça
//  évite de se faire limiter par la source.
// =========================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/sports_repository.dart';
import '../domain/sport_models.dart';

Future<void> showTeamPickerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (BuildContext ctx) => const _TeamPickerSheet(),
  );
}

class _TeamPickerSheet extends StatefulWidget {
  const _TeamPickerSheet();

  @override
  State<_TeamPickerSheet> createState() => _TeamPickerSheetState();
}

class _TeamPickerSheetState extends State<_TeamPickerSheet> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;
  List<SportTeam> _results = const <SportTeam>[];
  bool _searching = false;

  /// Numéro de la recherche en cours. Une réponse lente d'une ancienne
  /// requête ne doit JAMAIS écraser le résultat d'une plus récente —
  /// sinon on voit s'afficher les résultats d'un mot déjà effacé.
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _results = const <SportTeam>[];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final int mine = ++_seq;
      final List<SportTeam> found = await SportsRepository.instance.search(q);
      if (!mounted || mine != _seq) return;
      setState(() {
        _results = found;
        _searching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // On remonte la feuille au-dessus du clavier : sans ça, la liste des
    // résultats se retrouve cachée dès qu'on tape.
    final double bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceOverlay,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: _onChanged,
                style: AppTextStyles.bodyMedium,
                decoration: InputDecoration(
                  hintText: context.l10n.sportSearchTeamHint,
                  hintStyle: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.textMuted),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.surfaceHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 320,
              child: _body(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_ctrl.text.trim().length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            context.l10n.sportSearchTeamPrompt,
            textAlign: TextAlign.center,
            style:
                AppTextStyles.labelSmall.copyWith(color: AppColors.textTertiary),
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            context.l10n.sportSearchTeamNone,
            textAlign: TextAlign.center,
            style:
                AppTextStyles.labelSmall.copyWith(color: AppColors.textTertiary),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: _results.length,
      itemBuilder: (BuildContext context, int i) {
        final SportTeam t = _results[i];
        final bool already = SportsRepository.instance.isFavorite(t.id);
        return ListTile(
          title: Text(t.name, style: AppTextStyles.bodyMedium),
          subtitle: Text(
            <String>[
              if (t.sport.isNotEmpty) t.sport,
              if (t.league.isNotEmpty) t.league,
            ].join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                AppTextStyles.labelSmall.copyWith(color: AppColors.textTertiary),
          ),
          trailing: Icon(
            already ? Icons.check_circle_rounded : Icons.add_circle_outline,
            color: already ? AppColors.success : AppColors.accent,
          ),
          onTap: already
              ? null
              : () async {
                  await SportsRepository.instance.addFavorite(t);
                  if (context.mounted) Navigator.of(context).pop();
                },
        );
      },
    );
  }
}
