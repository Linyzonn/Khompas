// Tests du serveur Khompas — `deno test --unstable-kv server/`.
// Le module est importe SANS demarrer Deno.serve (garde import.meta.main),
// et un KV en memoire est injecte : chaque test parle au vrai handler.
import { gerer, injecterKv } from './main.ts';

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
