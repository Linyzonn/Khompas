import 'dart:convert';
import 'dart:math';

/// Tente de reparer un JSON TRONQUE (fichier coupe en pleine ecriture,
/// reponse d'IA interrompue par la limite de tokens) : coupe au dernier
/// separateur d'objet complet et referme les crochets restes ouverts.
/// Retourne le JSON repare, ou null si rien n'y fait. Publique : utilisee
/// par la copie de secours (store) ET le plan B des extractions IA.
String? repareJsonTronque(String raw) {
  // Points de coupe candidats : chaque '}' ou ']' en remontant depuis la
  // fin (bornes pour rester rapide sur un gros fichier).
  var essais = 0;
  for (var i = raw.length - 1; i >= 0 && essais < 60; i--) {
    final ch = raw[i];
    if (ch != '}' && ch != ']') continue;
    essais++;
    final tronque = raw.substring(0, i + 1);
    // Referme ce qui reste ouvert (scan hors chaines de caracteres).
    final pile = <String>[];
    var enChaine = false;
    var echappe = false;
    for (var k = 0; k < tronque.length; k++) {
      final c = tronque[k];
      if (echappe) {
        echappe = false;
        continue;
      }
      if (c == r'\') {
        echappe = true;
        continue;
      }
      if (c == '"') {
        enChaine = !enChaine;
        continue;
      }
      if (enChaine) continue;
      if (c == '{' || c == '[') pile.add(c);
      if (c == '}' || c == ']') {
        if (pile.isEmpty) break; // desequilibre : candidat invalide
        pile.removeLast();
      }
    }
    if (enChaine) continue;
    final fermetures =
        pile.reversed.map((c) => c == '{' ? '}' : ']').join();
    final candidat = tronque + fermetures;
    try {
      jsonDecode(candidat);
      return candidat;
    } catch (_) {
      // candidat invalide : on remonte encore
    }
  }
  return null;
}

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
  // Kholle de LANGUE : noms des listes de voc a savoir pour cette colle
  // (la veille, le tableau de bord fait reviser ces listes-la).
  List<String> listesVoc;

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
    List<String>? listesVoc,
  })  : id = id ?? _newId(),
        listesVoc = listesVoc ?? [];

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
        'listesVoc': listesVoc,
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
        listesVoc: ((j['listesVoc'] ?? []) as List)
            .map((e) => e.toString())
            .toList(),
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
  // Moyenne de la classe (facultative) : c'est ELLE qui dit si une note est
  // bonne — en prepa un 9 peut etre au-dessus de la barre. Jamais de rang.
  double? moyenneClasse;
  // Petite interro de cours (pas un vrai DS) : le plan fait RELIRE LE COURS
  // les jours d'avant (consigne dediee), coeff faible par defaut.
  bool interro;
  /// Chapitres AU PROGRAMME de ce DS (quand le prof l'annonce) : le plan du
  /// soir les fait remonter avant l'epreuve, au lieu de proposer la matiere
  /// en general.
  List<String> chapitreIds;

  Ds({
    String? id,
    required this.matiere,
    this.titre = 'DS',
    required this.date,
    this.note,
    this.coeff = 1,
    this.moyenneClasse,
    this.interro = false,
    List<String>? chapitreIds,
  })  : chapitreIds = chapitreIds ?? [],
        id = id ?? _newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'matiere': matiere,
        'titre': titre,
        'date': date.toIso8601String(),
        'note': note,
        'coeff': coeff,
        'moyenneClasse': moyenneClasse,
        'interro': interro,
        'chapitreIds': chapitreIds,
      };

  static Ds fromJson(Map<String, dynamic> j) => Ds(
        id: j['id'] as String?,
        matiere: (j['matiere'] ?? '') as String,
        titre: (j['titre'] ?? 'DS') as String,
        date: DateTime.parse(j['date'] as String),
        note: (j['note'] as num?)?.toDouble(),
        coeff: ((j['coeff'] ?? 1) as num).toDouble(),
        moyenneClasse: (j['moyenneClasse'] as num?)?.toDouble(),
        interro: (j['interro'] ?? false) as bool,
        chapitreIds: ((j['chapitreIds'] ?? []) as List)
            .map((e) => e.toString())
            .toList(),
      );
}

