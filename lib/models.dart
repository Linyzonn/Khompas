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

/// Hachage maison deterministe (djb2) : String.hashCode n'est pas garanti
/// stable entre plateformes -> les couleurs differaient entre web et iPhone.
int _djb2(String s) {
  var h = 5381;
  for (final c in s.codeUnits) {
    h = ((h * 33) ^ c) & 0x7fffffff;
  }
  return h;
}

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
  return kSubjectPalette[_djb2(m) % kSubjectPalette.length];
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

/// Un devoir surveille (ou concours blanc), avec son coefficient (les
/// lycees coefficientent presque tous les DS).
class Ds {
  String id;
  String matiere;
  String titre;
  DateTime date;
  double? note;
  double coeff;

  Ds({
    String? id,
    required this.matiere,
    this.titre = 'DS',
    required this.date,
    this.note,
    this.coeff = 1,
  }) : id = id ?? _newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'matiere': matiere,
        'titre': titre,
        'date': date.toIso8601String(),
        'note': note,
        'coeff': coeff,
      };

  static Ds fromJson(Map<String, dynamic> j) => Ds(
        id: j['id'] as String?,
        matiere: (j['matiere'] ?? '') as String,
        titre: (j['titre'] ?? 'DS') as String,
        date: DateTime.parse(j['date'] as String),
        note: (j['note'] as num?)?.toDouble(),
        coeff: ((j['coeff'] ?? 1) as num).toDouble(),
      );
}

/// Filieres proposees (onboarding + Reglages).
const List<String> kFilieres = [
  'MPSI', 'PCSI', 'PTSI', 'MP2I', 'BCPST',
  'MP', 'PC', 'PSI', 'PT', 'MPI',
  'ECG', 'Hypokhâgne', 'Khâgne', 'Autre',
];

/// Normalise un nom de matiere pour eviter les DOUBLONS ("Maths" vs
/// "Mathématiques", "Francais" vs "Français"...) : chaque source (import IA,
/// palette EDT, saisie manuelle) ecrit differemment, on canonise tout a
/// l'entree ET au chargement (migration des donnees existantes).
/// Les fusions risquees (LV1 -> Anglais ?) ne sont PAS automatiques :
/// l'outil « Fusionner deux matières » des Reglages est la pour ca.
String normaliseMatiere(String brut) {
  final propre = brut.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (propre.isEmpty) return propre;
  final cle = _sansAccents(propre.toLowerCase());
  const alias = <String, String>{
    'math': 'Maths',
    'maths': 'Maths',
    'mathematique': 'Maths',
    'mathematiques': 'Maths',
    'francais': 'Français',
    'francais-philo': 'Français',
    'francais-philosophie': 'Français',
    'lettres': 'Français',
    'anglais': 'Anglais',
    'espagnol': 'Espagnol',
    'allemand': 'Allemand',
    'physique-chimie': 'Physique-Chimie',
    'physique chimie': 'Physique-Chimie',
    'pc': 'Physique-Chimie',
    'physique': 'Physique',
    'chimie': 'Chimie',
    'si': 'SII',
    'sii': 'SII',
    's2i': 'SII',
    'sciences de l\'ingenieur': 'SII',
    'sciences industrielles': 'SII',
    'info': 'Info',
    'informatique': 'Info',
    'tipe': 'TIPE',
    'philosophie': 'Philosophie',
    'philo': 'Philosophie',
  };
  final canon = alias[cle];
  if (canon != null) return canon;
  // Matiere inconnue : on garde la graphie mais avec une majuscule.
  return propre[0].toUpperCase() + propre.substring(1);
}

String _sansAccents(String s) {
  const map = {
    'à': 'a', 'â': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i',
    'ô': 'o', 'ö': 'o',
    'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c',
  };
  final b = StringBuffer();
  for (final r in s.split('')) {
    b.write(map[r] ?? r);
  }
  return b.toString();
}

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
  // Repetition espacee : prochaine revision programmee et intervalle courant
  // (double a chaque succes, se resserre en cas de difficulte).
  DateTime? prochaineRevision;
  int intervalleJours;
  // Le prof est EN PLEIN DEDANS : une partie a ete vue en classe mais le
  // chapitre n'est pas fini — on ne declenche ni etape ni espacement.
  bool entame;

  Chapitre({
    String? id,
    required this.matiere,
    required this.nom,
    this.maitrise = 2,
    this.etape = 0,
    this.dernierRevu,
    this.prochaineRevision,
    this.intervalleJours = 1,
    this.entame = false,
  }) : id = id ?? _newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'matiere': matiere,
        'nom': nom,
        'maitrise': maitrise,
        'etape': etape,
        'dernierRevu': dernierRevu?.toIso8601String(),
        'prochaineRevision': prochaineRevision?.toIso8601String(),
        'intervalleJours': intervalleJours,
        'entame': entame,
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
        prochaineRevision: j['prochaineRevision'] == null
            ? null
            : DateTime.tryParse(j['prochaineRevision'] as String),
        intervalleJours: (j['intervalleJours'] ?? 1) as int,
        entame: (j['entame'] ?? false) as bool,
      );
}

