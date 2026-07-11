// =========================================================
//  tv_language_screen.dart — Langue de l'application (TV)
// =========================================================
//  Par DÉFAUT l'app suit la langue de la TV (choix « Système »,
//  locale = null dans LocaleRepository). Cet écran permet de FORCER
//  une des 8 langues si l'utilisateur préfère (ex. TV réglée en
//  anglais par le magasin mais foyer francophone).
//
//  Les noms de langues sont affichés dans leur langue NATIVE
//  (LocaleRepository.localeLabels, jamais traduits) : chacun doit
//  reconnaître sa langue même si l'app est dans une langue qu'il
//  ne lit pas. Le changement est appliqué immédiatement (TvApp
//  écoute LocaleRepository et reconstruit).
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/i18n/locale_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

class TvLanguageScreen extends StatelessWidget {
  const TvLanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleRepository.instance,
      builder: (BuildContext context, _) {
        final Locale? current = LocaleRepository.instance.locale;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(context.l10n.tvLanguageTitle,
                    style: TextStyle(
                        fontSize: TvDimens.displayS,
                        fontWeight: FontWeight.w800,
                        color: TvTokens.text)),
                const SizedBox(height: 6),
                Text(context.l10n.tvLanguageSubtitle,
                    style: TextStyle(
                        fontSize: TvDimens.body, color: TvTokens.muted)),
                const SizedBox(height: 22),
                _LanguageRow(
                  label: context.l10n.tvLanguageSystem,
                  selected: current == null,
                  autofocus: current == null,
                  onSelect: () => LocaleRepository.instance.setLocale(null),
                ),
                const SizedBox(height: 10),
                ...LocaleRepository.supportedLocales.map((Locale loc) {
                  final bool selected =
                      current?.languageCode == loc.languageCode;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _LanguageRow(
                      label: LocaleRepository
                              .localeLabels[loc.languageCode] ??
                          loc.languageCode,
                      selected: selected,
                      autofocus: selected,
                      onSelect: () =>
                          LocaleRepository.instance.setLocale(loc),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.label,
    required this.selected,
    required this.onSelect,
    this.autofocus = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.large,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused ? TvTokens.gold : TvTokens.sel;
        final Color fg = focused ? const Color(0xFF1A1206) : TvTokens.text;
        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border: Border.all(
                color: selected ? TvTokens.gold : Colors.transparent,
                width: 1.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: TvDimens.title,
                        fontWeight: FontWeight.w700,
                        color: fg)),
              ),
              if (selected)
                Icon(Icons.check_rounded,
                    color: focused ? fg : TvTokens.gold, size: 26),
            ],
          ),
        );
      },
    );
  }
}
