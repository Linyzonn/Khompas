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
ExtractionResult parseExtraction(String text) {
  var clean = text.replaceAll('```json', '').replaceAll('```', '').trim();
  final start = clean.indexOf('{');
  final end = clean.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw Exception("Réponse illisible de l'IA.");
  }
  clean = clean.substring(start, end + 1);
  final j = jsonDecode(clean) as Map<String, dynamic>;

  final colles = <Colle>[];
  for (final e in (j['colles'] ?? []) as List) {
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
        matiere: (m['matiere'] ?? '?').toString(),
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

  final warnings = ((j['avertissements'] ?? []) as List)
      .map((e) => e.toString())
      .toList();

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
