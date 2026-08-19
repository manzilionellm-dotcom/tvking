// =========================================================
//  tv_language_screen.dart — Choix de la langue de l'app (écran TV)
// =========================================================
//  DEMANDE EXPLOITANT (19/08) : la TV n'avait AUCUN sélecteur de langue —
//  elle suivait uniquement la langue système de la box (souvent réglée par
//  le magasin, pas par le client). Ici : « Système » + toutes les langues
//  embarquées (LocaleRepository.supportedLocales).
//
//  Application INSTANTANÉE : TvApp écoute LocaleRepository via un
//  ListenableBuilder au-dessus de MaterialApp → setLocale() reconstruit
//  toute l'app dans la nouvelle langue, sans redémarrage. Les libellés de
//  langues (localeLabels) restent volontairement dans leur langue native :
//  chacun doit reconnaître la sienne, quelle que soit la langue courante.
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
    final LocaleRepository repo = LocaleRepository.instance;
    return SafeArea(
      child: ListenableBuilder(
        listenable: repo,
        builder: (BuildContext context, _) {
          final String? current = repo.locale?.languageCode;
          return Padding(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.l10n.tvSettingsLanguage,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.l10n.tvLanguageHelp,
                  style: const TextStyle(fontSize: 15, color: TvTokens.muted),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    // « Système » : l'app suit la langue de la box.
                    _choice(
                      label: context.l10n.tvLanguageSystem,
                      selected: current == null,
                      autofocus: current == null,
                      onSelect: () => repo.setLocale(null),
                    ),
                    for (final Locale loc in LocaleRepository.supportedLocales)
                      _choice(
                        label: LocaleRepository
                                .localeLabels[loc.languageCode] ??
                            loc.languageCode,
                        selected: current == loc.languageCode,
                        autofocus: current == loc.languageCode,
                        onSelect: () => repo.setLocale(loc),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback onSelect,
    bool autofocus = false,
  }) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused
            ? TvTokens.gold
            : (selected ? TvTokens.badgeBg : TvTokens.sel);
        final Color fg = focused ? const Color(0xFF1A1206) : TvTokens.text;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border: Border.all(
                color: selected ? TvTokens.gold : TvTokens.lineSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (selected) ...<Widget>[
                Icon(Icons.check_rounded,
                    size: 18, color: focused ? fg : TvTokens.gold),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: fg),
              ),
            ],
          ),
        );
      },
    );
  }
}
