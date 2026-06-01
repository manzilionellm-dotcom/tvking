// =========================================================
//  empty_state.dart — Ecran d'activation (login + remote)
// =========================================================
//  Refonte (post-decision utilisateur) :
//
//    Le client tout neuf qui n'a pas encore de chaines ne voit
//    PLUS son MAC en heros ni la mention "Activation par notre
//    equipe". Il voit un formulaire de connexion classique a 2
//    champs (Identifiant + Code secret) — comme une app bancaire
//    ou un service streaming. Le serveur IPTV est hardcode dans
//    `FlavorConfig.current.iptvServerUrl` et JAMAIS expose a
//    l'ecran. Pour le client, ca ressemble a un compte premium,
//    pas a un panel IPTV de revendeur.
//
//    Le revendeur fournit a chaque client :
//      - un Identifiant (= username Xtream)
//      - un Code secret (= password Xtream)
//
//    En option, le mecanisme historique d'activation a distance
//    par MAC reste disponible — replie en bas dans une section
//    discrete "Activation a distance" qu'on deplie sur tap. La
//    MAC reste indispensable cote backend (heartbeat, trial,
//    statut paye / freeze / ban) donc on la conserve mais on la
//    cache visuellement.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/branding/brand_logo.dart';
import '../../../../core/flavor/flavor.dart';
import '../../../../core/support/support_choice_sheet.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../device/data/device_identity.dart';
import '../../../playlists/data/playlist_repository.dart';

class EmptyStateView extends StatefulWidget {
  const EmptyStateView({
    required this.onAddPlaylist,
    super.key,
  });

  /// Conserve pour compat avec HomeScreen. Non utilise dans la
  /// nouvelle UX — la connexion se fait directement ici.
  final VoidCallback onAddPlaylist;

  @override
  State<EmptyStateView> createState() => _EmptyStateViewState();
}

class _EmptyStateViewState extends State<EmptyStateView> {
  final TextEditingController _idCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();

  bool _busy = false;
  String? _error;

  String? _mac;
  bool _remoteExpanded = false;

  @override
  void initState() {
    super.initState();
    DeviceIdentity.instance.mac.then((String v) {
      if (mounted) setState(() => _mac = v);
    });
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  // -------------------------------------------------------
  //  Login (Xtream cache derriere les libelles Identifiant /
  //  Code secret)
  // -------------------------------------------------------

  Future<void> _login() async {
    final String id = _idCtrl.text.trim();
    final String code = _codeCtrl.text.trim();
    if (id.isEmpty || code.isEmpty) {
      setState(() => _error = 'Identifiant et code secret obligatoires.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Le serveur est hardcode dans FlavorConfig — invisible
      // pour le client. Le nom de playlist est volontairement
      // sobre ("Mon abonnement") pour pas evoquer IPTV.
      await PlaylistRepository.instance.addXtreamPlaylist(
        name: 'Mon abonnement',
        serverUrl: FlavorConfig.current.iptvServerUrl,
        username: id,
        password: code,
      );
      // Apres succes, le repository emet sur son stream et le
      // HomeScreen sort automatiquement de l'EmptyStateView ;
      // pas besoin de callback.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Acces active. Chargement de tes chaines…',
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Maquillage du message : on ne dit pas "Xtream", on dit
        // "Identifiant ou code secret incorrect" comme une app banale.
        final String raw = e.toString();
        if (raw.contains('401') ||
            raw.toLowerCase().contains('invalid') ||
            raw.toLowerCase().contains('auth')) {
          _error = 'Identifiant ou code secret incorrect.';
        } else {
          _error = 'Connexion impossible. Reessaie dans un instant.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Connexion impossible. Reessaie dans un instant.';
      });
    }
  }

  // -------------------------------------------------------
  //  Activation distance (MAC) — chemin secondaire
  // -------------------------------------------------------

  Future<void> _copyMac() async {
    if (_mac == null) return;
    await Clipboard.setData(ClipboardData(text: _mac!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Identifiant copie : $_mac',
          style: AppTextStyles.bodyMedium,
        ),
      ),
    );
  }

  Future<void> _contactAdmin() async {
    if (_mac == null) return;
    await showSupportChoiceSheet(
      context,
      customMessage:
          'Bonjour, voici mon identifiant pour activer mes chaines :\n\n$_mac',
    );
  }

  // -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const BrandLogo.splash(),
                const SizedBox(height: 22),

                Text(
                  'Active ton acces',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headlineLarge.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  'Saisis les informations communiquees par ton revendeur '
                  'pour acceder a ton compte.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),

                // ----- Champ Identifiant -----
                _Label('Identifiant'),
                TextField(
                  controller: _idCtrl,
                  enabled: !_busy,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: const InputDecoration(
                    hintText: 'ex : LMK274',
                  ),
                ),
                const SizedBox(height: 12),

                // ----- Champ Code secret -----
                _Label('Code secret'),
                TextField(
                  controller: _codeCtrl,
                  enabled: !_busy,
                  obscureText: true,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  onSubmitted: (_) => _login(),
                  decoration: const InputDecoration(
                    hintText: '••••••••',
                  ),
                ),

                // ----- Erreur eventuelle -----
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.live.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.live.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.live,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),

                // ----- CTA Connexion -----
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _login,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login_rounded, size: 20),
                    label: Text(
                      _busy ? 'Verification…' : 'Connexion',
                      style: AppTextStyles.button.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.voidSurface,
                    ),
                  ),
                ),

                // ===== Activation a distance (replie) =====
                const SizedBox(height: 28),
                _RemoteActivationBlock(
                  mac: _mac,
                  expanded: _remoteExpanded,
                  onToggle: () => setState(() {
                    _remoteExpanded = !_remoteExpanded;
                  }),
                  onCopy: _copyMac,
                  onContact: _contactAdmin,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Petit label uppercase au-dessus des champs (style premium banque).
class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Text(
        text.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.textSecondary,
          fontSize: 11,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

// =========================================================
//  Bloc "Activation a distance" (MAC) — replie par defaut
// =========================================================
//  Affiche un en-tete fin tappable. Quand deplie, montre la MAC
//  (qu'on appelle ici 'Identifiant appareil' pour ne pas evoquer
//  l'IPTV technique) + 2 actions : copier et contacter le
//  revendeur. La MAC reste necessaire backend pour le pricing /
//  trial / freeze, on la garde simplement hors du chemin
//  principal d'activation.
class _RemoteActivationBlock extends StatelessWidget {
  const _RemoteActivationBlock({
    required this.mac,
    required this.expanded,
    required this.onToggle,
    required this.onCopy,
    required this.onContact,
  });

  final String? mac;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onCopy;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    final String macDisplay = mac ?? 'MK:??:??:??:??:??';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // ----- En-tete tappable (toujours visible) -----
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.support_agent_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Activation a distance',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ----- Contenu deplie -----
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Divider(height: 1, color: AppColors.border),
                        const SizedBox(height: 12),
                        Text(
                          'Communique cet identifiant a ton revendeur '
                          'pour qu\'il active tes chaines a distance.',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.border,
                            ),
                          ),
                          child: SelectableText(
                            macDisplay,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: mac == null ? null : onCopy,
                                icon: const Icon(
                                  Icons.copy_rounded,
                                  size: 16,
                                ),
                                label: const Text('Copier'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: mac == null ? null : onContact,
                                icon: const Icon(
                                  Icons.send_rounded,
                                  size: 16,
                                ),
                                label: const Text('Envoyer'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