/// Un devoir a RENDRE (DM, DNS...) : ce qui pilote souvent les soirees.
class Devoir {
  String id;
  String matiere;
  String titre;
  DateTime dateRendu;
  // Jour de distribution : le soir meme, le moteur propose de LIRE le DM
  // (le conseil de prof classique — ca desamorce la procrastination).
  DateTime dateDonne;
  bool rendu;
  String remarque;

  Devoir({
    String? id,
    required this.matiere,
    this.titre = 'DM',
    required this.dateRendu,
    DateTime? dateDonne,
    this.rendu = false,
    this.remarque = '',
  })  : dateDonne = dateDonne ?? DateTime.now(),
        id = id ?? _newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'matiere': matiere,
        'titre': titre,
        'dateRendu': dateRendu.toIso8601String(),
        'dateDonne': dateDonne.toIso8601String(),
        'rendu': rendu,
        'remarque': remarque,
      };

  static Devoir fromJson(Map<String, dynamic> j) => Devoir(
        id: j['id'] as String?,
        matiere: (j['matiere'] ?? '') as String,
        titre: (j['titre'] ?? 'DM') as String,
        dateRendu: DateTime.parse(j['dateRendu'] as String),
        dateDonne: j['dateDonne'] == null
            ? DateTime.parse(j['dateRendu'] as String)
                .subtract(const Duration(days: 7))
            : DateTime.tryParse(j['dateDonne'] as String),
        rendu: (j['rendu'] ?? false) as bool,
        remarque: (j['remarque'] ?? '') as String,
      );
}

/// Un evenement PONCTUEL (pas de schema recurrent) : seance de sport dont la
/// date tombe tard, TP info une semaine sur trois, sortie, oral blanc...
class Evenement {
  String id;
  String titre;
  String matiere; // facultatif — s'il y en a une, le moteur la voit
  DateTime date; // jour
  int debutMin;
  int dureeMin;

  Evenement({
    String? id,
    required this.titre,
    this.matiere = '',
    required this.date,
    required this.debutMin,
    this.dureeMin = 60,
  }) : id = id ?? _newId();

  String get labelHeure {
    String h(int m) =>
        '${m ~/ 60}h${(m % 60) == 0 ? '' : (m % 60).toString().padLeft(2, '0')}';
    return '${h(debutMin)}–${h(debutMin + dureeMin)}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'titre': titre,
        'matiere': matiere,
        'date': date.toIso8601String(),
        'debutMin': debutMin,
        'dureeMin': dureeMin,
      };

