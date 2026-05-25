// =========================================================
//  settings_screen.dart — Réglages globaux de l'app
// =========================================================
//  Hub central des réglages. Sections :
//    - Lecteur (buffer, hwdec, stats overlay)
//    - Playlists (gestion)
//    - Cache (vider logos, vider l'historique)
//    - À propos (version, GitHub, mises à jour)
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/theme_mode_repository.dart';
import '../../about/presentation/about_screen.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../device/data/remote_config_repository.dart';
import '../../device/presentation/device_id_card.dart';
import '../../player/data/player_settings.dart';
import '../../playlists/presentation/playlists_screen.dart';
import '../../recordings/presentation/recordings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Réglages'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: <Widget>[
            // ====== APPARENCE ======
            //  Cinema (Maison Noir) = défaut, identité du produit.
            //  Daylight = version claire dérivée pour usage diurne.
            _SectionTitle('Apparence'),
            const _ThemeModePicker(),

            // ====== LECTEUR ======
            _SectionTitle('Lecteur vidéo'),
            ListenableBuilder(
              listenable: PlayerSettings.instance,
              builder: (BuildContext context, _) {
                final PlayerSettings s = PlayerSettings.instance;
                return Column(
                  children: <Widget>[
                    _SliderTile(
                      icon: Icons.timer_outlined,
                      title: 'Taille du buffer',
                      subtitle:
                          '${s.bufferSeconds}s · plus c\'est haut, mieux la lecture résiste aux coupures réseau (mais plus de latence sur le live)',
                      value: s.bufferSeconds.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11,
                      onChanged: (double v) =>
                          s.setBufferSeconds(v.toInt()),
                    ),
                    _SwitchTile(
                      icon: Icons.memory_rounded,
                      title: 'Décodage matériel',
                      subtitle:
                          'Utilise le GPU pour décoder. Indispensable pour 4K / 8K.',
                      value: s.hardwareDecode,
                      onChanged: s.setHardwareDecode,
                    ),
                    _SwitchTile(
                      icon: Icons.analytics_outlined,
                      title: 'Afficher les statistiques',
                      subtitle:
                          'Résolution, codec, FPS en surimpression pendant la lecture.',
                      value: s.showStats,
                      onChanged: s.setShowStats,
                    ),
                  ],
                );
              },
            ),

            // ====== PLAYLISTS ======
            _SectionTitle('Playlists'),
            _ActionTile(
              icon: Icons.playlist_play_rounded,
              title: 'Mes playlists',
              subtitle:
                  'Ajouter, supprimer, gérer les sources M3U / Xtream.',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const PlaylistsScreen(),
                ),
              ),
            ),

            // ====== PROVISIONING À DISTANCE ======
            //  L'admin (toi) maintient un JSON sur GitHub Gist (ou
            //  n'importe quel endpoint HTTP). Chaque appareil pioche
            //  ses playlists en se reconnaissant par son MAC virtuel.
            _SectionTitle('Provisioning à distance'),
            const _RemoteConfigCard(),

            // ====== ENREGISTREMENTS ======
            _SectionTitle('Enregistrements'),
            _ActionTile(
              icon: Icons.movie_filter_outlined,
              title: 'Mes enregistrements',
              subtitle:
                  'Liste des flux capturés via le bouton REC du lecteur.',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const RecordingsScreen(),
                ),
              ),
            ),

            // ====== STOCKAGE ======
            _SectionTitle('Stockage'),
            _ActionTile(
              icon: Icons.history_rounded,
              title: 'Vider l\'historique de visionnage',
              subtitle:
                  'Supprime la liste "Reprendre" sur l\'accueil.',
              destructive: true,
              onTap: () async {
                final bool? confirm = await _confirm(
                  context,
                  title: 'Vider l\'historique ?',
                  message: 'La section "Reprendre" sera vide.',
                );
                if (confirm == true) {
                  await RecentlyWatchedRepository.instance.clear();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Historique vidé'),
                      ),
                    );
                  }
                }
              },
            ),

            // ====== À PROPOS ======
            _SectionTitle('Application'),
            _ActionTile(
              icon: Icons.info_outline_rounded,
              title: 'À propos',
              subtitle: 'Version, mises à jour, crédits, légal.',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const AboutScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.live),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
//  Composants internes
// ============================================================

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text.toUpperCase(),
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final Color iconColor =
        destructive ? AppColors.live : AppColors.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: value.toInt().toString(),
            activeColor: AppColors.accent,
            inactiveColor: AppColors.accent.withValues(alpha: 0.2),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ============================================================
//  _RemoteConfigCard — Bloc "Provisioning à distance"
// ============================================================
//  Affiche :
//    - L'identifiant unique (MAC virtuel) de l'appareil
//    - Un champ pour l'URL JSON publiée par l'admin
//    - L'état de la dernière sync (succès / erreur / inconnu)
//    - Un bouton "Synchroniser maintenant"
// ============================================================

// ============================================================
//  _ThemeModePicker — Sélecteur Cinema / Daylight / Système
// ============================================================
//  Trois pastilles côte à côte. La sélection active porte la
//  bordure champagne et un léger halo cuivré.
// ============================================================

