# Charte de design — Khompas

> Référence unique du style de l'app. Toute nouvelle interface s'y conforme.
> Adaptée à Flutter : les « tokens » ne sont pas du CSS mais un
> `ThemeExtension` + le `ColorScheme` de `ThemeData` (voir §2).

## 1. Identité : sobre et technique

**Khompas est un instrument de bord, pas une application de bien-être.**
Elle s'utilise le soir, fatigué, en 30 secondes : on doit voir *quoi
travailler* sans lire. D'où :

- **densité assumée** — beaucoup d'information utile par écran, peu de
  décoration ; on préfère une ligne de plus à un scroll de plus ;
- **couleur = information, jamais ornement** — chaque couleur signifie
  quelque chose (matière, urgence, état) ; un écran calme est un écran où
  rien n'est urgent ;
- **hiérarchie par le poids et l'espace**, pas par les fonds colorés ;
- **zéro culpabilisation visuelle** : pas de rouge pour une mauvaise note,
  pas de barre de progression qui juge. Le rouge est réservé aux pertes de
  données et aux actions destructrices.

Deux détails signature à conserver et systématiser :
1. la **barre d'accent latérale** teintée par matière sur les cartes ;
2. les **chiffres tabulaires** (heures, notes, durées) alignés en colonnes.

## 2. Couleurs — tokens sémantiques

Aucun `Colors.red` / `Colors.grey.shade700` en dur dans un écran. Deux
sources autorisées :

**a) `Theme.of(context).colorScheme`** pour le socle (généré depuis la
graine violette `#6B5CEB`, en clair et en sombre) :

| Rôle | Token | Usage |
|---|---|---|
| Primaire | `colorScheme.primary` | actions principales, sélection, focus |
| Surface | `colorScheme.surface` / `surfaceContainerHighest` | fonds de page et de carte |
| Contour | `colorScheme.outlineVariant` | bordures de cartes, séparateurs |
| Erreur | `colorScheme.error` | perte de données, suppression |
| Conteneur d'alerte | `colorScheme.tertiaryContainer` + `onTertiaryContainer` | encarts « à vérifier » |

**b) `KhompasTokens` (ThemeExtension, à créer dans `theme.dart`)** pour ce
que le ColorScheme ne couvre pas — chaque entrée porte un SENS :

| Token | Sens | Clair / Sombre |
|---|---|---|
| `texteSecondaire` | métadonnées, aides | reprend l'actuel `couleurSecondaire()` |
| `urgent` | échéance ≤ 24 h, retard | rouge-orangé désaturé |
| `attention` | échéance proche, conflit de synchro | ambre |
| `succes` | fait, consolidé, à jour | vert désaturé |
| `info` | rappel neutre, cartes, trajet | indigo |
| `repos` | jour off, vacances, dimanche | bleu-gris |

Les couleurs de **matières** restent générées par `subjectColor()`
(`models.dart`) : palette fixe, stable par hachage du nom. Ne pas la
dupliquer ailleurs.

**Règle de contraste** : tout texte ≥ 4.5:1 sur son fond (3:1 pour le texte
≥ 18 px ou gras), vérifié en clair ET en sombre. Un fond teinté impose son
`on*` correspondant — jamais la couleur de texte par défaut.

## 3. Typographie

Une seule famille : celle du système (pas de dépendance `google_fonts` —
elle alourdit le bundle web pour un gain faible ici). La hiérarchie vient
du **poids** et de la **taille**, pas de la fantaisie.

| Rôle | Taille | Graisse | Usage |
|---|---|---|---|
| Titre d'écran | 22 | 700 | AppBar |
| Titre de section | 17 | 600 | « Ce soir, tu as… » |
| Titre de carte | 13 | 700, `letterSpacing: .5`, MAJUSCULES | en-tête des blocs du cockpit |
| Corps | 14 | 400 | contenu principal |
| Corps dense | 13 | 400 | listes longues |
| Métadonnée | 11.5 | 400, `texteSecondaire` | « salle 12 · M. Dupont » |
| Chiffre clé | 22 | 700, `fontFeatures: [tabular figures]` | heures, moyennes |

Hauteur de ligne : `height: 1.35` sur tout texte de plus d'une ligne.
Jamais plus de 3 niveaux de taille visibles simultanément dans un bloc.

## 4. Espacement — grille de 4 px

Valeurs autorisées : **4, 8, 12, 16, 24, 32**. Rien d'autre.

- padding d'écran : `16`
- padding interne de carte : `14`
- entre deux cartes : `12`
- entre un titre et son contenu : `8`
- entre deux lignes d'une même liste : `4`
- séparation de deux sections : `24`

## 5. Formes et élévation

- **Rayons** : `10` pour les petits éléments (chips, blocs de la vue
  semaine), `14` pour les cartes et dialogues, `999` pour les pastilles.
  Les valeurs 3, 4, 6, 8, 12, 16 actuellement dispersées convergent vers
  ces deux-là.
- **Élévation : 0 partout.** La séparation se fait par une bordure
  `outlineVariant` de 1 px, pas par une ombre — plus net, et supporte le
  mode sombre sans halo grisâtre.
- Une seule exception : les éléments flottants (FAB, snackbar, dialogue)
  gardent l'élévation par défaut de Material.

## 6. Mouvement

- Durée : **150 ms** (retour tactile : hover, pression) ou **250 ms**
  (apparition/disparition d'un bloc). Jamais plus.
- Courbe : `Curves.easeOut`.
- Toute zone cliquable a un état survol/pression visible (`InkWell` avec
  `borderRadius` correspondant à la forme).
- **Pas d'animation décorative** : rien ne bouge sans changement d'état.

## 7. États obligatoires

Tout écran affichant une liste doit traiter les cinq cas :

1. **vide** — une phrase qui explique quoi faire, jamais « Aucune donnée » ;
2. **chargement** — squelette ou indicateur, jamais un écran blanc ;
3. **erreur** — cause + action de sortie ;
4. **succès** — confirmation brève (snackbar), pas de dialogue bloquant ;
5. **désactivé** — visiblement inactif, avec la raison au survol/en aide.

## 8. Accessibilité

- Cible tactile ≥ 44 × 44 px.
- Focus clavier visible sur PC (l'app tourne aussi en web).
- `Semantics` / `tooltip` sur toute icône seule.
- L'information ne passe **jamais uniquement par la couleur** : un état
  urgent porte aussi un mot ou une icône.
