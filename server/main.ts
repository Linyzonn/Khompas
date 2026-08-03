// Serveur Khompas (beta) — Deno Deploy + Deno KV.
//
// Ce que fait ce serveur :
//  - un eleve cree une "classe" en envoyant les photos du colloscope
//    -> il recoit un CODE a 6 caracteres a partager ;
//  - chaque camarade demande "code + numero de groupe" -> le serveur extrait
//    les kholles de CE groupe avec la cle API du serveur (variable
//    d'environnement ANTHROPIC_API_KEY) et met le resultat en cache :
//    une seule extraction payante par groupe, pour toute la classe.
//
// Garde-fous : limites par IP et globale par jour, taille des photos bornee,
// tout expire apres ~13 mois (le temps d'une annee scolaire).

// Moteur d'extraction, au choix via les variables d'environnement :
//  - GEMINI_API_KEY : GRATUIT (clé AI Studio, sans carte bancaire) — prioritaire ;
//  - ANTHROPIC_API_KEY : payant (~5 centimes/extraction), qualité maximale.
// Pour changer de moteur : il suffit de changer la variable, pas le code.
// (Apres un changement, ?force=1 permet de re-extraire un groupe deja en cache.)
const MODELE_CLAUDE = 'claude-sonnet-4-6';
// Google retire regulierement ses anciens modeles (le 2.5-flash est deja
// mort pour les nouveaux comptes) : on essaie ces modeles dans l'ordre et on
// saute automatiquement ceux qui repondent 404. GEMINI_MODEL force un modele.
const MODELES_GEMINI = [
  'gemini-3.5-flash',
  'gemini-3.6-flash',
  'gemini-3.5-flash-lite',
];
const MAX_PHOTOS = 5;
const MAX_B64_PAR_PHOTO = 4_000_000; // ~2,8 Mo une fois decode (photo ou PDF)
const CHUNK = 60_000; // Deno KV limite chaque valeur a 64 Ko
const LIMITE_IP_JOUR = 30; // extractions max / appareil / jour
const LIMITE_GLOBALE_JOUR = 200; // extractions max / jour (protege le budget)
const TTL = 400 * 24 * 3600 * 1000; // ~13 mois, en millisecondes
// Les PHOTOS de colloscope (noms de kholleurs = donnees de tiers) expirent
// bien avant le reste : ~4 mois couvrent le semestre + retardataires.
const TTL_PHOTO = 120 * 24 * 3600 * 1000;
// Alphabet sans caracteres ambigus (pas de O/0, I/1/L...).
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

// KV injectable : en production il est ouvert au demarrage (tout en bas,
// sous import.meta.main) ; les tests injectent un KV en memoire via
// injecterKv() — c'est ce qui rend les 660 lignes exposees a Internet
// enfin testables sans les deployer.
let kv: Deno.Kv;
export function injecterKv(k: Deno.Kv) {
  kv = k;
}

function cors(h: Headers = new Headers()): Headers {
  h.set('access-control-allow-origin', '*');
  h.set(
    'access-control-allow-headers',
    'content-type, x-khompas-cle, x-khompas-gestion',
  );
  h.set('access-control-allow-methods', 'GET,POST,PUT,DELETE,OPTIONS');
  return h;
}

function json(data: unknown, status = 200): Response {
  const h = cors(new Headers({ 'content-type': 'application/json; charset=utf-8' }));
  return new Response(JSON.stringify(data), { status, headers: h });
}

function erreur(msg: string, status: number): Response {
  return json({ erreur: msg }, status);
}

async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function genCode(): string {
  const a = new Uint8Array(6);
  crypto.getRandomValues(a);
  let s = '';
  for (const b of a) s += ALPHABET[b % ALPHABET.length];
  return s;
}

