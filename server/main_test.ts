// Tests du serveur Khompas — `deno test --unstable-kv --allow-read server/`.
// Le module est importe SANS demarrer Deno.serve (garde import.meta.main),
// et un KV en memoire est injecte : chaque test parle au vrai handler.
// (--allow-read : le test d'egalite des prompts lit lib/ai_extractor.dart.)
import { gerer, injecterKv, promptColloscope } from './main.ts';

const kv = await Deno.openKv(':memory:');
injecterKv(kv);

const BASE = 'http://localhost';

// Chaque test utilise sa propre IP : les limites journalieres par IP ne
// se marchent pas dessus d'un test a l'autre.
function infoIp(ip: string): Deno.ServeHandlerInfo {
  return {
    remoteAddr: { transport: 'tcp', hostname: ip, port: 4321 },
    completed: Promise.resolve(),
  } as unknown as Deno.ServeHandlerInfo;
}

function req(
  methode: string,
  chemin: string,
  options: { body?: string; headers?: Record<string, string> } = {},
): Request {
  return new Request(`${BASE}${chemin}`, {
    method: methode,
    body: options.body,
    headers: options.headers,
  });
}

async function creerClasse(ip: string): Promise<{ code: string; gestion: string }> {
  const r = await gerer(req('POST', '/api/classes'), infoIp(ip));
  if (r.status !== 200) throw new Error(`creation classe : HTTP ${r.status}`);
  return await r.json();
}

Deno.test('page de santé', async () => {
  const r = await gerer(req('GET', '/'), infoIp('10.0.0.1'));
  if (r.status !== 200) throw new Error(`HTTP ${r.status}`);
  const texte = await r.text();
  if (!texte.includes('Khompas OK')) throw new Error(`corps inattendu : ${texte}`);
});

Deno.test('route inconnue -> 404', async () => {
  const r = await gerer(req('GET', '/api/nimporte'), infoIp('10.0.0.2'));
  if (r.status !== 404) throw new Error(`HTTP ${r.status}`);
  await r.body?.cancel();
});

Deno.test('CORS : DELETE et x-khompas-gestion autorisés (préflight)', async () => {
  const r = await gerer(req('OPTIONS', '/api/classes/ABCDEF'), infoIp('10.0.0.3'));
  const methodes = r.headers.get('access-control-allow-methods') ?? '';
  const entetes = r.headers.get('access-control-allow-headers') ?? '';
  if (!methodes.includes('DELETE')) {
    throw new Error(`DELETE absent des méthodes CORS : ${methodes}`);
  }
  if (!entetes.includes('x-khompas-gestion')) {
    throw new Error(`x-khompas-gestion absent des en-têtes CORS : ${entetes}`);
  }
  await r.body?.cancel();
});

Deno.test('création de classe : code 6 car., gestion 12 car.', async () => {
  const { code, gestion } = await creerClasse('10.0.0.4');
  if (code.length !== 6) throw new Error(`code : ${code}`);
  if (gestion.length !== 12) throw new Error(`gestion : ${gestion}`);
});

Deno.test('limite de classes/jour : la 4e création est refusée (429)', async () => {
  const ip = '10.0.0.5';
  for (let i = 0; i < 3; i++) await creerClasse(ip);
  const r = await gerer(req('POST', '/api/classes'), infoIp(ip));
  if (r.status !== 429) throw new Error(`HTTP ${r.status} au lieu de 429`);
  await r.body?.cancel();
});

Deno.test('limite atomique sous requêtes PARALLÈLES : jamais plus de 3', async () => {
  const ip = '10.0.0.6';
  const reponses = await Promise.all(
    Array.from({ length: 10 }, () => gerer(req('POST', '/api/classes'), infoIp(ip))),
  );
  const ok = reponses.filter((r) => r.status === 200).length;
  for (const r of reponses) await r.body?.cancel();
  if (ok > 3) {
    throw new Error(`${ok} créations passées en parallèle (limite : 3) — compteur non atomique`);
  }
});

