// =========================================================
//  blackboxDiagnosis.ts — Lire la boîte noire à la place de l'humain
// =========================================================
//  Le journal d'une box fait des centaines de lignes techniques. Cette
//  page les relit et dit EN CLAIR : quelle panne, pourquoi, quoi faire.
//
//  Né d'un cas réel (13/11/2026) : un PC n'ouvrait aucune liste depuis
//  des semaines. La cause (« no such column: hidden ») était écrite dans
//  le journal à chaque démarrage, mais noyée dans 150 lignes.
//
//  RÈGLES
//   • Chaque diagnostic vient d'une phrase réellement présente dans le
//     journal. Rien n'est deviné : pas de signature, pas de diagnostic.
//   • On cite la ligne qui le prouve (`evidence`).
//   • On distingue ce qui touche la DERNIÈRE session (depuis le dernier
//     démarrage) de l'historique : une panne d'il y a un mois n'est
//     peut-être plus d'actualité.
//   • Logique pure : testée dans blackboxDiagnosis.test.ts.
// =========================================================

export type Severity = 'critical' | 'warning' | 'info';

export interface Finding {
  id: string;
  severity: Severity;
  /// Ce qui se passe, en une phrase.
  title: string;
  /// Pourquoi, en mots simples.
  why: string;
  /// Ce qu'il faut faire.
  action: string;
  /// Nombre de lignes concernées dans tout le journal.
  count: number;
  /// Vrai si au moins une ligne date de la dernière session.
  current: boolean;
  /// Horodatage de la dernière ligne concernée (texte du journal).
  last: string;
  /// La ligne qui le prouve, raccourcie.
  evidence: string;
}

export interface Diagnosis {
  /// Version lue sur le dernier démarrage (« 113.0.3+3 »), ou ''.
  version: string;
  /// Horodatage du dernier démarrage, ou ''.
  lastBoot: string;
  /// Nombre de lignes lues.
  lines: number;
  findings: Finding[];
}

interface Line { stamp: string; level: string; tag: string; text: string; raw: string; index: number }

const LINE_RX = /^(\d{2}\/\d{2} \d{2}:\d{2}:\d{2}) ([A-Z]) \[([^\]]+)\] ?(.*)$/;

function parse(text: string): Line[] {
  const out: Line[] = [];
  const rows = text.split(/\r?\n/);
  for (let i = 0; i < rows.length; i++) {
    const m = LINE_RX.exec(rows[i]);
    if (!m) continue;
    out.push({ stamp: m[1], level: m[2], tag: m[3], text: m[4], raw: rows[i], index: i });
  }
  return out;
}

function short(raw: string): string {
  return raw.length > 220 ? `${raw.slice(0, 220)}…` : raw;
}

/// Ce que veut dire le type d'erreur d'un ajout de liste.
const ADD_FAILURES: Record<string, { why: string; action: string }> = {
  SqfliteFfiException: {
    why: 'L’application n’arrive pas à écrire dans sa base locale.',
    action: 'Mettre l’application à jour. Sinon, fermer l’app, supprimer le fichier tv_king.db du dossier Documents, puis rouvrir.',
  },
  DatabaseException: {
    why: 'L’application n’arrive pas à écrire dans sa base locale.',
    action: 'Mettre l’application à jour, ou réinstaller l’application.',
  },
  SocketException: {
    why: 'L’appareil n’arrive pas à joindre le serveur de la liste (pas d’internet, serveur éteint ou adresse fausse).',
    action: 'Vérifier la connexion de l’appareil, puis l’adresse du serveur. Essayer le lien dans un navigateur.',
  },
  TimeoutException: {
    why: 'Le serveur de la liste répond trop lentement ou pas du tout.',
    action: 'Réessayer plus tard. Si ça dure, voir avec le fournisseur de la liste.',
  },
  HandshakeException: {
    why: 'La connexion sécurisée (https) avec le serveur de la liste est refusée.',
    action: 'Essayer la même adresse en http, ou voir avec le fournisseur.',
  },
  FormatException: {
    why: 'Le serveur a répondu, mais pas avec une liste lisible (page d’erreur, fichier vide).',
    action: 'Vérifier le lien complet. Souvent : abonnement expiré ou identifiants faux.',
  },
  PlaylistDeletedException: {
    why: 'Cette liste a été supprimée sur l’appareil : l’application refuse qu’elle revienne toute seule.',
    action: 'La rajouter à la main dans l’application (Réglages → Sources).',
  },
};

