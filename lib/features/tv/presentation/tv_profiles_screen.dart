// =========================================================
//  tv_profiles_screen.dart — Profils famille (TV, façon Netflix)
// =========================================================
//  Chaque membre a SON profil : ses « Derniers vus », son historique de
//  recherche, ses collections. Ici on choisit le profil ACTIF, on en crée
//  (pastilles prêtes, pas de clavier) et on en supprime (2 temps).
//
//  STABILITÉ : zéro contact lecteur / écran Direct. Changer de profil
//  recharge simplement les 3 petits dépôts locaux concernés.
// =========================================================
import 'package:flutter/material.dart';


import '../../../core/i18n/l10n_extension.dart';
import '../../../core/profiles/profile_switch.dart';
import '../../../core/profiles/profiles_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

/// Nom AFFICHÉ d'un profil : le profil par défaut est montré dans la langue
/// active (« Famille »/« Family »/« Familia »…) alors que le nom STOCKÉ reste
/// 'Famille' (partagé avec l'app téléphone — on ne touche pas au dépôt).
/// Les profils créés par l'utilisateur gardent leur nom tel quel.
String tvProfileDisplayName(BuildContext context, TvProfile p) =>
    p.id == ProfilesRepository.familyProfile.id
        ? context.l10n.tvProfileFamily
        : p.name;

/// Modèles proposés à la création (un clic, pas de clavier fastidieux),
/// traduits dans la langue active.
List<({String name, String emoji})> _presets(BuildContext context) =>
    <({String name, String emoji})>[
      (name: context.l10n.tvProfilePresetDad, emoji: '👨'),
      (name: context.l10n.tvProfilePresetMom, emoji: '👩'),
      (name: context.l10n.tvProfilePresetKids, emoji: '🧒'),
      (name: context.l10n.tvProfilePresetTeen, emoji: '🧑'),
      (name: context.l10n.tvProfileGuest, emoji: '🛋️'),
    ];

class TvProfilesScreen extends StatefulWidget {
  const TvProfilesScreen({super.key});

  @override
  State<TvProfilesScreen> createState() => _TvProfilesScreenState();
}

class _TvProfilesScreenState extends State<TvProfilesScreen> {
  String? _confirmDeleteId;

  @override
  void initState() {
    super.initState();
    ProfilesRepository.instance.load();
  }

  /// Demande le code s'il y en a un, puis bascule. La liste des dépôts à
  /// recharger vit dans `activateProfile` (profile_switch.dart) : un seul
  /// endroit pour les trois écrans qui savent changer de profil.
  Future<void> _activate(String id) async {
    if (ProfilesRepository.instance.byId(id)?.enabled == false) return;
    if (!await ensureUnlocked(context, id)) return;
    await activateProfile(id);
  }