/// Filieres proposees (onboarding + Reglages).
const List<String> kFilieres = [
  'MPSI', 'PCSI', 'PTSI', 'MP2I', 'BCPST', 'TSI', 'ATS',
  'MP', 'PC', 'PSI', 'PT', 'MPI',
  'ECG', 'B/L', 'Hypokhâgne', 'Khâgne', 'Autre',
];

/// Filieres de 2e annee scientifique (jalons TIPE/SCEI proposes).
const List<String> kFilieresDeuxiemeAnnee = ['MP', 'PC', 'PSI', 'PT', 'MPI'];

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

/// Matieres « litteraires » (francais + langues) : PAS de chapitres a
/// reviser en repetition espacee — le travail y est le travail impose
/// (kholle, DM), puis les CARTES (voc d'anglais, citations) et la
/// preparation de la prochaine colle. Le moteur les traite a part.
bool matiereLitteraire(String matiere) {
  final m = _sansAccents(matiere.trim().toLowerCase());
  return m.contains('francais') ||
      m.contains('philo') ||
      m.contains('anglais') ||
      m.contains('espagnol') ||
      m.contains('allemand') ||
      m.contains('italien') ||
      m.contains('arabe') ||
      m.contains('lv1') ||
      m.contains('lv2');
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
  // Nombre d'auto-evaluations "difficile" recentes d'affilee : un chapitre
  // chroniquement dur voit ses intervalles s'allonger moins vite (memoire
  // des echecs, dans l'esprit de l'ease factor de SM-2). Remis a zero par
  // une evaluation "facile".
  int echecs;

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
    this.echecs = 0,
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
        'echecs': echecs,
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
        echecs: ((j['echecs'] ?? 0) as num).toInt(),
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
  /// Charge de travail ANNONCEE par le prof, en minutes (0 = inconnue).
  /// « Ces exos, comptez 6 h » : sans elle, le plan proposait un bloc de
  /// 60 min sans anticiper — un devoir de 6 h doit s'ETALER sur les jours
  /// qui restent, sinon il tombe entier la veille.
  int dureeEstimeeMin;

  Devoir({
    String? id,
    required this.matiere,
    this.titre = 'DM',
    required this.dateRendu,
    DateTime? dateDonne,
    this.rendu = false,
    this.remarque = '',
    this.dureeEstimeeMin = 0,
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
        'dureeEstimeeMin': dureeEstimeeMin,
      };

  static Devoir fromJson(Map<String, dynamic> j) => Devoir(
        id: j['id'] as String?,
        matiere: (j['matiere'] ?? '') as String,
        titre: (j['titre'] ?? 'DM') as String,
        dateRendu: DateTime.parse(j['dateRendu'] as String),
        // Absent OU illisible -> dateRendu - 7 j. (Un tryParse nul laissait
        // le defaut DateTime.now() du constructeur -> le moteur proposait
        // "Lis le DM distribué aujourd'hui" a tort a chaque chargement.)
        dateDonne: DateTime.tryParse((j['dateDonne'] ?? '') as String) ??
            DateTime.parse(j['dateRendu'] as String)
                .subtract(const Duration(days: 7)),
        rendu: (j['rendu'] ?? false) as bool,
        remarque: (j['remarque'] ?? '') as String,
        dureeEstimeeMin: ((j['dureeEstimeeMin'] ?? 0) as num).toInt(),
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

  // Nature de la plage : pilote le comportement du plan du soir.
  //  - 'vacances'  : petites vacances scolaires (etaleur de DM actif) ;
  //  - 'revisions' : semaine de revisions avant les ecrits (3/2 et 5/2) ;
  //  - 'ete'       : GRANDES vacances -> mode reactivation douce du
  //                  programme (rotation des chapitres, annales, repos).
  String type;

  PlageSansCours({
    String? id,
    required this.titre,
    required this.debut,
    required this.fin,
    this.type = 'vacances',
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
        'type': type,
      };

  static PlageSansCours fromJson(Map<String, dynamic> j) {
    final debut = DateTime.parse(j['debut'] as String);
    final fin = DateTime.parse(j['fin'] as String);
    var type = (j['type'] ?? '') as String;
    if (type.isEmpty) {
      // Donnees d'avant le champ : une longue plage touchant juillet ou
      // aout est de toute evidence l'ete.
      final longue = fin.difference(debut).inDays >= 40;
      final toucheEte = [debut.month, fin.month]
              .any((mois) => mois == 7 || mois == 8) ||
          (debut.month <= 6 && fin.month >= 9);
      type = (longue && toucheEte) ? 'ete' : 'vacances';
    }
    return PlageSansCours(
      id: j['id'] as String?,
      titre: (j['titre'] ?? '') as String,
      debut: debut,
      fin: fin,
      type: type,
    );
  }
}

/// Types de plage sans cours proposes a la creation (etiquette + emoji).
const List<(String, String, String)> kTypesPlage = [
  ('vacances', '🏖', 'Vacances'),
  ('revisions', '📖', 'Révisions'),
  ('ete', '☀️', 'Été (grandes vacances)'),
];

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
  // SUCCESSIVE RELEARNING (Rawson & Dunlosky) : UNE reussite ne suffit pas
  // a retenir une correction — une erreur « refaite » ressort en veille
  // d'epreuve apres 30 j, jusqu'a DEUX succes espaces. Avant : cochee une
  // fois, l'erreur sortait du circuit pour toujours et revenait... au DS.
  DateTime? refaiteLe;
  int foisRefaite;

  /// L'erreur merite-t-elle de repasser dans le plan ?
  bool aRefaire(DateTime maintenant) {
    if (!refaite) return true;
    if (foisRefaite >= 2) return false; // consolidee : 2 succes espaces
    if (refaiteLe == null) return false;
    return maintenant.difference(refaiteLe!).inDays > 30;
  }

  Erreur({
    String? id,
    required this.matiere,
    required this.texte,
    this.type = 'Autre',
    this.source = 'Autre',
    this.chapitreId,
    DateTime? date,
    this.refaite = false,
    this.refaiteLe,
    this.foisRefaite = 0,
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
        'refaiteLe': refaiteLe?.toIso8601String(),
        'foisRefaite': foisRefaite,
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
        refaiteLe: j['refaiteLe'] == null
            ? null
            : DateTime.tryParse(j['refaiteLe'] as String),
        foisRefaite: ((j['foisRefaite'] ?? 0) as num).toInt(),
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
  'Français', // Mines-Ponts a un oral de francais
];

/// Une ŒUVRE du programme de francais-philo de l'annee (3 livres + un
/// theme). La lecture se fait idealement PENDANT L'ETE — le plan d'ete
/// programme des seances de lecture, et le debut d'annee rattrape ce qui
/// manque. [pages] facultatif : s'il est connu, l'app calcule le rythme
/// (« ~N pages par seance pour finir avant la rentree »).
class Oeuvre {
  String id;
  String titre;
  String auteur;
  int? pages;
  int pageActuelle;
  bool finie;

  Oeuvre({
    String? id,
    required this.titre,
    this.auteur = '',
    this.pages,
    this.pageActuelle = 0,
    this.finie = false,
  }) : id = id ?? _newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'titre': titre,
        'auteur': auteur,
        'pages': pages,
        'pageActuelle': pageActuelle,
        'finie': finie,
      };

  static Oeuvre fromJson(Map<String, dynamic> j) => Oeuvre(
        id: j['id'] as String?,
        titre: (j['titre'] ?? '') as String,
        auteur: (j['auteur'] ?? '') as String,
        pages: (j['pages'] as num?)?.toInt(),
        pageActuelle: ((j['pageActuelle'] ?? 0) as num).toInt(),
        finie: (j['finie'] ?? false) as bool,
      );
}

/// Une CITATION de francais-philo, revisee facon Anki. Le sens de revision
/// est celui de la dissertation : on voit l'AXE du theme et l'USAGE (« pour
/// montrer que... »), on doit restituer la citation ET son auteur — un meme
/// argument peut s'appuyer sur deux auteurs, l'auteur fait partie de la
/// reponse.
class Citation {
  String id;
  String texte;
  String auteur;
  // Titre de l'oeuvre d'origine (texte libre : une citation peut venir
  // d'ailleurs que des 3 oeuvres au programme).
  String oeuvre;
  // Axe / sous-theme du theme de l'annee auquel elle repond.
  String axe;
  // Comment s'en servir : « pour montrer que... », la phrase d'attaque.
  String usage;
  // Repetition espacee (memes regles que les chapitres).
  int intervalleJours;
  DateTime? prochaineRevision;
  DateTime? dernierRevu;
  int echecs;

  Citation({
    String? id,
    required this.texte,
    this.auteur = '',
    this.oeuvre = '',
    this.axe = '',
    this.usage = '',
    this.intervalleJours = 1,
    this.prochaineRevision,
    this.dernierRevu,
    this.echecs = 0,
  }) : id = id ?? _newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'texte': texte,
        'auteur': auteur,
        'oeuvre': oeuvre,
        'axe': axe,
        'usage': usage,
        'intervalleJours': intervalleJours,
        'prochaineRevision': prochaineRevision?.toIso8601String(),
        'dernierRevu': dernierRevu?.toIso8601String(),
        'echecs': echecs,
      };

  static Citation fromJson(Map<String, dynamic> j) => Citation(
        id: j['id'] as String?,
        texte: (j['texte'] ?? '') as String,
        auteur: (j['auteur'] ?? '') as String,
        oeuvre: (j['oeuvre'] ?? '') as String,
        axe: (j['axe'] ?? '') as String,
        usage: (j['usage'] ?? '') as String,
        intervalleJours: ((j['intervalleJours'] ?? 1) as num).toInt(),
        prochaineRevision: j['prochaineRevision'] == null
            ? null
            : DateTime.tryParse(j['prochaineRevision'] as String),
        dernierRevu: j['dernierRevu'] == null
            ? null
            : DateTime.tryParse(j['dernierRevu'] as String),
        echecs: ((j['echecs'] ?? 0) as num).toInt(),
      );
}

/// Un mot de VOCABULAIRE d'anglais (kholles), revise facon Anki dans le
/// sens PRODUCTION : on voit le francais, on doit sortir l'anglais — c'est
/// ce qui compte en colle. [pourColle] : a savoir absolument pour la
/// prochaine kholle (la veille, le tableau de bord le rappelle).
class MotVocab {
  String id;
  String francais;
  String anglais;
  // Prononciation, contexte, faux-ami...
  String remarque;
  // Nom de la LISTE (feuille de voc du prof, theme...) : le voc s'organise
  // par listes, et une kholle d'anglais peut exiger telle(s) liste(s).
  String liste;
  bool pourColle;
  // Repetition espacee (memes regles que les chapitres).
  int intervalleJours;
  DateTime? prochaineRevision;
  DateTime? dernierRevu;
  int echecs;

  MotVocab({
    String? id,
    required this.francais,
    required this.anglais,
    this.remarque = '',
    this.liste = '',
    this.pourColle = false,
    this.intervalleJours = 1,
    this.prochaineRevision,
    this.dernierRevu,
    this.echecs = 0,
  }) : id = id ?? _newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'francais': francais,
        'anglais': anglais,
        'remarque': remarque,
        'liste': liste,
        'pourColle': pourColle,
        'intervalleJours': intervalleJours,
        'prochaineRevision': prochaineRevision?.toIso8601String(),
        'dernierRevu': dernierRevu?.toIso8601String(),
        'echecs': echecs,
      };

  static MotVocab fromJson(Map<String, dynamic> j) => MotVocab(
        id: j['id'] as String?,
        francais: (j['francais'] ?? '') as String,
        anglais: (j['anglais'] ?? '') as String,
        remarque: (j['remarque'] ?? '') as String,
        liste: (j['liste'] ?? '') as String,
        pourColle: (j['pourColle'] ?? false) as bool,
        intervalleJours: ((j['intervalleJours'] ?? 1) as num).toInt(),
        prochaineRevision: j['prochaineRevision'] == null
            ? null
            : DateTime.tryParse(j['prochaineRevision'] as String),
        dernierRevu: j['dernierRevu'] == null
            ? null
            : DateTime.tryParse(j['dernierRevu'] as String),
        echecs: ((j['echecs'] ?? 0) as num).toInt(),
      );
}

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

/// Epreuves ORALES d'une banque de concours pour une filiere de 2e annee
/// (liste indicative — la saisie libre reste possible). Sert au bouton
/// « Générer mon planning d'oraux » : les dates/salles se remplissent
/// apres l'admissibilite.
List<String> kEpreuvesOralesPour(String filiere, String concours) {
  final f = filiere.toUpperCase();
  final c = concours.toLowerCase();
  // Matiere « sciences » selon la filiere.
  final sciences = switch (f) {
    'MP' || 'MPI' => ['Maths', 'Physique'],
    'PC' => ['Maths', 'Physique-Chimie'],
    'PSI' => ['Maths', 'Physique-Chimie', 'SII'],
    'PT' => ['Maths', 'Physique', 'SII (manip)'],
    _ => ['Maths', 'Physique'],
  };
  if (c.contains('ccinp')) {
    return [...sciences, 'TIPE', 'Anglais'];
  }
  if (c.contains('centrale')) {
    return [...sciences, if (f == 'PSI' || f == 'PT') 'SII (manip)', 'TIPE', 'Anglais'];
  }
  if (c.contains('mines-ponts') || c == 'mines ponts') {
    return [...sciences, 'TIPE', 'Anglais', 'Français'];
  }
  if (c.contains('x-ens') || c.contains('polytechnique')) {
    return [...sciences, 'TIPE', 'ADS', 'Anglais', 'Français'];
  }
  if (c.contains('mines-télécom') || c.contains('mines-telecom')) {
    return [...sciences, 'Entretien', 'Anglais'];
  }
  if (c.contains('e3a')) {
    return [...sciences, 'TIPE', 'Anglais'];
  }
  // Banque inconnue : le socle commun.
  return [...sciences, 'TIPE', 'Anglais'];
}

/// Un RESULTAT d'epreuve ecrite d'un concours deja passe (3/2 devenu 5/2) :
/// la note, le coefficient, et si on la connait la BARRE (admissibilite ou
/// moyenne). C'est la donnee la plus precieuse d'une 5/2 : elle dit ou se
/// perdent reellement les points, et pilote les priorites de matieres.
class ResultatConcours {
  String id;
  String concours;
  String epreuve; // 'Maths 1', 'Physique-Chimie', 'Français'...
  String matiere; // matiere de l'app a laquelle rattacher l'epreuve
  int annee;
  double? note; // /20
  double? barre; // barre d'admissibilite (ou moyenne) sur la MEME echelle
  double coeff;

  ResultatConcours({
    String? id,
    required this.concours,
    required this.epreuve,
    required this.matiere,
    required this.annee,
    this.note,
    this.barre,
    this.coeff = 1,
  }) : id = id ?? _newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'concours': concours,
        'epreuve': epreuve,
        'matiere': matiere,
        'annee': annee,
        'note': note,
        'barre': barre,
        'coeff': coeff,
      };

  static ResultatConcours fromJson(Map<String, dynamic> j) => ResultatConcours(
        id: j['id'] as String?,
        concours: (j['concours'] ?? '') as String,
        epreuve: (j['epreuve'] ?? '') as String,
        matiere: (j['matiere'] ?? '') as String,
        annee: ((j['annee'] ?? 2020) as num).toInt(),
        note: (j['note'] as num?)?.toDouble(),
        barre: (j['barre'] as num?)?.toDouble(),
        coeff: ((j['coeff'] ?? 1) as num).toDouble(),
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
