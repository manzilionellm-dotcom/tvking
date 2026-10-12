// Parcours réel : formulaire React → Worker local → D1 → lecture de l'app.
import assert from 'node:assert/strict';

export async function campaignsParcours({ page, box, check }) {
  await page.goto('http://127.0.0.1:5173/campaigns');
  await page.getByRole('heading', { name: 'Publicités et événements', exact: true }).waitFor();
  await page.getByLabel('Titre', { exact: true }).fill('Rendez-vous découverte');
  await page.getByLabel('Message', { exact: true }).fill('Une rencontre ouverte à tous.');
  await page.getByLabel('Type', { exact: true }).selectOption('event');
  await page.getByLabel('Activer le visuel 3D').check();
  await page.getByRole('button', {name:'Prisme Un volume lumineux'}).click();
  await page.getByLabel('Ambiance', {exact:true}).selectOption('ice');
  await page.getByLabel('Petit badge', {exact:true}).fill('DÉCOUVERTE');
  const dates = await page.evaluate(() => {
    const format = at => {
      const d = new Date(at);
      const p = n => String(n).padStart(2, '0');
      return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
    };
    return [format(Date.now() - 60000), format(Date.now() + 3600000)];
  });
  await page.getByLabel('Début de diffusion', { exact: true }).fill(dates[0]);
  await page.getByLabel('Fin de diffusion', { exact: true }).fill(dates[1]);
  let savedStatus = null;
  const observeSave = response => {
    if (response.url().endsWith('/api/v1/campaigns') && response.request().method() === 'POST') savedStatus = response.status();
  };
  page.on('response', observeSave);
  await page.getByRole('button', { name: 'Enregistrer le brouillon', exact: true }).click();
  try {
    await page.getByRole('status').getByText(/Brouillon enregistré/).waitFor();
  } catch (error) {
    // Le scénario ne manipule que ses propres données fictives. Ne sortir
    // aucun en-tête, lien ou corps de requête dans ce diagnostic.
    process.stdout.write(JSON.stringify({
      diagnostic: 'enregistrement_campagne', http: savedStatus,
      statuts: await page.getByRole('status').allTextContents(),
      alertes: await page.getByRole('alert').allTextContents(),
      champsInvalides: await page.locator('form :invalid').evaluateAll(elements => elements.map(e => ({ type: e.type, message: e.validationMessage }))),
    }) + '\n');
    throw error;
  } finally { page.off('response', observeSave); }
  const card = page.getByRole('article').filter({ has: page.getByRole('heading', { name: 'Rendez-vous découverte', exact: true }) });
  await card.getByText('Brouillon', { exact: true }).waitFor();
  const unpublished = await box('GET', '/api/announcement');
  assert.ok(!(unpublished.json.pending || []).some(a => a.title.includes('Rendez-vous découverte')));
  check('campagne créée dans le formulaire : brouillon absent des annonces publiques', true);

  await card.getByRole('button', { name: 'Programmer', exact: true }).click();
  await page.getByRole('alertdialog').getByRole('button', { name: 'Programmer', exact: true }).click();
  await page.getByRole('status').getByText('Période de diffusion enregistrée.').waitFor();
  // Douze apps interrogent le vrai workerd au début de la diffusion.
  // L'insertion doit rester unique même si chacune voit la campagne due.
  const readers = await Promise.all(Array.from({ length: 12 }, () => box('GET', '/api/announcement')));
  assert.ok(readers.every(r => r.status === 200));
  const messages = readers.map(r => r.json.pending.filter(a => a.title === 'Événement · Rendez-vous découverte'));
  assert.ok(messages.every(rows => rows.length === 1));
  assert.equal(new Set(messages.map(rows => rows[0].id)).size, 1);
  const available = readers[0];
  const message = available.json.pending.find(a => a.title === 'Événement · Rendez-vous découverte');
  assert.ok(message);
  assert.equal(message.body, 'Une rencontre ouverte à tous.');
  assert.equal(message.creative.template,'prism');
  assert.equal(message.creative.palette,'ice');
  check('studio 3D : le visuel créé dans React est reçu par la route app',true);
  await page.getByRole('button', { name: 'Actualiser', exact: true }).click();
  await card.getByText('Disponible dans l’app', { exact: true }).waitFor();
  check('campagne programmée dans le formulaire : message relu par la route de l’app', true);
  check('douze lecteurs concurrents sur workerd : un seul identifiant de campagne', true);

  await card.getByRole('button', { name: 'Mettre en pause', exact: true }).click();
  await card.getByText('En pause', { exact: true }).waitFor();
  const paused = await box('GET', '/api/announcement');
  assert.ok(!(paused.json.pending || []).some(a => a.id === message.id));
  await card.getByRole('button', { name: 'Reprendre', exact: true }).click();
  await page.getByRole('alertdialog').getByRole('button', { name: 'Programmer', exact: true }).click();
  await page.getByRole('status').getByText('Période de diffusion enregistrée.').waitFor();
  const resumed = await box('GET', `/api/announcement?after=${message.id}`);
  assert.ok(!(resumed.json.pending || []).some(a => a.title.includes('Rendez-vous découverte')));
  check('pause et reprise par boutons : aucune seconde annonce après le curseur', true);

  await card.getByRole('button', { name: 'Dupliquer', exact: true }).click();
  assert.equal(await page.getByLabel('Titre', { exact: true }).inputValue(), 'Rendez-vous découverte');
  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);
  check('duplication préparée et écran mobile sans débordement horizontal', true);
  await page.emulateMedia({reducedMotion:'reduce'});
  assert.equal(await page.locator('.creative-object').evaluate(el=>getComputedStyle(el).animationName),'none');
  await page.screenshot({path:new URL('./.state/studio-mobile.png',import.meta.url).pathname,fullPage:true});
  await page.emulateMedia({reducedMotion:'no-preference'});
  await page.setViewportSize({ width: 1280, height: 800 });
}