Deno.test('PUT photo REFUSÉ sans code de gestion (403), accepté avec', async () => {
  const ip = '10.0.0.7';
  const { code, gestion } = await creerClasse(ip);
  const b64 = btoa('fausse-photo-jpeg');
  // Sans le code de gestion : n'importe quel détenteur du code de classe
  // pouvait écraser le colloscope — c'est la faille corrigée.
  const sans = await gerer(
    req('PUT', `/api/classes/${code}/photos/0`, { body: b64 }),
    infoIp(ip),
  );
  if (sans.status !== 403) throw new Error(`sans gestion : HTTP ${sans.status}`);
  await sans.body?.cancel();
  const avec = await gerer(
    req('PUT', `/api/classes/${code}/photos/0`, {
      body: b64,
      headers: { 'x-khompas-gestion': gestion },
    }),
    infoIp(ip),
  );
  if (avec.status !== 200) throw new Error(`avec gestion : HTTP ${avec.status}`);
  await avec.body?.cancel();
});

Deno.test('DELETE classe : 403 mauvais code de gestion, 200 avec le bon', async () => {
  const ip = '10.0.0.8';
  const { code, gestion } = await creerClasse(ip);
  const mauvais = await gerer(
    req('DELETE', `/api/classes/${code}`, {
      headers: { 'x-khompas-gestion': 'MAUVAISCODE0' },
    }),
    infoIp(ip),
  );
  if (mauvais.status !== 403) throw new Error(`HTTP ${mauvais.status}`);
  await mauvais.body?.cancel();
  const bon = await gerer(
    req('DELETE', `/api/classes/${code}`, {
      headers: { 'x-khompas-gestion': gestion },
    }),
    infoIp(ip),
  );
  if (bon.status !== 200) throw new Error(`HTTP ${bon.status}`);
  await bon.body?.cancel();
});

Deno.test('anti-énumération : après 20 codes inconnus, 429 au lieu de 404', async () => {
  const ip = '10.0.0.9';
  let dernier = 0;
  for (let i = 0; i < 21; i++) {
    const r = await gerer(
      req('GET', '/api/classes/ZZZZZ2/programmes?semaine=2026-08-03'),
      infoIp(ip),
    );
    dernier = r.status;
    await r.body?.cancel();
  }
  if (dernier !== 429) {
    throw new Error(`21e sonde : HTTP ${dernier} — l'oracle d'énumération est ouvert`);
  }
});

Deno.test('compte anonyme : création, auth, aller-retour des données', async () => {
  const ip = '10.0.1.1';
  const rCompte = await gerer(
    req('POST', '/api/comptes', {
      body: JSON.stringify({ filiere: 'PSI', cinqDemi: true }),
      headers: { 'content-type': 'application/json' },
    }),
    infoIp(ip),
  );
  if (rCompte.status !== 200) throw new Error(`création : HTTP ${rCompte.status}`);
  const { cle } = await rCompte.json();
  if (cle.length !== 18) throw new Error(`clé : ${cle}`);

  // Mauvaise clé -> 401.
  const r401 = await gerer(
    req('GET', '/api/compte/data', {
      headers: { 'x-khompas-cle': 'AAAAAA222222222222' },
    }),
    infoIp(ip),
  );
  if (r401.status !== 401) throw new Error(`mauvaise clé : HTTP ${r401.status}`);
  await r401.body?.cancel();

  // Push puis pull : les données reviennent intactes.
  const donnees = JSON.stringify({
    app: 'khompas',
    exportedAt: '2026-08-03T10:00:00Z',
    chapitres: [],
  });
  const rPut = await gerer(
    req('PUT', '/api/compte/data', {
      body: donnees,
      headers: { 'x-khompas-cle': cle },
    }),
    infoIp(ip),
  );
  if (rPut.status !== 200) throw new Error(`push : HTTP ${rPut.status}`);
  await rPut.body?.cancel();
  const rGet = await gerer(
    req('GET', '/api/compte/data', { headers: { 'x-khompas-cle': cle } }),
    infoIp(ip),
  );
  const { data } = await rGet.json();
  if (data !== donnees) throw new Error('les données ne reviennent pas intactes');

  // Garde anti-écrasement : une sauvegarde PLUS ANCIENNE est refusée (409).
  const vieux = JSON.stringify({
    app: 'khompas',
    exportedAt: '2026-08-01T10:00:00Z',
  });
  const r409 = await gerer(
    req('PUT', '/api/compte/data', {
      body: vieux,
      headers: { 'x-khompas-cle': cle },
    }),
    infoIp(ip),
  );
  if (r409.status !== 409) throw new Error(`vieil export : HTTP ${r409.status}`);
  await r409.body?.cancel();
});