  static Evenement fromJson(Map<String, dynamic> j) => Evenement(
        id: j['id'] as String?,
        titre: (j['titre'] ?? '') as String,
        matiere: (j['matiere'] ?? '') as String,
        date: DateTime.parse(j['date'] as String),
        debutMin: (j['debutMin'] ?? 480) as int,
        dureeMin: (j['dureeMin'] ?? 60) as int,
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

// ---------- Cahier d'erreurs ----------

/// Types d'erreurs : le classement rend les stats possibles ("60 % de tes
/// erreurs de maths sont du calcul").
const List<String> kTypesErreur = [
  'Calcul', 'Méthode', 'Cours pas su', 'Étourderie', 'Autre',
];
const List<String> kSourcesErreur = ['Khôlle', 'DS', 'DM', 'TD', 'Autre'];

/// Une erreur notee apres une kholle / un DS / un TD. [refaite] = l'exercice
/// a ete refait AVEC SUCCES depuis (le but du cahier d'erreurs).
class Erreur {
  String id;
  String matiere;
  String texte;
  String type; // element de kTypesErreur
  String source; // element de kSourcesErreur
  String? chapitreId;
  DateTime date;
  bool refaite;

  Erreur({
    String? id,
    required this.matiere,
    required this.texte,
    this.type = 'Autre',
    this.source = 'Autre',
    this.chapitreId,
    DateTime? date,
    this.refaite = false,
  })  : date = date ?? DateTime.now(),
        id = id ?? _newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'matiere': matiere,
        'texte': texte,
        'type': type,
        'source': source,
        'chapitreId': chapitreId,
        'date': date.toIso8601String(),
        'refaite': refaite,
      };

  static Erreur fromJson(Map<String, dynamic> j) => Erreur(
        id: j['id'] as String?,
        matiere: (j['matiere'] ?? '') as String,
        texte: (j['texte'] ?? '') as String,
        type: (j['type'] ?? 'Autre') as String,
        source: (j['source'] ?? 'Autre') as String,
        chapitreId: j['chapitreId'] as String?,
        date: DateTime.parse(j['date'] as String),
        refaite: (j['refaite'] ?? false) as bool,
      );
}

// ---------- Annales et oraux (concours) ----------

/// Concours suggeres selon la filiere (liste indicative, saisie libre
/// toujours possible).
List<String> kConcoursPour(String filiere) {
  final f = filiere.toUpperCase();
  if (f == 'ECG') return ['BCE', 'Ecricome'];
  if (f == 'BCPST') return ['Agro-Veto', 'G2E', 'X-ENS A'];
  if (f.contains('KH')) return ['ENS Ulm', 'ENS Lyon', 'BEL'];
  return [
    'CCINP', 'Centrale-Supélec', 'Mines-Ponts', 'X-ENS',
    'Mines-Télécom', 'e3a-Polytech',
  ];
}

/// Epreuves orales suggerees (filieres scientifiques).
const List<String> kEpreuvesOrales = [
  'Maths', 'Physique-Chimie', 'SII (manip)', 'TIPE', 'Anglais', 'ADS',
];

/// Une annale (sujet de concours) a faire ou faite. [ressenti] : 0 = pas
/// note, sinon 1 (rate) a 5 (maitrise).
class Annale {
  String id;
  String concours;
  String matiere;
  int annee;
  bool fait;
  int ressenti;
  DateTime? dateFait;

  Annale({
    String? id,
    required this.concours,
    required this.matiere,
    required this.annee,
    this.fait = false,
    this.ressenti = 0,
    this.dateFait,
  }) : id = id ?? _newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'concours': concours,
        'matiere': matiere,
        'annee': annee,
        'fait': fait,
        'ressenti': ressenti,
        'dateFait': dateFait?.toIso8601String(),
      };

  static Annale fromJson(Map<String, dynamic> j) => Annale(
        id: j['id'] as String?,
        concours: (j['concours'] ?? '') as String,
        matiere: (j['matiere'] ?? '') as String,
        annee: (j['annee'] ?? 2020) as int,
        fait: (j['fait'] ?? false) as bool,
        ressenti: (j['ressenti'] ?? 0) as int,
        dateFait: j['dateFait'] == null
            ? null
            : DateTime.parse(j['dateFait'] as String),
      );
}

/// Une epreuve orale d'un concours. La date/heure n'est connue qu'apres
/// l'admissibilite : tout est facultatif sauf concours + epreuve.
class EpreuveOrale {
  String id;
  String concours;
  String epreuve; // 'Maths', 'TIPE', 'SII (manip)'...
  DateTime? date;
  int? debutMin; // minutes depuis minuit, null = heure inconnue
  String lieu;
  String remarque;

  EpreuveOrale({
    String? id,
    required this.concours,
    required this.epreuve,
    this.date,
    this.debutMin,
    this.lieu = '',
    this.remarque = '',
  }) : id = id ?? _newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'concours': concours,
        'epreuve': epreuve,
        'date': date?.toIso8601String(),
        'debutMin': debutMin,
        'lieu': lieu,
        'remarque': remarque,
      };

  static EpreuveOrale fromJson(Map<String, dynamic> j) => EpreuveOrale(
        id: j['id'] as String?,
        concours: (j['concours'] ?? '') as String,
        epreuve: (j['epreuve'] ?? '') as String,
        date: j['date'] == null ? null : DateTime.parse(j['date'] as String),
        debutMin: j['debutMin'] as int?,
        lieu: (j['lieu'] ?? '') as String,
        remarque: (j['remarque'] ?? '') as String,
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