// MEME prompt que buildPromptColloscope() dans lib/ai_extractor.dart :
// si tu changes l'un, change l'autre.
function promptColloscope(groupe: number): string {
  const now = new Date();
  const anneeDebut = now.getMonth() + 1 >= 8 ? now.getFullYear() : now.getFullYear() - 1;
  const anneeFin = anneeDebut + 1;
  const dateDuJour = `${now.getDate()}/${now.getMonth() + 1}/${now.getFullYear()}`;
  return `
Tu analyses la photo d'un COLLOSCOPE de classe préparatoire française (tableau : lignes = créneaux de khôlles par matière/professeur/horaire/salle, colonnes = numéros de semaines, cellules = numéro du groupe qui passe).

Ta mission : extraire TOUTES les khôlles du GROUPE ${groupe} uniquement.

Règles importantes :
1. Utilise le tableau des semaines (souvent en bas à droite) pour convertir chaque numéro de semaine en DATE CONCRÈTE, en tenant compte des semaines de vacances intercalées.
2. Le jour et l'heure de chaque khôlle viennent de la ligne du créneau (ex. "jeudi 16h"). Combine-les avec la semaine pour obtenir la date exacte.
3. Lis attentivement les NOTES en bas de page (roulements de créneaux, alternances "lundi 18h ou mardi 16h" selon les semaines, groupes sans certaines colles...) et applique-les.
4. Une cellule "--" ou vide = pas de colle. Ne retiens que les cellules contenant exactement le nombre ${groupe}.
5. Durée par défaut : 60 minutes ; si le créneau indique une plage (ex. "16h-17h30"), calcule la durée réelle.
6. Si une règle est ambiguë ou qu'une lecture est incertaine, fais ton meilleur choix ET signale-le dans "avertissements".
7. Si le tableau des semaines n'indique pas l'année, utilise l'année scolaire en cours : septembre-décembre ${anneeDebut}, janvier-juillet ${anneeFin} (nous sommes le ${dateDuJour}).

Réponds UNIQUEMENT avec ce JSON, sans aucun texte autour :
{
  "colles": [
    {"matiere": "Maths", "kholleur": "M. DUPONT", "salle": "32", "date": "2024-09-19", "heure": "16:00", "duree_min": 60}
  ],
  "avertissements": ["..."]
}
`;
}

// Incremente un compteur journalier de facon ATOMIQUE (check sur le
// versionstamp + retentatives) : sans cela, N requetes envoyees en parallele
// lisaient toutes "0" et passaient toutes sous la limite.
async function incrementerCompteur(
  key: Deno.KvKey,
  max: number,
): Promise<boolean> {
  for (let essai = 0; essai < 5; essai++) {
    const e = await kv.get(key);
    const n = ((e.value as number | null) ?? 0) + 1;
    if (n > max) return false;
    const ok = await kv.atomic()
      .check({ key, versionstamp: e.versionstamp })
      .set(key, n, { expireIn: 2 * 24 * 3600 * 1000 })
      .commit();
    if (ok.ok) return true;
  }
  // Contention anormale apres 5 essais : on refuse par prudence.
  return false;
}

// Retourne null si OK, sinon le message d'erreur a renvoyer (429).
async function limiterDebit(ip: string): Promise<string | null> {
  const jour = new Date().toISOString().slice(0, 10);
  if (!(await incrementerCompteur(['rl', ip, jour], LIMITE_IP_JOUR))) {
    return 'Limite quotidienne atteinte pour cet appareil — réessaie demain.';
  }
  if (!(await incrementerCompteur(['rlg', jour], LIMITE_GLOBALE_JOUR))) {
    return 'Le serveur a atteint sa limite du jour — réessaie demain.';
  }
  return null;
}

// Pieces d'une classe (photos jpeg ou PDF), en base64 + type MIME
// (reconstruites depuis les morceaux KV). null = code inconnu.
type Piece = { b64: string; mime: string };

