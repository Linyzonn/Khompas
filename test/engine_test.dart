import 'package:flutter_test/flutter_test.dart';
import 'package:khompas/ai_extractor.dart';
import 'package:khompas/engine.dart';
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
    m.colles.add(Colle(
        matiere: 'Maths', start: DateTime.now().add(const Duration(hours: 20))));
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
    final s = suggere(m, 120);
    expect(s.first.titre, contains('Annale CCINP 2024'));
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
}