Deno.test('programme de colle : PUT ouvert à la classe, GET le restitue', async () => {
  const ip = '10.0.1.2';
  const { code } = await creerClasse(ip);
  const rPut = await gerer(
    req('PUT', `/api/classes/${code}/programmes`, {
      body: JSON.stringify({
        semaine: '2026-09-07',
        matiere: 'Maths',
        texte: 'Espaces vectoriels normés, chapitres 1 à 3.',
      }),
      headers: { 'content-type': 'application/json' },
    }),
    infoIp(ip),
  );
  if (rPut.status !== 200) throw new Error(`PUT : HTTP ${rPut.status}`);
  await rPut.body?.cancel();
  const rGet = await gerer(
    req('GET', `/api/classes/${code}/programmes?semaine=2026-09-07`),
    infoIp(ip),
  );
  const { programmes } = await rGet.json();
  if (!programmes['maths']?.includes('normés')) {
    throw new Error(`programme absent : ${JSON.stringify(programmes)}`);
  }
});

// ---------- v0.19 : prompts synchrones, garde de version, DELETE compte ----------

Deno.test('prompt colloscope : IDENTIQUE à buildPromptColloscope (Dart)', async () => {
  // Le prompt existe en deux exemplaires (app Flutter + serveur), gardés
  // synchro à la main : ce test échoue dès que l'un diverge de l'autre.
  const dart = await Deno.readTextFile(
    new URL('../lib/ai_extractor.dart', import.meta.url),
  );
  const depuis = dart.indexOf('String buildPromptColloscope');
  const debut = dart.indexOf("return '''", depuis);
  const fin = dart.indexOf("''';", debut);
  if (depuis < 0 || debut < 0 || fin < 0) {
    throw new Error('template Dart introuvable dans lib/ai_extractor.dart');
  }
  // Interpolations Dart -> mêmes valeurs que le serveur.
  const now = new Date();
  const anneeDebut = now.getMonth() + 1 >= 8
    ? now.getFullYear()
    : now.getFullYear() - 1;
  const anneeFin = anneeDebut + 1;
  const dateDuJour = `${now.getDate()}/${now.getMonth() + 1}/${now.getFullYear()}`;
  const attendu = dart
    .slice(debut + "return '''".length, fin)
    .replaceAll('$groupe', '7')
    .replaceAll('$anneeDebut', String(anneeDebut))
    .replaceAll('$anneeFin', String(anneeFin))
    .replaceAll('$dateDuJour', dateDuJour)
    .trim();
  const serveur = promptColloscope(7).trim();
  if (serveur !== attendu) {
    // Trouve la premiere divergence pour un message actionnable.
    let i = 0;
    while (i < Math.min(serveur.length, attendu.length) && serveur[i] === attendu[i]) i++;
    throw new Error(
      `prompts divergents à partir du caractère ${i} :\n` +
        `serveur : …${serveur.slice(Math.max(0, i - 40), i + 40)}…\n` +
        `dart    : …${attendu.slice(Math.max(0, i - 40), i + 40)}…`,
    );
  }
});

async function creerCompte(ip: string): Promise<string> {
  const r = await gerer(req('POST', '/api/comptes'), infoIp(ip));
  if (r.status !== 200) throw new Error(`création compte : HTTP ${r.status}`);
  return (await r.json()).cle;
}

