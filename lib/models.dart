import 'dart:math';

/// Couleur stable par matiere (palette fixe, choisie par hachage du nom).
const List<int> kSubjectPalette = [
  0xFF6B5CEB, // violet
  0xFFEB5C9E, // rose
  0xFF2680F2, // bleu
  0xFF12A66F, // vert
  0xFFF2762E, // orange
  0xFFE23A55, // rouge
  0xFF8A6FBF, // lavande
  0xFF0FA3B1, // sarcelle
];

int subjectColor(String matiere) {
  final m = matiere.trim().toLowerCase();
  // Couleurs "canon" pour les matieres classiques de prepa.
  const fixed = {
    'maths': 0xFF6B5CEB,
    'mathématiques': 0xFF6B5CEB,
    'physique': 0xFF2680F2,
    'chimie': 0xFF12A66F,
    'physique-chimie': 0xFF2680F2,
    'sii': 0xFFF2762E,
    'si': 0xFFF2762E,
    'anglais': 0xFFE23A55,
    'lv1': 0xFFE23A55,
    'français': 0xFFEB5C9E,
    'francais': 0xFFEB5C9E,
    'info': 0xFF0FA3B1,
    'informatique': 0xFF0FA3B1,
  };
  if (fixed.containsKey(m)) return fixed[m]!;
  return kSubjectPalette[m.hashCode.abs() % kSubjectPalette.length];
}

String _newId() =>
    '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(9999)}';

/// Une khôlle concrete (pour MON groupe) : issue de l'import IA
/// ou ajoutee a la main (rattrapage, colle de francais ponctuelle...).
class Colle {
  String id;
  String matiere;
  String kholleur;
  String salle;
  DateTime start;
  int dureeMin;
  String programme; // programme de colle de la semaine
  double? note; // /20
  String remarque;
  bool custom; // ajoutee manuellement

  Colle({
    String? id,
    required this.matiere,
    this.kholleur = '',
    this.salle = '',
    required this.start,
    this.dureeMin = 60,
    this.programme = '',
    this.note,
    this.remarque = '',
    this.custom = false,
  }) : id = id ?? _newId();

  DateTime get end => start.add(Duration(minutes: dureeMin));

  Map<String, dynamic> toJson() => {
        'id': id,
        'matiere': matiere,
        'kholleur': kholleur,
        'salle': salle,
        'start': start.toIso8601String(),
        'dureeMin': dureeMin,
        'programme': programme,
        'note': note,
        'remarque': remarque,
        'custom': custom,
      };

  static Colle fromJson(Map<String, dynamic> j) => Colle(
        id: j['id'] as String?,
        matiere: (j['matiere'] ?? '') as String,
        kholleur: (j['kholleur'] ?? '') as String,
        salle: (j['salle'] ?? '') as String,
        start: DateTime.parse(j['start'] as String),
        dureeMin: (j['dureeMin'] ?? 60) as int,
        programme: (j['programme'] ?? '') as String,
        note: (j['note'] as num?)?.toDouble(),
        remarque: (j['remarque'] ?? '') as String,
        custom: (j['custom'] ?? false) as bool,
      );
}

/// Un devoir surveille (ou concours blanc).
class Ds {
  String id;
  String matiere;
  String titre;
  DateTime date;
  double? note;

  Ds({String? id, required this.matiere, this.titre = 'DS', required this.date, this.note})
      : id = id ?? _newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'matiere': matiere,
        'titre': titre,
        'date': date.toIso8601String(),
        'note': note,
      };

  static Ds fromJson(Map<String, dynamic> j) => Ds(
        id: j['id'] as String?,
        matiere: (j['matiere'] ?? '') as String,
        titre: (j['titre'] ?? 'DS') as String,
        date: DateTime.parse(j['date'] as String),
        note: (j['note'] as num?)?.toDouble(),
      );
}

/// Filieres proposees (onboarding + Reglages).
const List<String> kFilieres = [
  'MPSI', 'PCSI', 'PTSI', 'MP2I', 'BCPST',
  'MP', 'PC', 'PSI', 'PT', 'MPI',
  'ECG', 'Hypokhâgne', 'Khâgne', 'Autre',
];