  @override
  Widget build(BuildContext context) {
    final ProfilesRepository repo = ProfilesRepository.instance;
    return SafeArea(
      child: ListenableBuilder(
        listenable: repo,
        builder: (BuildContext context, _) {
          final List<TvProfile> all = repo.profiles;
          final List<({String name, String emoji})> available =
              _presets(context)
                  .where((({String name, String emoji}) p) =>
                      repo.byName(p.name) == null)
                  .toList(growable: false);
          return Padding(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
            child: ListView(
              children: <Widget>[
                Text(
                  context.l10n.tvProfilesTitle,
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: TvTokens.text),
                ),
                const SizedBox(height: 6),
                Text(
                  context.l10n.tvProfilesSubtitle,
                  style: const TextStyle(fontSize: 15, color: TvTokens.muted),
                ),
                const SizedBox(height: 22),
                // ----- Profils existants -----
                for (final TvProfile p in all)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: TvFocusBuilder(
                            scale: TvFocusScale.large,
                            autofocus: p.id == repo.active.id,
                            onSelect: () => _activate(p.id),
                            builder: (BuildContext context, bool focused) {
                              final bool isActive = p.id == repo.active.id;
                              // Profil coupé par le panel : ligne éteinte,
                              // visible mais inutilisable (cf. la règle
                              // expliquée dans profiles_repository.dart).
                              final bool off = !p.enabled;
                              final Color bg = focused && !off
                                  ? TvTokens.gold
                                  : TvTokens.sel;
                              final Color fg = focused && !off
                                  ? const Color(0xFF1A1206)
                                  : TvTokens.goldBright;
                              return Opacity(
                                opacity: off ? 0.4 : 1,
                                child: Container(
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(
                                      TvDimens.cardRadius),
                                  border: Border.all(
                                      color: isActive && !off
                                          ? TvTokens.gold
                                          : TvTokens.lineSoft),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 22, vertical: 16),
                                child: Row(
                                  children: <Widget>[
                                    Text(p.emoji,
                                        style:
                                            const TextStyle(fontSize: 26)),
                                    const SizedBox(width: 14),
                                    Text(tvProfileDisplayName(context, p),
                                        style: TextStyle(
                                            fontSize: TvDimens.title,
                                            fontWeight: FontWeight.w700,
                                            color: fg)),
                                    // Cadenas / interdit : dit AVANT le clic
                                    // qu'un code sera demandé, ou que le
                                    // profil est fermé.
                                    if (off || p.pin != null) ...<Widget>[
                                      const SizedBox(width: 10),
                                      Icon(
                                          off
                                              ? Icons.block_rounded
                                              : Icons.lock_rounded,
                                          size: 20,
                                          color: fg),
                                    ],
                                    const Spacer(),
                                    if (isActive)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Icon(Icons.check_circle_rounded,
                                              size: 20,
                                              color: focused
                                                  ? fg
                                                  : TvTokens.gold),
                                          const SizedBox(width: 6),
                                          Text(
                                              context
                                                  .l10n.tvProfileActiveBadge,
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight:
                                                      FontWeight.w700,
                                                  color: focused
                                                      ? fg
                                                      : TvTokens.gold)),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                              );
                            },
                          ),
                        ),
                        // Suppression : jamais « Famille », et jamais un
                        // profil VENU DU PANEL — sinon le contrôle parental
                        // se contournerait en supprimant le profil qui le
                        // porte. Le dépôt refuse déjà ; on n'affiche pas non
                        // plus un bouton qui ne ferait rien.
                        if (p.id != ProfilesRepository.familyProfile.id &&
                            !p.managed) ...<Widget>[
                          const SizedBox(width: 10),
                          TvFocusBuilder(
                            scale: TvFocusScale.small,
                            onSelect: () {
                              if (_confirmDeleteId == p.id) {
                                repo.delete(p.id);
                                setState(() => _confirmDeleteId = null);
                              } else {
                                setState(() => _confirmDeleteId = p.id);
                              }
                            },
                            builder: (BuildContext context, bool focused) {
                              final bool confirming =
                                  _confirmDeleteId == p.id;
                              final Color bg = focused
                                  ? (confirming
                                      ? TvTokens.live
                                      : TvTokens.gold)
                                  : TvTokens.card;
                              final Color fg = focused
                                  ? Colors.white
                                  : (confirming
                                      ? TvTokens.live
                                      : TvTokens.muted);
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 16),
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(
                                      TvDimens.cardRadius),
                                  border:
                                      Border.all(color: TvTokens.lineSoft),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(Icons.delete_outline_rounded,
                                        size: 20, color: fg),
                                    if (confirming) ...<Widget>[
                                      const SizedBox(width: 6),
                                      Text(context.l10n.tvConfirmAsk,
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: fg)),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                // ----- Création (pastilles) -----
                if (available.isNotEmpty &&
                    all.length < ProfilesRepository.maxProfiles) ...<Widget>[
                  Text(
                    context.l10n.tvProfileAddSection,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: TvTokens.mutedDim,
                        letterSpacing: 1.6),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      for (final ({String name, String emoji}) p in available)
                        TvFocusBuilder(
                          scale: TvFocusScale.small,
                          onSelect: () => repo.create(p.name, p.emoji),
                          builder: (BuildContext context, bool focused) {
                            final Color bg =
                                focused ? TvTokens.gold : TvTokens.card;
                            final Color fg = focused
                                ? const Color(0xFF1A1206)
                                : TvTokens.text;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 10),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(
                                    TvDimens.cardRadius),
                                border:
                                    Border.all(color: TvTokens.lineSoft),
                              ),
                              child: Text('${p.emoji}  ${p.name}',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: fg)),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
