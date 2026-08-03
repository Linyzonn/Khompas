import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Import des VACANCES SCOLAIRES OFFICIELLES depuis l'open data de
/// l'Éducation nationale (dataset `fr-en-calendrier-scolaire`) : pas de
/// dates codées en dur qui périment chaque année, et la zone (A/B/C) de
/// l'utilisateur est respectée.
///
/// Le parsing est une fonction PURE ([plagesDepuisJson]) : testable sans
/// réseau sur un JSON d'exemple.
const kZonesVacances = ['A', 'B', 'C'];

/// Année scolaire courante au format « 2026-2027 » (bascule en août).
String anneeScolaireCourante(DateTime now) {
  final debut = now.month >= 8 ? now.year : now.year - 1;
  return '$debut-${debut + 1}';
}

/// Récupère les périodes de vacances de [zone] pour [anneeScolaire]
/// (« 2026-2027 »). Lève une exception avec un message propre en cas de
/// problème réseau ou de réponse inattendue.
Future<List<PlageSansCours>> vacancesOfficielles(
    String zone, String anneeScolaire) async {
  final uri = Uri.https(
    'data.education.gouv.fr',
    '/api/records/1.0/search/',
    {
      'dataset': 'fr-en-calendrier-scolaire',
      'rows': '30',
      'refine.population': 'Élèves',
      'refine.zones': 'Zone $zone',
      'refine.annee_scolaire': anneeScolaire,
    },
  );
  final http.Response r;
  try {
    r = await http.get(uri).timeout(const Duration(seconds: 20));
  } catch (_) {
    throw Exception(
        'impossible de joindre data.education.gouv.fr — vérifie ta connexion.');
  }
  if (r.statusCode != 200) {
    throw Exception('le service des calendriers a répondu HTTP ${r.statusCode}.');
  }
  return plagesDepuisJson(utf8.decode(r.bodyBytes));
}

/// Transforme la réponse JSON de l'API en plages Khompas :
///  - « Vacances d'Été » -> type 'ete', fin bornée au 31 août (le dataset
///    fait parfois courir l'été jusqu'à la rentrée suivante) ;
///  - le reste -> type 'vacances' ;
///  - les enseignements hors vacances (« Début des Vacances… » absents,
///    pré-rentrée…) sont ignorés s'ils n'ont pas les deux dates.
List<PlageSansCours> plagesDepuisJson(String corps) {
  final decoded = jsonDecode(corps) as Map<String, dynamic>;
  final records = (decoded['records'] ?? []) as List;
  final out = <PlageSansCours>[];
  for (final rec in records) {
    final fields =
        ((rec as Map<String, dynamic>)['fields'] ?? {}) as Map<String, dynamic>;
    final description = (fields['description'] ?? '').toString().trim();
    final debutBrut = fields['start_date']?.toString();
    final finBrut = fields['end_date']?.toString();
    if (description.isEmpty || debutBrut == null || finBrut == null) continue;
    final debut = DateTime.tryParse(debutBrut);
    var fin = DateTime.tryParse(finBrut);
    if (debut == null || fin == null) continue;
    final ete = description.toLowerCase().contains('été') ||
        description.toLowerCase().contains('ete');
    if (ete) {
      final borne = DateTime(debut.year, 8, 31);
      if (fin.isAfter(borne)) fin = borne;
    }
    out.add(PlageSansCours(
      titre: description,
      debut: DateTime(debut.year, debut.month, debut.day),
      fin: DateTime(fin.year, fin.month, fin.day),
      type: ete ? 'ete' : 'vacances',
    ));
  }
  out.sort((a, b) => a.debut.compareTo(b.debut));
  return out;
}

/// true si [p] fait double emploi avec une plage existante : chevauchement
/// de dates (l'utilisateur a pu saisir « Toussaint » a la main avant
/// d'importer — on ne l'écrase pas, on saute).
bool plageEnDouble(PlageSansCours p, List<PlageSansCours> existantes) {
  for (final e in existantes) {
    final disjointes =
        p.fin.isBefore(e.debut) || p.debut.isAfter(e.fin);
    if (!disjointes) return true;
  }
  return false;
}
