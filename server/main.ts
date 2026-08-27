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
const CHUNK = 60_000; // Deno KV limite chaque valeur a 64 Ko (base64 = ASCII)

// Deno KV limite chaque valeur a 65 536 octets SERIALISES par V8 — et pour
// une chaine, V8 bascule en UTF-16 (2 octets par caractere, meme pour
// l'ASCII) des qu'UN SEUL caractere sort du latin1 : un emoji dans les
// donnees (l'app en met partout : 🎤 📝 ☀️) doublait la taille reelle de
// chaque morceau, d'ou « Value too large » et la synchro morte en prod.
// On stocke donc des OCTETS BRUTS (Uint8Array), dont la taille sérialisée
// est previsible, et on decoupe a 48 Ko pour garder une marge confortable.
const CHUNK_OCTETS = 48_000;

function decouperOctets(s: string): Uint8Array[] {
  const octets = new TextEncoder().encode(s);
  const out: Uint8Array[] = [];
  for (let i = 0; i < octets.length; i += CHUNK_OCTETS) {
    out.push(octets.slice(i, i + CHUNK_OCTETS));
  }
  return out.length ? out : [new Uint8Array(0)];
}

// Recolle les morceaux : Uint8Array (format actuel) ou chaine (ancien
// format, comptes qui n'ont pas repousse depuis la migration).
function recollerMorceaux(morceaux: (Uint8Array | string)[]): string {
  if (morceaux.every((m) => typeof m === 'string')) {
    return (morceaux as string[]).join('');
  }
  let total = 0;
  const bruts = morceaux.map((m) =>
    typeof m === 'string' ? new TextEncoder().encode(m) : m
  );
  for (const b of bruts) total += b.length;
  const tout = new Uint8Array(total);
  let pos = 0;
  for (const b of bruts) {
    tout.set(b, pos);
    pos += b.length;
  }
  return new TextDecoder().decode(tout);
}
const LIMITE_IP_JOUR = 30; // extractions max / appareil / jour
// Extractions max / jour, toutes classes confondues. Assez haut pour le PIC
// DE LA RENTREE (des dizaines de classes le meme jour) : a 200, une seule
// personne malveillante avec quelques IP pouvait assecher le quota de tout
// le monde le jour ou l'app se joue. Le cout reel par extraction est nul.
const LIMITE_GLOBALE_JOUR = 1000;
// Donnees de compte : ~1 Mo (17 chunks). L'ancienne limite de 256 Ko etait
// atteignable EN UNE ANNEE par un utilisateur assidu (kholles + voc +
// citations + bilans) — et la synchro mourait alors en silence.
const MAX_DONNEES_COMPTE = 1_000_000;
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
    'content-type, x-khompas-cle, x-khompas-gestion, x-khompas-version-connue, x-admin-jeton',
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
// si tu changes l'un, change l'autre — un test (main_test.ts) compare les
// deux textes et echoue si l'un diverge de l'autre. Exporte pour ce test.
export function promptColloscope(groupe: number): string {
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

// Donnees completes d'un compte (chunks versionnes, repli sur l'ancien
// schema plat), ou null si le compte n'a rien envoye.
async function lireDonneesCompte(id: string): Promise<string | null> {
  const meta = await kv.get(['accm', id]);
  if (!meta.value) return null;
  const { maj, chunks } = meta.value as { maj: number; chunks: number };
  const morceaux: (Uint8Array | string)[] = [];
  for (let i = 0; i < chunks; i++) {
    const part = await kv.get(['accd', id, maj, i]);
    if (part.value != null) {
      morceaux.push(part.value as Uint8Array | string);
      continue;
    }
    const ancien = await kv.get(['accd', id, i]);
    if (ancien.value != null) {
      morceaux.push(ancien.value as Uint8Array | string);
      continue;
    }
    // Morceau manquant = copie INCOHERENTE (ecriture concurrente d'un vieux
    // client, purge croisee). ECHOUER bruyamment : renvoyer un JSON tronque
    // en silence le ferait passer pour des donnees valides — et un
    // « Récupérer » rapatrierait un compte ampute.
    throw new Error(`compte : morceau ${i + 1}/${chunks} manquant`);
  }
  return recollerMorceaux(morceaux);
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

// ---------- ICS (flux d'agenda ABONNE, par compte) ----------
// L'agenda du telephone s'abonne a une URL et se met a jour tout seul :
// kholles, DS, DM a rendre, oraux. Heures FLOTTANTES (pas de fuseau) comme
// l'export local de l'app — interpretees dans le fuseau du telephone.

function icsEsc(s: string): string {
  return s.replaceAll('\\', '\\\\').replaceAll('\n', '\\n')
    .replaceAll(';', '\\;').replaceAll(',', '\\,');
}

// Pliage RFC 5545 §3.1 : lignes <= 75 octets, continuation par un espace,
// sans couper un caractere UTF-8 ni une sequence echappee ("\\n", "\\,").
function icsPlie(s: string): string {
  const enc = new TextEncoder();
  let out = '';
  let octets = 0;
  const chars = [...s];
  for (let i = 0; i < chars.length; i++) {
    let chunk = chars[i];
    if (chunk === '\\' && i + 1 < chars.length) {
      chunk += chars[i + 1];
      i++;
    }
    const taille = enc.encode(chunk).length;
    if (octets + taille > 75) {
      out += '\r\n ';
      octets = 1;
    }
    out += chunk;
    octets += taille;
  }
  return out;
}

// "2026-09-19T16:00:00.000" -> "20260919T160000" (par decoupage de chaine :
// aucun parsing de Date, donc aucun piege de fuseau serveur).
function icsDeIso(iso: string): string | null {
  if (typeof iso !== 'string' || iso.length < 16) return null;
  return iso.slice(0, 4) + iso.slice(5, 7) + iso.slice(8, 10) + 'T' +
    iso.slice(11, 13) + iso.slice(14, 16) + '00';
}

function icsDateSeule(iso: string): string | null {
  if (typeof iso !== 'string' || iso.length < 10) return null;
  return iso.slice(0, 4) + iso.slice(5, 7) + iso.slice(8, 10);
}

// deno-lint-ignore no-explicit-any
export function construireIcs(brut: Record<string, any>): string {
  const lignes: string[] = [];
  const l = (s: string) => lignes.push(icsPlie(s));
  const two = (n: number) => String(n).padStart(2, '0');
  const now = new Date();
  const stampUtc = `${now.getUTCFullYear()}${two(now.getUTCMonth() + 1)}${
    two(now.getUTCDate())
  }T${two(now.getUTCHours())}${two(now.getUTCMinutes())}00Z`;

  l('BEGIN:VCALENDAR');
  l('VERSION:2.0');
  l('PRODID:-//Khompas//Agenda abonne//FR');
  l('CALSCALE:GREGORIAN');
  l('X-WR-CALNAME:Khompas');

  const evenement = (
    uid: string,
    resume: string,
    options: {
      debut?: string | null;
      fin?: string | null;
      jour?: string | null;
      description?: string;
      lieu?: string;
      alarmeMin?: number;
    },
  ) => {
    if (!options.debut && !options.jour) return;
    l('BEGIN:VEVENT');
    l(`UID:khompas-${uid}@khompas.app`);
    l(`DTSTAMP:${stampUtc}`);
    if (options.jour) {
      l(`DTSTART;VALUE=DATE:${options.jour}`);
    } else {
      l(`DTSTART:${options.debut}`);
      if (options.fin) l(`DTEND:${options.fin}`);
    }
    l(`SUMMARY:${icsEsc(resume)}`);
    if (options.description) l(`DESCRIPTION:${icsEsc(options.description)}`);
    if (options.lieu) l(`LOCATION:${icsEsc(options.lieu)}`);
    if (options.alarmeMin) {
      l('BEGIN:VALARM');
      l(`TRIGGER:-PT${options.alarmeMin}M`);
      l('ACTION:DISPLAY');
      l(`DESCRIPTION:${icsEsc(resume)}`);
      l('END:VALARM');
    }
    l('END:VEVENT');
  };

  // Fin d'une kholle : debut + duree, calcule sur les composants (pas de
  // fuseau implique — l'heure reste flottante).
  const finDe = (iso: string, dureeMin: number): string | null => {
    const debut = icsDeIso(iso);
    if (!debut) return null;
    const h = Number(iso.slice(11, 13));
    const min = Number(iso.slice(14, 16));
    const total = h * 60 + min + (Number(dureeMin) || 60);
    if (total >= 24 * 60) return debut; // depasse minuit : on omet DTEND
    return debut.slice(0, 9) + two(Math.floor(total / 60)) + two(total % 60) +
      '00';
  };

  for (const c of (Array.isArray(brut.colles) ? brut.colles : [])) {
    const salle = c.salle ? ` (salle ${c.salle})` : '';
    const desc: string[] = [];
    if (c.kholleur) desc.push(`Khôlleur : ${c.kholleur}`);
    if (c.programme) desc.push(`Programme : ${c.programme}`);
    evenement(String(c.id ?? ''), `Khôlle ${c.matiere ?? ''}${salle}`, {
      debut: icsDeIso(c.start),
      fin: finDe(c.start, c.dureeMin),
      description: desc.join(' — ') || undefined,
      lieu: c.salle ? `Salle ${c.salle}` : undefined,
      alarmeMin: 60,
    });
  }
  for (const d of (Array.isArray(brut.ds) ? brut.ds : [])) {
    evenement(String(d.id ?? ''), `📝 ${d.titre ?? 'DS'} ${d.matiere ?? ''}`, {
      jour: icsDateSeule(d.date),
    });
  }
  for (const d of (Array.isArray(brut.devoirs) ? brut.devoirs : [])) {
    if (d.rendu) continue;
    evenement(
      String(d.id ?? ''),
      `📥 ${d.titre ?? 'DM'} ${d.matiere ?? ''} à rendre`,
      {
        jour: icsDateSeule(d.dateRendu),
        description: d.remarque || undefined,
      },
    );
  }
  for (const o of (Array.isArray(brut.oraux) ? brut.oraux : [])) {
    if (!o.date) continue;
    const jour = icsDateSeule(o.date);
    if (o.debutMin == null) {
      evenement(String(o.id ?? ''), `🎓 Oral ${o.concours ?? ''} — ${o.epreuve ?? ''}`, {
        jour,
        lieu: o.lieu || undefined,
      });
    } else {
      const debut = jour
        ? `${jour}T${two(Math.floor(o.debutMin / 60))}${two(o.debutMin % 60)}00`
        : null;
      evenement(String(o.id ?? ''), `🎓 Oral ${o.concours ?? ''} — ${o.epreuve ?? ''}`, {
        debut,
        lieu: o.lieu || undefined,
        alarmeMin: 120,
      });
    }
  }

  l('END:VCALENDAR');
  return lignes.join('\r\n') + '\r\n';
}

// Exportee pour les tests (fetch mocke) : c'est CETTE machine a etats qui
// casse si Google retire encore un modele — elle merite son filet.
export async function extraireGemini(
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

// ============================ STATISTIQUES PRODUIT ============================
// Tableau de bord du DEVELOPPEUR : combien de comptes, quelles
// fonctionnalites servent vraiment, l'app fait-elle progresser.
//
// REGLE ABSOLUE DE CONCEPTION : ces donnees sont celles de lyceens, souvent
// mineurs. On ne renvoie donc QUE des agregats — jamais une ligne par
// compte, jamais un identifiant, jamais un contenu (nom de chapitre, texte
// d'erreur, note individuelle). Et toute ventilation dont l'effectif est
// inferieur a kCohorteMin est masquee : sur un petit parc, « 1 compte en
// MPSI qui a 8 de moyenne » designerait quelqu'un.
const kCohorteMin = 5;

function _mediane(l: number[]): number {
  if (l.length === 0) return 0;
  const t = [...l].sort((a, b) => a - b);
  const m = t.length >> 1;
  return t.length % 2 ? t[m] : Math.round((t[m - 1] + t[m]) / 2);
}

/// Masque une ventilation trop fine pour rester anonyme.
function _ventilation(map: Record<string, number>): Record<string, number> {
  const out: Record<string, number> = {};
  let autres = 0;
  for (const [k, v] of Object.entries(map)) {
    if (v >= kCohorteMin) {
      out[k] = v;
    } else {
      autres += v;
    }
  }
  if (autres > 0) out['(effectifs trop faibles)'] = autres;
  return out;
}

export async function statistiquesGlobales(): Promise<unknown> {
  const maintenant = Date.now();
  const jourMs = 86_400_000;

  // ---- Parcours des comptes (agregation au vol, rien n'est conserve) ----
  let comptes = 0, illisibles = 0, sansDonnees = 0;
  let actifs7 = 0, actifs30 = 0, actifs90 = 0;
  let octetsTotal = 0;
  const filieres: Record<string, number> = {};
  const octets: number[] = [];
  const fonction: Record<string, number> = {
    colloscope: 0, chapitres: 0, edt: 0, cartes: 0, erreurs: 0, annales: 0,
    oeuvres: 0, devoirs: 0, classe: 0, eplS: 0, modeOraux: 0, cinqDemi: 0,
    dateConcours: 0, semaineAB: 0, zoneVacances: 0, trajet: 0, sommeil: 0,
    pomodoro: 0, bilanConcours: 0,
  };
  const nb: Record<string, number[]> = {
    chapitres: [], colles: [], ds: [], seances: [], erreurs: [], cartes: [],
  };
  const minutes30: number[] = [];
  const joursActifs30: number[] = [];
  const partConsolides: number[] = [];
  const intervalles: number[] = [];
  // Progression : delta de moyenne (30 j vs 30 j precedents), par compte.
  const deltas: number[] = [];
  let hausse = 0, stable = 0, baisse = 0;
  // Assidus vs occasionnels : l'app fait-elle progresser CEUX QUI S'EN
  // SERVENT ? (la question produit la plus utile)
  const deltasAssidus: number[] = [];
  const deltasAutres: number[] = [];

  for await (const e of kv.list({ prefix: ['acc'] })) {
    if (e.key.length !== 2 || e.key[0] !== 'acc') continue;
    comptes++;
    const id = String(e.key[1]);
    const meta = await kv.get(['accm', id]);
    if (!meta.value) {
      sansDonnees++;
      continue;
    }
    const maj = (meta.value as { maj?: number }).maj ?? 0;
    const age = maintenant - maj;
    if (age < 7 * jourMs) actifs7++;
    if (age < 30 * jourMs) actifs30++;
    if (age < 90 * jourMs) actifs90++;

    let d: Record<string, unknown>;
    try {
      const brut = await lireDonneesCompte(id);
      if (!brut) {
        sansDonnees++;
        continue;
      }
      octetsTotal += brut.length;
      octets.push(brut.length);
      d = JSON.parse(brut) as Record<string, unknown>;
    } catch (_) {
      illisibles++;
      continue;
    }

    const liste = (k: string): unknown[] =>
      Array.isArray(d[k]) ? d[k] as unknown[] : [];
    const filiere = typeof d.filiere === 'string' && d.filiere ? d.filiere : '?';
    filieres[filiere] = (filieres[filiere] ?? 0) + 1;

    const chapitres = liste('chapitres') as Record<string, unknown>[];
    const colles = liste('colles') as Record<string, unknown>[];
    const ds = liste('ds') as Record<string, unknown>[];
    const seances = liste('seances') as Record<string, unknown>[];
    const cartes = liste('citations').length + liste('vocab').length;

    nb.chapitres.push(chapitres.length);
    nb.colles.push(colles.length);
    nb.ds.push(ds.length);
    nb.seances.push(seances.length);
    nb.erreurs.push(liste('erreurs').length);
    nb.cartes.push(cartes);

    // ---- Fonctionnalites REELLEMENT utilisees ----
    if (colles.length > 0) fonction.colloscope++;
    if (chapitres.length > 0) fonction.chapitres++;
    if (liste('routines').length > 0) fonction.edt++;
    if (cartes > 0) fonction.cartes++;
    if (liste('erreurs').length > 0) fonction.erreurs++;
    if (liste('annales').length > 0) fonction.annales++;
    if (liste('oeuvres').length > 0) fonction.oeuvres++;
    if (liste('devoirs').length > 0) fonction.devoirs++;
    if (liste('resultatsConcours').length > 0) fonction.bilanConcours++;
    if (typeof d.codeClasse === 'string' && d.codeClasse) fonction.classe++;
    if (d.eplS === true) fonction.eplS++;
    if (d.modeOraux === true) fonction.modeOraux++;
    if (d.cinqDemi === true) fonction.cinqDemi++;
    if (d.dateConcours) fonction.dateConcours++;
    if (d.refSemaineA) fonction.semaineAB++;
    if (typeof d.zoneVacances === 'string' && d.zoneVacances) {
      fonction.zoneVacances++;
    }
    if (typeof d.trajetMinutes === 'number' && d.trajetMinutes > 0) {
      fonction.trajet++;
    }
    if (d.heureLimiteMin != null) fonction.sommeil++;
    if (d.methodeTravail && d.methodeTravail !== 'checklist') {
      fonction.pomodoro++;
    }

    // ---- Engagement sur 30 jours ----
    let min30 = 0;
    const jours = new Set<string>();
    for (const s of seances) {
      const t = Date.parse(String(s.date ?? ''));
      if (Number.isNaN(t) || maintenant - t > 30 * jourMs) continue;
      min30 += Number(s.minutes ?? 0);
      jours.add(new Date(t).toISOString().slice(0, 10));
    }
    minutes30.push(min30);
    joursActifs30.push(jours.size);

    // ---- Memorisation ----
    if (chapitres.length > 0) {
      const commences = chapitres.filter((c) => Number(c.etape ?? 0) > 0);
      if (commences.length > 0) {
        const consolides =
          commences.filter((c) => Number(c.maitrise ?? 0) >= 3).length;
        partConsolides.push(
          Math.round((consolides / commences.length) * 100),
        );
      }
      const programmes = chapitres.filter((c) => c.prochaineRevision);
      if (programmes.length > 0) {
        intervalles.push(
          Math.round(
            programmes.reduce(
              (t, c) => t + Number(c.intervalleJours ?? 0),
              0,
            ) / programmes.length,
          ),
        );
      }
    }

    // ---- PROGRESSION : moyenne des 30 derniers jours vs les 30 d'avant ----
    const recentes: number[] = [];
    const anciennes: number[] = [];
    const classe = (dateStr: unknown, note: unknown) => {
      const n = Number(note);
      if (!Number.isFinite(n) || note == null) return;
      const t = Date.parse(String(dateStr ?? ''));
      if (Number.isNaN(t)) return;
      const age = maintenant - t;
      if (age < 30 * jourMs) recentes.push(n);
      else if (age < 60 * jourMs) anciennes.push(n);
    };
    for (const c of colles) classe(c.start, c.note);
    for (const x of ds) classe(x.date, x.note);
    if (recentes.length > 0 && anciennes.length > 0) {
      const moy = (l: number[]) => l.reduce((a, b) => a + b, 0) / l.length;
      const delta = moy(recentes) - moy(anciennes);
      // Dixiemes de point : entiers, pour ne pas trainer de flottants.
      const d10 = Math.round(delta * 10);
      deltas.push(d10);
      if (d10 >= 3) hausse++;
      else if (d10 <= -3) baisse++;
      else stable++;
      if (jours.size >= 16) deltasAssidus.push(d10);
      else deltasAutres.push(d10);
    }
  }

  // ---- Classes ----
  let classes = 0;
  let programmesPartages = 0;
  for await (const e of kv.list({ prefix: ['class'] })) {
    if (e.key.length === 2) classes++;
  }
  for await (const _ of kv.list({ prefix: ['prog'] })) programmesPartages++;

  // ---- Serveur ----
  const jourIso = new Date().toISOString().slice(0, 10);
  const requetes = await kv.get(['rlg', jourIso]);
  let clesTotal = 0;
  for await (const _ of kv.list({ prefix: [] })) clesTotal++;

  const pct = (n: number) =>
    comptes === 0 ? 0 : Math.round((n / comptes) * 100);

  return {
    genereLe: new Date(maintenant).toISOString(),
    confidentialite:
      'Agrégats uniquement : aucun identifiant, aucun contenu, aucune ligne par compte. ' +
      `Les ventilations de moins de ${kCohorteMin} comptes sont regroupées.`,
    comptes: {
      total: comptes,
      actifs7j: actifs7,
      actifs30j: actifs30,
      actifs90j: actifs90,
      retention30j: pct(actifs30),
      sansDonnees,
      illisibles,
    },
    profils: {
      filieres: _ventilation(filieres),
      cinqDemi: fonction.cinqDemi,
      partCinqDemi: pct(fonction.cinqDemi),
    },
    fonctionnalites: Object.fromEntries(
      Object.entries(fonction).map(([k, v]) => [k, { comptes: v, part: pct(v) }]),
    ),
    contenu: {
      medianes: Object.fromEntries(
        Object.entries(nb).map(([k, v]) => [k, _mediane(v)]),
      ),
      totaux: Object.fromEntries(
        Object.entries(nb).map(([k, v]) => [k, v.reduce((a, b) => a + b, 0)]),
      ),
    },
    engagement: {
      minutes30jMediane: _mediane(minutes30),
      joursActifs30jMediane: _mediane(joursActifs30),
      // Un compte « assidu » travaille plus d'un jour sur deux.
      assidus: minutes30.length === 0
        ? 0
        : joursActifs30.filter((j) => j >= 16).length,
    },
    progression: {
      comptesMesurables: deltas.length,
      enHausse: hausse,
      stables: stable,
      enBaisse: baisse,
      deltaMedianDixiemes: _mediane(deltas),
      // La question produit : ceux qui s'en servent progressent-ils PLUS ?
      deltaMedianAssidus: deltasAssidus.length >= kCohorteMin
        ? _mediane(deltasAssidus)
        : null,
      deltaMedianOccasionnels: deltasAutres.length >= kCohorteMin
        ? _mediane(deltasAutres)
        : null,
      partConsolidesMediane: _mediane(partConsolides),
      intervalleMoyenMedianJours: _mediane(intervalles),
    },
    classes: {
      total: classes,
      programmesPartages,
      comptesRattaches: fonction.classe,
    },
    serveur: {
      requetesAujourdhui: Number(requetes.value ?? 0),
      clesKv: clesTotal,
      octetsComptes: octetsTotal,
      octetsCompteMedian: _mediane(octets),
      // Le KV gratuit plafonne a 1 Gio : de quoi voir venir.
      partQuotaKvPourMille: Math.round((octetsTotal / 1_073_741_824) * 1000),
    },
  };
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

  // ---------- SAUVEGARDE ADMINISTRATEUR ----------
  // Deno KV est l'UNIQUE copie des comptes : un projet supprime par erreur
  // et tous les semestres disparaissent — exactement le drame que le client
  // combat. Ce point de sortie exporte TOUT le KV en JSONL ; il n'existe
  // que si ADMIN_JETON est defini dans l'environnement (sinon 404, la
  // fonctionnalite est invisible), et exige ce jeton en en-tete. Une action
  // GitHub planifiee l'appelle chaque nuit et archive un dump CHIFFRE.
  // Garde commune aux routes d'administration : meme 404 qu'un chemin
  // inconnu (la fonctionnalite est INVISIBLE tant que le jeton n'est pas
  // configure, et un mauvais jeton n'apprend rien), comparaison en temps
  // constant — un jeton ne se compare jamais avec ===.
  const adminRefuse = (): Response | null => {
    const attendu = Deno.env.get('ADMIN_JETON') ?? '';
    if (attendu.length < 24) return erreur('Code inconnu.', 404);
    const a = new TextEncoder().encode(req.headers.get('x-admin-jeton') ?? '');
    const b = new TextEncoder().encode(attendu);
    let diff = a.length === b.length ? 0 : 1;
    for (let i = 0; i < Math.min(a.length, b.length); i++) diff |= a[i] ^ b[i];
    return diff === 0 ? null : erreur('Code inconnu.', 404);
  };

  // Statistiques PRODUIT (tableau de bord du developpeur) — agregats seuls.
  if (p === '/api/admin/stats' && req.method === 'GET') {
    const refus = adminRefuse();
    if (refus) return refus;
    return json(await statistiquesGlobales());
  }

  if (p === '/api/admin/dump' && req.method === 'GET') {
    const refus = adminRefuse();
    if (refus) return refus;
    const lignes: string[] = [];
    for await (const e of kv.list({ prefix: [] })) {
      // Les morceaux de comptes sont des Uint8Array : base64 pour survivre
      // au JSON. La restauration fait le chemin inverse.
      const v = e.value instanceof Uint8Array
        ? { __u8: btoa(String.fromCharCode(...e.value)) }
        : e.value;
      lignes.push(JSON.stringify({ k: e.key, v }));
    }
    return new Response(lignes.join('\n'), {
      headers: cors(
        new Headers({ 'content-type': 'application/jsonl; charset=utf-8' }),
      ),
    });
  }

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

  // Auth de compte AVEC anti brute-force : l'espace des secrets (31^12)
  // rend l'attaque irrealiste, mais compter les echecs coute 3 lignes
  // (defense en profondeur). Au-dela de 50 essais rates / IP / jour : 429.
  // Retourne l'ID du compte, ou la Response d'erreur a renvoyer telle quelle.
  const authOuRefus = async (): Promise<string | Response> => {
    const id = await compteAuth();
    if (id) return id;
    const abus = await compterAbus('auth', 50);
    return abus ? erreur(abus, 429) : erreur('Clé de compte invalide.', 401);
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
    const auth = await authOuRefus();
    if (auth instanceof Response) return auth;
    const id = auth;
    // GLISSEMENT DU TTL DE LA CLE : ['acc', id] ne recevait son expireIn
    // (400 j) qu'a la creation — un compte pousse tous les soirs expirait
    // QUAND MEME a ~13 mois, et les donnees (elles, rafraichies) devenaient
    // inaccessibles a jamais (aucune route ne recree un id impose). Chaque
    // push fait maintenant glisser l'expiration.
    const acc = await kv.get(['acc', id]);
    if (acc.value != null) {
      await kv.set(['acc', id], acc.value, { expireIn: TTL });
    }
    // Rejeter les corps enormes AVANT de les materialiser en memoire.
    const annonce = Number(req.headers.get('content-length') ?? '0');
    if (annonce > MAX_DONNEES_COMPTE + 100_000) {
      return erreur('Données trop volumineuses.', 413);
    }
    const corps = await req.text();
    if (!corps.trim()) return erreur('Données vides.', 400);
    if (corps.length > MAX_DONNEES_COMPTE) {
      return erreur('Données trop volumineuses.', 413);
    }
    const metaAvant = await kv.get(['accm', id]);
    // Garde anti-ecrasement, par VERSION SERVEUR : l'app envoie la derniere
    // version qu'elle connait (x-khompas-version-connue). Si le serveur en
    // detient une autre, un autre appareil a pousse entre temps -> 409,
    // l'app affiche le bandeau « Récupérer ». Fiable meme quand l'horloge
    // du telephone derive (l'ancienne garde comparait des horodatages
    // ECRITS PAR LES CLIENTS).
    const versionConnue = Number(
      req.headers.get('x-khompas-version-connue') ?? '0',
    );
    const metaPrev = (metaAvant.value ?? {}) as {
      maj?: number;
      exportedAt?: number;
    };
    if (versionConnue && metaPrev.maj && versionConnue !== metaPrev.maj) {
      return erreur(
        'Ton autre appareil a des données plus récentes — fais « Récupérer » dans Réglages → Compte avant de pousser depuis celui-ci.',
        409,
      );
    }
    // Repli pour les VIEUX clients (pas d'en-tete de version) : l'ancienne
    // garde par horodatage client, imparfaite mais mieux que rien.
    let exportedAt = 0;
    try {
      const t = Date.parse(JSON.parse(corps).exportedAt ?? '');
      if (!Number.isNaN(t)) exportedAt = t;
    } catch (_) {
      // corps illisible en JSON : pas de garde
    }
    const prev = metaPrev;
    if (
      !versionConnue && exportedAt && prev.exportedAt &&
      exportedAt < prev.exportedAt
    ) {
      return erreur(
        'Ton autre appareil a des données plus récentes — fais « Récupérer » dans Réglages → Compte avant de pousser depuis celui-ci.',
        409,
      );
    }
    // Ecriture VERSIONNEE : les chunks partent sous ['accd', id, maj, n] et
    // la meta ne bascule vers maj qu'a la fin — un GET concurrent lit donc
    // toujours un ensemble COHERENT (avant, il pouvait melanger ancien et
    // nouveau pendant l'ecriture). Les versions precedentes (et l'ancien
    // schema non versionne) sont purgees apres coup.
    // Version STRICTEMENT croissante : deux pushes dans la MEME milliseconde
    // (vu sur le runner CI) recevaient le meme numero, et un appareil
    // perime passait alors la garde — au moins prev+1, toujours.
    const maj = Math.max(Date.now(), (metaPrev.maj ?? 0) + 1);
    // Octets bruts (voir decouperOctets) : taille previsible cote KV.
    const morceaux = decouperOctets(corps);
    for (let i = 0; i < morceaux.length; i++) {
      await kv.set(['accd', id, maj, i], morceaux[i], { expireIn: TTL });
    }
    const n = morceaux.length;
    // Bascule ATOMIQUE de la meta, conditionnee a la version lue au debut :
    // deux appareils pouvaient passer la garde 409 ensemble (lecture avant
    // la premiere ecriture de l'autre), et la purge du premier supprimait
    // les chunks du second — meta pointant vers des morceaux absents. Le
    // perdant recoit 409 ; ses chunks orphelins partent a la purge suivante.
    const commit = await kv.atomic()
      .check({ key: ['accm', id], versionstamp: metaAvant.versionstamp })
      .set(
        ['accm', id],
        { maj, chunks: n, exportedAt: exportedAt || maj },
        { expireIn: TTL },
      )
      .commit();
    if (!commit.ok) {
      return erreur(
        'Ton autre appareil a poussé au même moment — fais « Récupérer » puis réessaie.',
        409,
      );
    }
    for await (const e of kv.list({ prefix: ['accd', id] })) {
      if (e.key.length === 4 && e.key[2] === maj) continue; // version courante
      await kv.delete(e.key);
    }
    return json({ version: maj });
  }

  // Version legere (sans les donnees) : l'app la compare au demarrage a la
  // derniere version qu'ELLE connait — si un autre appareil a pousse entre
  // temps, bannière "Récupérer" AVANT la premiere modification locale.
  if (p === '/api/compte/version' && req.method === 'GET') {
    const auth = await authOuRefus();
    if (auth instanceof Response) return auth;
    const id = auth;
    const meta = await kv.get(['accm', id]);
    if (!meta.value) return json({ version: 0 });
    return json({ version: (meta.value as { maj: number }).maj });
  }

  if (p === '/api/compte/data' && req.method === 'GET') {
    const auth = await authOuRefus();
    if (auth instanceof Response) return auth;
    const id = auth;
    const meta = await kv.get(['accm', id]);
    if (!meta.value) {
      return erreur('Aucune donnée sur ce compte pour le moment.', 404);
    }
    const { maj } = meta.value as { maj: number };
    // Copie incoherente (morceau manquant) : message CLAIR plutot que le
    // 500 generique — l'utilisateur sait quoi faire (re-pousser).
    let data: string | null;
    try {
      data = await lireDonneesCompte(id);
    } catch (e) {
      console.error('lecture compte incoherente :', e);
      return erreur(
        'Copie serveur incomplète — refais « Envoyer » depuis un appareil à jour.',
        500,
      );
    }
    return json({ version: maj, data: data ?? '' });
  }

  // ---------- Flux ICS heberge (agenda ABONNE) ----------
  // Le jeton est DEDIE et vit dans l'URL (les applis calendrier ne posent
  // pas d'en-tetes) : moins privilegie que la cle — il ne donne que le
  // calendrier, jamais la possibilite de modifier ou de tout lire ailleurs.

  if (p === '/api/compte/ics-jeton' && req.method === 'POST') {
    const auth = await authOuRefus();
    if (auth instanceof Response) return auth;
    const id = auth;
    // Idempotent : le meme compte retrouve toujours le meme jeton.
    const existant = await kv.get(['accicsDe', id]);
    if (existant.value) return json({ jeton: existant.value });
    const jeton = genCode() + genCode();
    await kv.set(['accics', jeton], id, { expireIn: TTL });
    await kv.set(['accicsDe', id], jeton, { expireIn: TTL });
    return json({ jeton });
  }

  if (p === '/api/compte/ics' && req.method === 'GET') {
    // Les applis calendrier interrogent toutes les quelques heures : 500/j
    // par IP laisse de la marge tout en bloquant un scraping.
    const refus = await compterAbus('ics', 500);
    if (refus) return erreur(refus, 429);
    const jeton = (url.searchParams.get('j') ?? '').trim().toUpperCase();
    if (jeton.length !== 12) return erreur('Jeton invalide.', 404);
    const acc = await kv.get(['accics', jeton]);
    if (!acc.value) return erreur('Jeton inconnu.', 404);
    const data = await lireDonneesCompte(acc.value as string);
    if (data === null || !data.trim()) {
      return erreur('Aucune donnée sur ce compte pour le moment.', 404);
    }
    // deno-lint-ignore no-explicit-any
    let brut: Record<string, any>;
    try {
      brut = JSON.parse(data);
    } catch (_) {
      return erreur('Données du compte illisibles.', 500);
    }
    return new Response(construireIcs(brut), {
      headers: cors(new Headers({
        'content-type': 'text/calendar; charset=utf-8',
        'cache-control': 'private, max-age=3600',
      })),
    });
  }

  // Suppression du COMPTE (RGPD) : la classe avait son DELETE, le compte y
  // a droit aussi — donnees, meta et profil purges, y compris d'eventuels
  // vieux chunks au-dela de meta.chunks. Auth par la cle, comme le reste.
  if (p === '/api/compte' && req.method === 'DELETE') {
    const auth = await authOuRefus();
    if (auth instanceof Response) return auth;
    const id = auth;
    for await (const entree of kv.list({ prefix: ['accd', id] })) {
      await kv.delete(entree.key);
    }
    await kv.delete(['accm', id]);
    // Le jeton ICS meurt avec le compte (sinon le calendrier resterait
    // lisible apres la suppression RGPD).
    const jetonIcs = await kv.get(['accicsDe', id]);
    if (jetonIcs.value) await kv.delete(['accics', jetonIcs.value as string]);
    await kv.delete(['accicsDe', id]);
    await kv.delete(['acc', id]);
    return json({ ok: true });
  }

  return erreur('Route inconnue.', 404);
}
