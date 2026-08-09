import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Resultat d'une extraction de colloscope.
class ExtractionResult {
  final List<Colle> colles;
  final List<String> avertissements;
  ExtractionResult(this.colles, this.avertissements);
}

/// Une piece jointe du colloscope : photo (jpeg) ou document PDF.
class PieceColloscope {
  final Uint8List bytes;
  final bool pdf;
  PieceColloscope(this.bytes, {this.pdf = false});
}

/// Prompt d'extraction. Public car utilise par DEUX chemins :
/// - l'appel API direct (extraireColloscope, avec la cle de l'utilisateur) ;
/// - l'import "copier-coller" : l'utilisateur copie ce prompt dans SON appli
///   d'IA (ChatGPT, Claude, Gemini...), joint la photo, et rapporte le JSON.
String buildPromptColloscope(int groupe) {
  final now = DateTime.now();
  // Annee scolaire en cours : le colloscope n'indique pas toujours l'annee
  // dans son tableau des semaines, et un modele appele par API ne connait
  // pas la date du jour.
  final anneeDebut = now.month >= 8 ? now.year : now.year - 1;
  final anneeFin = anneeDebut + 1;
  final dateDuJour = '${now.day}/${now.month}/${now.year}';
  return '''
Tu analyses la photo d'un COLLOSCOPE de classe préparatoire française (tableau : lignes = créneaux de khôlles par matière/professeur/horaire/salle, colonnes = numéros de semaines, cellules = numéro du groupe qui passe).

Ta mission : extraire TOUTES les khôlles du GROUPE $groupe uniquement.

Règles importantes :
1. Utilise le tableau des semaines (souvent en bas à droite) pour convertir chaque numéro de semaine en DATE CONCRÈTE, en tenant compte des semaines de vacances intercalées.
2. Le jour et l'heure de chaque khôlle viennent de la ligne du créneau (ex. "jeudi 16h"). Combine-les avec la semaine pour obtenir la date exacte.
3. Lis attentivement les NOTES en bas de page (roulements de créneaux, alternances "lundi 18h ou mardi 16h" selon les semaines, groupes sans certaines colles...) et applique-les.
4. Une cellule "--" ou vide = pas de colle. Ne retiens que les cellules contenant exactement le nombre $groupe.
5. Durée par défaut : 60 minutes ; si le créneau indique une plage (ex. "16h-17h30"), calcule la durée réelle.
6. Si une règle est ambiguë ou qu'une lecture est incertaine, fais ton meilleur choix ET signale-le dans "avertissements".
7. Si le tableau des semaines n'indique pas l'année, utilise l'année scolaire en cours : septembre-décembre $anneeDebut, janvier-juillet $anneeFin (nous sommes le $dateDuJour).

Réponds UNIQUEMENT avec ce JSON, sans aucun texte autour :
{
  "colles": [
    {"matiere": "Maths", "kholleur": "M. DUPONT", "salle": "32", "date": "2024-09-19", "heure": "16:00", "duree_min": 60}
  ],
  "avertissements": ["..."]
}
''';
}