async function lirePhotos(code: string): Promise<Piece[] | null> {
  const meta = await kv.get(['class', code]);
  if (!meta.value) return null;
  const n = (meta.value as { photos: number }).photos;
  const out: Piece[] = [];
  for (let i = 0; i < n; i++) {
    const m = await kv.get(['mime', code, i]);
    const info = m.value as string | { mime: string; chunks: number } | null;
    let b64 = '';
    if (info && typeof info === 'object') {
      // Format actuel : le nombre de morceaux est connu -> lecture BORNEE.
      // (Sans cette borne, remplacer une photo par une plus petite laissait
      // les vieux morceaux au-dela concatenes -> base64 corrompu.)
      let ok = true;
      for (let c = 0; c < info.chunks; c++) {
        const part = await kv.get(['photo', code, i, c]);
        if (!part.value) {
          ok = false; // morceau expire : photo incomplete, on l'ignore
          break;
        }
        b64 += part.value as string;
      }
      if (ok && b64) out.push({ b64, mime: info.mime });
    } else {
      // Format historique (mime = chaine, pas de compte de morceaux) :
      // lecture jusqu'au premier trou, comme avant.
      for (let c = 0; ; c++) {
        const part = await kv.get(['photo', code, i, c]);
        if (!part.value) break;
        b64 += part.value as string;
      }
      if (b64) out.push({ b64, mime: (info as string | null) ?? 'image/jpeg' });
    }
  }
  return out;
}

async function extraire(pieces: Piece[], groupe: number): Promise<string> {
  const cleGemini = Deno.env.get('GEMINI_API_KEY');
  const cleClaude = Deno.env.get('ANTHROPIC_API_KEY');
  if (cleGemini) return await extraireGemini(cleGemini, pieces, groupe);
  if (cleClaude) return await extraireClaude(cleClaude, pieces, groupe);
  throw new Error(
    "aucune clé configurée sur le serveur — ajoute GEMINI_API_KEY (gratuite, aistudio.google.com) ou ANTHROPIC_API_KEY dans les variables d'environnement.",
  );
}

async function extraireGemini(
  cle: string,
  pieces: Piece[],
  groupe: number,
): Promise<string> {
  const forceModele = Deno.env.get('GEMINI_MODEL');
  const modeles = forceModele ? [forceModele] : MODELES_GEMINI;
  const parts: unknown[] = pieces.map((p) => ({
    inline_data: { mime_type: p.mime, data: p.b64 },
  }));
  parts.push({ text: promptColloscope(groupe) });
  const body = JSON.stringify({
    contents: [{ parts }],
    // Tres large : la reflexion interne du modele compte dans la sortie, et
    // une reponse coupee = JSON casse (vu en vrai a 16384).
    generationConfig: { maxOutputTokens: 32768 },
  });
  let indisponibles = '';
  for (const modele of modeles) {
    for (let essai = 0; essai < 2; essai++) {
      // La cle passe en EN-TETE, jamais dans l'URL : une query string finit
      // dans les logs de plateforme et les traces de proxy.
      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${modele}:generateContent`,
        {
          method: 'POST',
          headers: { 'content-type': 'application/json', 'x-goog-api-key': cle },
          body,
        },
      );
      if (res.ok) {
        const data = await res.json() as {
          candidates?: { content?: { parts?: { text?: string }[] } }[];
        };
        return (data.candidates?.[0]?.content?.parts ?? [])
          .map((p) => p.text ?? '')
          .join('\n');
      }
      const texte = (await res.text()).slice(0, 300);
      // 404 = modele retire par Google : on passe au suivant de la liste.
      if (res.status === 404) {
        indisponibles += `${modele} `;
        break;
      }
      // Quota gratuit : ~10 requetes/minute. Si toute une classe arrive en
      // meme temps, on encaisse un refus en retentant une fois apres 8 s.
      if ((res.status === 429 || res.status === 503) && essai === 0) {
        await new Promise((r) => setTimeout(r, 8000));
        continue;
      }
      // Le detail (corps amont) reste dans les logs serveur ; le client ne
      // recoit que le statut — pas d'infos sur notre configuration.
      console.error(`API Gemini ${res.status} (${modele}) : ${texte}`);
      throw new Error(
        `le moteur d'extraction a répondu HTTP ${res.status} — réessaie dans quelques minutes.`,
      );
    }
  }
  throw new Error(
    `API Gemini : aucun modèle disponible (essayés : ${indisponibles.trim()}). ` +
      "Fixe GEMINI_MODEL dans les variables d'environnement avec un modèle actuel.",
  );
}