Deno.test('compte : garde par VERSION serveur (x-khompas-version-connue)', async () => {
  const ip = '10.0.2.1';
  const cle = await creerCompte(ip);
  const corps = JSON.stringify({ app: 'khompas', colles: [] });
  // Premier push : pas encore de version connue.
  const r1 = await gerer(
    req('PUT', '/api/compte/data', {
      body: corps,
      headers: { 'x-khompas-cle': cle },
    }),
    infoIp(ip),
  );
  if (r1.status !== 200) throw new Error(`push 1 : HTTP ${r1.status}`);
  const v1 = (await r1.json()).version;
  // Push depuis le MEME appareil (version connue = v1) : accepté.
  const r2 = await gerer(
    req('PUT', '/api/compte/data', {
      body: corps,
      headers: { 'x-khompas-cle': cle, 'x-khompas-version-connue': String(v1) },
    }),
    infoIp(ip),
  );
  if (r2.status !== 200) throw new Error(`push 2 : HTTP ${r2.status}`);
  await r2.body?.cancel();
  // Push depuis un appareil RESTÉ sur v1 (un autre a poussé entre temps) :
  // refusé, quelle que soit l'horloge du téléphone.
  const r3 = await gerer(
    req('PUT', '/api/compte/data', {
      body: corps,
      headers: { 'x-khompas-cle': cle, 'x-khompas-version-connue': String(v1) },
    }),
    infoIp(ip),
  );
  if (r3.status !== 409) throw new Error(`push périmé : HTTP ${r3.status}`);
  await r3.body?.cancel();
});

Deno.test('compte : DELETE purge tout, la clé devient invalide', async () => {
  const ip = '10.0.2.2';
  const cle = await creerCompte(ip);
  const rPut = await gerer(
    req('PUT', '/api/compte/data', {
      body: JSON.stringify({ app: 'khompas' }),
      headers: { 'x-khompas-cle': cle },
    }),
    infoIp(ip),
  );
  if (rPut.status !== 200) throw new Error(`push : HTTP ${rPut.status}`);
  await rPut.body?.cancel();
  const rDel = await gerer(
    req('DELETE', '/api/compte', { headers: { 'x-khompas-cle': cle } }),
    infoIp(ip),
  );
  if (rDel.status !== 200) throw new Error(`DELETE : HTTP ${rDel.status}`);
  await rDel.body?.cancel();
  // La clé ne donne plus accès à rien (profil purgé -> auth invalide).
  const rGet = await gerer(
    req('GET', '/api/compte/data', { headers: { 'x-khompas-cle': cle } }),
    infoIp(ip),
  );
  if (rGet.status !== 401) throw new Error(`après DELETE : HTTP ${rGet.status}`);
  await rGet.body?.cancel();
});

Deno.test('compte : les échecs d\'auth répétés finissent en 429', async () => {
  const ip = '10.0.2.3';
  // 50 clés invalides (18 caractères, id inconnu) : 401. La 51e : 429.
  let dernier = 0;
  for (let i = 0; i < 51; i++) {
    const r = await gerer(
      req('GET', '/api/compte/version', {
        headers: { 'x-khompas-cle': 'ZZZZZZ' + 'A23456789234' },
      }),
      infoIp(ip),
    );
    dernier = r.status;
    await r.body?.cancel();
    if (i < 50 && r.status !== 401) {
      throw new Error(`essai ${i + 1} : HTTP ${r.status} (attendu 401)`);
    }
  }
  if (dernier !== 429) throw new Error(`51e essai : HTTP ${dernier} (attendu 429)`);
});

// ---------- Machine d'extraction Gemini (fetch mocké) ----------
// C'est elle qui casse si Google retire un modèle : les routes étaient
// testées, pas la bascule de modèles.

import { extraireGemini } from './main.ts';

Deno.test('extraction Gemini : 404 -> modèle suivant, réponse restituée', async () => {
  const vraiFetch = globalThis.fetch;
  const appels: string[] = [];
  try {
    globalThis.fetch = ((entree: Request | URL | string) => {
      appels.push(String(entree));
      // Premier modèle : retiré par Google (404). Suivant : répond.
      if (appels.length === 1) {
        return Promise.resolve(new Response('not found', { status: 404 }));
      }
      return Promise.resolve(
        new Response(
          JSON.stringify({
            candidates: [{ content: { parts: [{ text: '{"colles": []}' }] } }],
          }),
          { status: 200 },
        ),
      );
    }) as typeof fetch;
    const texte = await extraireGemini('cle-test', [], 7);
    if (!texte.includes('colles')) throw new Error(`réponse : ${texte}`);
    if (appels.length !== 2) {
      throw new Error(`${appels.length} appel(s) (attendu : 404 puis succès)`);
    }
    if (appels[0] === appels[1]) {
      throw new Error('même modèle rappelé après un 404 — pas de bascule');
    }
  } finally {
    globalThis.fetch = vraiFetch;
  }
});

