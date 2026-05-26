// =========================================================
//  upnp_av_transport.dart — Client SOAP pour AVTransport:1
// =========================================================
//  Envoie les commandes UPnP A/V Control Point qui font tourner
//  les MediaRenderers DLNA :
//    - SetAVTransportURI(uri, metadata)  → choisir le flux
//    - Play                              → lecture
//    - Pause                             → pause
//    - Stop                              → arrêt + libère le renderer
//    - GetTransportInfo                  → diagnostic post-SetURI
//
//  --- Pourquoi cette refonte ---
//
//  La version v1 envoyait un protocolInfo ultra-minimal
//  (`http-get:*:video/mp2t:*`) qui faisait planter Samsung, LG,
//  Sony (HTTP 500 sur SetAVTransportURI) parce qu'il manque les
//  tokens DLNA.ORG_PN / DLNA.ORG_OP / DLNA.ORG_FLAGS. Elle ne
//  faisait pas non plus de Stop préalable, ce qui fait qu'un
//  renderer en état TRANSITIONING refusait la nouvelle URI.
//
//  v2 :
//    1. Toujours Stop AVANT SetAVTransportURI (best-effort).
//    2. Construit un DIDL-Lite complet avec [DlnaProfile] qui
//       choisit le bon profil (MPEG_TS_SD_NA_ISO pour TS, etc.).
//    3. Après SetAVTransportURI, on poll GetTransportInfo jusqu'à
//       ce que le state sorte de TRANSITIONING (max 2s) AVANT
//       d'envoyer Play — beaucoup de TVs renvoient 500 sinon.
//    4. Whitespace compacté dans le SOAP envelope (certaines TVs
//       Samsung parsent strict et rejettent les espaces excédentaires).
//    5. Header `Content-Type: text/xml; charset=utf-8` (sans quotes
//       autour de utf-8 — c'est ce que la spec UPnP DA2.0 §3.2.3
//       attend).
//    6. Trois modes de métadonnée [MetadataMode] que le caller peut
//       basculer entre tentatives : `full` (profil DLNA complet),
//       `minimal` (protocolInfo sans PN, juste MIME) ou `none`
//       (CurrentURIMetaData vide — fallback ultime).
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../domain/cast_device.dart';
import 'cast_transport.dart';
import 'dlna_profiles.dart';

/// Niveau de détail du DIDL-Lite envoyé au récepteur. Le caller
/// (cast_manager) bascule entre ces modes au fil des retries.
enum MetadataMode {
  /// Profil DLNA complet (DLNA.ORG_PN + OP + FLAGS). Cas par défaut
  /// qui fonctionne sur 90% des récepteurs modernes.
  full,

  /// Pas de DLNA.ORG_PN — `protocolInfo` réduit à `http-get:*:<MIME>:*`.
  /// Utile pour les vieilles TVs ou les renderers atypiques (VLC en
  /// renderer mode, BubbleUPnP) qui n'aiment pas un PN qui ne matche
  /// pas leur Sink exact.
  minimal,

  /// CurrentURIMetaData totalement vide — uniquement l'URL est envoyée.
  /// Fallback ultime : certains récepteurs Roku-en-mode-DLNA et vieux
  /// Sony refusent toute métadonnée.
  none,
}

class UpnpAvTransport implements CastTransport {
  UpnpAvTransport(this.device);

  final CastDevice device;

  /// Profil DLNA à utiliser. Initialisé par défaut sur MPEG-TS LIVE
  /// (cas IPTV le plus courant). Le cast_manager le remplace avec
  /// un profil déduit du [StreamProbe] avant chaque tentative.
  DlnaProfile profile = const DlnaProfile(
    mime: 'video/mp2t',
    profileName: 'MPEG_TS_SD_NA_ISO',
    transferMode: DlnaTransferMode.streaming,
    objectClass: 'object.item.videoItem.videoBroadcast',
    fileExtension: 'ts',
  );

  /// Mode de métadonnée pour la PROCHAINE tentative. Le cast_manager
  /// le bascule (`full` → `minimal` → `none`) entre les retries.
  MetadataMode metadataMode = MetadataMode.full;

  static const String _kAvTransportService =
      'urn:schemas-upnp-org:service:AVTransport:1';

