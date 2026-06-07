// =========================================================
//  dlna_profiles.dart — Profils DLNA + heuristique
// =========================================================
//  Beaucoup de récepteurs DLNA (Samsung, LG, Sony, Philips...)
//  refusent un flux dont le `protocolInfo` n'inclut pas les
//  tokens DLNA standardisés :
//
//     http-get:*:<MIME>:DLNA.ORG_PN=<profil>;
//                       DLNA.ORG_OP=<seek-mask>;
//                       DLNA.ORG_CI=<conversion>;
//                       DLNA.ORG_FLAGS=<flags>
//
//  Sans `DLNA.ORG_PN`, Samsung répond 500 sur SetAVTransportURI,
//  LG affiche "Format non supporté", Sony tombe en TRANSITIONING
//  sans jamais sortir. Ce fichier centralise :
//
//    1. Le catalogue des profils DLNA usuels pour la vidéo
//       streaming (MPEG_TS_*, AVC_TS_*, AVC_MP4_*, MP3...).
//    2. Une heuristique qui devine le bon profil à partir du
//       MIME / extension / résolution annoncée.
//    3. Les constantes pour DLNA.ORG_OP (seek), DLNA.ORG_CI
//       (transcoded), DLNA.ORG_FLAGS (streaming / interactive).
//
//  Spec : DLNA Guidelines vol. 1 §7.3 + UPnP MediaServer 4.0
//  https://www.dlna.org/sites/default/files/2018-01/dlna_guidelines.pdf
// =========================================================

import 'package:flutter/foundation.dart';

/// Type de transfert DLNA selon le contenu.
///
/// - [streaming] = flux LIVE qui n'a pas de fin connue. Le
///   récepteur ne doit pas calculer de barre de progression.
/// - [interactive] = VOD (mp4/mkv/avi avec durée fixe). Permet
///   au récepteur d'afficher une barre + de seek.
/// - [background] = téléchargement long arrière-plan. Pas utilisé
///   ici mais réservé pour les recordings futurs.
enum DlnaTransferMode {
  streaming,
  interactive,
  background,
}

extension DlnaTransferModeHeader on DlnaTransferMode {
  /// Valeur du header HTTP `transferMode.dlna.org`.
  String get header {
    switch (this) {
      case DlnaTransferMode.streaming:
        return 'Streaming';
      case DlnaTransferMode.interactive:
        return 'Interactive';
      case DlnaTransferMode.background:
        return 'Background';
    }
  }
}

/// Représente un `protocolInfo` complet prêt à injecter dans le
/// DIDL-Lite et dans les headers HTTP de la relay.
@immutable
class DlnaProfile {
  const DlnaProfile({
    required this.mime,
    required this.profileName,
    required this.transferMode,
    this.objectClass = 'object.item.videoItem',
    this.fileExtension = 'ts',
  });

  /// Type MIME canonique (ex. `video/mp2t`).
  final String mime;

  /// Valeur du token `DLNA.ORG_PN=` (ex. `MPEG_TS_SD_NA_ISO`).
  /// `null` = profil inconnu, on émet quand même un protocolInfo
  /// mais sans PN — certains récepteurs tolèrent.
  final String? profileName;

  final DlnaTransferMode transferMode;

  /// Classe d'objet UPnP — `videoBroadcast` pour le LIVE TV, `videoItem`
  /// pour la VOD. Les Sony/Bravia notamment exigent `videoBroadcast`
  /// pour les flux IPTV sans durée.
  final String objectClass;

  /// Extension à coller au token de la relay (`/r/<token>.<ext>`) pour
  /// les récepteurs anciens qui filtrent par extension d'URL.
  final String fileExtension;

  /// Booléen utile pour les flags : seek autorisé.
  bool get supportsSeek => transferMode == DlnaTransferMode.interactive;