class _ThemeModePicker extends StatelessWidget {
  const _ThemeModePicker();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeModeRepository.instance,
      builder: (BuildContext context, _) {
        final ThemeMode current = ThemeModeRepository.instance.mode;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: <Widget>[
              _ThemeOption(
                icon: Icons.nightlight_round,
                label: 'Cinema',
                subtitle: 'Maison Noir',
                selected: current == ThemeMode.dark,
                onTap: () =>
                    ThemeModeRepository.instance.setMode(ThemeMode.dark),
              ),
              _ThemeOption(
                icon: Icons.wb_sunny_outlined,
                label: 'Daylight',
                subtitle: 'Lumière du jour',
                selected: current == ThemeMode.light,
                onTap: () =>
                    ThemeModeRepository.instance.setMode(ThemeMode.light),
              ),
              _ThemeOption(
                icon: Icons.brightness_auto_outlined,
                label: 'Auto',
                subtitle: 'Suit l\'OS',
                selected: current == ThemeMode.system,
                onTap: () =>
                    ThemeModeRepository.instance.setMode(ThemeMode.system),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Respect du système : si l'utilisateur a activé "réduire les
    // animations" dans l'OS, MediaQuery.disableAnimations remonte
    // true et on coupe la transition.
    final bool disableMotion =
        MediaQuery.disableAnimationsOf(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: AnimatedContainer(
              duration: disableMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.accentSurface
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? AppColors.accent
                      : AppColors.border,
                  width: selected ? 1.4 : 1,
                ),
                boxShadow: selected ? AppColors.champagneGlow : null,
              ),
              child: Column(
                children: <Widget>[
                  Icon(
                    icon,
                    color:
                        selected ? AppColors.accent : AppColors.textSecondary,
                    size: 22,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? AppColors.accent
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoteConfigCard extends StatefulWidget {
  const _RemoteConfigCard();

  @override
  State<_RemoteConfigCard> createState() => _RemoteConfigCardState();
}

class _RemoteConfigCardState extends State<_RemoteConfigCard> {
  final TextEditingController _urlController = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _seedFromRepo(RemoteConfigStatus status) {
    if (_seeded) return;
    _seeded = true;
    final String? url = status.url;
    if (url != null && url.isNotEmpty) {
      _urlController.text = url;
    }
  }

  Future<void> _save() async {
    final String value = _urlController.text.trim();
    await RemoteConfigRepository.instance.setUrl(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value.isEmpty
              ? 'Provisioning à distance désactivé.'
              : 'URL enregistrée. Synchronisation en cours…',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _syncNow() async {
    await RemoteConfigRepository.instance.syncNow();
  }

  String _formatTime(DateTime? t) {
    if (t == null) return 'jamais';
    final DateTime local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RemoteConfigRepository.instance,
      builder: (BuildContext context, _) {
        final RemoteConfigStatus status =
            RemoteConfigRepository.instance.status;
        _seedFromRepo(status);
        final bool syncing = RemoteConfigRepository.instance.isSyncing;

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Identifiant — l'admin en a besoin pour cibler ce client
              const DeviceIdCard(showCaption: false),
              const SizedBox(height: 14),

              // Champ URL
              Text(
                'URL du fichier de configuration',
                style: AppTextStyles.bodyLarge.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: AppTextStyles.bodyLarge.copyWith(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'https://gist.github.com/…/raw/config.json',
                  hintStyle: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'L\'app interrogera cette URL toutes les 30 minutes '
                'pour récupérer les playlists assignées à cet appareil.',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: const Text('Enregistrer'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: syncing ? null : _syncNow,
                      icon: syncing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.sync_rounded, size: 16),
                      label: Text(syncing ? 'Sync…' : 'Synchroniser'),
                    ),
                  ),
                ],
              ),

              // ---- Statut ----
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _statusLine(
                      icon: status.knownAtAdmin
                          ? Icons.verified_rounded
                          : Icons.help_outline_rounded,
                      color: status.knownAtAdmin
                          ? AppColors.success
                          : AppColors.textMuted,
                      label: status.knownAtAdmin
                          ? 'Reconnu par ton admin'
                          : 'Pas encore enregistré côté admin',
                    ),
                    const SizedBox(height: 6),
                    _statusLine(
                      icon: Icons.playlist_add_check_rounded,
                      color: AppColors.accent,
                      label: '${status.playlistsApplied} '
                          'playlist(s) appliquée(s)',
                    ),
                    const SizedBox(height: 6),
                    _statusLine(
                      icon: Icons.check_circle_outline_rounded,
                      color: AppColors.textSecondary,
                      label:
                          'Dernier succès : ${_formatTime(status.lastSuccessAt)}',
                    ),
                    const SizedBox(height: 6),
                    _statusLine(
                      icon: Icons.access_time_rounded,
                      color: AppColors.textSecondary,
                      label:
                          'Dernière tentative : ${_formatTime(status.lastAttemptAt)}',
                    ),
                    if (status.lastError != null) ...<Widget>[
                      const SizedBox(height: 6),
                      _statusLine(
                        icon: Icons.error_outline_rounded,
                        color: AppColors.live,
                        label: status.lastError!,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusLine({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 12,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
