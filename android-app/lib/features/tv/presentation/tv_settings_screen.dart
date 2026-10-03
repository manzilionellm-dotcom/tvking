// =========================================================
//  tv_settings_screen.dart — Réglages (MAC à activer + statut)
// =========================================================
//  ESSENTIEL : la MAC de cette TV (à donner au revendeur pour l'activer) +
//  l'état de l'abonnement (lu sur le MÊME worker que le panel).
//
//  PRÉSENTATION (27/09/2026) : ANNEAU 3D — chaque rubrique est une carte
//  qui tourne (◀ ▶), OK ouvre. 1re carte « Mon appareil » : MAC + statut,
//  OK = rafraîchir le statut. Sous l'anneau, titre + description de la
//  carte au centre.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/blackbox/black_box.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../core/i18n/locale_repository.dart';
import '../../../core/update/update_service.dart';
import '../core/tv_tokens.dart';
import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';
import '../../carousel/domain/carousel_config.dart';
import '../../carousel/presentation/zuno_ring_carousel.dart';
import '../../box_extras/box_text.dart';
import '../../box_extras/presentation/tv_extras_screen.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../profiles/data/profile_repository.dart';
import '../../remote/presentation/tv_remote_screen.dart';
import '../../voice/data/voice_remote_assist.dart';
import '../data/startup_preference.dart';
import 'tv_audio_diagnostic_screen.dart';
import 'tv_black_box_screen.dart';
import 'tv_profiles_screen.dart';
import 'tv_legal_screen.dart';
import 'tv_parental_screen.dart';
import 'tv_recordings_screen.dart';
import 'tv_shell.dart';
import 'tv_sources_screen.dart';

class TvSettingsScreen extends StatefulWidget {
  const TvSettingsScreen({super.key});

  @override
  State<TvSettingsScreen> createState() => _TvSettingsScreenState();
}

class _TvSettingsScreenState extends State<TvSettingsScreen> {
  String _mac = '…';
  bool _busy = false;

  // ----- Mise à jour in-app (bouton « qui fonctionne réellement ») -----
  // Cycle : à l'ouverture des Réglages on VÉRIFIE (silencieux) ; la ligne
  // affiche « À jour (build N) » ou « Nouvelle version N disponible — OK pour
  // installer » ; OK → téléchargement avec pourcentage → installateur
  // Android (mise à jour par-dessus, même signature). Tout est journalisé.
  _UpdState _upd = _UpdState.checking;
  UpdateInfo? _updInfo;
  int _updPct = 0;
  String _current = '';
  bool _remoteAi = false;

