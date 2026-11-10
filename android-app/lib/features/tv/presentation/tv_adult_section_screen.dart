import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../profiles/data/profile_repository.dart';
import '../../security/data/adult_access.dart';
import '../../security/data/parental_controls.dart';
import '../core/tv_app_tokens.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../../cinema/domain/cinema_models.dart';
import 'tv_cinema_screen.dart';
import 'tv_glass.dart';
import 'tv_live_screen.dart';
import 'tv_parental_screen.dart';
import 'tv_shell.dart';

/// Seul point d'entrée de l'accueil : aucune rubrique ni affiche adulte
/// n'est construite avant la réussite de l'authentification de cette visite.
Future<void> openTvAdultSection(
  BuildContext context, {
  @visibleForTesting
  Future<AdultAccessGrant?> Function()? authenticateForTesting,
  @visibleForTesting
  Widget Function(AdultAccessGrant)? sectionBuilderForTesting,
}) async {
  if (ProfileRepository.instance.activeIsKids ||
      ParentalControls.instance.kidsMode.value) {
    return;
  }
  final AdultAccessGrant? grant = await (authenticateForTesting?.call() ??
      authenticateAdultAccess(
        reason: context.l10n.adultAuthReason,
        confirmPin: () async =>
            context.mounted && await askParentalPin(context),
      ));
  if (grant == null) return;
  try {
    if (!context.mounted ||
        !grant.isValid ||
        ProfileRepository.instance.activeIsKids ||
        ParentalControls.instance.kidsMode.value) {
      return;
    }
    final MaterialPageRoute<void> route = MaterialPageRoute<void>(
      builder: (_) => TvShell(
        child: sectionBuilderForTesting?.call(grant) ??
            TvAdultSectionScreen(adultAccess: grant),
      ),
    );
    await Navigator.of(context).push<void>(route);
    grant.revoke();
    // Attendre la fin de la transition : les écouteurs des sous-écrans
    // retirent leurs abonnements avant la destruction du notifier.
    await route.completed;
  } finally {
    // Le droit est limité à cette visite, jamais conservé pour la prochaine.
    grant.revoke();
    grant.dispose();
  }
}

class TvAdultSectionScreen extends StatefulWidget {
  const TvAdultSectionScreen({
    super.key,
    required this.adultAccess,
    this.liveBuilderForTesting,
    this.cinemaBuilderForTesting,
  });

  final AdultAccessGrant adultAccess;
  @visibleForTesting
  final Widget Function(AdultAccessGrant)? liveBuilderForTesting;
  @visibleForTesting
  final Widget Function(AdultAccessGrant)? cinemaBuilderForTesting;

  @override
  State<TvAdultSectionScreen> createState() => _TvAdultSectionScreenState();
}

class _TvAdultSectionScreenState extends State<TvAdultSectionScreen> {
  bool _exitScheduled = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    widget.adultAccess.addListener(_onAccessChanged);
    _onAccessChanged();
  }

  void _onAccessChanged() {
    if (widget.adultAccess.isValid || _exitScheduled) return;
    _exitScheduled = true;
    // Si le profil ou ses listes changent pendant une sous-rubrique, on
    // ferme aussi les routes de cette visite. Les écrans enfants vérifient
    // eux-mêmes le grant pour rester inertes avant ce prochain cadre.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ModalRoute<dynamic>? ownRoute = ModalRoute.of(context);
      if (ownRoute == null || !ownRoute.isActive) return;
      final NavigatorState navigator = Navigator.of(context);
      navigator.popUntil((route) => route == ownRoute || route.isFirst);
      if (ownRoute.isCurrent && navigator.canPop()) navigator.pop();
    });
  }

  Future<void> _open({required bool cinema}) async {
    if (_opening || !widget.adultAccess.isValid) return;
    _opening = true;
    try {
      final AdultAccessGrant grant = widget.adultAccess;
      await Navigator.of(context).push<void>(MaterialPageRoute<void>(
        builder: (_) => TvShell(
          child: cinema
              ? widget.cinemaBuilderForTesting?.call(grant) ??
                  TvCinemaScreen(kind: CinemaKind.movie, adultAccess: grant)
              : widget.liveBuilderForTesting?.call(grant) ??
                  TvLiveScreen(adultAccess: grant),
        ),
      ));
    } finally {
      _opening = false;
    }
  }

  @override
  void dispose() {
    widget.adultAccess.removeListener(_onAccessChanged);
    widget.adultAccess.revoke();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.adultAccess,
        builder: (context, _) {
          if (!widget.adultAccess.isValid) return const SizedBox.shrink();
          return PopScope(
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) widget.adultAccess.revoke();
            },
            child: ListView(
              padding: const EdgeInsets.all(TvDimens.gutter),
              children: <Widget>[
                Text(
                  context.l10n.sectionAdult,
                  style: TvAppTokens.of(context).display(TvDimens.displayS),
                ),
                const SizedBox(height: TvDimens.gutter),
                _AdultAction(
                  key: const ValueKey<String>('tv-adult-live'),
                  icon: Icons.live_tv_rounded,
                  label: context.l10n.tvAdultLive,
                  autofocus: true,
                  onSelect: () => _open(cinema: false),
                ),
                const SizedBox(height: TvDimens.gutter),
                _AdultAction(
                  key: const ValueKey<String>('tv-adult-cinema'),
                  icon: Icons.movie_rounded,
                  label: context.l10n.tvAdultCinema,
                  onSelect: () => _open(cinema: true),
                ),
              ],
            ),
          );
        },
      );
}

/// Les mêmes panneaux rectangulaires et le même focus que l'accueil 117.
/// Pas de miniature : seule la rubrique choisie charge son catalogue.
class _AdultAction extends StatelessWidget {
  const _AdultAction({
    super.key,
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
  Widget build(BuildContext context) => TvFocusBuilder(
        autofocus: autofocus,
        scale: TvFocusScale.small,
        onSelect: onSelect,
        builder: (context, focused) => TvGlassPanel(
          blur: false,
          focused: focused,
          radius: TvDimens.panelRadius,
          padding: const EdgeInsets.all(TvDimens.gutter),
          child: Row(
            children: <Widget>[
              Icon(icon,
                  size: TvDimens.headline,
                  color: TvAppTokens.of(context).accentBright),
              const SizedBox(width: TvDimens.gutter),
              Expanded(
                child: Text(label,
                    style: TvAppTokens.of(context).ui(TvDimens.title)),
              ),
            ],
          ),
        ),
      );
}