  /// Construit la chaîne complète qui ira dans `<res protocolInfo="…">`
  /// et dans les headers `contentFeatures.dlna.org` / `getcontentFeatures.dlna.org`.
  ///
  /// Format final (4 segments séparés par `:`):
  ///   `http-get:*:<MIME>:<DLNA-flags>`
  ///
  /// Avec `<DLNA-flags>` une chaîne de tokens séparés par `;` :
  ///   `DLNA.ORG_PN=<profil>;DLNA.ORG_OP=<seek>;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=<32-hex>`
  ///
  /// Si [profileName] est null on émet un `*` à la place (compatibilité
  /// dégradée mais lisible par certains récepteurs comme VLC, Plex, BubbleUPnP).
  String buildProtocolInfo() {
    final StringBuffer dlnaFlags = StringBuffer();
    if (profileName != null) {
      dlnaFlags.write('DLNA.ORG_PN=$profileName;');
    }
    // OP=01 = seek-by-byte autorisé (essentiel pour la VOD)
    // OP=00 = pas de seek (LIVE)
    dlnaFlags.write('DLNA.ORG_OP=${supportsSeek ? '01' : '00'};');
    // CI=0 = contenu NON transcodé (CI=1 si on transcode plus tard)
    dlnaFlags.write('DLNA.ORG_CI=0;');
    // FLAGS — 32 hex chars. Les bits qu'on positionne :
    //   bit 24 (0x01000000) = transfer-mode interactif autorisé
    //   bit 25 (0x02000000) = transfer-mode background autorisé
    //   bit 26 (0x04000000) = transfer-mode streaming autorisé
    //   bit 28 (0x10000000) = HTTP byte-range seek
    //   bit 31 (0x80000000) = sender paced (le serveur fixe le rythme)
    // Pour le LIVE : streaming + sender-paced  → 0x84000000
    // Pour la VOD  : interactive + streaming + byte-seek → 0x95000000
    // Les 24 derniers hex sont réservés/zero.
    final String first32 = supportsSeek ? '95000000' : '84000000';
    dlnaFlags.write('DLNA.ORG_FLAGS=${first32}000000000000000000000000');
    return 'http-get:*:$mime:$dlnaFlags';
  }

  /// Variante minimaliste sans PN — fallback ultime quand le récepteur
  /// rejette même un PN correct. Beaucoup de TVs tolèrent ce format
  /// quand elles n'ont pas le profil exact (VLC notamment).
  String buildMinimalProtocolInfo() {
    return 'http-get:*:$mime:*';
  }
}

// ============================================================
//  Heuristique : URL/MIME → profil
// ============================================================

class DlnaProfiles {
  DlnaProfiles._();

