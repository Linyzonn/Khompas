// RESTAURATION d'une sauvegarde KV — le pendant de .github/workflows/backup-kv.yml.
//
// Une sauvegarde jamais restaurée n'est qu'une espérance : ce script est le
// chemin de retour, et il est testé (outils/restaurer-kv_test.ts).
//
// 1. Récupérer l'artefact « kv-<numéro> » depuis GitHub (onglet Actions →
//    le run de « Sauvegarde KV » → section Artifacts), le dézipper.
// 2. Déchiffrer :
//      openssl enc -d -aes-256-cbc -pbkdf2 -pass "pass:<BACKUP_CLE>" \
//        -in dump.jsonl.enc -out dump.jsonl
// 3. Inspecter AVANT d'écrire (toujours) :
//      deno run --unstable-kv --allow-read outils/restaurer-kv.ts dump.jsonl
// 4. Restaurer pour de vrai, dans un KV LOCAL d'abord :
//      deno run --unstable-kv --allow-read --allow-write \
//        outils/restaurer-kv.ts dump.jsonl --ecrire --kv ./verif.kv
//
// Pour réécrire dans le KV de PRODUCTION, il faut un jeton Deno Deploy
// (DENO_KV_ACCESS_TOKEN) et l'URL du KV distant — à ne faire qu'en cas de
// sinistre avéré, après avoir vérifié le contenu localement.

/// Une ligne du dump : la clé KV et sa valeur (les Uint8Array ont été
/// encodés en base64 sous la forme {__u8: "..."} par l'export).
interface LigneDump {
  k: (string | number)[];
  v: unknown;
}

/// Rétablit les Uint8Array encodés en base64 par l'export.
export function decoderValeur(v: unknown): unknown {
  if (v && typeof v === 'object' && '__u8' in (v as Record<string, unknown>)) {
    const b64 = String((v as Record<string, unknown>).__u8);
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  return v;
}

/// Analyse un dump JSONL. Les lignes illisibles sont COMPTÉES, jamais
/// ignorées en silence : une sauvegarde partiellement corrompue doit se
/// voir avant qu'on écrive quoi que ce soit.
export function lireDump(texte: string): {
  lignes: LigneDump[];
  illisibles: number;
  parPrefixe: Record<string, number>;
} {
  const lignes: LigneDump[] = [];
  const parPrefixe: Record<string, number> = {};
  let illisibles = 0;
  for (const brut of texte.split('\n')) {
    if (!brut.trim()) continue;
    try {
      const l = JSON.parse(brut) as LigneDump;
      if (!Array.isArray(l.k)) throw new Error('clé absente');
      lignes.push(l);
      const p = String(l.k[0] ?? '?');
      parPrefixe[p] = (parPrefixe[p] ?? 0) + 1;
    } catch (_) {
      illisibles++;
    }
  }
  return { lignes, illisibles, parPrefixe };
}

/// Écrit les lignes dans [kv]. Retourne le nombre d'entrées restaurées.
export async function restaurer(
  kv: Deno.Kv,
  lignes: LigneDump[],
): Promise<number> {
  let n = 0;
  for (const l of lignes) {
    await kv.set(l.k as Deno.KvKey, decoderValeur(l.v));
    n++;
  }
  return n;
}

// Les noms des espaces de clés, pour un rapport lisible.
const NOMS: Record<string, string> = {
  acc: 'comptes (clé + profil)',
  accd: 'données de compte (morceaux)',
  accm: 'métadonnées de compte',
  class: 'classes',
  prog: 'programmes de colle partagés',
  photo: 'photos de colloscope',
  mime: 'types de fichier',
  res: 'résultats d’extraction',
  err: 'erreurs d’extraction',
  rlg: 'compteurs (limite globale)',
  rlx: 'compteurs (limite par appareil)',
  rlc: 'compteurs (créations de compte)',
};

if (import.meta.main) {
  const args = [...Deno.args];
  const ecrire = args.includes('--ecrire');
  const iKv = args.indexOf('--kv');
  const cheminKv = iKv >= 0 ? args[iKv + 1] : ':memory:';
  const fichier = args.find((a) => !a.startsWith('--') && a !== cheminKv);

  if (!fichier) {
    console.error(
      'usage : deno run --unstable-kv --allow-read [--allow-write] \\\n' +
        '          outils/restaurer-kv.ts <dump.jsonl> [--ecrire] [--kv <chemin>]',
    );
    Deno.exit(2);
  }

  const { lignes, illisibles, parPrefixe } = lireDump(
    await Deno.readTextFile(fichier),
  );

  console.log(`\nDump : ${fichier}`);
  console.log(`  ${lignes.length} entrée(s) lisible(s)`);
  if (illisibles > 0) {
    console.log(`  ⚠ ${illisibles} ligne(s) ILLISIBLE(S) — sauvegarde partielle`);
  }
  console.log('\nContenu par espace de clés :');
  for (const [p, n] of Object.entries(parPrefixe).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${String(n).padStart(6)}  ${p.padEnd(6)} ${NOMS[p] ?? ''}`);
  }
  const comptes = parPrefixe['acc'] ?? 0;
  console.log(`\n→ ${comptes} compte(s) récupérable(s).`);

  if (!ecrire) {
    console.log(
      '\nLecture seule. Ajoute --ecrire (et --kv <chemin>) pour restaurer.\n',
    );
    Deno.exit(0);
  }

  console.log(`\nÉcriture dans ${cheminKv}…`);
  const kv = await Deno.openKv(cheminKv);
  const n = await restaurer(kv, lignes);
  kv.close();
  console.log(`✅ ${n} entrée(s) restaurée(s).\n`);
}
