import 'dart:math';

import 'methodes.dart';
import 'models.dart';
import 'store.dart';

/// Une suggestion de travail pour la soiree.
class Suggestion {
  final String matiere;
  final String titre;
  final String raison;
  final int minutes;
  // Chapitre vise : permet de le marquer "revu" d'un tap.
  final String? chapitreId;
  // Rappel espace : le ✓ declenche l'auto-evaluation en 1 tap.
  final bool rappel;
  // Consigne d'action testable (rappel actif) affichee sous la suggestion.
  final String consigne;
  Suggestion(this.matiere, this.titre, this.raison, this.minutes,
      {this.chapitreId, this.rappel = false, this.consigne = ''});
}

/// Moteur "Que faire ce soir ?" — volontairement TRANSPARENT :
/// des regles simples et explicables, pas une boite noire.
///
/// Ordre du plan (mode normal) :
/// 1. Rappels du jour (repetition espacee : chapitres dont la revision est due)
/// 2. "Lis le DM distribue aujourd'hui" le cas echeant
/// 3. Scoring par matiere : urgence (kholle/DS/DM) x priorite x fragilite
///    (moyenne + minimum) x bonus cours du jour x jachere (matieres delaissees)
/// En mode REVISIONS CONCOURS : rotation des chapitres, revisions dues d'abord.
List<Suggestion> suggere(AppModel m, int minutesDispo) {
  // Mode ORAUX (post-ecrits) : prioritaire sur tout le reste.
  if (m.modeOraux && m.oraux.isNotEmpty) {
    return _suggereOraux(m, minutesDispo);
  }
  if (m.dateConcours != null &&
      DateTime.now().isBefore(m.dateConcours!) &&
      m.chapitres.any((c) => c.etape > 0)) {
    return _suggereRevisions(m, minutesDispo);
  }
  return _suggereNormal(m, minutesDispo);
}

/// Chapitres dont la revision espacee est due (aujourd'hui ou en retard).
List<Chapitre> rappelsDus(AppModel m) {
  final now = DateTime.now();
  final finJour = DateTime(now.year, now.month, now.day, 23, 59);
  return m.chapitres
      .where((c) =>
          c.prochaineRevision != null && c.prochaineRevision!.isBefore(finJour))
      .toList()
    ..sort((a, b) => a.prochaineRevision!.compareTo(b.prochaineRevision!));
}