  /// Timeout SOAP par commande. Initialement à 5s mais constaté
  /// trop court sur LG webOS QNED816QA (diag du user) : la TV met
  /// 8-12s à répondre au SetAVTransportURI quand le service AVTransport
  /// vient juste de s'allumer (mode standby). On passe à 15s — large
  /// pour ne pas timeout sur les TVs lentes, sans bloquer l'UX trop
  /// longtemps en cas de TV vraiment morte.
  static const Duration _kSoapTimeout = Duration(seconds: 15);

  /// Détection LG WebOS / NetCast. Certaines TVs LG sont strictes
  /// sur le User-Agent et n'acceptent les commandes SOAP que si
  /// l'agent leur ressemble à un client maison ("LG NetCast 4.0").
  /// Avec un agent générique, elles répondent 200 sur SetURI puis
  /// restent silencieuses en STOPPED sur Play.
  bool get _isLg =>
      (device.manufacturer?.toLowerCase().contains('lg') ?? false) ||
      device.name.toLowerCase().contains('webos') ||
      device.name.toLowerCase().contains(' lg ') ||
      device.name.toLowerCase().startsWith('lg ') ||
      device.name.toLowerCase().startsWith('[lg]');

  /// Détection Samsung Tizen / Smart TV. Idem : User-Agent custom
  /// pour matcher les attentes du serveur DMR Samsung.
  bool get _isSamsung =>
      (device.manufacturer?.toLowerCase().contains('samsung') ?? false) ||
      device.name.toLowerCase().contains('samsung');

  // ============================================================
  //  Interface CastTransport
  // ============================================================

  /// Envoie un flux au récepteur et démarre la lecture.
  /// Le caller s'attend à ce que cette méthode retourne une fois
  /// la lecture VRAIMENT commencée — pour ça on poll GetTransportInfo
  /// jusqu'à TRANSPORT_STATE = PLAYING (timeout 4s).
  @override
  Future<void> playStream({
    required String streamUrl,
    String title = '7 MOTION',
  }) async {
    // (1) Best-effort Stop pour libérer le récepteur s'il était occupé.
    //     Beaucoup de Samsung / Sony renvoient 500 sur SetAVTransportURI
    //     si le state actuel est PLAYING ou TRANSITIONING. Stop force
    //     le retour à STOPPED. On ignore les erreurs (le device peut
    //     déjà être stopped → 200, ou ne pas connaître Stop → 500).
    try {
      await _soapCall(
        action: 'Stop',
        body: '<InstanceID>0</InstanceID>',
      );
    } on Exception {
      // ignore — best effort
    }

    // (2) Construit le bloc de métadonnées DIDL-Lite selon le mode courant.
    final String metadata = _buildMetadataForCurrentMode(streamUrl, title);

    // (3) SetAVTransportURI — le point où ça pète habituellement.
    await _soapCall(
      action: 'SetAVTransportURI',
      body: '<InstanceID>0</InstanceID>'
          '<CurrentURI>${_escape(streamUrl)}</CurrentURI>'
          '<CurrentURIMetaData>${_escape(metadata)}</CurrentURIMetaData>',
    );

    // (4) Poll GetTransportInfo jusqu'à sortir de TRANSITIONING.
    //     Sans ça, Play sur un device en TRANSITIONING renvoie 500.
    await _waitOutOfTransition(maxWait: const Duration(seconds: 2));

    // (5) Play
    await _soapCall(
      action: 'Play',
      body: '<InstanceID>0</InstanceID><Speed>1</Speed>',
    );

    // (6) Vérifie qu'on est vraiment passé en PLAYING (ou PAUSED — certains
    //     récepteurs démarrent en PAUSED avant de jouer). Sinon on lève.
    await _waitForPlaying(maxWait: const Duration(seconds: 4));
  }

  @override
  Future<void> pause() => _soapCall(
        action: 'Pause',
        body: '<InstanceID>0</InstanceID>',
      );

  @override
  Future<void> resume() => _soapCall(
        action: 'Play',
        body: '<InstanceID>0</InstanceID><Speed>1</Speed>',
      );

  @override
  Future<void> stop() => _soapCall(
        action: 'Stop',
        body: '<InstanceID>0</InstanceID>',
      );

  // ============================================================
  //  Construction des SOAP envelopes
  // ============================================================