Deno.test('extraction Gemini : tous les modèles retirés -> message actionnable', async () => {
  const vraiFetch = globalThis.fetch;
  try {
    globalThis.fetch = (() =>
      Promise.resolve(new Response('nf', { status: 404 }))) as typeof fetch;
    let message = '';
    try {
      await extraireGemini('cle-test', [], 7);
    } catch (e) {
      message = String(e);
    }
    if (!message.includes('GEMINI_MODEL')) {
      throw new Error(`message pas actionnable : ${message}`);
    }
  } finally {
    globalThis.fetch = vraiFetch;
  }
});

Deno.test('compte : chunks VERSIONNÉS — donnée intacte et purge des vieilles versions', async () => {
  const ip = '10.0.2.6';
  const cle = await creerCompte(ip);
  const id = cle.slice(0, 6);
  // > 60 Ko : force plusieurs chunks.
  const v1 = JSON.stringify({ app: 'khompas', bourrage: 'x'.repeat(130_000) });
  const r1 = await gerer(
    req('PUT', '/api/compte/data', { body: v1, headers: { 'x-khompas-cle': cle } }),
    infoIp(ip),
  );
  if (r1.status !== 200) throw new Error(`push 1 : HTTP ${r1.status}`);
  const maj1 = (await r1.json()).version;
  const v2 = JSON.stringify({ app: 'khompas', bourrage: 'y'.repeat(70_000) });
  const r2 = await gerer(
    req('PUT', '/api/compte/data', {
      body: v2,
      headers: { 'x-khompas-cle': cle, 'x-khompas-version-connue': String(maj1) },
    }),
    infoIp(ip),
  );
  if (r2.status !== 200) throw new Error(`push 2 : HTTP ${r2.status}`);
  await r2.body?.cancel();
  const rGet = await gerer(
    req('GET', '/api/compte/data', { headers: { 'x-khompas-cle': cle } }),
    infoIp(ip),
  );
  const { data } = await rGet.json();
  if (data !== v2) throw new Error('la donnée ne revient pas intacte');
  // Purge : seuls les chunks de la version courante subsistent (70 Ko -> 2).
  let restants = 0;
  for await (const _ of kv.list({ prefix: ['accd', id] })) restants++;
  if (restants !== 2) {
    throw new Error(`${restants} chunk(s) restants (attendu 2 : purge ratée)`);
  }
});

Deno.test('compte : l\'ancien schéma de chunks (plat) reste lisible', async () => {
  const ip = '10.0.2.7';
  const cle = await creerCompte(ip);
  const id = cle.slice(0, 6);
  // Seed a l'ancienne : chunks ['accd', id, n] + meta d'avant la migration.
  await kv.set(['accd', id, 0], 'ancien-');
  await kv.set(['accd', id, 1], 'format');
  await kv.set(['accm', id], { maj: 123, chunks: 2, exportedAt: 123 });
  const rGet = await gerer(
    req('GET', '/api/compte/data', { headers: { 'x-khompas-cle': cle } }),
    infoIp(ip),
  );
  const { data } = await rGet.json();
  if (data !== 'ancien-format') throw new Error(`lu : ${data}`);
});

