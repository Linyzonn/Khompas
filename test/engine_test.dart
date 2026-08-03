import 'package:flutter_test/flutter_test.dart';
import 'package:khompas/ai_extractor.dart';
import 'package:khompas/engine.dart';
import 'package:khompas/ics.dart';
import 'package:khompas/vacances_officielles.dart';
import 'package:khompas/methodes.dart';
import 'package:khompas/models.dart';
import 'package:khompas/store.dart';

/// AppModel est un singleton : chaque test repart d'un etat vierge.
void reset(AppModel m) {
  m.colles = [];
  m.ds = [];
  m.chapitres = [];
  m.routines = [];
  m.devoirs = [];
  m.seances = [];
  m.bilans = [];
  m.evenements = [];
  m.sansCours = [];
  m.erreurs = [];
  m.annales = [];
  m.oraux = [];
  m.resultatsConcours = [];
  m.oeuvres = [];
  m.joursOff = [];
  m.zoneVacances = '';
  m.modeOraux = false;
  m.refSemaineA = null;
  m.dateConcours = null;
  m.prios = {};
  m.heureLimiteMin = null;
}

void main() {
  // save() passe par les canaux natifs (fichier) : en test ils echouent
  // silencieusement (try/catch), mais le binding doit exister.
  TestWidgetsFlutterBinding.ensureInitialized();
  final m = AppModel.instance;

  setUp(() => reset(m));

  // ---------- Echeances ----------

  test('khôlle imminente : la matière passe en tête avec la bonne raison', () {
    // 26 h : TOUJOURS demain, quelle que soit l'heure du test (20 h pouvait
    // retomber le meme jour pour un test lance avant 4 h du matin).
    m.colles.add(Colle(
        matiere: 'Maths', start: DateTime.now().add(const Duration(hours: 26))));
    m.chapitres
        .add(Chapitre(matiere: 'Anglais', nom: 'Vocab', etape: 1, maitrise: 2));
    final s = suggere(m, 120);
    expect(s, isNotEmpty);
    expect(s.first.matiere, 'Maths');
    expect(s.first.raison.toLowerCase(), contains('demain'));
  });

  test('devoir en retard (≤ 5 j) : urgence maximale, raison EN RETARD', () {
    final now = DateTime.now();
    m.devoirs.add(Devoir(
      matiere: 'Physique-Chimie',
      dateRendu: now.subtract(const Duration(days: 2)),
      dateDonne: now.subtract(const Duration(days: 9)),
    ));
    final s = suggere(m, 120);
    expect(s.first.matiere, 'Physique-Chimie');
    expect(s.first.raison, contains('EN RETARD'));
  });

  // ---------- Jachere ----------

  test('jachère : une matière délaissée 8 j remonte devant une matière '
      'travaillée hier', () {
    final now = DateTime.now();
    m.chapitres
        .add(Chapitre(matiere: 'Français', nom: 'Thème', etape: 2, maitrise: 3));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 2, maitrise: 3));
    m.seances.add(Seance(
        matiere: 'Français',
        date: now.subtract(const Duration(days: 8)),
        minutes: 60));
    m.seances.add(Seance(
        matiere: 'Maths',
        date: now.subtract(const Duration(days: 1)),
        minutes: 60));
    final s = suggere(m, 120);
    expect(s.first.matiere, 'Français');
    expect(s.first.raison, contains('Pas travaillée'));
  });

  // ---------- Fragilite : moyenne + minimum ----------

  test('fragilité : un chapitre à zéro caché parmi de bons pèse plus '
      'qu\'une moyenne uniforme', () {
    for (final (nom, maitrise) in [('A1', 4), ('A2', 4), ('A3', 0)]) {
      m.chapitres.add(
          Chapitre(matiere: 'Chimie', nom: nom, etape: 2, maitrise: maitrise));
    }
    for (final (nom, maitrise) in [('B1', 3), ('B2', 3), ('B3', 3)]) {
      m.chapitres.add(
          Chapitre(matiere: 'SII', nom: nom, etape: 2, maitrise: maitrise));
    }
    final s = suggere(m, 120);
    expect(s.first.matiere, 'Chimie');
    // Le chapitre jamais consolide est signale par ⚠ dans le contenu.
    expect(s.first.titre, contains('⚠'));
  });

  // ---------- Repetition espacee ----------

  test('rappel dû aujourd\'hui : bloc de 15 min en tête, marqué rappel', () {
    final now = DateTime.now();
    m.chapitres.add(Chapitre(
      matiere: 'Maths',
      nom: 'Séries entières',
      etape: 2,
      maitrise: 3,
      prochaineRevision: DateTime(now.year, now.month, now.day),
      intervalleJours: 4,
    ));
    expect(rappelsDus(m).length, 1);
    final s = suggere(m, 120);
    expect(s.first.rappel, isTrue);
    expect(s.first.minutes, 15);
    expect(s.first.titre, contains('Séries entières'));
    expect(s.first.consigne, isNotEmpty);
  });

  test('evaluerRevision : facile double x2,5 avec plafond 45 j, '
      'difficile resserre à 2 j', () {
    final c = Chapitre(
        matiere: 'Maths',
        nom: 'X',
        etape: 2,
        maitrise: 3,
        prochaineRevision: DateTime.now(),
        intervalleJours: 40);
    m.chapitres.add(c);
    m.evaluerRevision(c.id, 'facile');
    expect(c.intervalleJours, 45); // 40 x 2,5 = 100 -> plafonne
    expect(c.maitrise, 4);
    expect(c.prochaineRevision, isNotNull);
    m.evaluerRevision(c.id, 'difficile');
    expect(c.intervalleJours, 2);
    expect(c.maitrise, 3);
  });

  // ---------- DM du jour ----------

  test('DM distribué aujourd\'hui : suggestion « lis-le ce soir »', () {
    final now = DateTime.now();
    m.devoirs.add(Devoir(
      matiere: 'Maths',
      titre: 'DM 4',
      dateRendu: now.add(const Duration(days: 7)),
      dateDonne: now,
    ));
    final s = suggere(m, 120);
    expect(s.any((x) => x.titre.contains('Lis le DM 4')), isTrue);
  });

  // ---------- EDT : parite A/B et plages sans cours ----------

  test('routinesLe : respecte les semaines A/B et les plages sans cours', () {
    final now = DateTime.now();
    m.refSemaineA = mondayOf(now); // cette semaine est une semaine A
    m.routines.add(Routine(
        titre: 'Maths', jour: now.weekday, debutMin: 480, matiere: 'Maths',
        semaines: 1));
    m.routines.add(Routine(
        titre: 'TP info', jour: now.weekday, debutMin: 600, matiere: 'Info',
        semaines: 2));
    expect(m.routinesLe(now).map((r) => r.titre).toList(), ['Maths']);
    expect(
        m
            .routinesLe(now.add(const Duration(days: 7)))
            .map((r) => r.titre)
            .toList(),
        ['TP info']);
    m.sansCours.add(PlageSansCours(titre: 'Vacances', debut: now, fin: now));
    expect(m.routinesLe(now), isEmpty);
  });

  // ---------- Mode revisions concours ----------

  test('mode révisions : rappels dus d\'abord, puis alternance des matières',
      () {
    final now = DateTime.now();
    m.dateConcours = now.add(const Duration(days: 30));
    m.chapitres.addAll([
      Chapitre(matiere: 'Maths', nom: 'M1', etape: 2, maitrise: 0),
      Chapitre(matiere: 'Maths', nom: 'M2', etape: 2, maitrise: 1),
      Chapitre(matiere: 'Physique-Chimie', nom: 'P1', etape: 2, maitrise: 2),
      Chapitre(matiere: 'Physique-Chimie', nom: 'P2', etape: 2, maitrise: 3),
    ]);
    final s = suggere(m, 120);
    expect(s.length, greaterThanOrEqualTo(2));
    expect(s.first.raison, contains('J-'));
    // Interleaving : deux matieres differentes en tete, pas deux fois la meme.
    expect(s[0].matiere == s[1].matiere, isFalse);

    // Un chapitre du a la revision espacee passe devant tout le monde.
    final du = Chapitre(
      matiere: 'SII',
      nom: 'Cinématique',
      etape: 2,
      maitrise: 4,
      prochaineRevision: DateTime(now.year, now.month, now.day),
    );
    m.chapitres.add(du);
    final s2 = suggere(m, 120);
    expect(s2.first.chapitreId, du.id);
    expect(s2.first.rappel, isTrue);
  });

  test('date de concours passée : retour au mode normal', () {
    m.dateConcours = DateTime.now().subtract(const Duration(days: 1));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 1, maitrise: 2));
    final s = suggere(m, 120);
    expect(s, isNotEmpty);
    expect(s.first.raison, isNot(contains('J-')));
  });

  // ---------- Consignes ----------

  test('consigneDe : jamais vide, quelle que soit la matière ou le type', () {
    for (final mat in [
      'Maths',
      'Physique-Chimie',
      'SII',
      'Info',
      'Anglais',
      'Français',
      'Histoire-Géo' // matiere inconnue -> table par defaut
    ]) {
      for (final type in [
        'rappel',
        'consolider',
        'kholle',
        'ds',
        'fond',
        'revision'
      ]) {
        expect(consigneDe(mat, type), isNotEmpty,
            reason: '$mat / $type devrait avoir une consigne');
      }
    }
  });

  // ---------- Cahier d'erreurs ----------

  test('épreuve imminente + erreurs non refaites : bloc « refais tes '
      'erreurs » en tête', () {
    final now = DateTime.now();
    m.ds.add(Ds(
        matiere: 'Maths',
        date: DateTime(now.year, now.month, now.day)
            .add(const Duration(days: 1))));
    m.erreurs.add(Erreur(
        matiere: 'Maths', texte: 'Oubli du cas λ = 0', type: 'Méthode'));
    m.erreurs.add(Erreur(
        matiere: 'Maths', texte: 'Signe', type: 'Calcul', refaite: true));
    final s = suggere(m, 120);
    expect(s.first.titre, contains('📕'));
    expect(s.first.titre, contains('1 à revoir')); // seule la non-refaite
    expect(s.first.matiere, 'Maths');
  });

  // ---------- Annales (mode revisions, J-45) ----------

  test('mode révisions à J-45 : une annale non faite entre dans le plan, '
      'matière la moins couverte d\'abord', () {
    m.dateConcours = DateTime.now().add(const Duration(days: 30));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 2, maitrise: 3));
    m.annales.add(
        Annale(concours: 'CCINP', matiere: 'Maths', annee: 2024));
    m.annales.add(Annale(
        concours: 'CCINP', matiere: 'Physique-Chimie', annee: 2023,
        fait: true));
    // Budget de soir de semaine -> c'est la version "une PARTIE" qui sort
    // (l'epreuve entiere est reservee aux gros budgets — teste plus bas).
    final s = suggere(m, 120);
    expect(s.first.titre, contains('CCINP 2024'));
    expect(s.first.matiere, 'Maths');
  });

  // ---------- Mode oraux ----------

  test('mode oraux : l\'oral daté imminent en tête, puis rotation des '
      'autres épreuves', () {
    final now = DateTime.now();
    m.modeOraux = true;
    m.oraux.addAll([
      EpreuveOrale(
          concours: 'CCINP',
          epreuve: 'Maths',
          date: DateTime(now.year, now.month, now.day)
              .add(const Duration(days: 3))),
      EpreuveOrale(concours: 'CCINP', epreuve: 'Anglais'),
      EpreuveOrale(concours: 'Centrale-Supélec', epreuve: 'TIPE'),
    ]);
    final s = suggere(m, 120);
    expect(s, isNotEmpty);
    expect(s.first.matiere, 'Maths');
    expect(s.first.raison, contains('J-3'));
    expect(s.first.consigne, isNotEmpty);
    // La rotation enchaine sur une AUTRE epreuve.
    expect(s.length, greaterThanOrEqualTo(2));
    expect(['Anglais', 'TIPE'], contains(s[1].matiere));
    // La consigne TIPE est specifique (pas la table generique).
    expect(consigneOral('TIPE'), contains('TIPE'));
  });

  // ---------- Normalisation et fusion des matieres ----------

  test('normaliseMatiere : plus de doublons Maths/Mathématiques, '
      'Francais/Français…', () {
    expect(normaliseMatiere('Mathématiques'), 'Maths');
    expect(normaliseMatiere('  maths '), 'Maths');
    expect(normaliseMatiere('francais'), 'Français');
    expect(normaliseMatiere('FRANÇAIS'), 'Français');
    expect(normaliseMatiere('physique-chimie'), 'Physique-Chimie');
    expect(normaliseMatiere('Physique'), 'Physique'); // PAS fusionnee avec PC
    expect(normaliseMatiere('informatique'), 'Info');
    expect(normaliseMatiere('s2i'), 'SII');
    // Matiere inconnue : gardee telle quelle, majuscule assuree.
    expect(normaliseMatiere('géographie'), 'Géographie');
    // LV1 volontairement PAS auto-fusionnee (outil manuel des Reglages).
    expect(normaliseMatiere('LV1'), 'LV1');
  });

  test('fusionnerMatieres : tout passe de la source vers la cible', () {
    m.colles.add(Colle(matiere: 'LV1', start: DateTime.now()));
    m.seances.add(
        Seance(matiere: 'LV1', date: DateTime.now(), minutes: 30));
    m.chapitres
        .add(Chapitre(matiere: 'Anglais', nom: 'Vocab', etape: 1));
    m.prios['LV1'] = 3;
    m.prios['Anglais'] = 1;
    m.fusionnerMatieres('LV1', 'Anglais');
    expect(m.colles.first.matiere, 'Anglais');
    expect(m.seances.first.matiere, 'Anglais');
    expect(m.prios.containsKey('LV1'), isFalse);
    expect(m.prios['Anglais'], 3); // la prio la plus haute gagne
    expect(m.matieres, ['Anglais']);
  });

  // ---------- Bilan : chapitre fini vs en plein dedans ----------

  test('setBilan chapitre NON termine : entame seulement, ni étape ni '
      'révision espacée', () {
    final c = Chapitre(matiere: 'Maths', nom: 'Séries', etape: 0);
    m.chapitres.add(c);
    m.setBilan(
      Bilan(
          jour: DateTime.now(),
          routineId: 'r1',
          matiere: 'Maths',
          type: 'Cours',
          chapitreId: c.id),
      chapitreTermine: false,
    );
    expect(c.entame, isTrue);
    expect(c.etape, 0);
    expect(c.prochaineRevision, isNull);
    // Le prof finit le chapitre au cours suivant :
    m.setBilan(
      Bilan(
          jour: DateTime.now().add(const Duration(days: 2)),
          routineId: 'r1',
          matiere: 'Maths',
          type: 'Cours',
          chapitreId: c.id),
    );
    expect(c.entame, isFalse);
    expect(c.etape, 1);
    expect(c.prochaineRevision, isNotNull);
    expect(c.intervalleJours, 1);
  });

  // ---------- Heure limite de sommeil (y compris apres minuit) ----------

  test('budgetSoir : limite 23 h opérante AVANT et APRÈS minuit', () {
    // 18h00, limite 23h -> 5 h disponibles, plafonnées à la durée choisie.
    expect(budgetSoir(minutes: 120, limiteMin: 23 * 60, nowMin: 18 * 60), 120);
    expect(budgetSoir(minutes: 600, limiteMin: 23 * 60, nowMin: 18 * 60), 300);
    // 00h30, limite 23h : la limite est DÉPASSÉE -> 0 (message sommeil).
    expect(budgetSoir(minutes: 120, limiteMin: 23 * 60, nowMin: 30), 0);
    // Limite 0h30 : à 22h il reste 2 h 30 ; à 1h du matin, 0.
    expect(budgetSoir(minutes: 600, limiteMin: 30, nowMin: 22 * 60), 150);
    expect(budgetSoir(minutes: 120, limiteMin: 30, nowMin: 60), 0);
    // Pas de limite -> la durée choisie.
    expect(budgetSoir(minutes: 120, limiteMin: null, nowMin: 30), 120);
  });

  // ---------- Parseur COLLES (le plus critique du produit) ----------

  test('parseExtraction : fences, heure 16:30, durée et salle relevées', () {
    const rep = '''
Voici le résultat :
```json
{"colles": [
  {"matiere": "Maths", "kholleur": "M. X", "salle": "12", "date": "2026-09-17", "heure": "16:30", "duree_min": 55},
  {"matiere": "Anglais", "date": "2026-09-18", "heure": "17:00"}
], "avertissements": ["roulement appliqué"]}
```
''';
    final r = parseExtraction(rep);
    expect(r.colles.length, 2);
    expect(r.colles.first.start.hour, 16);
    expect(r.colles.first.start.minute, 30);
    expect(r.colles.first.dureeMin, 55);
    expect(r.colles.first.salle, '12');
    expect(r.avertissements, contains('roulement appliqué'));
  });

  test('parseExtraction : JSON tronqué -> sauve les créneaux complets, '
      'créneau malformé ignoré', () {
    const tronque =
        '{"colles":[{"matiere":"Maths","date":"2026-09-17","heure":"16:00"},'
        '{"matiere":"Sans date"},'
        '{"matiere":"Phys'; // coupé net (maxOutputTokens)
    final r = parseExtraction(tronque);
    expect(r.colles.length, 1);
    expect(r.colles.first.matiere, 'Maths');
  });

  // ---------- Libelles d'echeance ----------

  test('khôlle du jour : « AUJOURD\'HUI », pas « demain » ni « EN RETARD »',
      () {
    final now = DateTime.now();
    // Une kholle plus tard dans la journee (ou tot le matin : le test doit
    // passer a toute heure — on prend 23h59 du jour meme).
    m.colles.add(Colle(
        matiere: 'Maths',
        start: DateTime(now.year, now.month, now.day, 23, 58)));
    final s = suggere(m, 120);
    expect(s.first.raison, contains('AUJOURD\'HUI'));
    expect(s.first.raison, isNot(contains('RETARD')));
  });

  test('DM à rendre AUJOURD\'HUI : plus jamais « EN RETARD » le jour J', () {
    final now = DateTime.now();
    m.devoirs.add(Devoir(
        matiere: 'Physique',
        dateRendu: DateTime(now.year, now.month, now.day),
        dateDonne: now.subtract(const Duration(days: 7))));
    final s = suggere(m, 120);
    expect(s.first.raison, contains('AUJOURD\'HUI'));
  });

  // ---------- Travail impose = tache cochable ----------

  test('DM proche : la suggestion EST la tâche (titre + remarque + '
      'devoirId)', () {
    final now = DateTime.now();
    final d = Devoir(
        matiere: 'Maths',
        titre: 'DM 3',
        dateRendu: now.add(const Duration(days: 5)),
        dateDonne: now.subtract(const Duration(days: 2)),
        remarque: 'exos 1 à 4');
    m.devoirs.add(d);
    final s = suggere(m, 120);
    final sug = s.firstWhere((x) => x.matiere == 'Maths');
    expect(sug.titre, contains('Avance DM 3'));
    expect(sug.titre, contains('exos 1 à 4'));
    expect(sug.devoirId, d.id);
  });

  // ---------- Jour libre : plus de matieres ----------

  test('jour libre (EDT rempli mais rien aujourd\'hui) + gros budget : '
      '4 matières retenues', () {
    final now = DateTime.now();
    // Une routine sur un AUTRE jour que celui du test -> aujourd'hui libre.
    final autreJour = now.weekday == 7 ? 1 : now.weekday + 1;
    m.routines.add(Routine(titre: 'Maths', jour: autreJour, debutMin: 480));
    for (final mat in ['Maths', 'Physique', 'Anglais', 'Français']) {
      m.chapitres
          .add(Chapitre(matiere: mat, nom: 'Ch $mat', etape: 2, maitrise: 2));
    }
    final s = suggere(m, 300);
    expect(s.map((x) => x.matiere).toSet().length, greaterThanOrEqualTo(4));
  });

  // ---------- Vacances : creneau DM etale, cadence annoncee ----------

  test('vacances + 2 DM : un créneau DM apparaît avec sa cadence', () {
    final now = DateTime.now();
    m.sansCours.add(PlageSansCours(
        titre: 'Vacances',
        debut: now.subtract(const Duration(days: 2)),
        fin: now.add(const Duration(days: 10))));
    m.devoirs.add(Devoir(
        matiere: 'Maths',
        titre: 'DM vacances',
        dateRendu: now.add(const Duration(days: 4)),
        dateDonne: now.subtract(const Duration(days: 1))));
    m.devoirs.add(Devoir(
        matiere: 'Physique',
        titre: 'DM 5',
        dateRendu: now.add(const Duration(days: 6)),
        dateDonne: now.subtract(const Duration(days: 1))));
    final s = suggere(m, 180);
    expect(s.any((x) => x.titre.contains('Créneau DM')), isTrue);
  });

  // ---------- Annales realistes ----------

  test('mode révisions : annale ENTIÈRE seulement à gros budget, sinon '
      'une PARTIE', () {
    m.dateConcours = DateTime.now().add(const Duration(days: 30));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 2, maitrise: 3));
    m.annales
        .add(Annale(concours: 'CCINP', matiere: 'Maths', annee: 2024));
    final soir = suggere(m, 120);
    expect(soir.any((x) => x.titre.contains('PARTIE')), isTrue);
    final weekend = suggere(m, 300);
    expect(weekend.any((x) => x.titre.contains('EN CONDITIONS')), isTrue);
  });

  test('annale faite récemment avec ressenti moyen : la CORRECTION ACTIVE '
      'passe devant', () {
    m.dateConcours = DateTime.now().add(const Duration(days: 30));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 2, maitrise: 3));
    m.annales.add(Annale(
        concours: 'CCINP',
        matiere: 'Maths',
        annee: 2023,
        fait: true,
        ressenti: 2,
        dateFait: DateTime.now().subtract(const Duration(days: 1))));
    m.annales.add(Annale(concours: 'CCINP', matiere: 'Maths', annee: 2024));
    final s = suggere(m, 120);
    expect(s.any((x) => x.titre.contains('Correction active')), isTrue);
    expect(s.any((x) => x.titre.contains('PARTIE')), isFalse);
  });

  // ---------- Parseur DS (tolerance + coefficient) ----------

  test('parseDsExtraction : fences markdown, texte autour, coeff facultatif',
      () {
    const reponse = '''
Voici le résultat demandé :
```json
{"ds": [
  {"matiere": "Maths", "titre": "DS 3", "date": "2026-03-14", "coeff": 2},
  {"matiere": "Anglais", "date": "2026-03-21"}
], "avertissements": []}
```
''';
    final r = parseDsExtraction(reponse);
    expect(r.ds.length, 2);
    expect(r.ds.first.titre, 'DS 3');
    expect(r.ds.first.coeff, 2.0);
    expect(r.ds[1].titre, 'DS'); // titre par defaut
    expect(r.ds[1].coeff, 1.0); // coeff par defaut
  });

  // ---------- DS du jour ----------

  test('un DS AUJOURD\'HUI (daté à minuit) reste visible dans le scoring', () {
    final now = DateTime.now();
    // Les DS sont dates a minuit : a 18 h, l'ancien code (isBefore(now))
    // ecartait le DS du jour et la branche AUJOURD'HUI etait morte.
    m.ds.add(Ds(
        matiere: 'Physique',
        titre: 'DS 4',
        date: DateTime(now.year, now.month, now.day),
        note: null));
    final s = suggere(m, 120);
    expect(s.any((x) => x.matiere == 'Physique'), isTrue);
    expect(
        s.firstWhere((x) => x.matiere == 'Physique').raison,
        contains('AUJOURD\'HUI'));
  });

  // ---------- Repetition espacee : verdicts et memoire des echecs ----------

  test('"ça va" multiplie par 1,7 (et non 2) — progression douce', () {
    final c = Chapitre(
        matiere: 'Maths',
        nom: 'Suites',
        etape: 1,
        intervalleJours: 10,
        prochaineRevision: DateTime.now());
    m.chapitres.add(c);
    m.evaluerRevision(c.id, 'cava');
    expect(c.intervalleJours, 17);
  });

  test('chapitre chroniquement difficile : la progression ralentit à x1,5',
      () {
    final c = Chapitre(
        matiere: 'Maths',
        nom: 'Intégrales',
        etape: 1,
        intervalleJours: 8,
        prochaineRevision: DateTime.now());
    m.chapitres.add(c);
    m.evaluerRevision(c.id, 'difficile'); // echecs = 1, intervalle = 2
    m.evaluerRevision(c.id, 'difficile'); // echecs = 2, intervalle = 2
    m.evaluerRevision(c.id, 'cava'); // x1,5 au lieu de x1,7
    expect(c.intervalleJours, 3);
    // Un "facile" efface la memoire des echecs.
    m.evaluerRevision(c.id, 'facile');
    expect(c.echecs, 0);
  });

  test('révision en retard (< 7 j) : la suivante s\'ancre sur la date DUE',
      () {
    final now = DateTime.now();
    final due = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 3));
    final c = Chapitre(
        matiere: 'Maths',
        nom: 'Espaces vectoriels',
        etape: 1,
        intervalleJours: 10,
        prochaineRevision: due);
    m.chapitres.add(c);
    m.evaluerRevision(c.id, 'cava'); // 10 -> 17 j, ancre sur la date due
    expect(c.prochaineRevision, due.add(Duration(days: c.intervalleJours)));
  });

  test('recalibrerChapitres : maîtrise plafonnée à 2, révision demain', () {
    final c = Chapitre(
        matiere: 'Physique',
        nom: 'Ondes',
        etape: 3,
        maitrise: 4,
        intervalleJours: 30);
    m.chapitres.add(c);
    m.recalibrerChapitres([c.id]);
    expect(c.maitrise, 2);
    expect(c.intervalleJours, 1);
    final now = DateTime.now();
    expect(
        c.prochaineRevision,
        DateTime(now.year, now.month, now.day)
            .add(const Duration(days: 1)));
  });

  test('demarrerEspacement : étape ≥ 1, révision demain, dernierRevu posé',
      () {
    final c = Chapitre(matiere: 'Chimie', nom: 'Cinétique', etape: 0);
    m.chapitres.add(c);
    m.demarrerEspacement(c.id);
    expect(c.etape, 1);
    expect(c.intervalleJours, 1);
    expect(c.prochaineRevision, isNotNull);
    expect(c.dernierRevu, isNotNull);
  });

  // ---------- Seuil J-90 du mode revisions ----------

  test('date de concours lointaine (> 90 j) : le mode normal continue', () {
    m.dateConcours = DateTime.now().add(const Duration(days: 200));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Suites', etape: 2, maitrise: 2));
    // Une khôlle demain doit toujours apparaitre : en mode revisions
    // premature, elle disparaissait pendant des mois.
    m.colles.add(Colle(
        matiere: 'Physique',
        start: DateTime.now().add(const Duration(hours: 26))));
    final s = suggere(m, 120);
    expect(s.any((x) => x.matiere == 'Physique'), isTrue,
        reason: 'la khôlle de demain doit rester dans le plan');
    expect(s.any((x) => x.titre.startsWith('Réviser :')), isFalse,
        reason: 'pas de rotation concours a J-200');
  });

  test('mode révisions : une khôlle imminente garde sa place dans le plan',
      () {
    m.dateConcours = DateTime.now().add(const Duration(days: 30));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Suites', etape: 2, maitrise: 2));
    m.colles.add(Colle(
        matiere: 'Anglais',
        programme: 'Press review',
        start: DateTime.now().add(const Duration(hours: 26))));
    final s = suggere(m, 120);
    expect(s.any((x) => x.titre.contains('khôlle')), isTrue);
  });

  // ---------- Rotation des DM de vacances ----------

  test('vacances + 2 DM : les créneaux tournent entre les DM', () {
    final now = DateTime.now();
    m.sansCours.add(PlageSansCours(
      titre: 'Vacances',
      debut: DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 2)),
      fin: DateTime(now.year, now.month, now.day).add(const Duration(days: 12)),
    ));
    m.devoirs.add(Devoir(
        matiere: 'Maths',
        titre: 'DM 5',
        dateRendu: now.add(const Duration(days: 10)),
        dateDonne: now.subtract(const Duration(days: 1))));
    m.devoirs.add(Devoir(
        matiere: 'Physique',
        titre: 'DM 3',
        dateRendu: now.add(const Duration(days: 12)),
        dateDonne: now.subtract(const Duration(days: 1))));
    // Cadence 1 (10 jours / 4 creneaux vises) : un creneau par jour, servi
    // alternativement a chaque DM selon le jour. On verifie simplement
    // qu'un creneau existe et cible l'un des deux DM (la rotation depend
    // du jour du test).
    final s = suggere(m, 240);
    final creneau = s.where((x) => x.titre.contains('Créneau DM')).toList();
    expect(creneau, isNotEmpty);
    expect(
        creneau.first.titre.contains('DM 5') ||
            creneau.first.titre.contains('DM 3'),
        isTrue);
  });

  // ---------- Pliage .ics (RFC 5545) ----------

  test('plieIcs : aucune ligne ne dépasse 75 octets, contenu preservé', () {
    final longue = 'DESCRIPTION:${'Programme de colle très détaillé — ' * 8}';
    final pliee = plieIcs(longue);
    for (final ligne in pliee.split('\r\n')) {
      // Longueur en OCTETS UTF-8 (les accents comptent double).
      final octets = ligne.runes.fold<int>(0, (t, r) => t + utf8Len(r));
      expect(octets, lessThanOrEqualTo(75));
    }
    // Depliage : retirer les "\r\n " redonne exactement la ligne d'origine.
    expect(pliee.replaceAll('\r\n ', ''), longue);
  });

  test('buildIcs : un long programme de colle produit un fichier plié', () {
    final ics = buildIcs([
      Colle(
        matiere: 'Maths',
        start: DateTime(2026, 3, 12, 16),
        programme: 'Chapitre 12 : espaces euclidiens, projecteurs '
            'orthogonaux, adjoint, réduction des endomorphismes symétriques, '
            'formes quadratiques, et toutes les démonstrations exigibles '
            'du programme officiel de la semaine.',
      ),
    ]);
    for (final ligne in ics.split('\r\n')) {
      final octets = ligne.runes.fold<int>(0, (t, r) => t + utf8Len(r));
      expect(octets, lessThanOrEqualTo(75));
    }
  });

  // ---------- Mode ETE (grandes vacances, 5/2) ----------
  // Horloge INJECTEE partout : ces tests sont deterministes quel que soit
  // le jour ou l'heure ou ils tournent.

  PlageSansCours plageEte(DateTime debut, DateTime fin) =>
      PlageSansCours(titre: 'Grandes vacances', debut: debut, fin: fin, type: 'ete');

  test('plage été : le plan bascule en réactivation, prios en premier', () {
    // Mardi 4 août 2026, plage été jusqu'au 31 août.
    final now = DateTime(2026, 8, 4, 10);
    m.sansCours.add(plageEte(DateTime(2026, 7, 1), DateTime(2026, 8, 31)));
    m.chapitres.add(
        Chapitre(matiere: 'Maths', nom: 'Suites', etape: 2, maitrise: 3));
    m.chapitres.add(
        Chapitre(matiere: 'SII', nom: 'Asservissements', etape: 2, maitrise: 3));
    m.prios = {'SII': 3, 'Maths': 1};
    final s = suggere(m, 180, maintenant: now);
    expect(s, isNotEmpty);
    expect(s.first.titre, startsWith('Réactiver :'));
    // Le bilan de concours (via prios) pilote l'ordre : SII d'abord.
    expect(s.first.matiere, 'SII');
    expect(s.first.raison, contains('Été'));
  });

  test('plage été · dimanche : un seul bloc léger facultatif', () {
    final now = DateTime(2026, 8, 2, 10); // un dimanche
    m.sansCours.add(plageEte(DateTime(2026, 7, 1), DateTime(2026, 8, 31)));
    m.chapitres.add(
        Chapitre(matiere: 'Maths', nom: 'Suites', etape: 2, maitrise: 2));
    m.chapitres.add(
        Chapitre(matiere: 'Physique-Chimie', nom: 'Ondes', etape: 2, maitrise: 2));
    final s = suggere(m, 240, maintenant: now);
    expect(s.length, 1);
    expect(s.first.minutes, 30);
    expect(s.first.raison.toLowerCase(), contains('repos'));
  });

  test('plage été · dernière semaine : message de remise en rythme', () {
    final now = DateTime(2026, 8, 27, 10); // jeudi, rentrée le 31
    m.sansCours.add(plageEte(DateTime(2026, 7, 1), DateTime(2026, 8, 31)));
    m.chapitres.add(
        Chapitre(matiere: 'Maths', nom: 'Suites', etape: 2, maitrise: 2));
    final s = suggere(m, 120, maintenant: now);
    expect(s.any((x) => x.raison.contains('Rentrée dans')), isTrue);
  });

  test('plage été : les rappels espacés dus passent en tête', () {
    final now = DateTime(2026, 8, 4, 10); // mardi
    m.sansCours.add(plageEte(DateTime(2026, 7, 1), DateTime(2026, 8, 31)));
    m.chapitres.add(Chapitre(
        matiere: 'Maths',
        nom: 'Suites',
        etape: 2,
        maitrise: 2,
        prochaineRevision: DateTime(2026, 8, 4)));
    m.chapitres.add(
        Chapitre(matiere: 'SII', nom: 'Asservissements', etape: 2, maitrise: 2));
    final s = suggere(m, 120, maintenant: now);
    expect(s.first.rappel, isTrue);
    expect(s.first.titre, contains('Suites'));
  });

  test('etalerReactivation : tout le programme réparti sur la plage', () {
    final now = DateTime(2026, 8, 4, 10);
    m.sansCours.add(plageEte(DateTime(2026, 7, 1), DateTime(2026, 8, 31)));
    for (var i = 0; i < 27; i++) {
      m.chapitres.add(Chapitre(
          matiere: i % 2 == 0 ? 'Maths' : 'SII',
          nom: 'Chapitre $i',
          etape: 1,
          maitrise: 2));
    }
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Pas vu', etape: 0, maitrise: 0));
    final n = m.etalerReactivation(maintenant: now);
    expect(n, 27); // les etape == 0 ne sont pas planifies
    // Toutes les revisions tombent entre demain et la fin de la plage.
    final fin = DateTime(2026, 8, 31);
    for (final c in m.chapitres.where((c) => c.etape > 0)) {
      expect(c.prochaineRevision, isNotNull);
      expect(c.prochaineRevision!.isAfter(DateTime(2026, 8, 4)), isTrue);
      expect(c.prochaineRevision!.isAfter(fin), isFalse);
      expect(c.intervalleJours, 1);
    }
    // Et elles sont REPARTIES, pas toutes le meme jour.
    final jours = m.chapitres
        .where((c) => c.etape > 0)
        .map((c) => c.prochaineRevision!.day)
        .toSet();
    expect(jours.length, greaterThan(5));
  });

  test('etalerReactivation sans plage été : ne fait rien', () {
    m.chapitres.add(
        Chapitre(matiere: 'Maths', nom: 'Suites', etape: 2, maitrise: 2));
    expect(m.etalerReactivation(maintenant: DateTime(2026, 8, 4)), 0);
    expect(m.chapitres.first.prochaineRevision, isNull);
  });

  // ---------- Bilan de concours (5/2) ----------

  test('deficitsConcours : coeff × points sous la barre, par matière', () {
    m.resultatsConcours.add(ResultatConcours(
        concours: 'CCINP', epreuve: 'Maths', matiere: 'Maths',
        annee: 2026, note: 6, barre: 10, coeff: 2)); // deficit 8
    m.resultatsConcours.add(ResultatConcours(
        concours: 'CCINP', epreuve: 'SII', matiere: 'SII',
        annee: 2026, note: 12, barre: 10, coeff: 3)); // au-dessus : 0
    m.resultatsConcours.add(ResultatConcours(
        concours: 'Centrale-Supélec', epreuve: 'Maths 1', matiere: 'Maths',
        annee: 2026, note: 8, barre: 11, coeff: 1)); // deficit 3
    final d = m.deficitsConcours();
    expect(d['Maths'], closeTo(11, 0.001)); // 8 + 3
    expect(d['SII'], 0);
  });

  test('appliquerPrioritesDepuisDeficits : le plus gros déficit passe à 3',
      () {
    m.resultatsConcours.add(ResultatConcours(
        concours: 'CCINP', epreuve: 'Maths', matiere: 'Maths',
        annee: 2026, note: 5, barre: 10, coeff: 2));
    m.resultatsConcours.add(ResultatConcours(
        concours: 'CCINP', epreuve: 'Physique', matiere: 'Physique-Chimie',
        annee: 2026, note: 9, barre: 10, coeff: 2));
    m.resultatsConcours.add(ResultatConcours(
        concours: 'CCINP', epreuve: 'Anglais', matiere: 'Anglais',
        annee: 2026, note: 14, barre: 10, coeff: 1));
    m.appliquerPrioritesDepuisDeficits();
    expect(m.prios['Maths'], 3);
    expect(m.prios['Anglais'], 1); // aucun point perdu
    expect(m.prios['Physique-Chimie'], greaterThanOrEqualTo(1));
    expect(m.prios['Maths']!, greaterThan(m.prios['Physique-Chimie']!));
  });

  // ---------- Retro-compatibilite du type de plage ----------

  test('PlageSansCours.fromJson sans type : été détecté, Toussaint non', () {
    final ete = PlageSansCours.fromJson({
      'titre': 'Vacances',
      'debut': '2026-07-04T00:00:00.000',
      'fin': '2026-08-31T00:00:00.000',
    });
    expect(ete.type, 'ete');
    final toussaint = PlageSansCours.fromJson({
      'titre': 'Toussaint',
      'debut': '2026-10-17T00:00:00.000',
      'fin': '2026-11-01T00:00:00.000',
    });
    expect(toussaint.type, 'vacances');
    // Round-trip : le type explicite est conserve.
    expect(PlageSansCours.fromJson(ete.toJson()).type, 'ete');
  });

  // ---------- Planning d'oraux par filiere ----------

  test('kEpreuvesOralesPour : épreuves PSI cohérentes par banque', () {
    final ccinp = kEpreuvesOralesPour('PSI', 'CCINP');
    expect(ccinp, containsAll(['Maths', 'Physique-Chimie', 'SII', 'TIPE']));
    final mines = kEpreuvesOralesPour('PSI', 'Mines-Ponts');
    expect(mines, contains('Français')); // Mines a un oral de francais
    final centrale = kEpreuvesOralesPour('PSI', 'Centrale-Supélec');
    expect(centrale, contains('SII (manip)'));
    // Une banque inconnue retourne au moins le socle sciences + TIPE.
    expect(kEpreuvesOralesPour('PSI', 'Banque mystère'), contains('TIPE'));
  });

  // ---------- Vacances officielles (parseur pur, pas de reseau) ----------

  test('plagesDepuisJson : mapping API -> plages, été borné au 31 août', () {
    const corps = '''
{"records": [
  {"fields": {"description": "Vacances de la Toussaint",
    "start_date": "2026-10-17T00:00:00+02:00",
    "end_date": "2026-11-02T00:00:00+01:00"}},
  {"fields": {"description": "Vacances d'Été",
    "start_date": "2027-07-06T00:00:00+02:00",
    "end_date": "2027-09-01T00:00:00+02:00"}},
  {"fields": {"description": "Pré-rentrée", "start_date": "2026-08-31T00:00:00+02:00"}}
]}
''';
    final plages = plagesDepuisJson(corps);
    expect(plages.length, 2); // la pre-rentree sans end_date est ignoree
    expect(plages.first.titre, 'Vacances de la Toussaint');
    expect(plages.first.type, 'vacances');
    final ete = plages.last;
    expect(ete.type, 'ete');
    // L'API fait courir l'été jusqu'à la rentrée suivante : borné.
    expect(ete.fin, DateTime(2027, 8, 31));
  });

  test('plageEnDouble : chevauchement détecté, plages disjointes acceptées',
      () {
    final existantes = [
      PlageSansCours(
          titre: 'Toussaint',
          debut: DateTime(2026, 10, 17),
          fin: DateTime(2026, 11, 2)),
    ];
    expect(
        plageEnDouble(
            PlageSansCours(
                titre: 'Vacances de la Toussaint',
                debut: DateTime(2026, 10, 18),
                fin: DateTime(2026, 11, 1)),
            existantes),
        isTrue);
    expect(
        plageEnDouble(
            PlageSansCours(
                titre: 'Noël',
                debut: DateTime(2026, 12, 19),
                fin: DateTime(2027, 1, 3)),
            existantes),
        isFalse);
  });

  // ---------- Oeuvres de francais ----------

  test('été : bloc lecture un jour sur deux, avec rythme de pages', () {
    m.sansCours.add(PlageSansCours(
        titre: 'Été',
        debut: DateTime(2026, 7, 1),
        fin: DateTime(2026, 8, 31),
        type: 'ete'));
    m.chapitres.add(
        Chapitre(matiere: 'Maths', nom: 'Suites', etape: 2, maitrise: 2));
    m.oeuvres.add(
        Oeuvre(titre: 'Le Rouge et le Noir', auteur: 'Stendhal', pages: 500));
    // On cherche deux jours de semaine consecutifs (hors dimanche) : la
    // lecture doit apparaitre sur exactement UN des deux (un jour sur 2).
    final j1 = DateTime(2026, 8, 4, 10); // mardi
    final j2 = DateTime(2026, 8, 5, 10); // mercredi
    bool aLecture(DateTime d) => suggere(m, 180, maintenant: d)
        .any((s) => s.oeuvreId != null);
    expect(aLecture(j1) != aLecture(j2), isTrue,
        reason: 'la lecture doit tomber un jour sur deux');
    // Le jour avec lecture affiche le rythme de pages.
    final jour = aLecture(j1) ? j1 : j2;
    final bloc = suggere(m, 180, maintenant: jour)
        .firstWhere((s) => s.oeuvreId != null);
    expect(bloc.matiere, 'Français');
    expect(bloc.raison, contains('p./séance'));
  });

  test('rentrée : œuvre pas finie -> rattrapage un jour sur trois', () {
    // Pas de plage d'ete : mode normal (mi-septembre).
    m.oeuvres.add(Oeuvre(titre: 'Candide', pages: 150, pageActuelle: 60));
    m.chapitres.add(
        Chapitre(matiere: 'Maths', nom: 'Suites', etape: 2, maitrise: 2));
    // Sur 3 jours consecutifs, le rattrapage apparait exactement 1 fois.
    var vus = 0;
    for (var d = 0; d < 3; d++) {
      final s = suggere(m, 120,
          maintenant: DateTime(2026, 9, 14 + d, 19));
      if (s.any((x) => x.oeuvreId != null)) vus++;
    }
    expect(vus, 1);
    // Une oeuvre FINIE ne revient pas.
    m.oeuvres.first.finie = true;
    for (var d = 0; d < 3; d++) {
      final s = suggere(m, 120,
          maintenant: DateTime(2026, 9, 14 + d, 19));
      expect(s.any((x) => x.oeuvreId != null), isFalse);
    }
  });

  test('Oeuvre : round-trip JSON', () {
    final o = Oeuvre(
        titre: 'Candide', auteur: 'Voltaire', pages: 150, pageActuelle: 42);
    final r = Oeuvre.fromJson(o.toJson());
    expect(r.titre, 'Candide');
    expect(r.pages, 150);
    expect(r.pageActuelle, 42);
    expect(r.finie, isFalse);
  });

  // ---------- Jours off ----------

  test('jour off : plan vide, quel que soit le mode', () {
    final now = DateTime(2026, 8, 4, 10);
    m.joursOff.add(DateTime(2026, 8, 4));
    m.chapitres.add(
        Chapitre(matiere: 'Maths', nom: 'Suites', etape: 2, maitrise: 2));
    m.colles.add(
        Colle(matiere: 'Physique', start: now.add(const Duration(hours: 26))));
    expect(suggere(m, 180, maintenant: now), isEmpty);
    // Le lendemain, le plan revient.
    expect(suggere(m, 180, maintenant: DateTime(2026, 8, 5, 10)), isNotEmpty);
  });

  test('etalerReactivation : les jours off sont évités', () {
    final now = DateTime(2026, 8, 4, 10);
    m.sansCours.add(PlageSansCours(
        titre: 'Été',
        debut: DateTime(2026, 7, 1),
        fin: DateTime(2026, 8, 14),
        type: 'ete'));
    // Les 15 et 16 août n'existent pas dans la plage ; on bloque les 6-8.
    m.joursOff.addAll([
      DateTime(2026, 8, 6),
      DateTime(2026, 8, 7),
      DateTime(2026, 8, 8),
    ]);
    for (var i = 0; i < 10; i++) {
      m.chapitres.add(Chapitre(
          matiere: 'Maths', nom: 'Chapitre $i', etape: 1, maitrise: 2));
    }
    m.etalerReactivation(maintenant: now);
    for (final c in m.chapitres) {
      expect(m.estJourOff(c.prochaineRevision!), isFalse,
          reason: '${c.nom} planifié un jour off (${c.prochaineRevision})');
    }
  });
}