List<Suggestion> _suggereNormal(AppModel m, int minutesDispo) {
  final now = DateTime.now();
  final horizon = now.add(const Duration(days: 10));
  final out = <Suggestion>[];
  var budget = minutesDispo;

  // ---- 1. Rappels du jour (repetition espacee) ----
  // Blocs courts (15 min), au plus 3, jamais plus de la moitie de la soiree.
  final dus = rappelsDus(m);
  for (final c in dus.take(3)) {
    if (budget < 30 || (minutesDispo - budget) + 15 > minutesDispo ~/ 2) break;
    final retard =
        DateTime(now.year, now.month, now.day).difference(c.prochaineRevision!).inDays;
    out.add(Suggestion(
      c.matiere,
      'Rappel 🔁 ${c.nom}',
      retard > 0 ? 'Révision espacée — en attente depuis $retard j' : 'Révision espacée — c\'est le bon jour',
      15,
      chapitreId: c.id,
      rappel: true,
      consigne: consigneDe(c.matiere, 'rappel'),
    ));
    budget -= 15;
  }

  // ---- 2. DM distribue aujourd'hui : le lire ce soir ----
  for (final d in m.devoirsARendre()) {
    if (d.dateDonne.year == now.year &&
        d.dateDonne.month == now.month &&
        d.dateDonne.day == now.day &&
        budget >= 30) {
      out.add(Suggestion(
        d.matiere,
        '📖 Lis le ${d.titre} distribué aujourd\'hui',
        'Le lire le soir même désamorce la procrastination',
        15,
        consigne:
            'Lis l\'énoncé en entier et repère les questions abordables — ton cerveau y travaillera en tâche de fond.',
      ));
      budget -= 15;
      break; // un seul par soir
    }
  }

  // ---- 2 bis. Cahier d'erreurs : kholle/DS dans ≤ 2 jours dans une
  // matiere ou des erreurs ne sont pas encore refaites -> les revoir est
  // le meilleur rendement de la soiree. Un seul bloc par soir.
  if (budget >= 30) {
    final proches = <String>{};
    final limite = now.add(const Duration(days: 2, hours: 12));
    for (final c in m.collesAvenir()) {
      if (c.start.isBefore(limite)) proches.add(c.matiere);
    }
    for (final d in m.ds) {
      if (!d.date.isBefore(now.subtract(const Duration(days: 1))) &&
          d.date.isBefore(limite)) {
        proches.add(d.matiere);
      }
    }
    for (final mat in proches) {
      final aRefaire =
          m.erreurs.where((e) => e.matiere == mat && !e.refaite).length;
      if (aRefaire == 0) continue;
      out.add(Suggestion(
        mat,
        '📕 Refais tes erreurs de $mat ($aRefaire à revoir)',
        'Épreuve imminente — tes erreurs passées sont tes points faibles connus',
        15,
        consigne:
            'Ouvre ton cahier d\'erreurs et REFAIS une erreur sans regarder la correction. Si tu la maîtrises, coche « refaite ».',
      ));
      budget -= 15;
      break; // un seul bloc erreurs par soir
    }
  }

  // ---- 3. Echeances par matiere (kholle, DS, devoir a rendre) ----
  final Map<String, _Echeance> echeances = {};
  for (final c in m.collesAvenir()) {
    if (c.start.isAfter(horizon)) continue;
    final e = echeances[c.matiere];
    if (e == null || c.start.isBefore(e.date)) {
      echeances[c.matiere] = _Echeance(
          c.start,
          'Khôlle ${c.kholleur.isEmpty ? '' : 'avec ${c.kholleur} '}',
          c.programme,
          'kholle');
    }
  }
  for (final d in m.ds) {
    if (d.date.isBefore(now) || d.date.isAfter(horizon)) continue;
    final e = echeances[d.matiere];
    if (e == null || d.date.isBefore(e.date)) {
      echeances[d.matiere] = _Echeance(d.date, '${d.titre} ', '', 'ds');
    }
  }
  for (final d in m.devoirsARendre()) {
    if (d.dateRendu.isBefore(now.subtract(const Duration(days: 5)))) continue;
    if (d.dateRendu.isAfter(horizon)) continue;
    final e = echeances[d.matiere];
    if (e == null || d.dateRendu.isBefore(e.date)) {
      echeances[d.matiere] =
          _Echeance(d.dateRendu, '${d.titre} à rendre ', '', 'dm');
    }
  }

  // ---- Cours du jour / du lendemain (EDT reel + evenements ponctuels) ----
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

  // ---- Jachere : derniere seance par matiere ----
  final derniereSeance = <String, DateTime>{};
  for (final s in m.seances) {
    final cle = s.matiere.toLowerCase();
    final prec = derniereSeance[cle];
    if (prec == null || s.date.isAfter(prec)) derniereSeance[cle] = s.date;
  }

  // ---- Scoring ----
  final scores = <String, double>{};
  final raisons = <String, String>{};
  final allMatieres = <String>{...m.matieres, ...echeances.keys};

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

    // Fragilite : moyenne (60 %) + MINIMUM (40 %) des chapitres commences —
    // la moyenne seule masquait un chapitre a zero au milieu de bons.
    final chs =
        m.chapitres.where((c) => c.matiere == mat && c.etape > 0).toList();
    double fragilite = 1.3;
    if (chs.isNotEmpty) {
      final avg = chs.map((c) => c.maitrise).reduce((a, b) => a + b) / chs.length;
      final mini = chs.map((c) => c.maitrise).reduce(min);
      fragilite = 1 + ((4 - avg) / 4) * 0.6 + ((4 - mini) / 4) * 0.4;
    }

    // Bonus "cours du jour / du lendemain".
    var bonusCours = 1.0;
    if (coursAujourdhui.contains(mat.toLowerCase())) {
      bonusCours = 1.5;
      if (e == null) raison = "Cours d'aujourd'hui — à revoir ce soir";
    } else if (coursDemain.contains(mat.toLowerCase())) {
      bonusCours = 1.2;
      if (e == null) raison = 'Cours demain — prends de l\'avance';
    }

    // Jachere : une matiere delaissee remonte progressivement (contre la
    // famine du francais et des langues, qui n'ont presque pas d'echeances).
    final dSeance = derniereSeance[mat.toLowerCase()];
    final joursSans =
        dSeance == null ? 999 : now.difference(dSeance).inDays;
    final jachere =
        1.0 + ((joursSans - 3) / 7).clamp(0.0, 1.0); // 1.0 -> 2.0 en ~10 j
    if (e == null &&
        bonusCours == 1.0 &&
        jachere >= 1.6 &&
        joursSans < 999) {
      raison = 'Pas travaillée depuis $joursSans j — entretien';
    }

    scores[mat] = urgence * prio * fragilite * bonusCours * jachere;
    raisons[mat] = raison;
  }

  if (scores.isEmpty || budget < 15) return out;

  // ---- Repartition du budget restant sur les 2-3 meilleures matieres ----
  final classees = scores.keys.toList()
    ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
  final retenues = classees.take(budget >= 150 ? 3 : 2).toList();
  final totalScore = retenues.fold<double>(0, (s, mat) => s + scores[mat]!);

  var reste = budget;
  for (var i = 0; i < retenues.length; i++) {
    if (reste < 15) break;
    final mat = retenues[i];
    var mins = i == retenues.length - 1
        ? reste
        : ((scores[mat]! / totalScore) * budget / 15).round() * 15;
    if (mins < 15) mins = 15;
    if (mins > reste) mins = reste;
    reste -= mins;

    // Contenu conseille + consigne d'action (rappel actif).
    var quoi = '';
    var typeConsigne = 'fond';
    final e = echeances[mat];
    final aRevoir =
        m.chapitres.where((c) => c.matiere == mat && c.etape == 1).toList();
    if (e != null && e.programme.trim().isNotEmpty) {
      quoi = 'Programme : ${e.programme.trim()}';
      typeConsigne = e.genre;
    } else if (aRevoir.isNotEmpty) {
      quoi =
          'À revoir (vu en cours) : ${aRevoir.take(2).map((c) => c.nom).join(', ')}';
      typeConsigne = 'rappel';
    } else {
      final fragiles = m.chapitres
          .where((c) => c.matiere == mat && c.maitrise <= 2 && c.etape > 0)
          .toList()
        ..sort((a, b) => a.maitrise.compareTo(b.maitrise));
      if (fragiles.isNotEmpty) {
        quoi =
            'À consolider : ${fragiles.take(2).map((c) => c.maitrise == 0 ? '⚠ ${c.nom} (jamais consolidé)' : c.nom).join(', ')}';
        typeConsigne = 'consolider';
      } else {
        quoi = 'Exercices + reprise du dernier cours';
        typeConsigne = e == null ? 'fond' : e.genre;
      }
    }
    if (e != null && typeConsigne == 'fond') typeConsigne = e.genre;

    out.add(Suggestion(mat, quoi, raisons[mat] ?? '', mins,
        consigne: typeConsigne == 'dm' ? '' : consigneDe(mat, typeConsigne)));
  }
  return out;
}