Deno.test('flux ICS : jeton idempotent, calendrier généré, 404 sinon', async () => {
  const ip = '10.0.3.1';
  const cle = await creerCompte(ip);
  const donnees = JSON.stringify({
    app: 'khompas',
    colles: [{
      id: 'C1',
      matiere: 'Maths',
      kholleur: 'M. X',
      salle: '12',
      start: '2026-09-19T16:00:00.000',
      dureeMin: 60,
      programme: 'Séries entières',
    }],
    ds: [{
      id: 'D1',
      titre: 'DS 1',
      matiere: 'Physique',
      date: '2026-09-26T00:00:00.000',
    }],
    devoirs: [{
      id: 'V1',
      titre: 'DM 2',
      matiere: 'Maths',
      dateRendu: '2026-09-28T00:00:00.000',
      rendu: false,
    }],
  });
  const rPut = await gerer(
    req('PUT', '/api/compte/data', {
      body: donnees,
      headers: { 'x-khompas-cle': cle },
    }),
    infoIp(ip),
  );
  if (rPut.status !== 200) throw new Error(`push : HTTP ${rPut.status}`);
  await rPut.body?.cancel();
  // Jeton : cree puis IDEMPOTENT.
  const rJ = await gerer(
    req('POST', '/api/compte/ics-jeton', { headers: { 'x-khompas-cle': cle } }),
    infoIp(ip),
  );
  if (rJ.status !== 200) throw new Error(`jeton : HTTP ${rJ.status}`);
  const { jeton } = await rJ.json();
  if (jeton.length !== 12) throw new Error(`jeton : ${jeton}`);
  const rJ2 = await gerer(
    req('POST', '/api/compte/ics-jeton', { headers: { 'x-khompas-cle': cle } }),
    infoIp(ip),
  );
  if ((await rJ2.json()).jeton !== jeton) {
    throw new Error('le jeton devrait être idempotent');
  }
  // Le calendrier contient kholle (horaire flottant), DS (jour) et DM.
  const rIcs = await gerer(
    req('GET', `/api/compte/ics?j=${jeton}`),
    infoIp(ip),
  );
  if (rIcs.status !== 200) throw new Error(`ics : HTTP ${rIcs.status}`);
  const ics = await rIcs.text();
  for (const attendu of [
    'BEGIN:VCALENDAR',
    'DTSTART:20260919T160000',
    'DTEND:20260919T170000',
    'Khôlle Maths (salle 12)',
    'DTSTART;VALUE=DATE:20260926',
    'DM 2 Maths à rendre',
    'END:VCALENDAR',
  ]) {
    if (!ics.includes(attendu)) {
      throw new Error(`"${attendu}" absent du calendrier :\n${ics}`);
    }
  }
  // Jeton inconnu -> 404.
  const r404 = await gerer(
    req('GET', '/api/compte/ics?j=ZZZZZZZZZZZ2'),
    infoIp(ip),
  );
  if (r404.status !== 404) throw new Error(`jeton inconnu : HTTP ${r404.status}`);
  await r404.body?.cancel();
  // Apres DELETE du compte, le flux meurt aussi (RGPD).
  const rDel = await gerer(
    req('DELETE', '/api/compte', { headers: { 'x-khompas-cle': cle } }),
    infoIp(ip),
  );
  if (rDel.status !== 200) throw new Error(`DELETE : HTTP ${rDel.status}`);
  await rDel.body?.cancel();
  const rMort = await gerer(
    req('GET', `/api/compte/ics?j=${jeton}`),
    infoIp(ip),
  );
  if (rMort.status !== 404) {
    throw new Error(`flux vivant après suppression : HTTP ${rMort.status}`);
  }
  await rMort.body?.cancel();
});

Deno.test('compte : un texte ACCENTUÉ volumineux passe (octets, pas caractères)', async () => {
  const ip = '10.0.4.1';
  const cle = await creerCompte(ip);
  // 100 000 caractères d'accents = 200 000 octets : l'ancien découpage en
  // 60 000 CARACTÈRES produisait des valeurs de 120 000 octets -> KV refusait
  // ("Value too large"), et la synchro mourait en production.
  // Un SEUL emoji suffit : V8 stocke alors toute la chaîne en UTF-16
  // (2 octets/caractère même pour l'ASCII) -> la valeur sérialisée double.
  const donnees = JSON.stringify({
    app: 'khompas',
    programme: 'Espaces vectoriels normes, series entieres. '.repeat(5_000),
    note: 'é'.repeat(20_000) + ' 🎤 revoir le chapitre',
  });
  const rPut = await gerer(
    req('PUT', '/api/compte/data', { body: donnees, headers: { 'x-khompas-cle': cle } }),
    infoIp(ip),
  );
  if (rPut.status !== 200) throw new Error(`push : HTTP ${rPut.status}`);
  await rPut.body?.cancel();
  const rGet = await gerer(
    req('GET', '/api/compte/data', { headers: { 'x-khompas-cle': cle } }),
    infoIp(ip),
  );
  const { data } = await rGet.json();
  if (data !== donnees) throw new Error('données accentuées corrompues au retour');
});