  /// Construit le bloc DIDL-Lite à mettre dans CurrentURIMetaData
  /// en fonction du [MetadataMode] courant.
  String _buildMetadataForCurrentMode(String url, String title) {
    switch (metadataMode) {
      case MetadataMode.full:
        return _buildDidlLite(
          url: url,
          title: title,
          protocolInfo: profile.buildProtocolInfo(),
        );
      case MetadataMode.minimal:
        return _buildDidlLite(
          url: url,
          title: title,
          protocolInfo: profile.buildMinimalProtocolInfo(),
        );
      case MetadataMode.none:
        // Quelques renderers refusent une chaîne vide et préfèrent
        // l'absence pure. Ici "" est valide pour le SOAP, le caller
        // n'a qu'à mettre des `<CurrentURIMetaData></CurrentURIMetaData>`.
        return '';
    }
  }

  /// Construit un bloc DIDL-Lite formaté sur UNE LIGNE pour éviter
  /// les espaces indésirables que certains parseurs SOAP stricts
  /// (Samsung Tizen 2019+) refusent.
  String _buildDidlLite({
    required String url,
    required String title,
    required String protocolInfo,
  }) {
    // Adaptation MIME selon le récepteur. Diagnostic capturé sur la TV
    // LG QNED816QA de l'utilisateur : sa sink contient
    // `video/vnd.dlna.mpeg-tts` mais PAS `video/mp2t`. Quand on envoie
    // `video/mp2t`, LG répond "Resource not found" car elle ne reconnaît
    // pas le MIME annoncé. On rewrite le MIME en MIME que LG comprend.
    String effectiveProtocolInfo = protocolInfo;
    if (_isLg && protocolInfo.contains('video/mp2t')) {
      effectiveProtocolInfo = protocolInfo.replaceAll(
        'video/mp2t',
        'video/vnd.dlna.mpeg-tts',
      );
    }
    final StringBuffer b = StringBuffer()
      ..write('<DIDL-Lite ')
      ..write('xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" ')
      ..write('xmlns:dc="http://purl.org/dc/elements/1.1/" ')
      ..write('xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" ')
      ..write('xmlns:sec="http://www.sec.co.kr/">')
      ..write('<item id="1" parentID="0" restricted="1">')
      ..write('<dc:title>${_escape(title)}</dc:title>')
      ..write('<upnp:class>${profile.objectClass}</upnp:class>')
      ..write('<res protocolInfo="${_escape(effectiveProtocolInfo)}">')
      ..write(_escape(url))
      ..write('</res>')
      ..write('</item>')
      ..write('</DIDL-Lite>');
    return b.toString();
  }

  // ============================================================
  //  Polling GetTransportInfo
  // ============================================================

  /// Poll GetTransportInfo jusqu'à ce que CurrentTransportState
  /// ne soit plus TRANSITIONING. Beaucoup de récepteurs renvoient
  /// 500 sur Play s'ils sont encore en transition.
  Future<void> _waitOutOfTransition({
    required Duration maxWait,
    Duration pollEvery = const Duration(milliseconds: 250),
  }) async {
    final DateTime deadline = DateTime.now().add(maxWait);
    while (DateTime.now().isBefore(deadline)) {
      final String? state = await _getTransportState();
      if (state == null || state != 'TRANSITIONING') return;
      await Future<void>.delayed(pollEvery);
    }
  }

  /// Poll GetTransportInfo jusqu'à PLAYING (ou PAUSED_PLAYBACK).
  /// Si on n'y arrive pas dans le délai, on lève — le caller
  /// déclenchera un retry avec un autre profil/mode.
  Future<void> _waitForPlaying({
    required Duration maxWait,
    Duration pollEvery = const Duration(milliseconds: 300),
  }) async {
    final DateTime deadline = DateTime.now().add(maxWait);
    String? lastState;
    while (DateTime.now().isBefore(deadline)) {
      lastState = await _getTransportState();
      if (lastState == 'PLAYING' ||
          lastState == 'PAUSED_PLAYBACK' ||
          lastState == 'RECORDING') {
        return;
      }
      // STOPPED après Play = le récepteur a refusé silencieusement
      // (cas typique d'un codec non supporté). On le déclare en
      // échec immédiatement pour déclencher le failover.
      if (lastState == 'STOPPED') {
        throw Exception(
          'Le récepteur a refusé le flux (état STOPPED après Play)',
        );
      }
      await Future<void>.delayed(pollEvery);
    }
    if (lastState == null) {
      // GetTransportInfo non supporté — on suppose que le Play a
      // marché (on n'a aucun moyen de vérifier).
      return;
    }
    throw Exception(
      'La lecture n\'a pas démarré (dernier état: $lastState)',
    );
  }

