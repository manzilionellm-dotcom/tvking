// Parcours réel du bouton M3U / Xtream : panel, Worker local et D1.
// Les adresses et les accès ci-dessous sont des fixtures sans fournisseur.
export async function testSourceButton({ page, panel, box, check, origin, mac, otherMac }) {
  const keptM3u = 'http://127.0.0.1/e2e/kept.m3u';
  const selfM3u = 'http://127.0.0.1/e2e/client.m3u';
  const oldServer = 'http://127.0.0.1/e2e/xtream-old';
  const newServer = 'http://127.0.0.1/e2e/xtream-new';
  const sourcesPath = '/api/v1/sources/' + encodeURIComponent(mac);
  const seeded = await panel(page, sourcesPath, {
    method: 'PUT', body: { sources: [
      { type: 'm3u', m3u_url: keptM3u, label: 'M3U conservé', enabled: false },
      { type: 'xtream', server_url: oldServer, username: 'u1', password: 'p1', label: 'Xtream conservé', enabled: false },
    ] },
  });
  check('préparation réelle : M3U et Xtream éteints', seeded.status === 200);
  const self = await box('POST', '/api/self-source/' + mac, {
    type: 'm3u', m3u_url: selfM3u, label: 'Liste du client',
  });
  check('préparation réelle : liste ajoutée par le client', self.status === 200);
  const otherBefore = await panel(page, '/api/v1/sources/' + encodeURIComponent(otherMac));

  await page.goto(origin + '/chaines?mac=' + encodeURIComponent(mac));
  await page.getByRole('heading', { name: 'Ajouter une liste', exact: true }).waitFor();
  const xtream = page.getByRole('radio', { name: 'Xtream', exact: true });
  const available = await xtream.count() === 1;
  check('le vrai écran Listes propose le choix Xtream', available);
  if (!available) throw new Error('Le choix Xtream est absent de l’écran Listes.');
  await xtream.check();
  await page.getByLabel('Serveur Xtream', { exact: true }).fill('adresse-invalide');
  await page.getByLabel('Identifiant Xtream', { exact: true }).fill('u2');
  const password = page.getByLabel('Mot de passe Xtream', { exact: true });
  await password.fill('p2');
  check('le champ de mot de passe Xtream est masqué', await password.getAttribute('type') === 'password');
  const submit = page.getByRole('button', { name: 'Ajouter la source Xtream', exact: true });
  let writes = 0;
  const observe = (request) => {
    if (request.method() === 'PUT' && request.url().includes('/api/v1/sources/')) writes++;
  };
  page.on('request', observe);
  try {
    await submit.click();
    await page.getByText('Serveur Xtream : adresse http:// ou https:// attendue.', { exact: true }).waitFor();
    check('une adresse Xtream invalide n’envoie aucune écriture', writes === 0);

    await page.getByLabel('Serveur Xtream', { exact: true }).fill(newServer);
    const response = page.waitForResponse((r) => r.request().method() === 'PUT'
      && r.url().endsWith(sourcesPath));
    await submit.click();
    const sent = await (await response).json();
    check('le bouton Xtream produit un ordre traçable pour la MAC choisie',
      sent.ok === true && sent.mac === mac && typeof sent.order_id === 'string' && Number.isInteger(sent.rev));
    const stored = await panel(page, sourcesPath);
    check('ajouter Xtream conserve les trois listes du panel et celle du client',
      stored.json.sources.length === 4
      && stored.json.sources.filter((s) => s.origin !== 'self').length === 3
      && stored.json.sources.some((s) => s.m3u_url === keptM3u && s.enabled === false)
      && stored.json.sources.some((s) => s.server_url === oldServer && s.enabled === false)
      && stored.json.sources.some((s) => s.origin === 'self' && s.m3u_url === selfM3u));
    const readByBox = await box('GET', '/api/device-source/' + mac);
    check('la route de la box reçoit les accès Xtream saisis',
      readByBox.json.sources.some((s) => s.type === 'xtream' && s.server_url === newServer
        && s.username === 'u2' && s.password === 'p2'));
    const otherAfter = await panel(page, '/api/v1/sources/' + encodeURIComponent(otherMac));
    check('l’ajout Xtream ne modifie pas l’autre MAC',
      JSON.stringify(otherAfter) === JSON.stringify(otherBefore));
    await password.waitFor();
    check('les accès saisis sont effacés après l’envoi',
      await password.inputValue() === ''
      && await page.getByLabel('Identifiant Xtream', { exact: true }).inputValue() === '');

    const delivery = page.getByRole('region', { name: 'Suivi de l’envoi', exact: true });
    await delivery.getByText('Enregistrée sur le serveur. En attente de la box…', { exact: true }).waitFor();
    check('le nouvel ajout ne prétend pas être chargé sans accusé', true);
    const received = await box('POST', '/api/box/ack/' + mac, { orders: [{
      order_id: sent.order_id, state: 'received', received_at: Date.now(),
    }] });
    check('le Worker reçoit l’accusé Xtream RECEIVED', received.json.results[0].state === 'received');
    await delivery.getByText('Ordre reçu par la box. Chargement en cours…', { exact: true }).waitFor();
    const applied = await box('POST', '/api/box/ack/' + mac, { orders: [{
      order_id: sent.order_id, state: 'applied', received_at: Date.now(), applied_at: Date.now(),
      result: 'loaded', config_rev: sent.rev,
    }] });
    check('le Worker reçoit l’accusé Xtream APPLIED', applied.json.results[0].state === 'applied');
    await delivery.getByText('Listes confirmées sur la box.', { exact: true }).waitFor();

    // Le même compte avec un nouveau mot de passe doit être mis à jour,
    // même si trois listes sont déjà présentes ; aucun doublon n’est créé.
    await page.getByLabel('Serveur Xtream', { exact: true }).fill(newServer + '/');
    await page.getByLabel('Identifiant Xtream', { exact: true }).fill('u2');
    await password.fill('p3');
    const updatedResponse = page.waitForResponse((r) => r.request().method() === 'PUT'
      && r.url().endsWith(sourcesPath));
    await submit.click();
    await updatedResponse;
    const updated = await panel(page, sourcesPath);
    const sameAccount = updated.json.sources.filter((s) => s.type === 'xtream' && s.username === 'u2');
    check('renvoyer le même Xtream actualise son mot de passe sans quatrième liste',
      sameAccount.length === 1 && sameAccount[0].password === 'p3'
      && updated.json.sources.length === 4);

    // Une quatrième source distincte doit être refusée AVANT le PUT.
    await page.getByLabel('Serveur Xtream', { exact: true }).fill('http://127.0.0.1/e2e/fourth');
    await page.getByLabel('Identifiant Xtream', { exact: true }).fill('u4');
    await password.fill('p4');
    const beforeFourth = writes;
    await submit.click();
    await page.getByText('Cette box a déjà 3 listes du panel. Retire-en une ci-dessous, ou coche « remplacer ».', { exact: true }).waitFor();
    check('une quatrième liste est refusée sans écriture', writes === beforeFourth);
    await page.getByRole('checkbox', { name: /Remplacer les listes du panel/ }).check();
    const replacedResponse = page.waitForResponse((r) => r.request().method() === 'PUT'
      && r.url().endsWith(sourcesPath));
    await page.locator('form button[type="submit"]').click();
    await replacedResponse;
    const replaced = await panel(page, sourcesPath);
    check('le remplacement explicite garde la liste ajoutée par le client',
      replaced.json.sources.length === 2
      && replaced.json.sources.filter((s) => s.origin !== 'self').length === 1
      && replaced.json.sources.some((s) => s.origin === 'self' && s.m3u_url === selfM3u));
  } finally {
    page.off('request', observe);
  }
  // Cette fixture client ne doit pas modifier les autres parcours de la suite.
  const cleaned = await box('DELETE', '/api/self-source/' + mac);
  check('la fixture de liste client est retirée après le parcours', cleaned.status === 200);
}
