# Plan d'exécution — refonte visuelle (à lancer après le reset de quota)

Référence : `DESIGN.md` (charte, identité « sobre et technique »).
Contrainte : ne casser aucune fonctionnalité. `flutter analyze` + les 77
tests doivent rester verts à chaque phase.

## État des lieux (audit fait le 2026-08-20)

- **17 000 lignes de Dart, 25 écrans.** `today.dart` en pèse 1 987 à lui seul.
- **`theme.dart` ne contient qu'une fonction** (`couleurSecondaire`). Il n'y
  a donc quasiment AUCUNE fondation de design : tout le style est en dur
  dans les écrans. C'est le principal levier — et la principale dette.
- **~100 couleurs codées en dur** hors thème : 27 `Colors.grey`,
  12 `Colors.grey.shade700`, 10 `Colors.blue`, 7 `Colors.red`,
  6 `Colors.orange`, 6 `Colors.indigo`, 6 `Colors.green`, 5 `Colors.teal`,
  4 `Colors.white`… Beaucoup cassent le mode sombre.
- **7 rayons de bordure différents** (3, 4, 6, 8, 10, 12, 16) — à ramener à 2.
- Le thème est généré depuis une graine violette `#6B5CEB`, clair + sombre,
  suivant le réglage système (`main.dart`).

## Outils : ce qui est disponible, ce qui ne s'applique pas

| Outil demandé | Verdict |
|---|---|
| Plugin « Frontend Design » | **Absent du catalogue** (recherche faite). Conçu pour React/Tailwind de toute façon. |
| MCP navigateur | **Disponible** : panneau intégré + Chrome. ⚠ Les captures échouent tant que le panneau navigateur n'est pas AFFICHÉ côté interface — à vérifier avant la phase 2. |
| shadcn/ui MCP | **Non applicable** : bibliothèque React. L'équivalent Flutter est Material 3, déjà en place. |
| Figma MCP | Sans objet (pas de maquette de référence). |

## Phase 1 — Fondations (~250-400 k tokens) · sans dépendance au navigateur

1. Créer `KhompasTokens extends ThemeExtension<KhompasTokens>` dans
   `theme.dart` (§2 de la charte) : les 6 couleurs sémantiques, en variante
   claire et sombre. Exposer `context.tokens` via une extension.
2. Enrichir les deux `ThemeData` de `main.dart` : `cardTheme` (élévation 0 +
   bordure `outlineVariant`, rayon 14), `chipTheme`, `listTileTheme`,
   `textTheme` (§3), `snackBarTheme`, `dividerTheme`.
3. Extraire les helpers partagés dans `theme.dart` : `carteKhompas(...)`
   (aujourd'hui `_carte`, privé dans `today.dart`), `banniere(...)`,
   `titreSection(...)`, `metaTexte(...)`, `chiffreCle(...)`.
4. Remplacer les ~100 couleurs en dur par les tokens (fichier par fichier,
   en vérifiant `flutter analyze` à chaque lot).
5. Uniformiser les rayons (7 valeurs → 10 et 14) et les espacements sur la
   grille de 4 px.

**Effet attendu** : comme les 25 écrans partagent ces helpers, l'app entière
change d'allure sans les toucher un par un. C'est le meilleur rapport
impact/coût, et ça corrige au passage les derniers défauts de mode sombre.

## Phase 2 — Boucle visuelle par écran (~1,2-2 M tokens)

Prérequis : panneau navigateur affiché, `flutter run -d chrome` lancé
(le hot reload évite de rebuilder — le build initial prend ~4 min).
Pour chaque écran : capture (clair, sombre, mobile 390 px, desktop 1400 px)
→ critique contre la checklist → correction → nouvelle capture.

Ordre de priorité (impact décroissant) :

| # | Écran | Pourquoi | Coût estimé |
|---|---|---|---|
| 1 | `today.dart` — Aujourd'hui | Écran vu chaque jour, 2 000 lignes, cockpit 3 colonnes | ~200 k |
| 2 | `onboarding.dart` | Première impression, décide de l'adoption | ~90 k |
| 3 | `agenda.dart` + `semaine.dart` + `grille_semaine.dart` | Deuxième écran le plus consulté | ~150 k |
| 4 | `chapters.dart` | Listes longues = test de densité | ~90 k |
| 5 | `cartes.dart` (révision Anki) | Plein écran, mérite un vrai soin | ~90 k |
| 6 | `settings.dart` + les 6 sous-pages | Beaucoup de surface, peu de complexité | ~150 k |
| 7 | `verify.dart` | Vitrine de l'import de colloscope | ~80 k |
| 8 | `progression.dart`, `grades.dart`, `bilan_concours.dart` | Écrans de données/graphiques | ~130 k |
| 9 | `import*.dart`, `lectures`, `oraux`, `annales`, `erreurs`, `minuteur`, `edt`, `calendrier` | Le reste | ~250 k |

## Phase 3 — États et finitions (~150 k tokens)

- Passer les cinq états obligatoires (§7) sur chaque liste : beaucoup
  d'écrans n'ont aujourd'hui que le cas nominal et le cas vide.
- Micro-interactions : `InkWell` + transitions 150/250 ms partout où on clique.
- Accessibilité : cibles ≥ 44 px, `tooltip` sur les icônes seules, focus
  clavier visible (l'app tourne aussi sur PC).
- Passe de contraste en mode sombre, capture à l'appui.

## Checklist appliquée à chaque écran

- [ ] Hiérarchie : le point d'entrée du regard est évident.
- [ ] Espacement sur la grille 4 px, aucune valeur arbitraire.
- [ ] Rayons 10/14, élévation 0, bordure `outlineVariant`.
- [ ] Aucune couleur en dur ; contraste vérifié en clair et en sombre.
- [ ] États vide / chargement / erreur / succès / désactivé traités.
- [ ] Zones cliquables ≥ 44 px avec retour visuel.
- [ ] Testé en 390 px et en 1400 px de large.
- [ ] `flutter analyze` propre, 77 tests verts.

## Arbitrages de goût à me soumettre (ne pas trancher seul)

1. **Garder le violet `#6B5CEB` comme couleur primaire ?** Il donne
   l'identité actuelle ; un bleu d'encre ou un vert profond changerait
   nettement le ressenti.
2. **Emojis dans l'interface** : très présents (🎤 📝 ☀️ 🔁). Cohérents avec
   le ton bienveillant, mais en tension avec « sobre et technique ». Trois
   options : tout garder, les remplacer par des icônes Material dans les
   listes denses et les garder dans les messages, ou tout remplacer.
3. **Densité du cockpit** sur grand écran : 3 colonnes aujourd'hui, à
   confirmer face à une mise en page à 2 colonnes plus aérée.