  @override
  void initState() {
    super.initState();
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = m);
    });
    StartupPreference.instance.load().then((_) {
      if (mounted) setState(() {});
    });
    ProfileRepository.instance.addListener(_onProfile);
    unawaited(VoiceRemoteAssist.load().then((bool on) {
      if (mounted) setState(() => _remoteAi = on);
    }));
    _checkUpdate();
  }

  @override
  void dispose() {
    ProfileRepository.instance.removeListener(_onProfile);
    super.dispose();
  }

  void _onProfile() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleStartup() async {
    final bool next = !StartupPreference.instance.openLastChannel;
    BlackBox.instance.info(
      'DEMARRAGE',
      next ? 'dernière chaîne' : 'accueil',
    );
    await StartupPreference.instance.setOpenLastChannel(next);
    if (mounted) setState(() {});
  }

  Future<void> _checkUpdate() async {
    setState(() => _upd = _UpdState.checking);
    try {
      final PackageInfo p = await PackageInfo.fromPlatform();
      _current = p.version; // numéro visible (88, 89, 90…)
    } catch (_) {}
    final UpdateInfo? u = await UpdateService.instance.check();
    if (!mounted) return;
    setState(() {
      _updInfo = u;
      _upd = u == null ? _UpdState.upToDate : _UpdState.available;
    });
    // Nouvelle version : on commence le téléchargement TOUT DE SUITE, en
    // arrière-plan (s'il n'est pas déjà fait au démarrage de la box). Quand
    // le client appuie, l'installateur s'ouvre sans attendre.
    if (u != null) unawaited(UpdateService.instance.prefetch(u));
  }

  Future<void> _onUpdatePressed() async {
    switch (_upd) {
      case _UpdState.checking:
      case _UpdState.downloading:
        return; // déjà en cours
      case _UpdState.upToDate:
      case _UpdState.failed:
        await _checkUpdate(); // re-vérifie à la demande
        return;
      case _UpdState.available:
        final UpdateInfo? u = _updInfo;
        if (u == null) return;
        BlackBox.instance
            .info('MAJ', 'installation demandée → build ${u.versionCode}');
        setState(() {
          _upd = _UpdState.downloading;
          _updPct = 0;
        });
        final bool ok = await UpdateService.instance.downloadAndInstall(
          u,
          onProgress: (double p) {
            final int pct = (p * 100).round();
            if (mounted && pct != _updPct) setState(() => _updPct = pct);
          },
        );
        if (!mounted) return;
        // Si l'installateur s'est ouvert, Android prend la main : l'app sera
        // relancée par le système une fois la mise à jour installée.
        setState(() => _upd = ok ? _UpdState.available : _UpdState.failed);
        return;
    }
  }

  // ----- Langue -----
  // `null` = Automatique : l'app suit la langue de la TV (cas normal). Chaque
  // OK passe à la langue suivante de la liste, puis revient à Automatique.
  // Le libellé de chaque langue est dans SA langue (« Deutsch », « 中文 »)
  // pour qu'un client reconnaisse la sienne même si l'app est dans une
  // langue qu'il ne lit pas.
  String _languageLabel(BuildContext context) {
    final Locale? cur = LocaleRepository.instance.locale;
    if (cur == null) return context.l10n.tvLanguageAuto;
    return LocaleRepository.localeLabels[cur.languageCode] ?? cur.languageCode;
  }

  Future<void> _nextLanguage() async {
    final List<Locale> all = LocaleRepository.supportedLocales;
    final Locale? cur = LocaleRepository.instance.locale;
    Locale? next;
    if (cur == null) {
      next = all.first;
    } else {
      final int i =
          all.indexWhere((Locale l) => l.languageCode == cur.languageCode);
      next = (i < 0 || i + 1 >= all.length) ? null : all[i + 1];
    }
    BlackBox.instance.info('LANGUE', 'choix : ${next?.languageCode ?? 'auto'}');
    await LocaleRepository.instance.setLocale(next);
    if (mounted) setState(() {});
  }

  Future<void> _toggleRemoteAi() async {
    final bool next = !_remoteAi;
    await VoiceRemoteAssist.setEnabled(next);
    if (mounted) setState(() => _remoteAi = VoiceRemoteAssist.enabled);
  }

  String _updateLabel(BuildContext context) {
    switch (_upd) {
      case _UpdState.checking:
        return context.l10n.tvUpdateChecking;
      case _UpdState.upToDate:
        return _current.isEmpty
            ? context.l10n.tvUpdateUpToDateNoVersion
            : context.l10n.tvUpdateUpToDate(_current);
      case _UpdState.available:
        return context.l10n.tvUpdateAvailable(_updInfo?.versionName ?? '');
      case _UpdState.downloading:
        return context.l10n.tvUpdateDownloading(_updPct.toString());
      case _UpdState.failed:
        return context.l10n.tvUpdateFailed;
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await SubscriptionState.instance.syncWithBackend();
    if (mounted) setState(() => _busy = false);
  }

  ({String label, Color color}) _statusOf(BuildContext context) {
    switch (SubscriptionState.instance.status) {
      case SubscriptionStatus.paid:
        return (
          label: context.l10n.tvStatusPaid,
          color: const Color(0xFF3FBE7C)
        );
      case SubscriptionStatus.trialActive:
        final int d = SubscriptionState.instance.trialDaysRemaining;
        return (
          label: context.l10n.tvStatusTrial(d),
          color: const Color(0xFF5AA0E8)
        );
      case SubscriptionStatus.trialExpired:
        return (
          label: context.l10n.tvStatusTrialExpired,
          color: const Color(0xFFE8B23A)
        );
      case SubscriptionStatus.frozen:
        return (
          label: context.l10n.tvStatusFrozen,
          color: const Color(0xFFE8B23A)
        );
      case SubscriptionStatus.banned:
        return (
          label: context.l10n.tvStatusBanned,
          color: const Color(0xFFFF5A4A)
        );
      case SubscriptionStatus.unknown:
        return (label: context.l10n.tvStatusUnknown, color: TvTokens.mutedDim);
    }
  }

  // ----- Anneau 3D (demande du propriétaire 27/09/2026) -----
  // Les Réglages ne sont plus une liste : chaque rubrique est une CARTE sur
  // l'anneau 3D de Zuno (ZunoRingCarousel). ◀ ▶ fait tourner, OK ouvre.
  // Sous l'anneau, le titre et la description de la carte au centre.
  static const CarouselConfig _ringConfig = CarouselConfig(
    cardWidth: 210,
    cardAspect: 0.78, // carte « portrait » courte : icône + titre + valeur
  );
  int _focusIndex = 0;

  List<_SettingEntry> _entries(BuildContext context) {
    final ({String label, Color color}) st = _statusOf(context);
    final int channels = PlaylistRepository.instance.currentChannels.length;
    void open(Widget page) => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => TvShell(child: page)))
            .then((_) {
          if (mounted) setState(() {}); // compteurs à jour au retour
        });
    return <_SettingEntry>[
      _SettingEntry(
        icon: Icons.tv_rounded,
        title: context.l10n.tvDeviceCard,
        value: _mac,
        mono: true,
        value2: _busy ? context.l10n.tvChecking : st.label,
        value2Color: _busy ? TvTokens.muted : st.color,
        description:
            '${context.l10n.tvDeviceAddressHelp}  ·  OK = ${context.l10n.tvRefreshStatus}',
        onSelect: _busy ? () {} : _refresh,
      ),
      _SettingEntry(
        icon: Icons.settings_remote_rounded,
        title: context.l10n.tvRemoteTitle,
        description: context.l10n.tvSettingsRemote,
        onSelect: () => open(const TvRemoteScreen()),
      ),
      _SettingEntry(
        icon: Icons.auto_awesome_rounded,
        title: boxText(context, 'En plus', 'Extras'),
        description: boxText(
          context,
          'Fonctions que tu peux couper une par une. Aucune ne bloque une chaîne.',
          'Features you can turn off one by one. None of them blocks a channel.',
        ),
        onSelect: () => open(const TvExtrasScreen()),
      ),
      _SettingEntry(
        icon: Icons.play_circle_outline_rounded,
        title: context.l10n.tvStartupTitle,
        value: StartupPreference.instance.openLastChannel
            ? context.l10n.tvStartupLast
            : context.l10n.tvStartupHome,
        description: StartupPreference.instance.openLastChannel
            ? context.l10n.tvStartupHelpLast
            : context.l10n.tvStartupHelpHome,
        onSelect: _toggleStartup,
      ),
      _SettingEntry(
        icon: Icons.dns_rounded,
        title: context.l10n.tvMySources,
        value: context.l10n.tvSourceChannels(channels),
        description: context.l10n.tvSettingsSources,
        onSelect: () => open(const TvSourcesScreen()),
      ),
      _SettingEntry(
        icon: Icons.video_library_rounded,
        title: context.l10n.tvMyRecordings,
        description: context.l10n.tvSettingsRecordingsHint,
        onSelect: () => open(const TvRecordingsScreen()),
      ),
      _SettingEntry(
        icon: Icons.switch_account_rounded,
        title: 'Profils',
        value: ProfileRepository.instance.active.name,
        description:
            'Favoris, historique, reprise, rappels et code séparés. Jusqu\'à 4 profils.',
        onSelect: () => open(const TvProfilesScreen()),
      ),
      _SettingEntry(
        icon: Icons.child_care_rounded,
        title: context.l10n.tvParentalTitle,
        description: context.l10n.tvSettingsParental,
        onSelect: () => open(const TvParentalScreen()),
      ),
      _SettingEntry(
        icon: _upd == _UpdState.available
            ? Icons.system_update_rounded
            : Icons.update_rounded,
        title: context.l10n.tvUpdateTitle,
        value: _updateShort(),
        value2Color: _upd == _UpdState.available ? TvTokens.accentBright : null,
        description: _updateLabel(context),
        onSelect: _onUpdatePressed,
      ),
      _SettingEntry(
        icon: Icons.language_rounded,
        title: context.l10n.tvLanguage,
        value: _languageLabel(context),
        description: context.l10n.tvSettingsLanguage(_languageLabel(context)),
        onSelect: _nextLanguage,
      ),
      _SettingEntry(
        icon: Icons.mic_none_rounded,
        title: context.l10n.tvVoiceRemoteAi,
        value: _remoteAi
            ? context.l10n.tvVoiceRemoteAiOn
            : context.l10n.tvVoiceRemoteAiOff,
        value2Color: _remoteAi ? TvTokens.accentBright : TvTokens.mutedDim,
        description: context.l10n.tvVoiceRemoteAiHelp,
        onSelect: _toggleRemoteAi,
      ),
      _SettingEntry(
        icon: Icons.flight_takeoff_rounded,
        title: context.l10n.tvBlackBoxTitle,
        description: context.l10n.tvSettingsBlackBox,
        onSelect: () => open(const TvBlackBoxScreen()),
      ),
      _SettingEntry(
        icon: Icons.graphic_eq_rounded,
        title: 'Diagnostic du son',
        description:
            'Bouton « Rapport son complet », puis « Envoyer par e-mail ». '
            'Rien ne part tout seul. Les correctifs restent coupés.',
        onSelect: () => open(const TvAudioDiagnosticScreen()),
      ),
      _SettingEntry(
        icon: Icons.gavel_rounded,
        title: context.l10n.tvLegalTitle,
        description: context.l10n.tvSettingsLegal,
        onSelect: () => open(const TvLegalScreen()),
      ),
    ];
  }

  /// Valeur courte de la carte « Mise à jour » : chiffres et symboles
  /// seulement (rien à traduire) — le texte complet est sous l'anneau.
  String _updateShort() {
    switch (_upd) {
      case _UpdState.checking:
        return '…';
      case _UpdState.upToDate:
        return _current.isEmpty ? '✓' : 'v$_current  ✓';
      case _UpdState.available:
        return '→ v${_updInfo?.versionName ?? ''}';
      case _UpdState.downloading:
        return '$_updPct %';
      case _UpdState.failed:
        return '⚠';
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<_SettingEntry> entries = _entries(context);
    final _SettingEntry cur = entries[_focusIndex.clamp(0, entries.length - 1)];
    const CarouselConfig cfg = _ringConfig;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(context.l10n.tvNavSettings,
                style: TextStyle(
                    fontSize: TvDimens.displayM,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.text)),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(context.l10n.tvRingHint,
                  style: TvTokens.ui(TvDimens.caption,
                      color: TvTokens.mutedDim, spacing: 0.6)),
            ),
          ],
        ),
        Expanded(
          child: Center(
            child: ZunoRingCarousel.builder(
              itemCount: entries.length,
              config: cfg,
              autofocus: true,
              initialIndex: _focusIndex,
              semanticLabel: (int i) => entries[i].title,
              cardKey: (int i) => 'settings-$i',
              onFocusIndex: (int i) => setState(() => _focusIndex = i),
              onSelectedIndex: (int i) => entries[i].onSelect(),
              cardBuilder: (BuildContext c, int i, bool selected) =>
                  _SettingCard(
                entry: entries[i],
                width: cfg.cardWidth,
                height: cfg.cardHeight,
                elevated: selected,
              ),
            ),
          ),
        ),
        // ----- Texte de la carte au centre (fondu à chaque changement) -----
        SizedBox(
          height: 92,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Column(
              key: ValueKey<int>(_focusIndex),
              children: <Widget>[
                Text(cur.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.display(TvDimens.headline,
                        weight: FontWeight.w500, spacing: 0.4)),
                const SizedBox(height: 6),
                Text(cur.description,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.ui(TvDimens.body, color: TvTokens.muted)
                        .copyWith(height: 1.35)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // ----- Avertissement « lecteur » toujours visible (bas de page) -----
        Text(
          'Cette application est un LECTEUR multimédia. Elle ne vend, ne '
          'fournit et n\'héberge aucune chaîne, aucun flux ni aucun lien '
          'M3U. Le contenu est fourni par l\'utilisateur, seul responsable '
          'de sa licéité.',
          textAlign: TextAlign.center,
          maxLines: 2,
          style: TvTokens.ui(TvDimens.caption, color: TvTokens.mutedDim)
              .copyWith(height: 1.4),
        ),
      ],
    );
  }
}