/// Transforme la reponse TEXTE de l'IA en creneaux exploitables.
/// Utilise par l'appel API ET par l'import copier-coller.
/// Tolerant : texte autour du JSON, clotures markdown, creneaux malformes
/// (ignores un par un — l'ecran de verification permet de completer).
/// Socle commun des parseurs : isole le JSON de la reponse, le decode, et en
/// cas de JSON casse (reponse tronquee en plein vol par la limite de tokens)
/// repeche les elements un par un — chaque element est un petit objet {...}
/// autonome sans accolades imbriquees ; le dernier, incomplet, ne matchera
/// pas, et l'ecran de verification permet de completer.
/// Retourne (elements de la liste [cleListe], avertissements).
(List<dynamic>, List<String>) _objetsJson(String text, String cleListe) {
  var clean = text.replaceAll('```json', '').replaceAll('```', '').trim();
  final start = clean.indexOf('{');
  final end = clean.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw Exception("Réponse illisible de l'IA.");
  }
  clean = clean.substring(start, end + 1);

  Map<String, dynamic>? j;
  try {
    j = jsonDecode(clean) as Map<String, dynamic>;
  } catch (_) {
    j = null;
  }

  final warnings = <String>[];
  List<dynamic> bruts;
  if (j != null) {
    bruts = (j[cleListe] ?? []) as List;
    warnings.addAll(
        ((j['avertissements'] ?? []) as List).map((e) => e.toString()));
  } else {
    bruts = [];
    for (final m in RegExp(r'\{[^{}]*\}').allMatches(clean)) {
      try {
        bruts.add(jsonDecode(m.group(0)!));
      } catch (_) {
        // objet incomplet ou illisible : ignore
      }
    }
    if (bruts.isEmpty) {
      throw Exception("Réponse illisible de l'IA.");
    }
    warnings.add(
        "Réponse de l'IA incomplète : les éléments de fin peuvent manquer — vérifie et relance l'extraction au besoin.");
  }
  return (bruts, warnings);
}

ExtractionResult parseExtraction(String text) {
  final (bruts, warnings) = _objetsJson(text, 'colles');

  final colles = <Colle>[];
  for (final e in bruts) {
    try {
      final m = e as Map<String, dynamic>;
      final date = (m['date'] ?? '').toString(); // YYYY-MM-DD
      // Les IA grand public ecrivent parfois "16h30" ou "16H" au lieu de
      // "16:30" : on normalise avant de decouper.
      final heure = (m['heure'] ?? '').toString().toLowerCase().replaceAll('h', ':');
      final dp = date.split('-').map(int.parse).toList();
      final hp = heure
          .split(':')
          .where((s) => s.trim().isNotEmpty)
          .map((s) => int.parse(s.trim()))
          .toList();
      // Idem pour la duree, parfois renvoyee entre guillemets ("60").
      final dureeRaw = m['duree_min'];
      final duree = dureeRaw is num
          ? dureeRaw.toInt()
          : (int.tryParse((dureeRaw ?? '').toString()) ?? 60);
      colles.add(Colle(
        matiere: normaliseMatiere((m['matiere'] ?? '?').toString()),
        kholleur: (m['kholleur'] ?? '').toString(),
        salle: (m['salle'] ?? '').toString(),
        start: DateTime(dp[0], dp[1], dp[2], hp[0], hp.length > 1 ? hp[1] : 0),
        dureeMin: duree,
      ));
    } catch (_) {
      // creneau malforme : ignore
    }
  }
  colles.sort((a, b) => a.start.compareTo(b.start));

  return ExtractionResult(colles, warnings);
}

/// Envoie la ou les photos du colloscope a Claude (vision) et recupere
/// les creneaux du groupe demande, avec les DATES CONCRETES deja calculees
/// (l'IA fait le mapping semaine -> dates a partir du tableau des semaines,
/// vacances comprises, et applique les regles ecrites en bas de page,
/// comme les roulements de creneaux).
Future<ExtractionResult> extraireColloscope({
  required String apiKey,
  required List<PieceColloscope> pieces,
  required int groupe,
}) async {
  final content = <Map<String, dynamic>>[];
  for (final p in pieces) {
    content.add({
      // Un PDF passe par un bloc "document", une photo par un bloc "image".
      'type': p.pdf ? 'document' : 'image',
      'source': {
        'type': 'base64',
        'media_type': p.pdf ? 'application/pdf' : 'image/jpeg',
        'data': base64Encode(p.bytes),
      },
    });
  }
  content.add({'type': 'text', 'text': buildPromptColloscope(groupe)});

  final res = await http
      .post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
          // Permet de tester aussi sur flutter run -d chrome.
          'anthropic-dangerous-direct-browser-access': 'true',
        },
        body: jsonEncode({
          'model': 'claude-sonnet-4-6',
          'max_tokens': 8000,
          'messages': [
            {'role': 'user', 'content': content}
          ],
        }),
      )
      .timeout(const Duration(seconds: 120));

  if (res.statusCode != 200) {
    throw Exception('Erreur API (${res.statusCode}) : ${res.body}');
  }

  final data = jsonDecode(res.body) as Map<String, dynamic>;
  final text = ((data['content'] ?? []) as List)
      .where((b) => b['type'] == 'text')
      .map((b) => b['text'] as String)
      .join('\n');

  return parseExtraction(text);
}

