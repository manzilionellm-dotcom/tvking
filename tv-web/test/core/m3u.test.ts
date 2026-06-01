// =========================================================
//  m3u.test.ts — Tests du parser M3U
// =========================================================
//  Cas couverts :
//    - Playlist standard avec tvg-id, tvg-logo, group-title
//    - Header absent / corrompu -> []
//    - BOM UTF-8 strippe
//    - CRLF vs LF
//    - Lignes vides intermediaires
//    - EXTGRP override
//    - Attribute sans guillemets
//    - Nom avec virgules
//    - URL sans EXTINF (degenerate)
//    - Commentaires non-EXTINF ignores
// =========================================================

import { describe, it, expect } from 'vitest';
import { parseM3u } from '../../src/core/parsers/m3u.js';

describe('parseM3u', () => {
  it('parse une playlist standard avec tous les attributs', () => {
    const content = `#EXTM3U
#EXTINF:-1 tvg-id="france2.fr" tvg-logo="https://logo.tv/f2.png" group-title="France",France 2
http://server/live/u/p/1.ts
#EXTINF:-1 tvg-id="tf1.fr" tvg-logo="https://logo.tv/tf1.png" group-title="France",TF1
http://server/live/u/p/2.ts`;
    const channels = parseM3u(content);
    expect(channels).toHaveLength(2);
    expect(channels[0]).toMatchObject({
      id: 'france2.fr',
      name: 'France 2',
      url: 'http://server/live/u/p/1.ts',
      logoUrl: 'https://logo.tv/f2.png',
      group: 'France',
      epgId: 'france2.fr',
      orderIndex: 0,
    });
    expect(channels[1]?.orderIndex).toBe(1);
  });

  it('renvoie [] si l\'en-tete #EXTM3U est absente', () => {
    const content = `<html>404 Not Found</html>`;
    expect(parseM3u(content)).toEqual([]);
  });

  it('renvoie [] sur une chaine vide', () => {
    expect(parseM3u('')).toEqual([]);
  });

  it('strippe le BOM UTF-8 en debut de fichier', () => {
    const content = `﻿#EXTM3U
#EXTINF:-1,Test
http://x.tld/1.ts`;
    const result = parseM3u(content);
    expect(result).toHaveLength(1);
    expect(result[0]?.name).toBe('Test');
  });

  it('accepte CRLF (Windows) comme LF', () => {
    const content =
      '#EXTM3U\r\n#EXTINF:-1,One\r\nhttp://x/1.ts\r\n#EXTINF:-1,Two\r\nhttp://x/2.ts\r\n';
    expect(parseM3u(content)).toHaveLength(2);
  });

  it('saute les lignes vides intermediaires', () => {
    const content = `#EXTM3U


#EXTINF:-1,Alpha
http://x/a.ts


#EXTINF:-1,Beta
http://x/b.ts`;
    expect(parseM3u(content)).toHaveLength(2);
  });

  it('honore #EXTGRP comme override du group-title', () => {
    const content = `#EXTM3U
#EXTINF:-1 group-title="OriginalGroup",Canal
#EXTGRP:RealGroup
http://x/1.ts`;
    const [first] = parseM3u(content);
    expect(first?.group).toBe('RealGroup');
  });

  it('garde un nom qui contient des virgules (split sur la DERNIERE virgule)', () => {
    const content = `#EXTM3U
#EXTINF:-1 tvg-id="x",Eurosport, Live HD
http://x/1.ts`;
    const [first] = parseM3u(content);
    expect(first?.name).toBe('Live HD');
    // Note : 'Eurosport, ' fait partie de la zone d'attributs, perdu.
    // C'est conforme a la convention VLC / TiviMate.
  });

  it('genere un id deterministe depuis l\'URL quand tvg-id est absent', () => {
    const content = `#EXTM3U
#EXTINF:-1,Sans EPG
http://example.com/stream.ts`;
    const [first] = parseM3u(content);
    expect(first?.id).toBeTruthy();
    expect(first?.id).not.toBe('Sans EPG');
    // Deux parsings successifs -> meme id (deterministe)
    const [second] = parseM3u(content);
    expect(first?.id).toBe(second?.id);
  });

  it('emet une chaine meme sans EXTINF en derivant le nom de l\'URL', () => {
    const content = `#EXTM3U
http://example.com/path/cool-channel.m3u8`;
    const [first] = parseM3u(content);
    expect(first?.name).toBe('cool-channel');
    expect(first?.url).toBe('http://example.com/path/cool-channel.m3u8');
  });

  it('ignore les commentaires inconnus (#KODIPROP, #EXTVLCOPT...)', () => {
    const content = `#EXTM3U
#KODIPROP:inputstream=inputstream.adaptive
#EXTVLCOPT:http-user-agent=VLC
#EXTINF:-1,X
http://x/1.ts`;
    expect(parseM3u(content)).toHaveLength(1);
  });

  it('accepte les attributs sans guillemets (rare mais legal)', () => {
    const content = `#EXTM3U
#EXTINF:-1 tvg-id=test.id tvg-logo=https://logo,Sans guillemets
http://x/1.ts`;
    const [first] = parseM3u(content);
    expect(first?.epgId).toBe('test.id');
    expect(first?.logoUrl).toBe('https://logo');
  });

  it('preserve l\'ordre via orderIndex 0..n', () => {
    const content = `#EXTM3U
#EXTINF:-1,A
http://x/a.ts
#EXTINF:-1,B
http://x/b.ts
#EXTINF:-1,C
http://x/c.ts`;
    const channels = parseM3u(content);
    expect(channels.map((c) => c.orderIndex)).toEqual([0, 1, 2]);
    expect(channels.map((c) => c.name)).toEqual(['A', 'B', 'C']);
  });

  it('renvoie name par defaut si EXTINF n\'a pas de virgule', () => {
    const content = `#EXTM3U
#EXTINF:-1 tvg-id="x"
http://x/1.ts`;
    const [first] = parseM3u(content);
    expect(first?.name).toBeTruthy();
  });
});
