import 'models.dart';
import 'store.dart';

/// Une suggestion de travail pour la soiree.
class Suggestion {
  final String matiere;
  final String titre;
  final String raison;
  final int minutes;
  // Chapitre vise (mode revisions) : permet de le marquer "revu" d'un tap.
  final String? chapitreId;
  Suggestion(this.matiere, this.titre, this.raison, this.minutes,
      {this.chapitreId});
}

/// Moteur "Que faire ce soir ?" — volontairement TRANSPARENT :
/// des regles simples et explicables, pas une boite noire.
///
/// Deux regimes :
/// - normal : score = urgence (kholle/DS/DM proche) x priorite x fragilite,
///   avec bonus cours du jour / du lendemain (Ma semaine type) ;
/// - REVISIONS CONCOURS (date des ecrits fixee) : on fait tourner les
///   chapitres — jamais revus d'abord, puis les plus anciens.
List<Suggestion> suggere(AppModel m, int minutesDispo) {
  if (m.dateConcours != null &&
      DateTime.now().isBefore(m.dateConcours!) &&
      m.chapitres.any((c) => c.etape > 0)) {
    return _suggereRevisions(m, minutesDispo);
  }
  return _suggereNormal(m, minutesDispo);
}

List<Suggestion> _suggereNormal(AppModel m, int minutesDispo) {
  final now = DateTime.now();
  final horizon = now.add(const Duration(days: 10));

  // Prochaine echeance par matiere (kholle, DS ou devoir a rendre).
  final Map<String, _Echeance> echeances = {};
  for (final c in m.collesAvenir()) {
    if (c.start.isAfter(horizon)) continue;
    final e = echeances[c.matiere];
    if (e == null || c.start.isBefore(e.date)) {
      echeances[c.matiere] = _Echeance(c.start,
          'Khôlle ${c.kholleur.isEmpty ? '' : 'avec ${c.kholleur} '}', c.programme);
    }
  }
  for (final d in m.ds) {
    if (d.date.isBefore(now) || d.date.isAfter(horizon)) continue;
    final e = echeances[d.matiere];
    if (e == null || d.date.isBefore(e.date)) {
      // Espace final : le type est concatene directement avec "demain"...
      echeances[d.matiere] = _Echeance(d.date, '${d.titre} ', '');
    }
  }
  for (final d in m.devoirsARendre()) {
    // Un DM en retard reste affiche (jusqu'a 5 jours) : il faut le rendre !
    if (d.dateRendu.isBefore(now.subtract(const Duration(days: 5)))) continue;
    if (d.dateRendu.isAfter(horizon)) continue;
    final e = echeances[d.matiere];
    if (e == null || d.dateRendu.isBefore(e.date)) {
      echeances[d.matiere] = _Echeance(d.dateRendu, '${d.titre} à rendre ', '');
    }
  }

  // Matieres ayant cours aujourd'hui / demain — via l'emploi du temps REEL
  // (roulement A/B et vacances compris) : regle d'or de la prepa — revoir
  // le cours du jour le soir meme, et preparer celui du lendemain.
  final coursAujourdhui = <String>{};
  final coursDemain = <String>{};
  final demain = now.add(const Duration(days: 1));
  for (final r in m.routinesLe(now)) {
    if (r.matiere.trim().isNotEmpty) {
      coursAujourdhui.add(r.matiere.trim().toLowerCase());
    }
  }
  for (final r in m.routinesLe(demain)) {
    if (r.matiere.trim().isNotEmpty) {
      coursDemain.add(r.matiere.trim().toLowerCase());
    }
  }
  // Les evenements ponctuels a matiere (TP info, oral blanc...) comptent
  // comme des cours du jour / du lendemain.
  for (final e in m.evenementsLe(now)) {
    if (e.matiere.trim().isNotEmpty) {
      coursAujourdhui.add(e.matiere.trim().toLowerCase());
    }
  }
  for (final e in m.evenementsLe(demain)) {
    if (e.matiere.trim().isNotEmpty) {
      coursDemain.add(e.matiere.trim().toLowerCase());
    }
  }

  // Score par matiere.
  final scores = <String, double>{};
  final raisons = <String, String>{};
  final allMatieres = <String>{
    ...m.matieres,
    ...echeances.keys,
    ...m.routines
        .where((r) => r.matiere.trim().isNotEmpty)
        .map((r) => r.matiere.trim()),
  };

  for (final mat in allMatieres) {
    double urgence = 0.6; // travail de fond par defaut
    String raison = 'Travail de fond';
    final e = echeances[mat];
    if (e != null) {
      final jours = e.date.difference(now).inHours / 24.0;
      // Les DS et devoirs sont dates a minuit : pas d'heure a afficher.
      final heure = (e.date.hour == 0 && e.date.minute == 0)
          ? ''
          : ' ${frHeure(e.date)}';
      if (jours < 0) {
        urgence = 4.5;
        raison = '${e.type}EN RETARD — rends-le vite';
      } else if (jours <= 1.2) {
        urgence = 4;
        raison = '${e.type}demain (${frJour(e.date)}$heure)';
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

    // Fragilite : 1 (tout maitrise) a 2 (tout fragile) — calculee sur les
    // chapitres COMMENCES (etape > 0), pas sur le programme entier importe.
    final chs =
        m.chapitres.where((c) => c.matiere == mat && c.etape > 0).toList();
    double fragilite = 1.3;
    if (chs.isNotEmpty) {
      final avg = chs.map((c) => c.maitrise).reduce((a, b) => a + b) / chs.length;
      fragilite = 1 + (4 - avg) / 4; // maitrise 4 -> 1.0 ; maitrise 0 -> 2.0
    }

    // Bonus "cours du jour / du lendemain" (Ma semaine type).
    var bonusCours = 1.0;
    if (coursAujourdhui.contains(mat.toLowerCase())) {
      bonusCours = 1.5;
      if (e == null) raison = "Cours d'aujourd'hui — à revoir ce soir";
    } else if (coursDemain.contains(mat.toLowerCase())) {
      bonusCours = 1.2;
      if (e == null) raison = 'Cours demain — prends de l\'avance';
    }

    scores[mat] = urgence * prio * fragilite * bonusCours;
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

    // Contenu conseille, dans l'ordre : programme de colle s'il existe,
    // sinon chapitres "vus en cours mais pas revus", sinon chapitres fragiles.
    var quoi = '';
    final e = echeances[mat];
    final aRevoir =
        m.chapitres.where((c) => c.matiere == mat && c.etape == 1).toList();
    if (e != null && e.programme.trim().isNotEmpty) {
      quoi = 'Programme : ${e.programme.trim()}';
    } else if (aRevoir.isNotEmpty) {
      quoi =
          'À revoir (vu en cours) : ${aRevoir.take(2).map((c) => c.nom).join(', ')}';
    } else {
      final fragiles = m.chapitres
          .where((c) => c.matiere == mat && c.maitrise <= 2 && c.etape > 0)
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

/// MODE REVISIONS CONCOURS : couvrir tout le programme avant les ecrits.
/// Rotation des chapitres commences : jamais revus d'abord (les plus
/// fragiles en premier), puis les revus les plus anciens.
List<Suggestion> _suggereRevisions(AppModel m, int minutesDispo) {
  final now = DateTime.now();
  final jours = m.dateConcours!.difference(now).inDays + 1;
  final out = <Suggestion>[];
  var reste = minutesDispo;

  // Un DS / concours blanc dans les 2 jours garde la priorite absolue.
  final aujourdHui = DateTime(now.year, now.month, now.day);
  Ds? prochainDs;
  for (final d in m.ds) {
    final dj = DateTime(d.date.year, d.date.month, d.date.day)
        .difference(aujourdHui)
        .inDays;
    if (dj < 0 || dj > 2) continue;
    if (prochainDs == null || d.date.isBefore(prochainDs.date)) prochainDs = d;
  }
  if (prochainDs != null && reste >= 30) {
    final mins = reste >= 90 ? 60 : 30;
    out.add(Suggestion(
      prochainDs.matiere,
      'Prépa ${prochainDs.titre} : annales et points faibles',
      '${prochainDs.titre} ${frJour(prochainDs.date)} — priorité',
      mins,
    ));
    reste -= mins;
  }

  final aReviser = m.chapitres.where((c) => c.etape > 0).toList()
    ..sort((a, b) {
      if (a.dernierRevu == null && b.dernierRevu != null) return -1;
      if (a.dernierRevu != null && b.dernierRevu == null) return 1;
      if (a.dernierRevu == null && b.dernierRevu == null) {
        return a.maitrise.compareTo(b.maitrise); // plus fragile d'abord
      }
      final cmp = a.dernierRevu!.compareTo(b.dernierRevu!); // plus ancien d'abord
      return cmp != 0 ? cmp : a.maitrise.compareTo(b.maitrise);
    });

  // Blocs de ~1 h par chapitre.
  var i = 0;
  while (reste >= 30 && i < aReviser.length) {
    final c = aReviser[i];
    final mins = reste >= 75 ? 60 : (reste ~/ 15) * 15;
    final quandRevu = c.dernierRevu == null
        ? 'jamais revu'
        : 'revu il y a ${now.difference(c.dernierRevu!).inDays} j';
    out.add(Suggestion(
      c.matiere,
      'Réviser : ${c.nom}',
      'J-$jours · $quandRevu',
      mins,
      chapitreId: c.id,
    ));
    reste -= mins;
    i++;
  }
  return out;
}

class _Echeance {
  final DateTime date;
  final String type;
  final String programme;
  _Echeance(this.date, this.type, this.programme);
}