  /// Choisit un profil en fonction du MIME final (récupéré par le
  /// [StreamProbe]) et de l'URL d'origine. Quand le MIME est ambigu
  /// (cas fréquent du `application/octet-stream` retourné par certains
  /// serveurs IPTV), on retombe sur l'extension.
  ///
  /// [isLive] doit refléter l'état réel : un flux IPTV en continu =
  /// streaming, un fichier VOD avec durée = interactive.
  static DlnaProfile select({
    required String url,
    required String? finalMime,
    bool isLive = true,
  }) {
    final String lowerUrl = url.toLowerCase();
    final String? lowerMime = finalMime?.toLowerCase();

    // ----- HLS playlist (m3u8) -----
    // Beaucoup de récepteurs DLNA ne sont PAS compatibles HLS. On
    // marque quand même le MIME ; le récepteur décidera s'il sait le
    // lire.
    if (lowerUrl.contains('.m3u8') ||
        (lowerMime != null && lowerMime.contains('mpegurl'))) {
      return const DlnaProfile(
        mime: 'application/vnd.apple.mpegurl',
        profileName: null, // HLS n'est pas un profil DLNA officiel
        transferMode: DlnaTransferMode.streaming,
        objectClass: 'object.item.videoItem.videoBroadcast',
        fileExtension: 'm3u8',
      );
    }

    // ----- DASH (mpd) -----
    if (lowerUrl.contains('.mpd') ||
        (lowerMime != null && lowerMime.contains('dash+xml'))) {
      return const DlnaProfile(
        mime: 'application/dash+xml',
        profileName: null,
        transferMode: DlnaTransferMode.streaming,
        objectClass: 'object.item.videoItem.videoBroadcast',
        fileExtension: 'mpd',
      );
    }

    // ----- MPEG-TS (cas standard IPTV) -----
    // Les serveurs Xtream Codes servent du MPEG-TS soit avec
    // `video/mp2t`, soit `video/mpeg`, soit (frustrant) `application/
    // octet-stream`. Tous les trois pointent vers le même profil.
    final bool looksLikeTs = lowerUrl.contains('.ts') ||
        lowerUrl.contains('mpegts') ||
        lowerUrl.contains('/live/') ||
        (lowerMime != null &&
            (lowerMime.contains('mp2t') ||
                lowerMime.contains('mpegts') ||
                lowerMime == 'video/mpeg'));
    if (looksLikeTs) {
      // SD / HD heuristique très grossière par défaut. La résolution
      // exacte sortira plus tard quand on aura un probe codec.
      return DlnaProfile(
        mime: 'video/mp2t',
        profileName: 'MPEG_TS_SD_NA_ISO',
        transferMode:
            isLive ? DlnaTransferMode.streaming : DlnaTransferMode.interactive,
        objectClass: isLive
            ? 'object.item.videoItem.videoBroadcast'
            : 'object.item.videoItem',
        fileExtension: 'ts',
      );
    }

    // ----- MP4 (VOD typiquement) -----
    if (lowerUrl.contains('.mp4') ||
        (lowerMime != null && lowerMime.contains('mp4'))) {
      return const DlnaProfile(
        mime: 'video/mp4',
        profileName: 'AVC_MP4_BL_CIF15_AAC_520',
        transferMode: DlnaTransferMode.interactive,
        objectClass: 'object.item.videoItem',
        fileExtension: 'mp4',
      );
    }

    // ----- MKV / autres conteneurs -----
    if (lowerUrl.contains('.mkv') ||
        (lowerMime != null && lowerMime.contains('matroska'))) {
      return const DlnaProfile(
        mime: 'video/x-matroska',
        profileName: null,
        transferMode: DlnaTransferMode.interactive,
        objectClass: 'object.item.videoItem',
        fileExtension: 'mkv',
      );
    }

    // ----- Audio -----
    if (lowerUrl.contains('.mp3') ||
        (lowerMime != null && lowerMime.contains('audio/mpeg'))) {
      return const DlnaProfile(
        mime: 'audio/mpeg',
        profileName: 'MP3',
        transferMode: DlnaTransferMode.interactive,
        objectClass: 'object.item.audioItem.musicTrack',
        fileExtension: 'mp3',
      );
    }

    // ----- Inconnu : on suppose MPEG-TS live (cas par défaut IPTV) -----
    return DlnaProfile(
      mime: 'video/mp2t',
      profileName: 'MPEG_TS_SD_NA_ISO',
      transferMode:
          isLive ? DlnaTransferMode.streaming : DlnaTransferMode.interactive,
      objectClass: isLive
          ? 'object.item.videoItem.videoBroadcast'
          : 'object.item.videoItem',
      fileExtension: 'ts',
    );
  }

  /// Vérifie qu'un profil est annoncé dans la Sink du récepteur
  /// (récupérée via [DlnaCapabilities.fetchSink]). Si Sink est vide
  /// ou non parseable, on retourne `true` par défaut — mieux vaut
  /// tenter que de bloquer l'utilisateur sur un faux négatif.
  static bool isAdvertised(DlnaProfile profile, List<String> receiverSink) {
    if (receiverSink.isEmpty) return true;
    for (final String entry in receiverSink) {
      // entry typique :
      //   http-get:*:video/mp2t:DLNA.ORG_PN=MPEG_TS_SD_NA_ISO
      final List<String> parts = entry.split(':');
      if (parts.length < 3) continue;
      final String entryMime = parts[2].toLowerCase();
      if (entryMime != profile.mime.toLowerCase()) continue;
      if (profile.profileName == null) return true;
      if (parts.length < 4) return true;
      if (parts[3].contains('DLNA.ORG_PN=${profile.profileName}')) {
        return true;
      }
      // MIME OK même sans PN exact = compatibilité probable
      return true;
    }
    return false;
  }
}
