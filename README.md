# 🧭 Khompas — le compagnon de ta prépa

Le manque que toutes les prépas connaissent : un outil qui comprend VRAIMENT le fonctionnement d'une CPGE — colloscope, khôlles, programmes de colles, DS du samedi — et qui t'aide à décider quoi travailler chaque soir.

## ✨ Fonctionnalités (bêta 0.2)

- 📸 **Import du colloscope en une photo** : l'IA repère tes créneaux (ton groupe), convertit les numéros de semaines en vraies dates (vacances comprises) et applique les règles écrites en bas de page (roulements de créneaux…). Tu vérifies et corriges tout avant l'ajout.
- 🆓 **Import "copier-coller" sans clé API** : copie le prompt d'extraction, colle-le (avec la photo) dans ton appli ChatGPT / Claude / Gemini, puis colle sa réponse dans Khompas. Gratuit avec l'IA que tu as déjà.
- 📅 **Agenda des khôlles et DS** par semaine, avec ajout manuel (rattrapages, colles ponctuelles de français).
- 🔔 **Export vers l'agenda du téléphone** (fichier .ics) : tes khôlles dans ton calendrier natif, avec un rappel 1 h avant.
- 🌙 **"Ce soir, j'ai 2 h : je fais quoi ?"** : plan de travail transparent, basé sur tes échéances (khôlle J-2 &gt; DS samedi &gt; fond), tes priorités et tes chapitres fragiles.
- 📋 **Programmes de colles** attachés à chaque créneau.
- 📊 **Notes de khôlles et de DS**, moyennes et **tendance** par matière (3 dernières notes vs moyenne).
- 🎯 **Auto-évaluation par chapitre** (0 à 4) qui nourrit les suggestions.
- 💾 **Sauvegarde / restauration** de toutes tes données (fichier .json à partager vers Fichiers, Drive, mail…) — indispensable en sideload AltStore où l'app peut expirer, et c'est aussi le pont téléphone ↔ PC.
- 💻 **Version web (PC/Mac)** déployée automatiquement sur GitHub Pages — mêmes fonctionnalités, données dans le navigateur.
- 🔒 Tout est stocké **en local** sur l'appareil (téléphone ou navigateur).

## 🛠️ Mise en route — RIEN à installer sur ton PC

Ce dossier **est** le projet complet : les workflows GitHub génèrent eux-mêmes les squelettes iOS / Android / web (`flutter create .`) et injectent les permissions iOS. Pas besoin de Flutter en local, pas d'Info.plist à éditer.

1. **Publie ce dossier sur GitHub** avec GitHub Desktop : *Add local repository* → commit → *Publish repository*, en **public** (nécessaire pour GitHub Pages gratuit). Le nom du dépôt est libre : le workflow web s'y adapte automatiquement.
2. **Active la version web** (une seule fois) : sur github.com → ton repo → *Settings* → *Pages* → *Source* : **GitHub Actions**.
3. C'est tout. Ensuite :

### 💻 Sur ton ordi (version web)
Chaque push sur `main` redéploie automatiquement l'app sur **`https://<ton-pseudo>.github.io/khompas/`**. Les données vivent dans le navigateur ; pour passer tes données du téléphone au PC (ou l'inverse) : Réglages → **Sauvegarder** sur l'un, **Restaurer** sur l'autre.

### 📱 Sur ton iPhone (comme pour Lume)
**Actions → Build IPA (iOS, non signé)** → récupère `Khompas-unsigned.ipa` → installe avec **AltStore** (AltServer → Sideload .ipa).

### 🤖 Sur Android
**Actions → Build APK (Android)** → télécharge l'APK → installe-le directement (autorise les sources inconnues).

### 🧪 (Facultatif) Tester en local
Si tu installes Flutter un jour : `flutter create . --platforms=web && flutter pub get && flutter run -d chrome`.

## 🔑 L'extraction IA (bêta)

Deux chemins :

1. **Automatique** : l'app appelle l'API Claude (`claude-sonnet-4-6`, vision) avec **ta clé API** (Réglages → console.anthropic.com → API keys ; quelques centimes par import).
2. **Copier-coller (gratuit)** : l'app copie le prompt d'extraction dans le presse-papiers ; tu le colles avec la photo dans **ton** appli d'IA (ChatGPT, Claude, Gemini…), puis tu colles la réponse JSON dans Khompas. Même écran de vérification à l'arrivée.

Étape suivante prévue : un petit serveur Khompas qui porte la clé, avec code de partage par classe (un élève importe, les 50 autres choisissent juste leur numéro de groupe).

## 🗺️ Prochaines étapes

- Compte + partage du colloscope par classe (le moteur viral)
- Import des programmes de colles par photo (même pipeline IA)
- Connexion Cahier de prépa / e-colle
- Notifications internes (en plus de l'export calendrier)
- Statistiques de progression, mode "3 semaines de révisions concours"

## ⚠️ Permissions iOS : gérées automatiquement

Le workflow iOS injecte `NSCameraUsageDescription` et `NSPhotoLibraryUsageDescription` dans `Info.plist` à chaque build (sinon l'app **crashe** à l'ouverture de l'appareil photo). Tu n'as rien à faire. (Si un jour tu compiles l'iOS en local avec ton propre `flutter create`, pense à ajouter ces deux clés à la main.)

Sur Android et sur le web, rien à faire.