  Future<String?> _getTransportState() async {
    try {
      final http.Response resp = await _soapRequest(
        action: 'GetTransportInfo',
        body: '<InstanceID>0</InstanceID>',
      );
      if (resp.statusCode != 200) return null;
      final XmlDocument doc = XmlDocument.parse(resp.body);
      final Iterable<XmlElement> matches =
          doc.findAllElements('CurrentTransportState');
      if (matches.isEmpty) return null;
      return matches.first.innerText.trim();
    } on Exception {
      return null;
    }
  }

  // ============================================================
  //  HTTP SOAP plomberie
  // ============================================================

  Future<void> _soapCall({
    required String action,
    required String body,
  }) async {
    final http.Response resp = await _soapRequest(action: action, body: body);
    if (resp.statusCode != 200) {
      if (kDebugMode) {
        debugPrint(
          '[UPnP] $action → HTTP ${resp.statusCode}\n${resp.body}',
        );
      }
      // Tentative de lecture du faultString UPnP pour un message plus
      // précis (mais on ne le montre PAS à l'utilisateur, juste en log).
      final String detail = _parseSoapFault(resp.body) ??
          'HTTP ${resp.statusCode}';
      throw Exception('UPnP $action a échoué : $detail');
    }
  }

  Future<http.Response> _soapRequest({
    required String action,
    required String body,
  }) async {
    final String envelope =
        '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>'
        '<u:$action xmlns:u="$_kAvTransportService">'
        '$body'
        '</u:$action>'
        '</s:Body>'
        '</s:Envelope>';

    // En-têtes adaptés au constructeur. LG et Samsung sont stricts
    // sur le User-Agent — un agent générique peut faire passer
    // SetURI en 200 sans erreur, puis Play reste muet en STOPPED.
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'text/xml; charset=utf-8',
      'SOAPAction': '"$_kAvTransportService#$action"',
      'Connection': 'close',
    };
    if (_isLg) {
      headers['User-Agent'] = 'LG NetCast 4.0';
    } else if (_isSamsung) {
      headers['User-Agent'] = 'SEC_HHP_PC/1.0';
    } else {
      headers['User-Agent'] = '7MOTION/1.0 UPnP/1.0';
    }
    // Pour SetAVTransportURI sur du LIVE, on annonce explicitement
    // un transfert "Streaming" via les en-têtes DLNA — ça aide les
    // renderers récents à choisir le bon décodeur sans deviner
    // depuis l'extension du fichier (.ts est ambigu pour beaucoup
    // de TVs grand public).
    if (action == 'SetAVTransportURI') {
      headers['transferMode.dlna.org'] = 'Streaming';
      // Le contentFeatures complet (4 champs : pn / op / ps / flags)
      // = exactement ce qu'on met dans protocolInfo, sans le préfixe
      // `http-get:*:<mime>:`.
      final List<String> parts = profile.buildProtocolInfo().split(':');
      if (parts.length >= 4) {
        headers['contentFeatures.dlna.org'] = parts[3];
      }
    }

    if (kDebugMode) {
      debugPrint(
        '[UPnP] → ${_isLg ? "LG " : _isSamsung ? "SS " : ""}'
        '${device.name} :: $action',
      );
    }

    final http.Response resp = await http
        .post(
          Uri.parse(device.controlUrl),
          headers: headers,
          body: envelope,
        )
        .timeout(_kSoapTimeout);

    if (kDebugMode && resp.statusCode != 200) {
      debugPrint(
        '[UPnP] ← ${resp.statusCode} from ${device.name} :: $action',
      );
    }
    return resp;
  }

  /// Extrait le `<errorDescription>` ou `<faultstring>` d'une réponse
  /// SOAP 500 — uniquement pour les logs dev. Format UPnP 1.0 §3.2.2.
  String? _parseSoapFault(String body) {
    try {
      final XmlDocument doc = XmlDocument.parse(body);
      final Iterable<XmlElement> errDesc =
          doc.findAllElements('errorDescription');
      if (errDesc.isNotEmpty) return errDesc.first.innerText.trim();
      final Iterable<XmlElement> fault = doc.findAllElements('faultstring');
      if (fault.isNotEmpty) return fault.first.innerText.trim();
    } on Exception {
      // body pas XML → tant pis
    }
    return null;
  }

  String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
