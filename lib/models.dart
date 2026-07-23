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

/// Etapes de progression d'un chapitre (le workflow prepa).
const List<String> kEtapesChapitre = [
  'pas vu', 'vu en cours', 'revu chez moi', 'exos faits', 'DS/DNS passé',
];

/// Un chapitre du programme, avec :
/// - [etape] : ou tu en es dans le workflow (0 = pas vu ... 4 = DS/DNS passe) ;
/// - [maitrise] : a quel point tu le tiens (0 = fragile ... 4 = maitrise).
class Chapitre {
  String id;
  String matiere;
  String nom;
  int maitrise; // 0 = pas vu, 4 = maitrise
  int etape; // index dans kEtapesChapitre

  Chapitre({
    String? id,
    required this.matiere,
    required this.nom,
    this.maitrise = 2,
    this.etape = 0,
  }) : id = id ?? _newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'matiere': matiere,
        'nom': nom,
        'maitrise': maitrise,
        'etape': etape,
      };

  static Chapitre fromJson(Map<String, dynamic> j) => Chapitre(
        id: j['id'] as String?,
        matiere: (j['matiere'] ?? '') as String,
        nom: (j['nom'] ?? '') as String,
        maitrise: (j['maitrise'] ?? 2) as int,
        etape: (j['etape'] ?? 0) as int,
      );
}

/// Un evenement recurrent de la semaine type : cours qui finit tard, sport,
/// musique, association... Affiche sur l'onglet Aujourd'hui pour avoir la
/// journee complete en tete et calibrer le travail du soir.
class Routine {
  String id;
  String titre;
  int jour; // 1 = lundi ... 7 = dimanche
  int debutMin; // minutes depuis minuit (ex. 18h30 -> 1110)
  int dureeMin;
  // Matiere associee (facultatif) : "Cours de Maths" -> 'Maths'. Le moteur
  // du soir s'en sert : cours vu aujourd'hui = a revoir ce soir.
  String matiere;

  Routine({
    String? id,
    required this.titre,
    required this.jour,
    required this.debutMin,
    this.dureeMin = 60,
    this.matiere = '',
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
      };

  static Routine fromJson(Map<String, dynamic> j) => Routine(
        id: j['id'] as String?,
        titre: (j['titre'] ?? '') as String,
        jour: (j['jour'] ?? 1) as int,
        debutMin: (j['debutMin'] ?? 1080) as int,
        dureeMin: (j['dureeMin'] ?? 60) as int,
        matiere: (j['matiere'] ?? '') as String,
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