async function extraireClaude(
  cle: string,
  pieces: Piece[],
  groupe: number,
): Promise<string> {
  const content: unknown[] = pieces.map((p) => ({
    // PDF -> bloc "document", photo -> bloc "image".
    type: p.mime === 'application/pdf' ? 'document' : 'image',
    source: { type: 'base64', media_type: p.mime, data: p.b64 },
  }));
  content.push({ type: 'text', text: promptColloscope(groupe) });
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': cle,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: MODELE_CLAUDE,
      max_tokens: 8000,
      messages: [{ role: 'user', content }],
    }),
  });
  if (!res.ok) {
    console.error(`API Claude ${res.status} : ${(await res.text()).slice(0, 300)}`);
    throw new Error(
      `le moteur d'extraction a répondu HTTP ${res.status} — réessaie dans quelques minutes.`,
    );
  }
  const data = await res.json() as { content?: { type: string; text?: string }[] };
  return (data.content ?? [])
    .filter((b) => b.type === 'text')
    .map((b) => b.text ?? '')
    .join('\n');
}

// Demarrage REEL uniquement (pas quand les tests importent ce module).
if (import.meta.main) {
  injecterKv(await Deno.openKv());
  Deno.serve(async (req: Request, info: Deno.ServeHandlerInfo) => {
    try {
      return await gerer(req, info);
    } catch (e) {
      // Quoi qu'il arrive, repondre AVEC les en-tetes CORS : sans eux, le
      // navigateur masque tout derriere un "Failed to fetch" indebogable.
      // Le detail part dans les logs, pas chez le client (fuite d'infos).
      console.error('Erreur interne :', e);
      return erreur('Erreur interne du serveur — réessaie.', 500);
    }
  });
}