// ---------- Planning de DS (meme principe : prompt + parse tolerant) ----------

/// Resultat d'une extraction de planning de DS.
class DsExtraction {
  final List<Ds> ds;
  final List<String> avertissements;
  DsExtraction(this.ds, this.avertissements);
}

/// Prompt d'extraction d'un planning de DS (photo ou PDF), a copier dans
/// son appli d'IA comme pour le colloscope.
String buildPromptDs() {
  final now = DateTime.now();
  final anneeDebut = now.month >= 8 ? now.year : now.year - 1;
  final anneeFin = anneeDebut + 1;
  final dateDuJour = '${now.day}/${now.month}/${now.year}';
  return '''
Tu analyses la photo (ou le PDF) d'un PLANNING DE DS (devoirs surveillés) de classe préparatoire française.

Ta mission : extraire TOUS les DS avec leur date concrète.

Règles :
1. Un DS a une matière (Maths, Physique, Chimie, SII, Français, Anglais...), éventuellement un titre ou un numéro (DS 3, Concours blanc...), et une date.
2. Si le document donne des numéros de semaines plutôt que des dates, convertis-les en dates concrètes (vacances comprises) ; les DS ont très souvent lieu le samedi matin.
3. Si l'année n'est pas indiquée, utilise l'année scolaire en cours : septembre-décembre $anneeDebut, janvier-juillet $anneeFin (nous sommes le $dateDuJour).
4. Si le document indique un coefficient (coef 2, ×3...), mets-le dans "coeff" ; sinon omets ce champ.
5. En cas de doute sur une ligne, fais ton meilleur choix ET signale-le dans "avertissements".

Réponds UNIQUEMENT avec ce JSON, sans aucun texte autour :
{
  "ds": [
    {"matiere": "Maths", "titre": "DS 1", "date": "2026-09-19", "coeff": 2}
  ],
  "avertissements": ["..."]
}
''';
}

// ---------- Programme officiel -> chapitres (meme principe) ----------

/// Resultat d'une extraction de programme officiel.
class ChapitresExtraction {
  final List<Chapitre> chapitres;
  final List<String> avertissements;
  ChapitresExtraction(this.chapitres, this.avertissements);
}

/// Prompt d'extraction des chapitres depuis le PROGRAMME OFFICIEL d'une
/// filiere (texte copie depuis prepa.org, ou PDF officiel). L'utilisateur
/// le colle dans son appli d'IA avec le programme, comme pour le colloscope.
/// Sur prepa.org les programmes sont publies PAR MATIERE : si [matiere] est
/// renseignee, le prompt cible cette matiere et impose son nom exact (pour
/// coller aux noms de matieres deja utilises dans l'app).
String buildPromptChapitres(String filiere, {String matiere = ''}) {
  final mat = matiere.trim();
  final cible = mat.isEmpty
      ? "l'ensemble des matières couvertes par le document"
      : 'la matière « $mat » uniquement';
  final regleMatiere = mat.isEmpty
      ? '1. Matières normalisées : "Maths", "Physique", "Chimie", "SII", "Informatique", "Français", "Anglais" (selon ce que couvre le document).'
      : '1. Utilise EXACTEMENT "$mat" comme valeur du champ "matiere" pour tous les chapitres.';
  return '''
Tu analyses le PROGRAMME OFFICIEL d'une classe préparatoire française, filière $filiere (texte copié depuis prepa.org ou PDF officiel joint).

Ta mission : en extraire une liste de CHAPITRES travaillables par un élève, pour $cible.

Règles :
$regleMatiere
2. Un chapitre = un bloc révisable en quelques soirées (ex. "Espaces vectoriels", "Optique géométrique"). Regroupe les sous-points trop fins, ne découpe pas trop.
3. Garde l'ordre du programme. Si le document sépare 1er et 2e semestre (ou 1re et 2e année), garde cet ordre et signale-le dans "avertissements".
4. Vise la liste complète (typiquement 10 à 25 chapitres par matière scientifique et par année).

Réponds UNIQUEMENT avec ce JSON, sans aucun texte autour :
{
  "chapitres": [
    {"matiere": "Maths", "nom": "Espaces vectoriels"}
  ],
  "avertissements": ["..."]
}
''';
}