/// Lit le journal et rend les pannes reconnues, la plus grave d'abord.
export function diagnoseBlackBox(text: string): Diagnosis {
  const lines = parse(text || '');
  let bootIndex = -1;
  let version = '';
  let lastBoot = '';
  for (const l of lines) {
    if (l.tag === 'BOOT') {
      bootIndex = l.index;
      lastBoot = l.stamp;
      const v = /v(\d[\w.+-]*)/.exec(l.text);
      version = v ? v[1] : '';
    }
  }
  const findings: Finding[] = [];

  function collect(test: (l: Line) => boolean): Line[] {
    return lines.filter(test);
  }
  function add(
    id: string, severity: Severity, hits: Line[],
    title: string, why: string, action: string, evidence?: Line,
  ) {
    if (hits.length === 0) return;
    const lastHit = hits[hits.length - 1];
    findings.push({
      id, severity, title, why, action,
      count: hits.length,
      current: hits.some((h) => h.index >= bootIndex),
      last: lastHit.stamp,
      evidence: short((evidence || lastHit).raw),
    });
  }

  // 1. Base locale sans ses colonnes : plus aucune liste ne peut s'enregistrer.
  const schema = collect((l) => /no such column|has no column n/i.test(l.text));
  const column = /no such column: (\w+)/i.exec(schema.map((l) => l.text).join(' '));
  add('db_schema', 'critical', schema,
    'Base locale abîmée : aucune liste ne peut s’enregistrer',
    `Il manque une colonne${column ? ` (« ${column[1]} »)` : ''} dans le fichier de l’application. ` +
      'Le lien et le fournisseur ne sont pas en cause.',
    'Installer une version qui répare la base au démarrage. En attendant : fermer l’app, supprimer tv_king.db dans Documents, rouvrir.');

  // 2. Listes envoyées par le panel et refusées.
  const refused = collect((l) => l.tag === 'SOURCE' && /du panel refusée/.test(l.text));
  if (schema.length === 0) {
    add('panel_refused', 'critical', refused,
      'Les listes envoyées par le panel sont refusées',
      'L’appareil reçoit bien l’ordre du panel, mais le chargement de la liste échoue.',
      'Lire la ligne citée : elle donne la raison exacte. Essayer aussi le lien dans un navigateur.');
  }

  // 3. Ajout à la main en échec, avec le type d'erreur.
  const manual = collect((l) => l.tag === 'SOURCE' && /ajout source ouverte échoué/.test(l.text));
  if (manual.length > 0) {
    const kind = /échoué \((\w+)\)/.exec(manual[manual.length - 1].text)?.[1] || '';
    const known = ADD_FAILURES[kind];
    if (!(schema.length > 0 && /Sqflite|Database/.test(kind))) {
      add('manual_add', 'critical', manual,
        `Ajout d’une liste à la main en échec${kind ? ` (${kind})` : ''}`,
        known ? known.why : 'Le chargement de la liste a échoué pour une raison que le journal ne détaille pas.',
        known ? known.action : 'Essayer le lien dans un navigateur sur le même appareil, puis redemander le journal.');
    }
  }

  // 4. Ordres du panel en échec.
  const orders = collect((l) => l.tag === 'PANEL' && /en échec/.test(l.text));
  if (schema.length === 0 && refused.length === 0) {
    add('panel_order', 'warning', orders,
      'Un ordre du panel n’a pas pu être appliqué',
      'L’appareil a reçu l’ordre mais ne l’a pas exécuté.',
      'Lire la ligne citée (le mot après « en échec : ») et renvoyer l’ordre.');
  }

  // 5. Aucune chaîne à l'écran.
  const empty = collect((l) => l.tag === 'DIRECT' && /^0 chaînes/.test(l.text));
  if (schema.length === 0) {
    add('no_channels', 'warning', empty,
      'L’écran Direct est vide (0 chaîne)',
      'Aucune liste n’est chargée sur cet appareil, ou toutes sont éteintes.',
      'Ajouter une liste, ou la rallumer dans Réglages → Sources.');
  }

  // 6. Coupures de lecture.
  const cuts = collect((l) => l.tag === 'PLAYER' && /reconnexion dans|secours du direct|après gel/.test(l.text));
  if (cuts.length >= 3) {
    add('playback_cuts', cuts.length >= 10 ? 'critical' : 'warning', cuts,
      `Lecture qui coupe (${cuts.length} reconnexions)`,
      'Le flux s’interrompt et le lecteur doit se reconnecter : serveur IPTV instable ou connexion de l’appareil trop faible.',
      'Tester une autre chaîne et un autre serveur. Si tout coupe : vérifier le Wi-Fi ou passer en câble.');
  }
  const replay = collect((l) => l.tag === 'PLAYER' && /replay : .*retour au direct/.test(l.text));
  add('replay_missing', 'info', replay,
    'Replay indisponible sur certaines émissions',
    'Le fournisseur n’a pas l’archive demandée : l’application est revenue au direct.',
    'Rien à faire côté application. Voir avec le fournisseur si le replay est vendu.');

  // 7. Écran figé. Au-delà de 10 minutes c'est presque toujours la mise
  //    en veille de l'appareil : on ne la compte pas comme une panne.
  const freezes = collect((l) => l.tag === 'GEL').filter((l) => {
    const ms = Number(/~(\d+) ms/.exec(l.text)?.[1] || 0);
    return ms >= 5000 && ms < 600000;
  });
  add('ui_freeze', 'warning', freezes,
    `Application figée plus de 5 secondes (${freezes.length} fois)`,
    'L’écran ne répond plus pendant un moment : appareil trop chargé, ou liste très lourde.',
    'Mettre l’application à jour. Sur un appareil faible : réduire le nombre de listes allumées.');

  // 8. Fermetures brutales.
  const crashes = collect((l) => l.tag === 'EXIT' && /FERMETURE BRUTALE/.test(l.text));
  if (crashes.length >= 2) {
    add('brutal_exit', 'warning', crashes,
      `Fermetures brutales (${crashes.length} fois)`,
      'L’application s’est arrêtée sans passer par une fermeture normale : plantage, manque de mémoire, ou appareil éteint à la prise.',
      'Si l’appareil est simplement débranché le soir, c’est normal. Sinon : mettre à jour et surveiller la mémoire.');
  }

  // 9. Mémoire.
  let peak = 0;
  const mem = collect((l) => {
    if (l.tag !== 'MEM') return false;
    const mo = Number(/rss (\d+) Mo/.exec(l.text)?.[1] || 0);
    if (mo > peak) peak = mo;
    return mo >= 900;
  });
  add('memory', peak >= 1500 ? 'critical' : 'warning', mem,
    `Mémoire très utilisée (jusqu’à ${peak} Mo)`,
    'L’application occupe beaucoup de mémoire : sur une petite box, elle peut être fermée par le système.',
    'Réduire le nombre de listes allumées. À signaler au développeur avec ce journal.');

  // 10. Mise à jour.
  const update = collect((l) => l.tag === 'MAJ' && /echec|non lance|peu de place|autorisation/i.test(l.text));
  add('update', 'warning', update,
    'La mise à jour de l’application n’aboutit pas',
    'Le téléchargement ou l’installation de la nouvelle version a échoué.',
    'Lire la ligne citée : place libre, autorisation « applications inconnues », ou réseau.');

  // 11. Réparations automatiques déjà faites (bonne nouvelle).
  const repaired = collect((l) => l.tag === 'DB' && /colonne manquante réparée/.test(l.text));
  add('db_repaired', 'info', repaired,
    'Base locale réparée automatiquement',
    'L’application a trouvé des colonnes manquantes et les a ajoutées.',
    'Rien à faire. Si une liste manquait, la renvoyer.');

  const order: Record<Severity, number> = { critical: 0, warning: 1, info: 2 };
  findings.sort((a, b) =>
    Number(b.current) - Number(a.current) || order[a.severity] - order[b.severity] || b.count - a.count);
  return { version, lastBoot, lines: lines.length, findings };
}
