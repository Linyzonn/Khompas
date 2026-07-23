# 🖥️ Serveur Khompas (bêta) — mise en route

Le serveur permet le **partage de colloscope par code de classe** : un élève envoie
les photos une fois, chaque camarade tape le code + son numéro de groupe, et le
serveur fait l'extraction avec **sa** clé API (personne d'autre n'a besoin de clé).
Chaque groupe n'est extrait qu'**une seule fois** (cache) : une classe entière de
17 groupes coûte ~1 € au total, quel que soit le nombre d'élèves.

## Mise en route (≈ 10 minutes, une seule fois)

1. **Compte Deno Deploy** (gratuit, sans carte bancaire) :
   va sur https://deno.com/deploy → *Sign in with GitHub*.
2. **Nouveau projet** : *New Project* → choisis le dépôt `Linyzonn/Khompas` →
   branche `main` → *Entrypoint* : `server/main.ts` → *Deploy*.
   → Deno Deploy redéploiera **automatiquement à chaque push**, comme Pages.
3. **La clé API du serveur** : sur https://console.anthropic.com → crée un compte
   API, achète le minimum de crédits (5 $ ≈ une centaine d'extractions), crée une
   clé. Puis dans Deno Deploy → ton projet → *Settings* → *Environment Variables* →
   ajoute `ANTHROPIC_API_KEY` = ta clé. (Elle ne quitte jamais le serveur.)
4. **Branche l'app** : l'URL de ton projet est du type `https://khompas.deno.dev`.
   Ouvre-la dans un navigateur : tu dois voir « Serveur Khompas OK ✅ ».
   Colle cette URL dans l'app : Réglages → « Serveur Khompas (URL) ».
   → L'écran d'import affiche alors la section « Code de classe ».

## Garde-fous intégrés (modifiables en tête de `main.ts`)

| Réglage | Valeur | Rôle |
|---|---|---|
| `LIMITE_IP_JOUR` | 30 | extractions max par appareil et par jour |
| `LIMITE_GLOBALE_JOUR` | 200 | plafond total par jour (~10 € max, protège ton budget) |
| `MAX_PHOTOS` / `MAX_B64_PAR_PHOTO` | 5 / ~1,5 Mo | borne l'envoi de photos |
| `TTL` | ~13 mois | tout (photos, codes, caches) expire après l'année scolaire |

## Comment ça marche (pour plus tard)

- `POST /api/classes` → crée une classe → `{code}` (6 caractères, sans O/0/I/1).
- `PUT /api/classes/{code}/photos/{i}` → reçoit chaque photo (jpeg en base64),
  découpée en morceaux de 60 Ko dans Deno KV (limite 64 Ko/valeur).
- `GET /api/classes/{code}/groupe/{n}` → renvoie le texte JSON du modèle pour le
  groupe n (cache d'abord, extraction sinon ; `?force=1` pour ignorer le cache).
- Le prompt est **le même** que `buildPromptColloscope()` côté app
  (`lib/ai_extractor.dart`) : si tu changes l'un, change l'autre.
