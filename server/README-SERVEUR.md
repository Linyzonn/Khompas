# 🖥️ Serveur Khompas (bêta) — mise en route

Le serveur permet le **partage de colloscope par code de classe** : un élève envoie
les photos une fois, chaque camarade tape le code + son numéro de groupe, et le
serveur fait l'extraction avec **sa** clé (personne d'autre n'a besoin de clé).
Chaque groupe n'est extrait qu'**une seule fois** (cache). Avec une clé Gemini
gratuite : **0 €**. Avec une clé Claude payante : ~1 € par classe entière de
17 groupes, quel que soit le nombre d'élèves.

## Mise en route (≈ 10 minutes, une seule fois — nouvelle interface Deno Deploy)

1. **Compte Deno Deploy** (gratuit, sans carte bancaire) :
   va sur https://console.deno.com → *Sign in with GitHub*.
2. **Nouvelle app** : *New App* (ou *Create your first app*) → connecte GitHub et
   choisis le dépôt `Linyzonn/Khompas` → framework : **None / No framework**
   (pas de commande d'install ni de build) → *Entrypoint* : **`server/main.ts`**
   → *Create App*. → Redéploiement **automatique à chaque push**, comme Pages.
3. **Base de données KV** : onglet *Databases* → crée une base **Deno KV** et
   associe-la à l'app (le code l'utilise via `Deno.openKv()`, sans URL de
   connexion). Sans cette étape, l'app plante au démarrage.
4. **La clé d'extraction du serveur** — deux options, il en faut UNE :
   - **Gratuite (recommandée pour la bêta)** : https://aistudio.google.com →
     *Get API key* (compte Google, **sans carte bancaire**). Quota gratuit
     ~10 requêtes/min et ~1 000/jour sur Gemini Flash : très large pour des
     dizaines de classes. Dans Deno Deploy → ton app → *Settings* →
     *Environment Variables* → ajoute `GEMINI_API_KEY` = ta clé.
   - **Payante (qualité maximale)** : https://console.anthropic.com → ~5 $ de
     crédits minimum (≈ une centaine d'extractions) → variable
     `ANTHROPIC_API_KEY`.
   Si les deux sont présentes, Gemini (gratuit) est prioritaire. Pour changer de
   moteur plus tard : change la variable, c'est tout — et `?force=1` sur la
   route groupe permet de re-extraire un groupe déjà en cache avec le nouveau
   moteur. (Les clés ne quittent jamais le serveur.)
5. **Branche l'app** : ouvre l'URL affichée sur la page de ton app Deno Deploy.
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