/// Transforme la reponse TEXTE de l'IA en liste de chapitres (etape et
/// maitrise a zero : c'est a l'eleve de les faire vivre ensuite).
ChapitresExtraction parseChapitresExtraction(String text) {
  final (bruts, warnings) = _objetsJson(text, 'chapitres');

  final chapitres = <Chapitre>[];
  for (final e in bruts) {
    try {
      final m = e as Map<String, dynamic>;
      final matiere = normaliseMatiere((m['matiere'] ?? '').toString());
      final nom = (m['nom'] ?? '').toString().trim();
      if (matiere.isEmpty || nom.isEmpty) continue;
      chapitres.add(Chapitre(matiere: matiere, nom: nom, maitrise: 0, etape: 0));
    } catch (_) {
      // ligne malformee : ignore
    }
  }
  return ChapitresExtraction(chapitres, warnings);
}

/// Transforme la reponse TEXTE de l'IA en liste de DS. Meme tolerance que
/// pour les colles (fences, texte autour, JSON tronque).
DsExtraction parseDsExtraction(String text) {
  final (bruts, warnings) = _objetsJson(text, 'ds');

  final ds = <Ds>[];
  for (final e in bruts) {
    try {
      final m = e as Map<String, dynamic>;
      final date = (m['date'] ?? '').toString();
      final dp = date.split('-').map(int.parse).toList();
      final titre = (m['titre'] ?? '').toString().trim();
      final coeffRaw = m['coeff'];
      final coeff = coeffRaw is num
          ? coeffRaw.toDouble()
          : double.tryParse((coeffRaw ?? '').toString().replaceAll(',', '.')) ??
              1.0;
      ds.add(Ds(
        matiere: normaliseMatiere((m['matiere'] ?? '?').toString()),
        titre: titre.isEmpty ? 'DS' : titre,
        date: DateTime(dp[0], dp[1], dp[2]),
        coeff: coeff <= 0 ? 1.0 : coeff,
      ));
    } catch (_) {
      // ligne malformee : ignore
    }
  }
  ds.sort((a, b) => a.date.compareTo(b.date));
  return DsExtraction(ds, warnings);
}

class VocabExtraction {
  final List<MotVocab> mots;
  final List<String> avertissements;
  VocabExtraction(this.mots, this.avertissements);
}

/// Prompt d'extraction du VOC D'ANGLAIS en masse : l'eleve le colle dans son
/// appli d'IA avec la photo/le PDF de sa feuille de voc (ou le texte copie),
/// puis colle la reponse dans l'app. Meme circuit gratuit que le programme.
String buildPromptVocab() {
  return '''
Tu analyses une liste de VOCABULAIRE D'ANGLAIS d'un élève de classe préparatoire française (photo, PDF ou texte d'une feuille de voc, souvent donnée par le professeur d'anglais pour les khôlles).

Ta mission : en extraire des paires français ↔ anglais.

Règles :
1. Une entrée = un mot ou une expression. Garde les expressions idiomatiques entières ("to make up for" en une entrée).
2. "fr" = le français, "en" = l'anglais. Si la feuille donne une remarque utile (prononciation, faux-ami, contexte), mets-la dans "remarque", sinon omets le champ.
3. Ne traduis pas toi-même ce qui n'est pas sur la feuille : extrais ce qui y figure.
4. Vise la liste complète, sans doublons.

Réponds UNIQUEMENT avec ce JSON, sans aucun texte autour :
{
  "vocab": [
    {"fr": "pallier", "en": "to make up for", "remarque": "faux-ami : ≠ palliate"}
  ],
  "avertissements": ["..."]
}
''';
}

