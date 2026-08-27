import 'models.dart';
import 'store.dart';

/// CALCUL DES STATISTIQUES — fonctions PURES, horloge injectable, aucune
/// dependance a l'interface : c'est ce qui les rend testables et ce qui
/// evite d'allonger encore store.dart (deja un god object).
///
/// Regle de la charte : une statistique INFORME, elle ne juge pas. Aucune
/// fonction ici ne renvoie de « score global » ni de comparaison a autrui —
/// des faits, des tendances, et de quoi decider quoi travailler ce soir.

// ---------------------------------------------------------------- Temps

/// Serie de jours CONSECUTIFS travailles, en remontant depuis aujourd'hui.
/// Un jour sans seance casse la serie — sauf AUJOURD'HUI (la soiree n'est
/// pas finie : on ne casse pas une serie a 8 h du matin).
int serieEnCours(AppModel m, {DateTime? maintenant}) {
  final now = maintenant ?? DateTime.now();
  final jours = _joursTravailles(m);
  if (jours.isEmpty) return 0;
  var jour = DateTime(now.year, now.month, now.day);
  if (!jours.contains(jour)) {
    jour = jour.subtract(const Duration(days: 1));
    if (!jours.contains(jour)) return 0;
  }
  var n = 0;
  while (jours.contains(jour)) {
    n++;
    jour = jour.subtract(const Duration(days: 1));
  }
  return n;
}

/// Plus longue serie jamais atteinte (sur l'historique conserve).
int meilleureSerie(AppModel m) {
  final jours = _joursTravailles(m).toList()..sort();
  if (jours.isEmpty) return 0;
  var meilleure = 1;
  var courante = 1;
  for (var i = 1; i < jours.length; i++) {
    if (jours[i].difference(jours[i - 1]).inDays == 1) {
      courante++;
      if (courante > meilleure) meilleure = courante;
    } else {
      courante = 1;
    }
  }
  return meilleure;
}

Set<DateTime> _joursTravailles(AppModel m) => {
      for (final s in m.seances)
        if (s.minutes > 0) DateTime(s.date.year, s.date.month, s.date.day)
    };

/// Minutes totales sur les [jours] derniers jours.
int minutesTotal(AppModel m, {DateTime? maintenant, int jours = 30}) {
  final now = maintenant ?? DateTime.now();
  final debut = now.subtract(Duration(days: jours));
  var t = 0;
  for (final s in m.seances) {
    if (!s.date.isBefore(debut) && !s.date.isAfter(now)) t += s.minutes;
  }
  return t;
}

/// Minutes moyennes par JOUR DE SEMAINE (index 0 = lundi ... 6 = dimanche)
/// sur les [jours] derniers jours : montre les creux reels de la semaine.
List<int> minutesParJourSemaine(AppModel m,
    {DateTime? maintenant, int jours = 56}) {
  final now = maintenant ?? DateTime.now();
  final debut = now.subtract(Duration(days: jours));
  final totaux = List<int>.filled(7, 0);
  final compte = List<int>.filled(7, 0);
  for (var d = 0; d <= jours; d++) {
    final jour = DateTime(debut.year, debut.month, debut.day + d);
    if (jour.isAfter(now)) break;
    compte[jour.weekday - 1]++;
  }
  for (final s in m.seances) {
    if (s.date.isBefore(debut) || s.date.isAfter(now)) continue;
    totaux[s.date.weekday - 1] += s.minutes;
  }
  return [
    for (var i = 0; i < 7; i++) compte[i] == 0 ? 0 : totaux[i] ~/ compte[i]
  ];
}

// ---------------------------------------------------------------- Notes

/// Moyennes d'une matiere, khôlles et DS SEPAREES (elles ne mesurent pas la
/// meme chose : l'oral et l'ecrit se travaillent differemment).
/// Retourne (moyenne kholles, moyenne DS, ecart moyen a la classe).
(double?, double?, double?) moyennesMatiere(AppModel m, String matiere) {
  final kh = <double>[];
  final dsN = <double>[];
  final ecarts = <double>[];
  for (final c in m.colles) {
    if (c.matiere == matiere && c.note != null) kh.add(c.note!);
  }
  for (final d in m.ds) {
    if (d.matiere != matiere || d.note == null) continue;
    dsN.add(d.note!);
    // L'ecart a la moyenne de classe dit ce qu'une note brute cache : un 9
    // pour 7 de moyenne est une BONNE note.
    if (d.moyenneClasse != null) ecarts.add(d.note! - d.moyenneClasse!);
  }
  double? moy(List<double> l) =>
      l.isEmpty ? null : l.reduce((a, b) => a + b) / l.length;
  return (moy(kh), moy(dsN), moy(ecarts));
}

/// Toutes les notes d'une matiere dans l'ordre chronologique (kholles + DS
/// confondus) : de quoi tracer une courbe de progression.
List<(DateTime, double)> historiqueNotes(AppModel m, String matiere) {
  final l = <(DateTime, double)>[];
  for (final c in m.colles) {
    if (c.matiere == matiere && c.note != null) l.add((c.start, c.note!));
  }
  for (final d in m.ds) {
    if (d.matiere == matiere && d.note != null) l.add((d.date, d.note!));
  }
  l.sort((a, b) => a.$1.compareTo(b.$1));
  return l;
}

// -------------------------------------------------- Memorisation (chapitres)