/// Une rubrique des Réglages = une carte de l'anneau.
class _SettingEntry {
  const _SettingEntry({
    required this.icon,
    required this.title,
    required this.description,
    required this.onSelect,
    this.value,
    this.value2,
    this.value2Color,
    this.mono = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onSelect;

  /// Valeur affichée sur la carte (MAC, nombre de chaînes, langue…).
  final String? value;

  /// 2e ligne optionnelle (ex. statut de l'abonnement, en couleur).
  final String? value2;
  final Color? value2Color;

  /// Valeur en police à chasse fixe (MAC : chaque caractère lisible).
  final bool mono;
}

/// Carte d'une rubrique — même charte que les affiches du carrousel :
/// dégradé noir → or très sourd, filet or, titre Oswald en capitales.
class _SettingCard extends StatelessWidget {
  const _SettingCard({
    required this.entry,
    required this.width,
    required this.height,
    required this.elevated,
  });

  final _SettingEntry entry;
  final double width;
  final double height;
  final bool elevated;

  static const BorderRadius _radius =
      BorderRadius.all(Radius.circular(TvDimens.cardRadius));

  @override
  Widget build(BuildContext context) {
    final Color top = Color.lerp(TvTokens.card, TvTokens.accentDeep, 0.12)!;
    final String? value = entry.value;
    final String? value2 = entry.value2;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: _radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[top, TvTokens.bg],
        ),
        border: Border.all(color: TvTokens.tileBorder),
        boxShadow: elevated
            ? <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: TvDimens.focusElevBlur,
                  offset: const Offset(0, TvDimens.focusElevDy),
                ),
              ]
            : null,
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
            borderRadius: _radius, gradient: TvTokens.brandGlow),
        child: Padding(
          padding: const EdgeInsets.all(TvDimens.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Pastille d'icône : cercle or très léger, liseré or.
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TvTokens.accent.withValues(alpha: 0.12),
                  border: Border.all(
                      color: TvTokens.accent.withValues(alpha: 0.35)),
                ),
                child: Icon(entry.icon, size: 26, color: TvTokens.accentBright),
              ),
              const Spacer(),
              const SizedBox(
                width: 28,
                height: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: TvTokens.accent,
                    borderRadius: BorderRadius.all(Radius.circular(1)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                entry.title.toUpperCase(),
                // 19 px sur 3 lignes : les mots longs (« ENREGISTREMENTS »,
                // « MENTIONS LÉGALES & CONDITIONS ») tiennent en entier.
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TvTokens.display(TvDimens.titleS,
                        weight: FontWeight.w500, spacing: 0.6)
                    .copyWith(height: 1.12),
              ),
              if (value != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: entry.mono
                      ? TvTokens.mono(TvDimens.caption,
                          color: TvTokens.text, spacing: 0.5)
                      : TvTokens.ui(TvDimens.caption,
                          weight: FontWeight.w500,
                          color:
                              entry.value2 == null && entry.value2Color != null
                                  ? entry.value2Color!
                                  : TvTokens.muted,
                          spacing: 0.4),
                ),
              ],
              if (value2 != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  value2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.ui(TvDimens.caption,
                      weight: FontWeight.w600,
                      color: entry.value2Color ?? TvTokens.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// États du bouton de mise à jour des Réglages.
enum _UpdState { checking, upToDate, available, downloading, failed }