/// Transforme la reponse TEXTE de l'IA en mots de voc. Meme tolerance que
/// les autres extractions (fences, texte autour, JSON tronque).
VocabExtraction parseVocabExtraction(String text) {
  final (bruts, warnings) = _objetsJson(text, 'vocab');
  final mots = <MotVocab>[];
  for (final e in bruts) {
    try {
      final m = e as Map<String, dynamic>;
      final fr = (m['fr'] ?? m['francais'] ?? '').toString().trim();
      final en = (m['en'] ?? m['anglais'] ?? '').toString().trim();
      if (fr.isEmpty || en.isEmpty) continue;
      mots.add(MotVocab(
        francais: fr,
        anglais: en,
        remarque: (m['remarque'] ?? '').toString().trim(),
      ));
    } catch (_) {
      // ligne malformee : ignore
    }
  }
  return VocabExtraction(mots, warnings);
}

class CitationsExtraction {
  final List<Citation> citations;
  final List<String> avertissements;
  CitationsExtraction(this.citations, this.avertissements);
}

/// Prompt d'extraction de CITATIONS de francais-philo en masse (notes de
/// cours, fiches, polycopie du prof) : chaque citation arrive avec son
/// auteur, son oeuvre, l'axe du theme et COMMENT s'en servir en dissert.
String buildPromptCitations() {
  return '''
Tu analyses des notes de FRANÇAIS-PHILO d'un élève de classe préparatoire scientifique française (fiches, polycopié, notes de cours sur le thème de l'année et ses 3 œuvres).

Ta mission : en extraire les CITATIONS utilisables en dissertation et en khôlle.

Règles :
1. "texte" = la citation exacte telle qu'elle figure dans les notes (guillemets non inclus).
2. "auteur" = l'auteur de la citation ; "oeuvre" = l'œuvre d'origine si elle est indiquée.
3. "axe" = l'axe ou sous-thème du thème de l'année auquel elle répond (court, ex. "la violence légitime").
4. "usage" = comment l'utiliser : « pour montrer que… », en une phrase — reprends la formulation des notes si elle existe.
5. N'invente RIEN : n'extrais que ce qui figure dans les notes. Si l'axe ou l'usage manquent, laisse le champ vide et signale-le dans "avertissements".

Réponds UNIQUEMENT avec ce JSON, sans aucun texte autour :
{
  "citations": [
    {"texte": "…", "auteur": "…", "oeuvre": "…", "axe": "…", "usage": "pour montrer que …"}
  ],
  "avertissements": ["..."]
}
''';
}

/// Transforme la reponse TEXTE de l'IA en citations.
CitationsExtraction parseCitationsExtraction(String text) {
  final (bruts, warnings) = _objetsJson(text, 'citations');
  final citations = <Citation>[];
  for (final e in bruts) {
    try {
      final m = e as Map<String, dynamic>;
      final texte = (m['texte'] ?? '').toString().trim();
      if (texte.isEmpty) continue;
      citations.add(Citation(
        texte: texte,
        auteur: (m['auteur'] ?? '').toString().trim(),
        oeuvre: (m['oeuvre'] ?? '').toString().trim(),
        axe: (m['axe'] ?? '').toString().trim(),
        usage: (m['usage'] ?? '').toString().trim(),
      ));
    } catch (_) {
      // ligne malformee : ignore
    }
  }
  return CitationsExtraction(citations, warnings);
}