export async function gerer(
  req: Request,
  info: Deno.ServeHandlerInfo,
): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors() });
  const url = new URL(req.url);
  const p = url.pathname.replace(/\/+$/, '');
  // Sur Deno Deploy, remoteAddr est l'adresse REELLE du client (la
  // plateforme termine la connexion). Surtout ne pas lire le premier
  // element de x-forwarded-for : c'est une valeur que le client ecrit
  // lui-meme, donc un contournement trivial de toutes les limites par IP.
  // (En dernier recours on prend la DERNIERE entree de XFF : celle ajoutee
  // par le proxy le plus proche, la seule non falsifiable.)
  const xff = req.headers.get('x-forwarded-for')?.split(',') ?? [];
  const ip = (info.remoteAddr as Deno.NetAddr).hostname ||
    (xff.length ? xff[xff.length - 1].trim() : '') || 'inconnu';

  // Petite page de sante, pratique pour verifier que le deploiement marche.
  if (p === '' || p === '/') {
    return new Response('Serveur Khompas OK ✅', {
      headers: cors(new Headers({ 'content-type': 'text/plain; charset=utf-8' })),
    });
  }

  // Compteur anti-abus generique : n operations max par IP et par jour.
  const compterAbus = async (
    quoi: string,
    max: number,
  ): Promise<string | null> => {
    const jour = new Date().toISOString().slice(0, 10);
    const ok = await incrementerCompteur(['rlx', quoi, ip, jour], max);
    return ok
      ? null
      : 'Limite quotidienne atteinte pour cet appareil — réessaie demain.';
  };

  // Anti-enumeration : repondre "Code inconnu" est gratuit pour nous mais
  // renseigne un attaquant qui balaie l'espace des codes. Au-dela de
  // quelques essais rates par jour et par IP, on repond 429 au lieu de 404.
  const codeInconnu = async (): Promise<Response> => {
    const jour = new Date().toISOString().slice(0, 10);
    if (!(await incrementerCompteur(['rlx', '404', ip, jour], 20))) {
      return erreur('Trop d\'essais — réessaie demain.', 429);
    }
    return erreur('Code inconnu.', 404);
  };

  // Creer une classe (vide) -> {code, gestion}. Le code se PARTAGE avec la
  // classe ; le code de GESTION reste chez le createur (suppression).
  if (p === '/api/classes' && req.method === 'POST') {
    // Sans limite, un script saturait le KV gratuit en quelques minutes.
    const refus = await compterAbus('classes', 3);
    if (refus) return erreur(refus, 429);
    for (let essai = 0; essai < 5; essai++) {
      const code = genCode();
      const gestion = genCode() + genCode();
      const ok = await kv.atomic()
        .check({ key: ['class', code], versionstamp: null })
        .set(['class', code], {
          photos: 0,
          cree: Date.now(),
          gestionHash: await sha256Hex(gestion),
        }, { expireIn: TTL })
        .commit();
      if (ok.ok) return json({ code, gestion });
    }
    return erreur('Impossible de générer un code, réessaie.', 500);
  }

  // Supprimer une classe (createur uniquement, via le code de gestion) :
  // photos, extractions et programmes compris. RGPD-friendly.
  const mDel = p.match(/^\/api\/classes\/([A-Z2-9]{6})$/);
  if (mDel && req.method === 'DELETE') {
    const code = mDel[1];
    const meta = await kv.get(['class', code]);
    if (!meta.value) return await codeInconnu();
    const mv = meta.value as { gestionHash?: string };
    const g = (req.headers.get('x-khompas-gestion') ?? '').trim().toUpperCase();
    if (!mv.gestionHash) {
      return erreur(
        'Classe créée avant la gestion des suppressions — elle expirera d\'elle-même.',
        403,
      );
    }
    if (!g || (await sha256Hex(g)) !== mv.gestionHash) {
      return erreur('Code de gestion invalide.', 403);
    }
    for (
      const prefix of [
        ['photo', code],
        ['mime', code],
        ['res', code],
        ['err', code],
        ['pending', code],
        ['prog', code],
      ]
    ) {
      for await (const e of kv.list({ prefix })) await kv.delete(e.key);
    }
    await kv.delete(['class', code]);
    return json({ ok: true });
  }

  // Envoyer la photo n°i (corps = jpeg en base64, texte brut).
  // Reserve au CREATEUR (code de gestion) : le code de classe circule sur
  // les groupes WhatsApp — sans cette verification, n'importe quel eleve
  // pouvait ecraser le colloscope de toute la classe.
  const mUp = p.match(/^\/api\/classes\/([A-Z2-9]{6})\/photos\/([0-9])$/);
  if (mUp && req.method === 'PUT') {
    const code = mUp[1];
    const i = Number(mUp[2]);
    if (i >= MAX_PHOTOS) return erreur(`Maximum ${MAX_PHOTOS} photos.`, 400);
    const meta = await kv.get(['class', code]);
    if (!meta.value) return await codeInconnu();
    const mv = meta.value as { gestionHash?: string };
    const g = (req.headers.get('x-khompas-gestion') ?? '').trim().toUpperCase();
    if (
      mv.gestionHash && (!g || (await sha256Hex(g)) !== mv.gestionHash)
    ) {
      return erreur(
        'Seul le créateur de la classe (code de gestion) peut envoyer les photos.',
        403,
      );
    }
    const refus = await compterAbus('photos', 15);
    if (refus) return erreur(refus, 429);
    // Rejeter les corps enormes AVANT de les materialiser en memoire.
    const annonce = Number(req.headers.get('content-length') ?? '0');
    if (annonce > MAX_B64_PAR_PHOTO + 10_000) {
      return erreur('Fichier trop lourd (2,8 Mo max).', 413);
    }
    const brut = await req.text();
    const b64 = brut.replace(/\s+/g, '');
    if (!b64) return erreur('Fichier vide.', 400);
    if (b64.length > MAX_B64_PAR_PHOTO) {
      return erreur('Fichier trop lourd (2,8 Mo max).', 413);
    }
    const mime = url.searchParams.get('mime') === 'pdf'
      ? 'application/pdf'
      : 'image/jpeg';
    // Les PHOTOS (donnees de tiers : noms des kholleurs) ne restent que
    // ~4 mois — le cache d'extraction, lui, garde son TTL long.
    let nChunks = 0;
    for (; nChunks * CHUNK < b64.length; nChunks++) {
      await kv.set(
        ['photo', code, i, nChunks],
        b64.slice(nChunks * CHUNK, (nChunks + 1) * CHUNK),
        { expireIn: TTL_PHOTO },
      );
    }
    // Le nombre de morceaux BORNE la lecture (voir lirePhotos).
    await kv.set(['mime', code, i], { mime, chunks: nChunks }, {
      expireIn: TTL_PHOTO,
    });
    const m = meta.value as { photos: number; cree: number };
    if (i + 1 > m.photos) {
      await kv.set(['class', code], { ...m, photos: i + 1 }, { expireIn: TTL });
    }
    return json({ ok: true });
  }

  // ---------- Programmes de colles partages (la 2e boucle virale) ----------
  // Un eleve colle le programme de la semaine -> toute la classe le recoit,
  // attache aux kholles de la matiere. Texte brut, pas d'IA.
  const mProg = p.match(/^\/api\/classes\/([A-Z2-9]{6})\/programmes$/);
  if (mProg && req.method === 'PUT') {
    const code = mProg[1];
    if (!(await kv.get(['class', code])).value) {
      return await codeInconnu();
    }
    const refus = await compterAbus('progs', 40);
    if (refus) return erreur(refus, 429);
    let corps: { semaine?: string; matiere?: string; texte?: string } = {};
    try {
      corps = await req.json();
    } catch (_) {
      return erreur('JSON attendu.', 400);
    }
    const semaine = (corps.semaine ?? '').toString().slice(0, 10);
    const matiere = (corps.matiere ?? '').toString().trim().toLowerCase()
      .slice(0, 40);
    const texte = (corps.texte ?? '').toString().trim().slice(0, 2000);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(semaine) || !matiere || !texte) {
      return erreur('semaine (lundi AAAA-MM-JJ), matiere et texte requis.', 400);
    }
    await kv.set(['prog', code, semaine, matiere], texte, {
      expireIn: 60 * 24 * 3600 * 1000,
    });
    return json({ ok: true });
  }
  if (mProg && req.method === 'GET') {
    const code = mProg[1];
    if (!(await kv.get(['class', code])).value) {
      return await codeInconnu();
    }
    const semaine = (url.searchParams.get('semaine') ?? '').slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(semaine)) {
      return erreur('?semaine=AAAA-MM-JJ (lundi) requis.', 400);
    }
    const programmes: Record<string, string> = {};
    for await (const e of kv.list({ prefix: ['prog', code, semaine] })) {
      programmes[String(e.key[3])] = e.value as string;
    }
    return json({ programmes });
  }

  // Kholles d'un groupe -> {text} (le texte JSON du modele ; l'app le parse).
  // ?force=1 pour re-extraire malgre le cache (si l'extraction etait mauvaise).
  const mG = p.match(/^\/api\/classes\/([A-Z2-9]{6})\/groupe\/([0-9]{1,2})$/);
  if (mG && req.method === 'GET') {
    const code = mG[1];
    const groupe = Number(mG[2]);
    if (groupe < 1 || groupe > 40) return erreur('Numéro de groupe invalide.', 400);
    const force = url.searchParams.get('force') === '1';
    if (!force) {
      const cache = await kv.get(['res', code, groupe]);
      if (cache.value) return json({ text: cache.value, cache: true });
    }
    // Erreur laissee par un travail precedent ? On la remonte (une fois).
    const errKey = ['err', code, groupe];
    const errPrec = await kv.get(errKey);
    if (errPrec.value) {
      await kv.delete(errKey);
      return erreur(`Extraction échouée : ${errPrec.value}`, 502);
    }
    // Extraction deja en cours (par toi ou un camarade) ? L'app repassera.
    const pendKey = ['pending', code, groupe];
    const pend = await kv.get(pendKey);
    if (pend.value) return json({ statut: 'en_cours' }, 202);

    const photos = await lirePhotos(code);
    if (photos === null) return await codeInconnu();
    if (photos.length === 0) {
      return erreur("Ce code n'a pas encore de photos de colloscope.", 409);
    }

    // Prise de verrou ATOMIQUE : deux camarades qui cliquent en meme temps
    // ne doivent declencher qu'UNE extraction payante. (Avant : get puis
    // set, donc les deux passaient.)
    const verrou = await kv.atomic()
      .check({ key: pendKey, versionstamp: null })
      .set(pendKey, 1, { expireIn: 4 * 60 * 1000 })
      .commit();
    if (!verrou.ok) return json({ statut: 'en_cours' }, 202);

    const refus = await limiterDebit(ip);
    if (refus) {
      await kv.delete(pendKey);
      return erreur(refus, 429);
    }

    // Une extraction dure 1 a 3 minutes : trop long pour une seule requete
    // HTTP (les passerelles coupent -> "Failed to fetch" cote navigateur).
    // On lance donc le travail EN TACHE DE FOND et on repond tout de suite ;
    // l'app re-interroge toutes les 5 s jusqu'a ce que le cache soit rempli.
    if (force) {
      // Sans cette purge, les sondages suivants (sans force) renverraient
      // l'ancienne version pendant que la nouvelle se calcule.
      await kv.delete(['res', code, groupe]);
    }
    (async () => {
      try {
        const text = await extraire(photos, groupe);
        let entiere = true;
        try {
          const s = text.indexOf('{');
          const e2 = text.lastIndexOf('}');
          if (s < 0 || e2 <= s) throw new Error('pas de JSON');
          JSON.parse(text.slice(s, e2 + 1));
        } catch (_) {
          entiere = false;
        }
        // Reponse entiere : cache longue duree. Reponse tronquee : on la
        // stocke quand meme (l'app en tire le maximum et avertit) mais
        // seulement 10 min, pour qu'un nouvel essai reparte de zero.
        // Garde-fou : si le verrou pending a expire (extraction > 4 min) et
        // qu'un travail concurrent a DEJA ecrit un resultat, on garde le
        // premier — pas d'ecrasement croise ni de double depense.
        const deja = await kv.get(['res', code, groupe]);
        if (!deja.value) {
          await kv.set(['res', code, groupe], text, {
            expireIn: entiere ? TTL : 10 * 60 * 1000,
          });
        }
      } catch (e) {
        await kv.set(
          errKey,
          String(e instanceof Error ? e.message : e).slice(0, 300),
          { expireIn: 10 * 60 * 1000 },
        );
      } finally {
        await kv.delete(pendKey);
      }
    })();
    return json({ statut: 'lancee' }, 202);
  }

  // ---------- Comptes anonymes (cle secrete, pas d'email/mot de passe) ----------
  // La cle = id (6 car.) + secret (12 car.). L'app l'envoie dans l'en-tete
  // x-khompas-cle ; le serveur stocke le profil et les donnees (chunkees).

  const compteAuth = async (): Promise<string | null> => {
    const cle = (req.headers.get('x-khompas-cle') ?? '').trim().toUpperCase();
    if (cle.length !== 18) return null;
    const id = cle.slice(0, 6);
    const acc = await kv.get(['acc', id]);
    if (!acc.value) return null;
    const v = acc.value as {
      secret?: string;
      secretHash?: string;
      [k: string]: unknown;
    };
    const fourni = cle.slice(6);
    if (v.secretHash) {
      return (await sha256Hex(fourni)) === v.secretHash ? id : null;
    }
    // Compte historique (secret en clair) : migration en douceur vers le
    // hash au premier passage — le secret en clair est efface.
    if (v.secret === fourni) {
      const { secret: _ancien, ...reste } = v;
      await kv.set(
        ['acc', id],
        { ...reste, secretHash: await sha256Hex(fourni) },
        { expireIn: TTL },
      );
      return id;
    }
    return null;
  };

  if (p === '/api/comptes' && req.method === 'POST') {
    // Garde-fou : 10 creations de compte max par appareil et par jour.
    const jour = new Date().toISOString().slice(0, 10);
    if (!(await incrementerCompteur(['rlc', ip, jour], 10))) {
      return erreur('Trop de comptes créés depuis cet appareil aujourd\'hui.', 429);
    }
    let corps: { filiere?: string; cinqDemi?: boolean } = {};
    try {
      corps = await req.json();
    } catch (_) {
      // corps vide tolere
    }
    for (let essai = 0; essai < 5; essai++) {
      const id = genCode();
      const secret = genCode() + genCode(); // 12 caracteres
      // Seul le HASH du secret est stocke : une fuite du KV ne donne pas
      // les cles des comptes.
      const ok = await kv.atomic()
        .check({ key: ['acc', id], versionstamp: null })
        .set(['acc', id], {
          secretHash: await sha256Hex(secret),
          filiere: (corps.filiere ?? '').toString().slice(0, 30),
          cinqDemi: !!corps.cinqDemi,
          cree: Date.now(),
        }, { expireIn: TTL })
        .commit();
      if (ok.ok) return json({ cle: id + secret });
    }
    return erreur('Impossible de créer le compte, réessaie.', 500);
  }

  if (p === '/api/compte/data' && req.method === 'PUT') {
    const id = await compteAuth();
    if (!id) return erreur('Clé de compte invalide.', 401);
    // Rejeter les corps enormes AVANT de les materialiser en memoire.
    const annonce = Number(req.headers.get('content-length') ?? '0');
    if (annonce > 300_000) return erreur('Données trop volumineuses.', 413);
    const corps = await req.text();
    if (!corps.trim()) return erreur('Données vides.', 400);
    if (corps.length > 256_000) return erreur('Données trop volumineuses.', 413);
    // Garde anti-ecrasement : la sauvegarde porte son horodatage
    // (exportedAt). Si le serveur detient deja une version PLUS RECENTE
    // (poussee par un autre appareil), on refuse — l'app affiche alors un
    // bandeau et propose « Récupérer ». Sans horodatage lisible (vieux
    // client), on accepte comme avant.
    let exportedAt = 0;
    try {
      const t = Date.parse(JSON.parse(corps).exportedAt ?? '');
      if (!Number.isNaN(t)) exportedAt = t;
    } catch (_) {
      // corps illisible en JSON : pas de garde
    }
    const metaAvant = await kv.get(['accm', id]);
    const prev = (metaAvant.value ?? {}) as { exportedAt?: number };
    if (exportedAt && prev.exportedAt && exportedAt < prev.exportedAt) {
      return erreur(
        'Ton autre appareil a des données plus récentes — fais « Récupérer » dans Réglages → Compte avant de pousser depuis celui-ci.',
        409,
      );
    }
    let n = 0;
    for (; n * CHUNK < corps.length; n++) {
      await kv.set(['accd', id, n], corps.slice(n * CHUNK, (n + 1) * CHUNK), {
        expireIn: TTL,
      });
    }
    const maj = Date.now();
    // meta.chunks borne la lecture : d'eventuels vieux chunks au-dela sont
    // simplement ignores (pas besoin de les supprimer).
    await kv.set(
      ['accm', id],
      { maj, chunks: n, exportedAt: exportedAt || maj },
      { expireIn: TTL },
    );
    return json({ version: maj });
  }

  // Version legere (sans les donnees) : l'app la compare au demarrage a la
  // derniere version qu'ELLE connait — si un autre appareil a pousse entre
  // temps, bannière "Récupérer" AVANT la premiere modification locale.
  if (p === '/api/compte/version' && req.method === 'GET') {
    const id = await compteAuth();
    if (!id) return erreur('Clé de compte invalide.', 401);
    const meta = await kv.get(['accm', id]);
    if (!meta.value) return json({ version: 0 });
    return json({ version: (meta.value as { maj: number }).maj });
  }

  if (p === '/api/compte/data' && req.method === 'GET') {
    const id = await compteAuth();
    if (!id) return erreur('Clé de compte invalide.', 401);
    const meta = await kv.get(['accm', id]);
    if (!meta.value) {
      return erreur('Aucune donnée sur ce compte pour le moment.', 404);
    }
    const { maj, chunks } = meta.value as { maj: number; chunks: number };
    let data = '';
    for (let i = 0; i < chunks; i++) {
      const part = await kv.get(['accd', id, i]);
      data += (part.value as string | null) ?? '';
    }
    return json({ version: maj, data });
  }

  return erreur('Route inconnue.', 404);
}
