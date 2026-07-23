import 'models.dart';
import 'store.dart';

/// Une suggestion de travail pour la soiree.
class Suggestion {
  final String matiere;
  final String titre;
  final String raison;
  final int minutes;
  Suggestion(this.matiere, this.titre, this.raison, this.minutes);
}

/// Moteur "Que faire ce soir ?" — volontairement TRANSPARENT :
/// des regles simples et explicables, pas une boite noire.
///
/// Score d'une matiere =
///   urgence (khôlle/DS proche) x priorite utilisateur x fragilite (chapitres)
List<Suggestion> suggere(AppModel m, int minutesDispo) {
  final now = DateTime.now();
  final horizon = now.add(const Duration(days: 10));

  // Prochaine echeance par matiere (khôlle ou DS) dans les 10 jours.
  final Map<String, _Echeance> echeances = {};
  for (final c in m.collesAvenir()) {
    if (c.start.isAfter(horizon)) continue;
    final e = echeances[c.matiere];
    if (e == null || c.start.isBefore(e.date)) {
      echeances[c.matiere] =
          _Echeance(c.start, 'Khôlle ${c.kholleur.isEmpty ? '' : 'avec ${c.kholleur} '}', c.programme);
    }
  }
  for (final d in m.ds) {
    if (d.date.isBefore(now) || d.date.isAfter(horizon)) continue;
    final e = echeances[d.matiere];
    if (e == null || d.date.isBefore(e.date)) {
      // Espace final : le type est concatene directement avec "demain",
      // "dans X jours"... (sinon on affichait "DSdemain").
      echeances[d.matiere] = _Echeance(d.date, '${d.titre} ', '');
    }
  }

  // Score par matiere.
  final scores = <String, double>{};
  final raisons = <String, String>{};
  final allMatieres = <String>{...m.matieres, ...echeances.keys};

  for (final mat in allMatieres) {
    double urgence = 0.6; // travail de fond par defaut
    String raison = 'Travail de fond';
    final e = echeances[mat];
    if (e != null) {
      final jours = e.date.difference(now).inHours / 24.0;
      if (jours <= 1.2) {
        urgence = 4;
        raison = '${e.type}demain (${frJour(e.date)} ${frHeure(e.date)})';
      } else if (jours <= 2.5) {
        urgence = 3;
        raison = '${e.type}dans ${jours.ceil()} jours';
      } else if (jours <= 7) {
        urgence = 2;
        raison = '${e.type}${frJour(e.date)} prochain';
      } else {
        urgence = 1.2;
        raison = '${e.type}le ${frDateCourte(e.date)}';
      }
    }

    final prio = (m.prios[mat] ?? 2).toDouble(); // 1 a 3

    // Fragilite : 1 (tout maitrise) a 2 (tout fragile).
    final chs = m.chapitres.where((c) => c.matiere == mat).toList();
    double fragilite = 1.3;
    if (chs.isNotEmpty) {
      final avg = chs.map((c) => c.maitrise).reduce((a, b) => a + b) / chs.length;
      fragilite = 1 + (4 - avg) / 4; // maitrise 4 -> 1.0 ; maitrise 0 -> 2.0
    }

    scores[mat] = urgence * prio * fragilite;
    raisons[mat] = raison;
  }

  if (scores.isEmpty) return [];

  // Repartition du temps dispo sur les 2-3 meilleures matieres.
  final classees = scores.keys.toList()
    ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
  final retenues = classees.take(minutesDispo >= 150 ? 3 : 2).toList();
  final totalScore =
      retenues.fold<double>(0, (s, mat) => s + scores[mat]!);

  final out = <Suggestion>[];
  var reste = minutesDispo;
  for (var i = 0; i < retenues.length; i++) {
    // S'il reste moins d'un quart d'heure, on arrete la (evite aussi
    // un clamp(15, 0) invalide qui plantait quand une matiere tres
    // urgente absorbait tout le temps disponible).
    if (reste < 15) break;
    final mat = retenues[i];
    var mins = i == retenues.length - 1
        ? reste
        : ((scores[mat]! / totalScore) * minutesDispo / 15).round() * 15;
    if (mins < 15) mins = 15;
    if (mins > reste) mins = reste;
    reste -= mins;

    // Contenu conseille : programme de colle s'il existe, sinon chapitres fragiles.
    var quoi = '';
    final e = echeances[mat];
    if (e != null && e.programme.trim().isNotEmpty) {
      quoi = 'Programme : ${e.programme.trim()}';
    } else {
      final fragiles = m.chapitres
          .where((c) => c.matiere == mat && c.maitrise <= 2)
          .toList()
        ..sort((a, b) => a.maitrise.compareTo(b.maitrise));
      if (fragiles.isNotEmpty) {
        quoi = 'À consolider : ${fragiles.take(2).map((c) => c.nom).join(', ')}';
      } else {
        quoi = 'Exercices + reprise du dernier cours';
      }
    }

    out.add(Suggestion(mat, quoi, raisons[mat] ?? '', mins));
  }
  return out;
}

class _Echeance {
  final DateTime date;
  final String type;
  final String programme;
  _Echeance(this.date, this.type, this.programme);
}
