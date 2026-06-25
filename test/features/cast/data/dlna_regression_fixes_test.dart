// =========================================================
//  dlna_regression_fixes_test.dart — Régression cast LG + durcissement
// =========================================================
//  Verrouille les correctifs DLNA de la mission « réparer le cast » :
//
//   (a) Stratégie DIRECT 0/1 : CastManager.dlnaDirectUrlFor renvoie bien
//       l'upstream DIRECT (jamais l'URL Worker /cs/ — régression 3586027
//       qui coupait le live à ~105 s).
//   (b) Sécurité HTTPS/DLNA : si une redirection a fait passer finalUrl
//       en https alors qu'originalUrl était http, on envoie l'URL HTTP
//       (la pile DLNA webOS gère mal le TLS).
//   (c) Cohérence MIME LG : UpnpAvTransport.applyLgMimeRewrite réécrit
//       video/mp2t → video/vnd.dlna.mpeg-tts UNIQUEMENT pour LG, et la
//       MÊME fonction sert au DIDL-Lite ET au header contentFeatures
//       → impossible de diverger.
//   (d) DLNA.ORG_FLAGS live : la valeur reconnue 01700000… pour le live,
//       95000000… conservée pour la VOD.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/dlna_profiles.dart';
import 'package:tv_king/features/cast/data/upnp_av_transport.dart';