/// Etapes de progression d'un chapitre (le workflow prepa).
const List<String> kEtapesChapitre = [
  'pas vu', 'vu en cours', 'revu chez moi', 'exos faits', 'DS/DNS passé',
];

/// Un chapitre du programme, avec :
/// - [etape] : ou tu en es dans le workflow (0 = pas vu ... 4 = DS/DNS passe) ;
/// - [maitrise] : a quel point tu le tiens (0 = fragile ... 4 = maitrise) ;
/// - [dernierRevu] : derniere revision "concours" (mode revisions).
class Chapitre {
  String id;
  String matiere;
  String nom;
  int maitrise; // 0 = pas vu, 4 = maitrise
  int etape; // index dans kEtapesChapitre
  DateTime? dernierRevu;

  Chapitre({
    String? id,
    required this.matiere,
    required this.nom,
    this.maitrise = 2,
    this.etape = 0,
    this.dernierRevu,
  }) : id = id ?? _newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'matiere': matiere,
        'nom': nom,
        'maitrise': maitrise,
        'etape': etape,
        'dernierRevu': dernierRevu?.toIso8601String(),
      };

  static Chapitre fromJson(Map<String, dynamic> j) => Chapitre(
        id: j['id'] as String?,
        matiere: (j['matiere'] ?? '') as String,
        nom: (j['nom'] ?? '') as String,
        maitrise: (j['maitrise'] ?? 2) as int,
        etape: (j['etape'] ?? 0) as int,
        dernierRevu: j['dernierRevu'] == null
            ? null
            : DateTime.tryParse(j['dernierRevu'] as String),
      );
}

/// Un devoir a RENDRE (DM, DNS...) : ce qui pilote souvent les soirees.
class Devoir {
  String id;
  String matiere;
  String titre;
  DateTime dateRendu;
  bool rendu;
  String remarque;

  Devoir({
    String? id,
    required this.matiere,
    this.titre = 'DM',
    required this.dateRendu,
    this.rendu = false,
    this.remarque = '',
  }) : id = id ?? _newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'matiere': matiere,
        'titre': titre,
        'dateRendu': dateRendu.toIso8601String(),
        'rendu': rendu,
        'remarque': remarque,
      };

  static Devoir fromJson(Map<String, dynamic> j) => Devoir(
        id: j['id'] as String?,
        matiere: (j['matiere'] ?? '') as String,
        titre: (j['titre'] ?? 'DM') as String,
        dateRendu: DateTime.parse(j['dateRendu'] as String),
        rendu: (j['rendu'] ?? false) as bool,
        remarque: (j['remarque'] ?? '') as String,
      );
}

/// Une periode SANS COURS du calendrier interne : vacances, ou semaine de
/// revisions avant les concours (3/2 et 5/2). L'emploi du temps s'y tait.
class PlageSansCours {
  String id;
  String titre;
  DateTime debut;
  DateTime fin; // incluse

  PlageSansCours({
    String? id,
    required this.titre,
    required this.debut,
    required this.fin,
  }) : id = id ?? _newId();

  bool contient(DateTime d) {
    final jour = DateTime(d.year, d.month, d.day);
    return !jour.isBefore(DateTime(debut.year, debut.month, debut.day)) &&
        !jour.isAfter(DateTime(fin.year, fin.month, fin.day));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'titre': titre,
        'debut': debut.toIso8601String(),
        'fin': fin.toIso8601String(),
      };

  static PlageSansCours fromJson(Map<String, dynamic> j) => PlageSansCours(
        id: j['id'] as String?,
        titre: (j['titre'] ?? '') as String,
        debut: DateTime.parse(j['debut'] as String),
        fin: DateTime.parse(j['fin'] as String),
      );
}

/// Types de creneau pour le bilan de journee.
const List<String> kTypesBilan = ['Cours', 'Exos', 'TP'];

/// Bilan d'un creneau de la journee : qu'a-t-on fait pendant ce cours ?
/// (cours magistral -> quel chapitre, exos, TP). Nourrit les chapitres
/// ("vu en cours") et donc le plan du soir.
class Bilan {
  String id;
  DateTime jour; // date (minuit)
  String routineId;
  String matiere;
  String type; // valeur de kTypesBilan
  String? chapitreId; // si type == Cours