/// MODE REVISIONS CONCOURS : couvrir tout le programme avant les ecrits.
/// Revisions espacees dues d'abord, puis jamais revus (fragiles en tete),
/// puis les plus anciens — en alternant les matieres (interleaving).
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
      consigne: consigneDe(prochainDs.matiere, 'ds'),
    ));
    reste -= mins;
  }

  // Annale du soir : a J-45 et moins, une annale en conditions vaut mieux
  // qu'une revision de plus. On prend la matiere la moins couverte (le
  // moins d'annales deja faites), l'annee la plus recente d'abord.
  if (jours <= 45 && reste >= 60) {
    final nonFaites = m.annales.where((a) => !a.fait).toList();
    if (nonFaites.isNotEmpty) {
      final faitesParMatiere = <String, int>{};
      for (final a in m.annales) {
        if (a.fait) {
          faitesParMatiere[a.matiere] = (faitesParMatiere[a.matiere] ?? 0) + 1;
        }
      }
      nonFaites.sort((x, y) {
        final fx = faitesParMatiere[x.matiere] ?? 0;
        final fy = faitesParMatiere[y.matiere] ?? 0;
        return fx != fy ? fx.compareTo(fy) : y.annee.compareTo(x.annee);
      });
      final a = nonFaites.first;
      final mins = reste >= 150 ? 90 : 60;
      out.add(Suggestion(
        a.matiere,
        '📜 Annale ${a.concours} ${a.annee} — ${a.matiere}',
        'J-$jours · ${faitesParMatiere[a.matiere] ?? 0} annale(s) faite(s) dans cette matière',
        mins,
        consigne:
            'En conditions réelles : chrono, sans le cours. Corrige ensuite en notant chaque erreur dans le cahier d\'erreurs, puis coche l\'annale « faite ».',
      ));
      reste -= mins;
    }
  }

  final finJour = DateTime(now.year, now.month, now.day, 23, 59);
  final aReviser = m.chapitres.where((c) => c.etape > 0).toList()
    ..sort((a, b) {
      // 1. Revisions espacees dues d'abord.
      final aDue = a.prochaineRevision != null &&
          a.prochaineRevision!.isBefore(finJour);
      final bDue = b.prochaineRevision != null &&
          b.prochaineRevision!.isBefore(finJour);
      if (aDue != bDue) return aDue ? -1 : 1;
      // 2. Jamais revus (les plus fragiles en tete).
      if (a.dernierRevu == null && b.dernierRevu != null) return -1;
      if (a.dernierRevu != null && b.dernierRevu == null) return 1;
      if (a.dernierRevu == null && b.dernierRevu == null) {
        return a.maitrise.compareTo(b.maitrise);
      }
      // 3. Revus les plus anciens.
      final cmp = a.dernierRevu!.compareTo(b.dernierRevu!);
      return cmp != 0 ? cmp : a.maitrise.compareTo(b.maitrise);
    });

  // Interleaving : on alterne les matieres en respectant l'ordre ci-dessus.
  final files = <String, List<Chapitre>>{};
  for (final c in aReviser) {
    files.putIfAbsent(c.matiere, () => []).add(c);
  }
  final ordreMatieres = <String>[];
  for (final c in aReviser) {
    if (!ordreMatieres.contains(c.matiere)) ordreMatieres.add(c.matiere);
  }
  final alternes = <Chapitre>[];
  while (alternes.length < aReviser.length) {
    for (final mat in ordreMatieres) {
      final file = files[mat]!;
      if (file.isNotEmpty) alternes.add(file.removeAt(0));
    }
  }

  var i = 0;
  while (reste >= 30 && i < alternes.length) {
    final c = alternes[i];
    final due = c.prochaineRevision != null &&
        c.prochaineRevision!.isBefore(finJour);
    final mins = due ? 30 : (reste >= 75 ? 60 : (reste ~/ 15) * 15);
    final quandRevu = due
        ? 'révision espacée due'
        : c.dernierRevu == null
            ? 'jamais revu'
            : 'revu il y a ${now.difference(c.dernierRevu!).inDays} j';
    out.add(Suggestion(
      c.matiere,
      'Réviser : ${c.nom}',
      'J-$jours · $quandRevu',
      mins > reste ? reste : mins,
      chapitreId: c.id,
      rappel: due,
      consigne: consigneDe(c.matiere, due ? 'rappel' : 'revision'),
    ));
    reste -= mins;
    i++;
  }
  return out;
}