void main() {
  // ============================================================
  //  (a)+(b) dlnaDirectUrlFor — direct upstream + http préféré
  // ============================================================
  group('CastManager.dlnaDirectUrlFor (régression 3586027 + TLS webOS)', () {
    test('finalUrl http (cas courant IPTV) → renvoyé tel quel (DIRECT)', () {
      const String u = 'http://1.2.3.4/live/u/p/42.ts';
      expect(
        CastManager.dlnaDirectUrlFor(finalUrl: u, originalUrl: u),
        u,
      );
    });

    test('jamais une URL Worker /cs/ — c\'est bien l\'upstream qui ressort', () {
      const String upstream = 'http://1.2.3.4/live/u/p/42.ts';
      final String out =
          CastManager.dlnaDirectUrlFor(finalUrl: upstream, originalUrl: upstream);
      expect(out, isNot(contains('/cs/')));
      expect(out, isNot(contains('app.7themotion.com')));
    });

    test('redirection http → https : on préfère l\'URL HTTP d\'origine', () {
      const String origin = 'http://1.2.3.4/live/u/p/42.ts';
      const String httpsFinal = 'https://cdn.example.com/live/u/p/42.ts';
      expect(
        CastManager.dlnaDirectUrlFor(finalUrl: httpsFinal, originalUrl: origin),
        origin,
      );
    });

    test('finalUrl https mais origin déjà https → on garde finalUrl', () {
      const String origin = 'https://x/live/1.ts';
      const String httpsFinal = 'https://cdn/live/1.ts';
      expect(
        CastManager.dlnaDirectUrlFor(finalUrl: httpsFinal, originalUrl: origin),
        httpsFinal,
      );
    });

    test('casse / scheme majuscule géré', () {
      const String origin = 'HTTP://x/1.ts';
      const String httpsFinal = 'HTTPS://cdn/1.ts';
      expect(
        CastManager.dlnaDirectUrlFor(finalUrl: httpsFinal, originalUrl: origin),
        origin,
      );
    });
  });

  // ============================================================
  //  (c) applyLgMimeRewrite — réécriture MIME cohérente LG
  // ============================================================
  group('UpnpAvTransport.applyLgMimeRewrite (cohérence DIDL/header)', () {
    test('LG : video/mp2t → video/vnd.dlna.mpeg-tts', () {
      const String p =
          'http-get:*:video/mp2t:DLNA.ORG_PN=MPEG_TS_SD_NA_ISO;DLNA.ORG_OP=00';
      final String out = UpnpAvTransport.applyLgMimeRewrite(p, isLg: true);
      expect(out, contains('video/vnd.dlna.mpeg-tts'));
      expect(out, isNot(contains('video/mp2t')));
    });

    test('non-LG : protocolInfo inchangé', () {
      const String p =
          'http-get:*:video/mp2t:DLNA.ORG_PN=MPEG_TS_SD_NA_ISO;DLNA.ORG_OP=00';
      expect(UpnpAvTransport.applyLgMimeRewrite(p, isLg: false), p);
    });

    test('LG sans mp2t (ex. mp4) : inchangé', () {
      const String p = 'http-get:*:video/mp4:DLNA.ORG_PN=AVC_MP4_BL_CIF15_AAC_520';
      expect(UpnpAvTransport.applyLgMimeRewrite(p, isLg: true), p);
    });

    test(
      'le 4e champ (flags) — utilisé par contentFeatures — reste identique '
      'après réécriture (DIDL et header ne divergent pas)',
      () {
        const String p =
            'http-get:*:video/mp2t:DLNA.ORG_PN=MPEG_TS_SD_NA_ISO;DLNA.ORG_OP=00;'
            'DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000';
        final String rewritten =
            UpnpAvTransport.applyLgMimeRewrite(p, isLg: true);
        // Le header contentFeatures.dlna.org = le 4e segment (index 3).
        expect(p.split(':')[3], rewritten.split(':')[3]);
      },
    );
  });

  // ============================================================
  //  (d) DLNA.ORG_FLAGS — live vs VOD
  // ============================================================
  group('DlnaProfile.buildProtocolInfo — FLAGS live/VOD', () {
    test('LIVE (streaming) → DLNA.ORG_FLAGS=01700000…', () {
      const DlnaProfile live = DlnaProfile(
        mime: 'video/mp2t',
        profileName: 'MPEG_TS_SD_NA_ISO',
        transferMode: DlnaTransferMode.streaming,
      );
      final String pi = live.buildProtocolInfo();
      expect(
        pi,
        contains('DLNA.ORG_FLAGS=01700000000000000000000000000000'),
      );
      expect(pi, contains('DLNA.ORG_OP=00')); // pas de seek en live
    });

    test('VOD (interactive) → FLAGS=95000000… + OP=01 (seek)', () {
      const DlnaProfile vod = DlnaProfile(
        mime: 'video/mp4',
        profileName: 'AVC_MP4_BL_CIF15_AAC_520',
        transferMode: DlnaTransferMode.interactive,
      );
      final String pi = vod.buildProtocolInfo();
      expect(
        pi,
        contains('DLNA.ORG_FLAGS=95000000000000000000000000000000'),
      );
      expect(pi, contains('DLNA.ORG_OP=01'));
    });
  });

  // ============================================================
  //  (e) Variantes MIME — universalité TV (Samsung)
  // ============================================================
  group('CastManager.buildAltMimeProfiles (Samsung / universalité)', () {
    test('flux MPEG-TS (mp2t) → variantes mpeg + vnd.dlna.mpeg-tts, PAS mp2t', () {
      const DlnaProfile base = DlnaProfile(
        mime: 'video/mp2t',
        profileName: 'MPEG_TS_SD_NA_ISO',
        transferMode: DlnaTransferMode.streaming,
      );
      final List<String> mimes =
          CastManager.buildAltMimeProfiles(base).map((p) => p.mime).toList();
      // Samsung accepte souvent `video/mpeg` : il DOIT être dans les variantes.
      expect(mimes, contains('video/mpeg'));
      expect(mimes, contains('video/vnd.dlna.mpeg-tts'));
      // On n'inclut pas l'étiquette de base (déjà essayée en stratégies 0-4).
      expect(mimes, isNot(contains('video/mp2t')));
    });

    test('variantes sans DLNA.ORG_PN (étiquette MIME nue)', () {
      const DlnaProfile base = DlnaProfile(
        mime: 'video/mp2t',
        profileName: 'MPEG_TS_SD_NA_ISO',
        transferMode: DlnaTransferMode.streaming,
      );
      for (final DlnaProfile p in CastManager.buildAltMimeProfiles(base)) {
        expect(p.profileName, isNull);
      }
    });

    test('flux NON-TS (mp4) → aucune variante (liste vide)', () {
      const DlnaProfile mp4 = DlnaProfile(
        mime: 'video/mp4',
        profileName: 'AVC_MP4_BL_CIF15_AAC_520',
        transferMode: DlnaTransferMode.interactive,
      );
      expect(CastManager.buildAltMimeProfiles(mp4), isEmpty);
    });

    test('base video/mpeg → variantes contiennent mp2t + tts, pas mpeg', () {
      const DlnaProfile base = DlnaProfile(
        mime: 'video/mpeg',
        profileName: null,
        transferMode: DlnaTransferMode.streaming,
      );
      final List<String> mimes =
          CastManager.buildAltMimeProfiles(base).map((p) => p.mime).toList();
      expect(mimes, contains('video/mp2t'));
      expect(mimes, contains('video/vnd.dlna.mpeg-tts'));
      expect(mimes, isNot(contains('video/mpeg')));
    });
  });
}