  Bilan({
    String? id,
    required this.jour,
    required this.routineId,
    required this.matiere,
    required this.type,
    this.chapitreId,
  }) : id = id ?? _newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'jour': jour.toIso8601String(),
        'routineId': routineId,
        'matiere': matiere,
        'type': type,
        'chapitreId': chapitreId,
      };

  static Bilan fromJson(Map<String, dynamic> j) => Bilan(
        id: j['id'] as String?,
        jour: DateTime.parse(j['jour'] as String),
        routineId: (j['routineId'] ?? '') as String,
        matiere: (j['matiere'] ?? '') as String,
        type: (j['type'] ?? 'Cours') as String,
        chapitreId: j['chapitreId'] as String?,
      );
}

/// Une seance de travail reellement effectuee (plan du soir coche).
class Seance {
  String id;
  String matiere;
  DateTime date;
  int minutes;

  Seance({
    String? id,
    required this.matiere,
    required this.date,
    required this.minutes,
  }) : id = id ?? _newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'matiere': matiere,
        'date': date.toIso8601String(),
        'minutes': minutes,
      };

  static Seance fromJson(Map<String, dynamic> j) => Seance(
        id: j['id'] as String?,
        matiere: (j['matiere'] ?? '') as String,
        date: DateTime.parse(j['date'] as String),
        minutes: (j['minutes'] ?? 0) as int,
      );
}

/// Un evenement recurrent de la semaine type : cours qui finit tard, sport,
/// musique, association... Affiche sur l'onglet Aujourd'hui pour avoir la
/// journee complete en tete et calibrer le travail du soir.
/// Alternance de semaines pour un creneau d'emploi du temps.
const List<String> kSemainesLabels = ['Toutes', 'Semaine A', 'Semaine B'];

class Routine {
  String id;
  String titre;
  int jour; // 1 = lundi ... 7 = dimanche
  int debutMin; // minutes depuis minuit (ex. 18h30 -> 1110)
  int dureeMin;
  // Matiere associee (facultatif) : "Cours de Maths" -> 'Maths'. Le moteur
  // du soir s'en sert : cours vu aujourd'hui = a revoir ce soir.
  String matiere;
  // 0 = toutes les semaines, 1 = semaines A, 2 = semaines B (roulement).
  int semaines;

  Routine({
    String? id,
    required this.titre,
    required this.jour,
    required this.debutMin,
    this.dureeMin = 60,
    this.matiere = '',
    this.semaines = 0,
  }) : id = id ?? _newId();

  String get labelHeure {
    String h(int m) =>
        '${m ~/ 60}h${(m % 60) == 0 ? '' : (m % 60).toString().padLeft(2, '0')}';
    return '${h(debutMin)}–${h(debutMin + dureeMin)}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'titre': titre,
        'jour': jour,
        'debutMin': debutMin,
        'dureeMin': dureeMin,
        'matiere': matiere,
        'semaines': semaines,
      };

  static Routine fromJson(Map<String, dynamic> j) => Routine(
        id: j['id'] as String?,
        titre: (j['titre'] ?? '') as String,
        jour: (j['jour'] ?? 1) as int,
        debutMin: (j['debutMin'] ?? 1080) as int,
        dureeMin: (j['dureeMin'] ?? 60) as int,
        matiere: (j['matiere'] ?? '') as String,
        semaines: (j['semaines'] ?? 0) as int,
      );
}

// ---------- Petits helpers de dates en francais (sans dependance) ----------

const _joursFr = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _moisFr = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
];

String frJour(DateTime d) => _joursFr[d.weekday - 1];
String frDate(DateTime d) => '${frJour(d)} ${d.day} ${_moisFr[d.month - 1]}';
String frDateCourte(DateTime d) => '${d.day} ${_moisFr[d.month - 1]}';
String frHeure(DateTime d) =>
    '${d.hour}h${d.minute == 0 ? '' : d.minute.toString().padLeft(2, '0')}';

/// Lundi de la semaine de [d].
DateTime mondayOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}