/// MODE ORAUX : apres les ecrits, le plan du soir prepare les epreuves
/// orales. Un oral date dans ≤ 7 jours prend la tete ; les autres epreuves
/// tournent (l'ordre de depart change chaque jour — couverture complete
/// sans etat supplementaire).
List<Suggestion> _suggereOraux(AppModel m, int minutesDispo) {
  final now = DateTime.now();
  final aujourdHui = DateTime(now.year, now.month, now.day);
  final out = <Suggestion>[];
  var reste = minutesDispo;

  // Epreuves encore a passer (datees en premier — triees par le store).
  final aVenir = m.oraux
      .where((o) => o.date == null || !o.date!.isBefore(aujourdHui))
      .toList();
  if (aVenir.isEmpty) return out;

  String raisonDe(EpreuveOrale o) {
    if (o.date == null) return 'Date pas encore connue — entretien régulier';
    final j = o.date!.difference(aujourdHui).inDays;
    if (j == 0) return 'C\'EST AUJOURD\'HUI — échauffement léger seulement';
    return 'Oral le ${frDateCourte(o.date!)} · J-$j';
  }

  // 1. Oral date imminent (≤ 7 jours) : bloc principal en tete.
  EpreuveOrale? urgent;
  for (final o in aVenir) {
    if (o.date == null) continue;
    if (o.date!.difference(aujourdHui).inDays > 7) continue;
    urgent = o;
    break; // aVenir est deja trie par date
  }
  if (urgent != null && reste >= 30) {
    final mins = reste >= 90 ? 60 : (reste ~/ 15) * 15;
    out.add(Suggestion(
      urgent.epreuve,
      'Oral ${urgent.concours} — ${urgent.epreuve}',
      raisonDe(urgent),
      mins,
      consigne: consigneOral(urgent.epreuve),
    ));
    reste -= mins;
  }

  // 2. Rotation quotidienne des autres epreuves.
  final autres = aVenir.where((o) => o.id != urgent?.id).toList();
  if (autres.isEmpty) return out;
  final depart = aujourdHui.difference(DateTime(2026)).inDays % autres.length;
  var i = 0;
  while (reste >= 30 && i < autres.length) {
    final o = autres[(depart + i) % autres.length];
    var mins = reste >= 75 ? 45 : (reste ~/ 15) * 15;
    if (mins > reste) mins = reste;
    out.add(Suggestion(
      o.epreuve,
      'Oral ${o.concours} — ${o.epreuve}',
      raisonDe(o),
      mins,
      consigne: consigneOral(o.epreuve),
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
  final String genre; // 'kholle' | 'ds' | 'dm'
  _Echeance(this.date, this.type, this.programme, this.genre);
}