/// Etat du programme : combien de chapitres a chaque niveau de maitrise,
/// combien attendent leur premiere revision, combien sont en retard.
class EtatMemoire {
  final List<int> parMaitrise; // index 0..4
  final int programmes; // dans la repetition espacee
  final int horsSysteme; // commences mais jamais programmes
  final int dus; // revision due aujourd'hui ou en retard
  final int enRetard; // due depuis plus d'un jour
  final int intervalleMoyen; // solidite moyenne, en jours
  final int consolides; // maitrise 4

  const EtatMemoire({
    required this.parMaitrise,
    required this.programmes,
    required this.horsSysteme,
    required this.dus,
    required this.enRetard,
    required this.intervalleMoyen,
    required this.consolides,
  });
}

EtatMemoire etatMemoire(AppModel m, {DateTime? maintenant}) {
  final now = maintenant ?? DateTime.now();
  final finJour = DateTime(now.year, now.month, now.day, 23, 59);
  final hier = DateTime(now.year, now.month, now.day);
  final parMaitrise = List<int>.filled(5, 0);
  var programmes = 0, horsSysteme = 0, dus = 0, enRetard = 0, sommeInt = 0;
  for (final c in m.chapitres) {
    if (matiereLitteraire(c.matiere)) continue; // pas de chapitres a revoir
    parMaitrise[c.maitrise.clamp(0, 4)]++;
    if (c.prochaineRevision != null) {
      programmes++;
      sommeInt += c.intervalleJours;
      if (c.prochaineRevision!.isBefore(finJour)) {
        dus++;
        if (c.prochaineRevision!.isBefore(hier)) enRetard++;
      }
    } else if (c.etape > 0) {
      horsSysteme++;
    }
  }
  return EtatMemoire(
    parMaitrise: parMaitrise,
    programmes: programmes,
    horsSysteme: horsSysteme,
    dus: dus,
    enRetard: enRetard,
    intervalleMoyen: programmes == 0 ? 0 : sommeInt ~/ programmes,
    consolides: parMaitrise[4],
  );
}

// ------------------------------------------------------- Cahier d'erreurs

/// Repartition des erreurs par [champ] ('type' ou 'source'), tri decroissant.
/// Le TYPE le plus frequent est la faiblesse recurrente a corriger en
/// priorite — c'est l'information la plus rentable du cahier.
List<(String, int)> erreursPar(AppModel m, String champ) {
  final map = <String, int>{};
  for (final e in m.erreurs) {
    final cle = champ == 'source' ? e.source : e.type;
    if (cle.trim().isEmpty) continue;
    map[cle] = (map[cle] ?? 0) + 1;
  }
  final l = map.entries.map((e) => (e.key, e.value)).toList()
    ..sort((a, b) => b.$2.compareTo(a.$2));
  return l;
}

/// (total, consolidees, en attente) — « consolidee » = deux succes espaces
/// (successive relearning), pas une simple coche.
(int, int, int) bilanErreurs(AppModel m, {DateTime? maintenant}) {
  final now = maintenant ?? DateTime.now();
  var consolidees = 0, attente = 0;
  for (final e in m.erreurs) {
    if (e.foisRefaite >= 2) {
      consolidees++;
    } else if (e.aRefaire(now)) {
      attente++;
    }
  }
  return (m.erreurs.length, consolidees, attente);
}

// --------------------------------------------------------------- Cartes

/// (total, dues aujourd'hui) pour les citations et le vocabulaire.
(int, int) bilanCartes(AppModel m) => (
      m.citations.length + m.vocab.length,
      m.citationsDues().length + m.vocabDus().length,
    );

// ------------------------------------------------------- Travail impose

/// (rendus a temps, rendus en retard, en cours, non rendus echus).
(int, int, int, int) bilanDevoirs(AppModel m, {DateTime? maintenant}) {
  final now = maintenant ?? DateTime.now();
  final aujourdHui = DateTime(now.year, now.month, now.day);
  var aTemps = 0, enRetard = 0, enCours = 0, rates = 0;
  for (final d in m.devoirs) {
    final echeance = DateTime(d.dateRendu.year, d.dateRendu.month, d.dateRendu.day);
    if (d.rendu) {
      // On ne sait pas QUAND il a ete coche : un devoir rendu dont
      // l'echeance est passee compte comme fait a temps (le plan le
      // proposait jusqu'au jour J).
      aTemps++;
    } else if (echeance.isBefore(aujourdHui)) {
      rates++;
    } else {
      enCours++;
    }
  }
  return (aTemps, enRetard, enCours, rates);
}

// -------------------------------------------------------------- Annales

/// (faites, total, ressenti moyen sur 5) — le ressenti dit ou en est la
/// confiance, la ou la note dit ce qui est acquis.
(int, int, double?) bilanAnnales(AppModel m) {
  final faites = m.annales.where((a) => a.fait).toList();
  final ressentis =
      faites.where((a) => a.ressenti > 0).map((a) => a.ressenti.toDouble());
  return (
    faites.length,
    m.annales.length,
    ressentis.isEmpty
        ? null
        : ressentis.reduce((a, b) => a + b) / ressentis.length,
  );
}

// -------------------------------------------------------------- Lecture

/// (pages lues, pages totales, oeuvres finies, oeuvres totales).
(int, int, int, int) bilanLecture(AppModel m) {
  var lues = 0, total = 0, finies = 0;
  for (final o in m.oeuvres) {
    lues += o.pageActuelle;
    total += o.pages ?? 0;
    if (o.finie) finies++;
  }
  return (lues, total, finies, m.oeuvres.length);
}
