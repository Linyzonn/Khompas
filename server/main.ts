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
const MAX_B64_PAR_PHOTO = 4_000_000; // ~3 Mo une fois decode (photo ou PDF)
const CHUNK = 60_000; // Deno KV limite chaque valeur a 64 Ko
const LIMITE_IP_JOUR = 30; // extractions max / appareil / jour
const LIMITE_GLOBALE_JOUR = 200; // extractions max / jour (protege le budget)
const TTL = 400 * 24 * 3600 * 1000; // ~13 mois, en millisecondes
// Alphabet sans caracteres ambigus (pas de O/0, I/1/L...).
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

const kv = await Deno.openKv();

function cors(h: Headers = new Headers()): Headers {
  h.set('access-control-allow-origin', '*');
  h.set('access-control-allow-headers', 'content-type');
  h.set('access-control-allow-methods', 'GET,POST,PUT,OPTIONS');
  return h;
}

function json(data: unknown, status = 200): Response {
  const h = cors(new Headers({ 'content-type': 'application/json; charset=utf-8' }));
  return new Response(JSON.stringify(data), { status, headers: h });
}

function erreur(msg: string, status: number): Response {
  return json({ erreur: msg }, status);
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

// Retourne null si OK, sinon le message d'erreur a renvoyer (429).
async function limiterDebit(ip: string): Promise<string | null> {
  const jour = new Date().toISOString().slice(0, 10);
  const kIp = ['rl', ip, jour];
  const kG = ['rlg', jour];
  const [a, b] = await Promise.all([kv.get(kIp), kv.get(kG)]);
  const ni = ((a.value as number | null) ?? 0) + 1;
  const ng = ((b.value as number | null) ?? 0) + 1;
  if (ni > LIMITE_IP_JOUR) {
    return 'Limite quotidienne atteinte pour cet appareil — réessaie demain.';
  }
  if (ng > LIMITE_GLOBALE_JOUR) {
    return 'Le serveur a atteint sa limite du jour — réessaie demain.';
  }
  await kv.set(kIp, ni, { expireIn: 2 * 24 * 3600 * 1000 });
  await kv.set(kG, ng, { expireIn: 2 * 24 * 3600 * 1000 });
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
    let b64 = '';
    for (let c = 0; ; c++) {
      const part = await kv.get(['photo', code, i, c]);
      if (!part.value) break;
      b64 += part.value as string;
    }
    if (b64) {
      const m = await kv.get(['mime', code, i]);
      out.push({ b64, mime: (m.value as string | null) ?? 'image/jpeg' });
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
      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${modele}:generateContent?key=${cle}`,
        { method: 'POST', headers: { 'content-type': 'application/json' }, body },
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
      throw new Error(`API Gemini ${res.status} : ${texte}`);
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
    throw new Error(`API ${res.status} : ${(await res.text()).slice(0, 300)}`);
  }
  const data = await res.json() as { content?: { type: string; text?: string }[] };
  return (data.content ?? [])
    .filter((b) => b.type === 'text')
    .map((b) => b.text ?? '')
    .join('\n');
}

Deno.serve(async (req: Request, info: Deno.ServeHandlerInfo) => {
  try {
    return await gerer(req, info);
  } catch (e) {
    // Quoi qu'il arrive, repondre AVEC les en-tetes CORS : sans eux, le
    // navigateur masque tout derriere un "Failed to fetch" indebogable.
    return erreur(
      `Erreur interne : ${String(e instanceof Error ? e.message : e).slice(0, 200)}`,
      500,
    );
  }
});

async function gerer(req: Request, info: Deno.ServeHandlerInfo): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors() });
  const url = new URL(req.url);
  const p = url.pathname.replace(/\/+$/, '');
  const ip = req.headers.get('x-forwarded-for')?.split(',')[0].trim() ||
    (info.remoteAddr as Deno.NetAddr).hostname || 'inconnu';

  // Petite page de sante, pratique pour verifier que le deploiement marche.
  if (p === '' || p === '/') {
    return new Response('Serveur Khompas OK ✅', {
      headers: cors(new Headers({ 'content-type': 'text/plain; charset=utf-8' })),
    });
  }

  // Creer une classe (vide) -> {code}
  if (p === '/api/classes' && req.method === 'POST') {
    for (let essai = 0; essai < 5; essai++) {
      const code = genCode();
      const ok = await kv.atomic()
        .check({ key: ['class', code], versionstamp: null })
        .set(['class', code], { photos: 0, cree: Date.now() }, { expireIn: TTL })
        .commit();
      if (ok.ok) return json({ code });
    }
    return erreur('Impossible de générer un code, réessaie.', 500);
  }

  // Envoyer la photo n°i (corps = jpeg en base64, texte brut)
  const mUp = p.match(/^\/api\/classes\/([A-Z2-9]{6})\/photos\/([0-9])$/);
  if (mUp && req.method === 'PUT') {
    const code = mUp[1];
    const i = Number(mUp[2]);
    if (i >= MAX_PHOTOS) return erreur(`Maximum ${MAX_PHOTOS} photos.`, 400);
    const meta = await kv.get(['class', code]);
    if (!meta.value) return erreur('Code inconnu.', 404);
    const brut = await req.text();
    const b64 = brut.replace(/\s+/g, '');
    if (!b64) return erreur('Fichier vide.', 400);
    if (b64.length > MAX_B64_PAR_PHOTO) {
      return erreur('Fichier trop lourd (3 Mo max).', 413);
    }
    const mime = url.searchParams.get('mime') === 'pdf'
      ? 'application/pdf'
      : 'image/jpeg';
    await kv.set(['mime', code, i], mime, { expireIn: TTL });
    for (let c = 0; c * CHUNK < b64.length; c++) {
      await kv.set(['photo', code, i, c], b64.slice(c * CHUNK, (c + 1) * CHUNK), {
        expireIn: TTL,
      });
    }
    const m = meta.value as { photos: number; cree: number };
    if (i + 1 > m.photos) {
      await kv.set(['class', code], { ...m, photos: i + 1 }, { expireIn: TTL });
    }
    return json({ ok: true });
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
    if (photos === null) return erreur('Code inconnu.', 404);
    if (photos.length === 0) {
      return erreur("Ce code n'a pas encore de photos de colloscope.", 409);
    }
    const refus = await limiterDebit(ip);
    if (refus) return erreur(refus, 429);

    // Une extraction dure 1 a 3 minutes : trop long pour une seule requete
    // HTTP (les passerelles coupent -> "Failed to fetch" cote navigateur).
    // On lance donc le travail EN TACHE DE FOND et on repond tout de suite ;
    // l'app re-interroge toutes les 5 s jusqu'a ce que le cache soit rempli.
    if (force) {
      // Sans cette purge, les sondages suivants (sans force) renverraient
      // l'ancienne version pendant que la nouvelle se calcule.
      await kv.delete(['res', code, groupe]);
    }
    await kv.set(pendKey, 1, { expireIn: 4 * 60 * 1000 });
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
        await kv.set(['res', code, groupe], text, {
          expireIn: entiere ? TTL : 10 * 60 * 1000,
        });
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

  return erreur('Route inconnue.', 404);
}
