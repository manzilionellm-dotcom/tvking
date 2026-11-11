import 'package:flutter/material.dart';

import '../../../core/app/app_platform.dart';
import '../../../core/app/repair_flags.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../playlists/data/channel_limit_snapshot.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../profiles/data/active_profile.dart';
import '../../profiles/data/profile_repository.dart';
import '../../security/data/parental_controls.dart';

Listenable _limitChanges() => Listenable.merge([
  PlaylistRepository.instance.channelLimitSnapshot,
  ActiveProfile.instance.scopeListenable,
  ProfileRepository.instance,
  ParentalControls.instance.kidsMode,
  ParentalControls.instance.readiness,
]);

ChannelLimitSnapshot? _currentLimit() {
  if (!AppPlatform.isZuno || RepairFlags.catalogLimitNoticeOff) return null;
  final snapshot = PlaylistRepository.instance.channelLimitSnapshot.value;
  if (snapshot == null ||
      !snapshot.hasLimit ||
      snapshot.scope != ActiveProfile.instance.scopeListenable.value ||
      snapshot.profileId != ActiveProfile.instance.id ||
      snapshot.sources.any(
        (source) => !ActiveProfile.instance.allowsPlaylist(source.playlistId),
      )) {
    return null;
  }
  return snapshot;
}

bool get _restrictLimitDetails {
  final controls = ParentalControls.instance;
  return !controls.protectsZuno ||
      !controls.contentReady ||
      controls.kidsMode.value ||
      ProfileRepository.instance.activeIsKids;
}

String _sourceName(ChannelLimitSource source, AppLocalizations l10n) =>
    source.name.trim().isEmpty
    ? l10n.catalogLimitUnnamed(source.playlistId)
    : source.name;

/// Réserve une place au bandeau dans le catalogue, jamais sur la vidéo
/// plein écran. Sans limitation, le contenu garde toute la place disponible.
class TvCatalogLimitFrame extends StatelessWidget {
  const TvCatalogLimitFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AppPlatform.isZuno) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const TvCatalogLimitNotice(),
        Expanded(child: child),
      ],
    );
  }
}

/// Aucun espace ajouté sans limitation. Les détails suivent les permissions
/// même si un changement de profil intervient pendant l'ouverture du dialogue.
class TvCatalogLimitNotice extends StatelessWidget {
  const TvCatalogLimitNotice({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _limitChanges(),
    builder: (context, _) {
      final snapshot = _currentLimit();
      if (snapshot == null) return const SizedBox.shrink();
      final l10n = AppLocalizations.of(context);
      final restricted = _restrictLimitDetails;
      final names = snapshot.affectedSources
          .take(2)
          .map((source) => _sourceName(source, l10n))
          .join(' · ');
      return Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.stealthSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.stealthIce.withValues(alpha: .35),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: AppColors.stealthIce),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.catalogLimitTitle, style: AppTextStyles.tvNotice),
                    const SizedBox(height: 4),
                    if (restricted)
                      Text(
                        l10n.catalogLimitKids,
                        style: AppTextStyles.bodyMedium,
                      )
                    else ...[
                      Text(
                        l10n.catalogLimitSummary(
                          snapshot.storedRows,
                          snapshot.loadedRows,
                          snapshot.loadedChannels,
                          snapshot.limit,
                        ),
                        style: AppTextStyles.bodyMedium,
                      ),
                      Text(
                        l10n.catalogLimitSources(names),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium,
                      ),
                      TextButton(
                        onPressed: () {
                          // La permission est relue ici puis dans le dialogue,
                          // jamais déduite d'un bouton construit auparavant.
                          if (_currentLimit() == null ||
                              _restrictLimitDetails) {
                            return;
                          }
                          showDialog<void>(
                            context: context,
                            builder: (_) => const _LimitDetails(),
                          );
                        },
                        child: Text(
                          l10n.detailDetails,
                          style: AppTextStyles.button.copyWith(
                            color: AppColors.stealthIce,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _LimitDetails extends StatelessWidget {
  const _LimitDetails();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _limitChanges(),
    builder: (context, _) {
      final l10n = AppLocalizations.of(context);
      final snapshot = _currentLimit();
      if (snapshot == null) {
        final route = ModalRoute.of(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && route?.isCurrent == true) {
            Navigator.of(context).pop();
          }
        });
        return const SizedBox.shrink();
      }
      final restricted = _restrictLimitDetails;
      final sources = snapshot.affectedSources;
      return AlertDialog(
        backgroundColor: AppColors.stealthSurface,
        title: Text(
          l10n.catalogLimitTitle,
          style: AppTextStyles.headlineMedium,
        ),
        content: restricted
            ? Text(l10n.catalogLimitKids, style: AppTextStyles.bodyMedium)
            : SizedBox(
                width: 600,
                height: 320,
                child: ListView.builder(
                  itemCount: sources.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.catalogLimitSummary(
                                snapshot.storedRows,
                                snapshot.loadedRows,
                                snapshot.loadedChannels,
                                snapshot.limit,
                              ),
                              style: AppTextStyles.bodyMedium,
                            ),
                            if (snapshot.hasLoadLimit)
                              Text(
                                l10n.catalogLimitPreserved,
                                style: AppTextStyles.bodyMedium,
                              ),
                          ],
                        ),
                      );
                    }
                    final source = sources[index - 1];
                    final name = _sourceName(source, l10n);
                    final imported = source.importCounts;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.catalogLimitSource(
                              name,
                              source.storedRows,
                              source.loadedRows,
                              source.loadedChannels,
                            ),
                            style: AppTextStyles.bodyLarge,
                          ),
                          if (imported != null && imported.truncated)
                            Text(
                              l10n.catalogLimitImport(
                                name,
                                imported.validEntries,
                                imported.retainedEntries,
                                imported.skippedEntries,
                              ),
                              style: AppTextStyles.bodyMedium,
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              l10n.tvClose,
              style: AppTextStyles.button.copyWith(color: AppColors.stealthIce),
            ),
          ),
        ],
      );
    },
  );
}
