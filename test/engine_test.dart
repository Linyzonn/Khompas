import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:khompas/ai_extractor.dart';
import 'package:khompas/notifs.dart';
import 'package:khompas/engine.dart';
import 'package:khompas/ics.dart';
import 'package:khompas/vacances_officielles.dart';
import 'package:khompas/methodes.dart';
import 'package:khompas/models.dart';
import 'package:khompas/stats.dart';
import 'package:khompas/store.dart';

/// AppModel est un singleton : chaque test repart d'un etat vierge.
/// Date fixe HORS ete et hors dimanche (mardi 6 octobre 2026, 18 h) :
/// les tests du mode normal ne doivent pas dependre du jour ou la suite
/// tourne — en aout, l'ete implicite (juillet/aout sans plage saisie)
/// capturait tout test base sur tNormal.
final tNormal = DateTime(2026, 10, 6, 18);

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
  m.citations = [];
  m.vocab = [];
  m.trajetMinutes = 0;
  m.joursOff = [];
  m.zoneVacances = '';
  m.modeOraux = false;
  m.eplS = false;
  m.dateEplS = null;
  m.faitsDuJour = {};
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
        matiere: 'Maths', start: tNormal.add(const Duration(hours: 26))));
    m.chapitres
        .add(Chapitre(matiere: 'Anglais', nom: 'Vocab', etape: 1, maitrise: 2));
    final s = suggere(m, 120, maintenant: tNormal);
    expect(s, isNotEmpty);
    expect(s.first.matiere, 'Maths');
    expect(s.first.raison.toLowerCase(), contains('demain'));
  });

  test('devoir en retard (≤ 5 j) : urgence maximale, raison EN RETARD', () {
    final now = tNormal;
    m.devoirs.add(Devoir(
      matiere: 'Physique-Chimie',
      dateRendu: now.subtract(const Duration(days: 2)),
      dateDonne: now.subtract(const Duration(days: 9)),
    ));
    final s = suggere(m, 120, maintenant: tNormal);
    expect(s.first.matiere, 'Physique-Chimie');
    expect(s.first.raison, contains('EN RETARD'));
  });

  // ---------- Jachere ----------

  test('jachère : une matière délaissée 8 j remonte devant une matière '
      'travaillée hier', () {
    final now = tNormal;
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
    final s = suggere(m, 120, maintenant: tNormal);
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
    final s = suggere(m, 120, maintenant: tNormal);
    expect(s.first.matiere, 'Chimie');
    // Le chapitre jamais consolide est signale par ⚠ dans le contenu.
    expect(s.first.titre, contains('⚠'));
  });

  // ---------- Repetition espacee ----------

  test('rappel dû aujourd\'hui : bloc de 15 min en tête, marqué rappel', () {
    final now = tNormal;
    m.chapitres.add(Chapitre(
      matiere: 'Maths',
      nom: 'Séries entières',
      etape: 2,
      maitrise: 3,
      prochaineRevision: DateTime(now.year, now.month, now.day),
      intervalleJours: 4,
    ));
    expect(rappelsDus(m, maintenant: tNormal).length, 1);
    final s = suggere(m, 120, maintenant: tNormal);
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
        prochaineRevision: tNormal,
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
    final now = tNormal;
    m.devoirs.add(Devoir(
      matiere: 'Maths',
      titre: 'DM 4',
      dateRendu: now.add(const Duration(days: 7)),
      dateDonne: now,
    ));
    final s = suggere(m, 120, maintenant: tNormal);
    expect(s.any((x) => x.titre.contains('Lis le DM 4')), isTrue);
  });

  // ---------- EDT : parite A/B et plages sans cours ----------

  test('routinesLe : respecte les semaines A/B et les plages sans cours', () {
    final now = tNormal;
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
    final now = tNormal;
    m.dateConcours = now.add(const Duration(days: 30));
    m.chapitres.addAll([
      Chapitre(matiere: 'Maths', nom: 'M1', etape: 2, maitrise: 0),
      Chapitre(matiere: 'Maths', nom: 'M2', etape: 2, maitrise: 1),
      Chapitre(matiere: 'Physique-Chimie', nom: 'P1', etape: 2, maitrise: 2),
      Chapitre(matiere: 'Physique-Chimie', nom: 'P2', etape: 2, maitrise: 3),
    ]);
    final s = suggere(m, 120, maintenant: tNormal);
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
    final s2 = suggere(m, 120, maintenant: tNormal);
    expect(s2.first.chapitreId, du.id);
    expect(s2.first.rappel, isTrue);
  });

  test('date de concours passée : retour au mode normal', () {
    m.dateConcours = tNormal.subtract(const Duration(days: 1));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 1, maitrise: 2));
    final s = suggere(m, 120, maintenant: tNormal);
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
    final now = tNormal;
    m.ds.add(Ds(
        matiere: 'Maths',
        date: DateTime(now.year, now.month, now.day)
            .add(const Duration(days: 1))));
    m.erreurs.add(Erreur(
        matiere: 'Maths', texte: 'Oubli du cas λ = 0', type: 'Méthode'));
    m.erreurs.add(Erreur(
        matiere: 'Maths', texte: 'Signe', type: 'Calcul', refaite: true));
    final s = suggere(m, 120, maintenant: tNormal);
    expect(s.first.titre, contains('📕'));
    expect(s.first.titre, contains('1 à revoir')); // seule la non-refaite
    expect(s.first.matiere, 'Maths');
  });

  // ---------- Annales (mode revisions, J-45) ----------

  test('mode révisions à J-45 : une annale non faite entre dans le plan, '
      'matière la moins couverte d\'abord', () {
    m.dateConcours = tNormal.add(const Duration(days: 30));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 2, maitrise: 3));
    m.annales.add(
        Annale(concours: 'CCINP', matiere: 'Maths', annee: 2024));
    m.annales.add(Annale(
        concours: 'CCINP', matiere: 'Physique-Chimie', annee: 2023,
        fait: true));
    // Budget de soir de semaine -> c'est la version "une PARTIE" qui sort
    // (l'epreuve entiere est reservee aux gros budgets — teste plus bas).
    final s = suggere(m, 120, maintenant: tNormal);
    expect(s.first.titre, contains('CCINP 2024'));
    expect(s.first.matiere, 'Maths');
  });

  // ---------- Mode oraux ----------

  test('mode oraux : l\'oral daté imminent en tête, puis rotation des '
      'autres épreuves', () {
    final now = tNormal;
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
    final s = suggere(m, 120, maintenant: tNormal);
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
    m.colles.add(Colle(matiere: 'LV1', start: tNormal));
    m.seances.add(
        Seance(matiere: 'LV1', date: tNormal, minutes: 30));
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
          jour: tNormal,
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
          jour: tNormal.add(const Duration(days: 2)),
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
    final now = tNormal;
    // Une kholle plus tard dans la journee (ou tot le matin : le test doit
    // passer a toute heure — on prend 23h59 du jour meme).
    m.colles.add(Colle(
        matiere: 'Maths',
        start: DateTime(now.year, now.month, now.day, 23, 58)));
    final s = suggere(m, 120, maintenant: tNormal);
    expect(s.first.raison, contains('AUJOURD\'HUI'));
    expect(s.first.raison, isNot(contains('RETARD')));
  });

  test('DM à rendre AUJOURD\'HUI : plus jamais « EN RETARD » le jour J', () {
    final now = tNormal;
    m.devoirs.add(Devoir(
        matiere: 'Physique',
        dateRendu: DateTime(now.year, now.month, now.day),
        dateDonne: now.subtract(const Duration(days: 7))));
    final s = suggere(m, 120, maintenant: tNormal);
    expect(s.first.raison, contains('AUJOURD\'HUI'));
  });

  // ---------- Travail impose = tache cochable ----------

  test('DM proche : la suggestion EST la tâche (titre + remarque + '
      'devoirId)', () {
    final now = tNormal;
    final d = Devoir(
        matiere: 'Maths',
        titre: 'DM 3',
        dateRendu: now.add(const Duration(days: 5)),
        dateDonne: now.subtract(const Duration(days: 2)),
        remarque: 'exos 1 à 4');
    m.devoirs.add(d);
    final s = suggere(m, 120, maintenant: tNormal);
    final sug = s.firstWhere((x) => x.matiere == 'Maths');
    expect(sug.titre, contains('Avance DM 3'));
    expect(sug.titre, contains('exos 1 à 4'));
    expect(sug.devoirId, d.id);
  });

  // ---------- Jour libre : plus de matieres ----------

  test('jour libre (EDT rempli mais rien aujourd\'hui) + gros budget : '
      '4 matières retenues', () {
    final now = tNormal;
    // Une routine sur un AUTRE jour que celui du test -> aujourd'hui libre.
    final autreJour = now.weekday == 7 ? 1 : now.weekday + 1;
    m.routines.add(Routine(titre: 'Maths', jour: autreJour, debutMin: 480));
    for (final mat in ['Maths', 'Physique', 'Anglais', 'Français']) {
      m.chapitres
          .add(Chapitre(matiere: mat, nom: 'Ch $mat', etape: 2, maitrise: 2));
    }
    final s = suggere(m, 300, maintenant: tNormal);
    expect(s.map((x) => x.matiere).toSet().length, greaterThanOrEqualTo(4));
  });

  // ---------- Vacances : creneau DM etale, cadence annoncee ----------

  test('vacances + 2 DM : un créneau DM apparaît avec sa cadence', () {
    final now = tNormal;
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
    final s = suggere(m, 180, maintenant: tNormal);
    expect(s.any((x) => x.titre.contains('Créneau DM')), isTrue);
  });

  // ---------- Annales realistes ----------

  test('mode révisions : annale ENTIÈRE seulement à gros budget, sinon '
      'une PARTIE', () {
    m.dateConcours = tNormal.add(const Duration(days: 30));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 2, maitrise: 3));
    m.annales
        .add(Annale(concours: 'CCINP', matiere: 'Maths', annee: 2024));
    final soir = suggere(m, 120, maintenant: tNormal);
    expect(soir.any((x) => x.titre.contains('PARTIE')), isTrue);
    final weekend = suggere(m, 300, maintenant: tNormal);
    expect(weekend.any((x) => x.titre.contains('EN CONDITIONS')), isTrue);
  });

  test('annale faite récemment avec ressenti moyen : la CORRECTION ACTIVE '
      'passe devant', () {
    m.dateConcours = tNormal.add(const Duration(days: 30));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 2, maitrise: 3));
    m.annales.add(Annale(
        concours: 'CCINP',
        matiere: 'Maths',
        annee: 2023,
        fait: true,
        ressenti: 2,
        dateFait: tNormal.subtract(const Duration(days: 1))));
    m.annales.add(Annale(concours: 'CCINP', matiere: 'Maths', annee: 2024));
    final s = suggere(m, 120, maintenant: tNormal);
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
    final now = tNormal;
    // Les DS sont dates a minuit : a 18 h, l'ancien code (isBefore(now))
    // ecartait le DS du jour et la branche AUJOURD'HUI etait morte.
    m.ds.add(Ds(
        matiere: 'Physique',
        titre: 'DS 4',
        date: DateTime(now.year, now.month, now.day),
        note: null));
    final s = suggere(m, 120, maintenant: tNormal);
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
        prochaineRevision: tNormal);
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
        prochaineRevision: tNormal);
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
    final now = tNormal;
    final due = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 3));
    final c = Chapitre(
        matiere: 'Maths',
        nom: 'Espaces vectoriels',
        etape: 1,
        intervalleJours: 10,
        prochaineRevision: due);
    m.chapitres.add(c);
    m.evaluerRevision(c.id, 'cava', maintenant: now); // 10 -> 17 j, ancre sur la date due
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
    m.recalibrerChapitres([c.id], maintenant: tNormal);
    expect(c.maitrise, 2);
    expect(c.intervalleJours, 1);
    final now = tNormal;
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
    m.dateConcours = tNormal.add(const Duration(days: 200));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Suites', etape: 2, maitrise: 2));
    // Une khôlle demain doit toujours apparaitre : en mode revisions
    // premature, elle disparaissait pendant des mois.
    m.colles.add(Colle(
        matiere: 'Physique',
        start: tNormal.add(const Duration(hours: 26))));
    final s = suggere(m, 120, maintenant: tNormal);
    expect(s.any((x) => x.matiere == 'Physique'), isTrue,
        reason: 'la khôlle de demain doit rester dans le plan');
    expect(s.any((x) => x.titre.startsWith('Réviser :')), isFalse,
        reason: 'pas de rotation concours a J-200');
  });

  test('mode révisions : une khôlle imminente garde sa place dans le plan',
      () {
    m.dateConcours = tNormal.add(const Duration(days: 30));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Suites', etape: 2, maitrise: 2));
    m.colles.add(Colle(
        matiere: 'Anglais',
        programme: 'Press review',
        start: tNormal.add(const Duration(hours: 26))));
    final s = suggere(m, 120, maintenant: tNormal);
    expect(s.any((x) => x.titre.contains('khôlle')), isTrue);
  });

  // ---------- Rotation des DM de vacances ----------

  test('vacances + 2 DM : les créneaux tournent entre les DM', () {
    // Date FIXE injectee : cale sur tNormal, ce test echouait un
    // jour sur deux — avec une cadence de 2, jourIdx % cadence != 0 les
    // jours impairs depuis kAncreRotation (et la parite dependait en plus
    // du fuseau horaire du runner). Echeances PROCHES (6 j devant, 2 DM)
    // -> cadence 1 : un creneau CHAQUE jour, servi en alternance.
    final now = DateTime(2026, 10, 20, 10);
    m.sansCours.add(PlageSansCours(
      titre: 'Vacances',
      debut: DateTime(2026, 10, 18),
      fin: DateTime(2026, 11, 1),
    ));
    m.devoirs.add(Devoir(
        matiere: 'Maths',
        titre: 'DM 5',
        dateRendu: now.add(const Duration(days: 5)),
        dateDonne: now.subtract(const Duration(days: 1))));
    m.devoirs.add(Devoir(
        matiere: 'Physique',
        titre: 'DM 3',
        dateRendu: now.add(const Duration(days: 7)),
        dateDonne: now.subtract(const Duration(days: 1))));
    // Quel DM le creneau du jour vise-t-il ?
    String? cible(DateTime quand) {
      final s = suggere(m, 240, maintenant: quand);
      final c = s.where((x) => x.titre.contains('Créneau DM')).toList();
      if (c.isEmpty) return null;
      return c.first.titre.contains('DM 5') ? 'DM 5' : 'DM 3';
    }

    final jour1 = cible(now);
    final jour2 = cible(now.add(const Duration(days: 1)));
    expect(jour1, isNotNull);
    expect(jour2, isNotNull);
    // Deux jours consecutifs visent deux DM differents : LA rotation,
    // testee pour de vrai (l'ancien test ne verifiait que l'existence).
    expect(jour1 != jour2, isTrue,
        reason: 'les créneaux doivent alterner entre les 2 DM');
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
      // 7 j et non 1 : l intervalle initial realiste est LE correctif du
      // backlog explosif mesure en simulation (0 -> 83 dus en un mois).
      expect(c.intervalleJours, 7);
    }
    // Et elles sont REPARTIES, pas toutes le meme jour.
    final jours = m.chapitres
        .where((c) => c.etape > 0)
        .map((c) => c.prochaineRevision!.day)
        .toSet();
    expect(jours.length, greaterThan(5));
  });

  test('etalerReactivation sans plage : implicite en juillet/août, inerte '
      'le reste de l’année', () {
    m.chapitres.add(
        Chapitre(matiere: 'Maths', nom: 'Suites', etape: 2, maitrise: 2));
    // Octobre sans plage : rien (pas de vacances a etaler).
    expect(m.etalerReactivation(maintenant: DateTime(2026, 10, 6)), 0);
    expect(m.chapitres.first.prochaineRevision, isNull);
    // Aout sans plage : fin implicite au 31 — l'etaleur ne doit plus
    // rendre 0 en silence (le bouton « Planifier » semblait mort).
    expect(m.etalerReactivation(maintenant: DateTime(2026, 8, 4)), 1);
    expect(m.chapitres.first.prochaineRevision, isNotNull);
  });

  // ---------- Bilan de concours (5/2) ----------

  test('deficitsConcours : normalisé par concours — un gros total de coeffs '
      'n\'écrase plus les autres', () {
    // CCINP : total de coeffs saisi = 5.
    m.resultatsConcours.add(ResultatConcours(
        concours: 'CCINP', epreuve: 'Maths', matiere: 'Maths',
        annee: 2026, note: 6, barre: 10, coeff: 2)); // 4 pts x 2/5 x 100 = 160
    m.resultatsConcours.add(ResultatConcours(
        concours: 'CCINP', epreuve: 'SII', matiere: 'SII',
        annee: 2026, note: 12, barre: 10, coeff: 3)); // au-dessus : 0
    // Centrale : total de coeffs saisi = 10 — la meme part relative qu'a
    // CCINP pese pareil, meme si les coeffs absolus sont plus gros.
    m.resultatsConcours.add(ResultatConcours(
        concours: 'Centrale-Supélec', epreuve: 'Maths 1', matiere: 'Maths',
        annee: 2026, note: 8, barre: 11, coeff: 6)); // 3 pts x 6/10 x 100 = 180
    m.resultatsConcours.add(ResultatConcours(
        concours: 'Centrale-Supélec', epreuve: 'Physique', matiere: 'Physique',
        annee: 2026, note: 11, barre: 11, coeff: 4)); // pile la barre : 0
    final d = m.deficitsConcours();
    expect(d['Maths'], closeTo(340, 0.001)); // 160 + 180
    expect(d['SII'], 0);
    expect(d['Physique'], 0);
  });

  test('deficitsConcours : même écart relatif = même poids, quel que soit le '
      'total de coeffs du concours (Centrale 100 vs Mines 30)', () {
    // 2 pts sous la barre, épreuve pesant 20 % de son concours — dans les
    // deux cas, malgré des coeffs absolus très différents (20 vs 6).
    m.resultatsConcours.add(ResultatConcours(
        concours: 'Centrale', epreuve: 'Maths 1', matiere: 'Maths',
        annee: 2026, note: 8, barre: 10, coeff: 20));
    m.resultatsConcours.add(ResultatConcours(
        concours: 'Centrale', epreuve: 'Reste', matiere: 'SII',
        annee: 2026, note: 12, barre: 10, coeff: 80));
    m.resultatsConcours.add(ResultatConcours(
        concours: 'Mines', epreuve: 'Physique', matiere: 'Physique',
        annee: 2026, note: 8, barre: 10, coeff: 6));
    m.resultatsConcours.add(ResultatConcours(
        concours: 'Mines', epreuve: 'Reste', matiere: 'SII',
        annee: 2026, note: 12, barre: 10, coeff: 24));
    final d = m.deficitsConcours();
    expect(d['Maths'], closeTo(d['Physique']!, 0.001));
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

  test('été : la lecture revient TOUS les jours (sauf dimanche), avec rythme '
      'de pages', () {
    m.sansCours.add(PlageSansCours(
        titre: 'Été',
        debut: DateTime(2026, 7, 1),
        fin: DateTime(2026, 8, 31),
        type: 'ete'));
    m.chapitres.add(
        Chapitre(matiere: 'Maths', nom: 'Suites', etape: 2, maitrise: 2));
    m.oeuvres.add(
        Oeuvre(titre: 'Le Rouge et le Noir', auteur: 'Stendhal', pages: 500));
    // Deux jours de semaine consecutifs : lecture les DEUX jours — les
    // oeuvres se lisent chaque jour de l'ete, pas un jour sur deux.
    final j1 = DateTime(2026, 8, 4, 10); // mardi
    final j2 = DateTime(2026, 8, 5, 10); // mercredi
    bool aLecture(DateTime d) => suggere(m, 180, maintenant: d)
        .any((s) => s.oeuvreId != null);
    expect(aLecture(j1), isTrue);
    expect(aLecture(j2), isTrue);
    final bloc = suggere(m, 180, maintenant: j1)
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

  // ---------- Remise a zero & detection d'ete ----------

  test('estEte : juillet/août toujours, sinon une plage « ete » en cours',
      () {
    expect(m.estEte(maintenant: DateTime(2026, 7, 15)), isTrue);
    expect(m.estEte(maintenant: DateTime(2026, 8, 31)), isTrue);
    expect(m.estEte(maintenant: DateTime(2026, 10, 1)), isFalse);
    // Une plage « ete » decalee (rentree tardive) compte aussi.
    m.sansCours.add(PlageSansCours(
        titre: 'Été décalé',
        debut: DateTime(2026, 9, 20),
        fin: DateTime(2026, 10, 5),
        type: 'ete'));
    expect(m.estEte(maintenant: DateTime(2026, 10, 1)), isTrue);
    // Une plage d'un autre type (revisions) ne compte pas.
    m.sansCours.clear();
    m.sansCours.add(PlageSansCours(
        titre: 'Révisions',
        debut: DateTime(2026, 9, 20),
        fin: DateTime(2026, 10, 5),
        type: 'revisions'));
    expect(m.estEte(maintenant: DateTime(2026, 10, 1)), isFalse);
  });

  test('reinitialiser : tout est vidé, compte oublié, onboarding réaffiché',
      () async {
    SharedPreferences.setMockInitialValues({});
    m.colles.add(Colle(matiere: 'Maths', start: DateTime(2026, 9, 10)));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 2, maitrise: 3));
    m.citations.add(Citation(texte: 'Test'));
    m.vocab.add(MotVocab(francais: 'mot', anglais: 'word'));
    m.trajetMinutes = 30;
    m.prios['Maths'] = 3;
    m.compteCle = 'ABCDEFGHIJKLMNOPQR';
    m.apiKey = 'sk-test';
    m.gestionClasse = 'GESTION';
    m.codeClasse = 'CODE42';
    m.filiere = 'MP';
    m.groupe = 7;
    m.cinqDemi = true;
    m.onboarded = true;
    m.loaded = true; // l'app tourne : la remise a zero ne doit pas le casser
    m.serverUrl = 'https://exemple.test';
    m.dateConcours = DateTime(2027, 4, 20);
    await m.reinitialiser();
    expect(m.colles, isEmpty);
    expect(m.chapitres, isEmpty);
    expect(m.citations, isEmpty);
    expect(m.vocab, isEmpty);
    expect(m.trajetMinutes, 0);
    expect(m.prios, isEmpty);
    // Plus AUCUN secret : la cle de compte est oubliee (les donnees du
    // serveur, elles, restent recuperables avec la cle).
    expect(m.compteCle, isEmpty);
    expect(m.apiKey, isEmpty);
    expect(m.gestionClasse, isEmpty);
    expect(m.codeClasse, isEmpty);
    // Profil aux valeurs d'usine, onboarding a refaire, app utilisable.
    expect(m.filiere, 'PCSI');
    expect(m.groupe, 1);
    expect(m.cinqDemi, isFalse);
    expect(m.onboarded, isFalse);
    expect(m.loaded, isTrue);
    expect(m.dateConcours, isNull);
    // Le serveur revient au defaut (sinon l'onboarding masque les comptes).
    expect(m.serverUrl, kServeurDefaut);
  });

  // ---------- Ordre des oeuvres, interros, cartes (v0.17) ----------

  test('ordre des œuvres : le plan d\'été sert le PREMIER livre pas fini',
      () {
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 1, maitrise: 2));
    m.sansCours.add(PlageSansCours(
        titre: 'Été',
        debut: DateTime(2026, 7, 1),
        fin: DateTime(2026, 8, 31),
        type: 'ete'));
    m.oeuvres.add(Oeuvre(titre: 'Premier'));
    m.oeuvres.add(Oeuvre(titre: 'Deuxième'));
    // Jour PAIR depuis l'ancre (cadence lecture 1 j/2), calcule au runtime
    // pour rester juste quel que soit le fuseau de la machine de test ;
    // pas un dimanche (jour de repos en ete, +2 garde la parite).
    var jour = DateTime(2026, 7, 10, 10);
    if (DateTime(jour.year, jour.month, jour.day)
            .difference(kAncreRotation)
            .inDays %
        2 !=
        0) {
      jour = jour.add(const Duration(days: 1));
    }
    if (jour.weekday == DateTime.sunday) jour = jour.add(const Duration(days: 2));
    final s = suggere(m, 240, maintenant: jour);
    final lecture = s.where((x) => x.titre.contains('Lis «')).toList();
    expect(lecture, isNotEmpty);
    expect(lecture.first.titre, contains('Premier'));
    // « Premier » fini -> c'est « Deuxième » qui prend la place.
    m.oeuvres.first.finie = true;
    final s2 = suggere(m, 240, maintenant: jour);
    expect(s2.where((x) => x.titre.contains('Lis «')).first.titre,
        contains('Deuxième'));
  });

  test('ordre des œuvres : le rattrapage de rentrée suit aussi l\'ordre', () {
    m.oeuvres.add(Oeuvre(titre: 'Premier'));
    m.oeuvres.add(Oeuvre(titre: 'Deuxième'));
    // Un jour multiple de 3 depuis l'ancre (cadence 1 j/3), hors vacances.
    var jour = DateTime(2026, 9, 15, 18);
    // MEME formule que le moteur (jourRotation, en UTC) : la recalculer
    // a la main ici la desynchronisait du code teste.
    while (jourRotation(jour) % 3 != 0) {
      jour = jour.add(const Duration(days: 1));
    }
    final s = suggere(m, 180, maintenant: jour);
    final rattrapage = s.where((x) => x.titre.contains('Rattrape')).toList();
    expect(rattrapage, isNotEmpty);
    expect(rattrapage.first.titre, contains('Premier'));
  });

  test('interro de cours : la consigne fait relire le COURS, pas les annales',
      () {
    final now = DateTime(2026, 10, 6, 18);
    m.ds.add(Ds(
        matiere: 'Physique',
        titre: 'Interro',
        date: DateTime(2026, 10, 7),
        coeff: 0.5,
        interro: true));
    final s = suggere(m, 120, maintenant: now);
    final sug = s.where((x) => x.matiere == 'Physique').toList();
    expect(sug, isNotEmpty);
    expect(sug.first.raison, contains('Interro'));
    expect(sug.first.consigne, contains('COURS'));
  });

  test('cartes : dues dès l\'ajout, espacement selon le verdict', () {
    m.addCitation(Citation(texte: 'Vivre sans temps mort', auteur: 'V.'));
    m.addMotVocab(MotVocab(francais: 'pallier', anglais: 'to make up for'));
    // Une carte neuve est due AUJOURD'HUI (elle entre dans la prochaine
    // session sans attendre demain).
    expect(m.citationsDues(), hasLength(1));
    expect(m.vocabDus(), hasLength(1));
    // Dates FIXES pour la suite (independant du jour reel du test).
    final now = DateTime(2026, 10, 6, 18);
    m.vocab.first.prochaineRevision = DateTime(2026, 10, 6);
    m.citations.first.prochaineRevision = DateTime(2026, 10, 6);
    m.evaluerMotVocab(m.vocab.first.id, 'facile', maintenant: now);
    // facile : x2.5 -> intervalle 3, revu dans 3 jours.
    expect(m.vocab.first.intervalleJours, 3);
    expect(m.vocab.first.prochaineRevision, DateTime(2026, 10, 9));
    expect(m.vocabDus(maintenant: now), isEmpty);
    m.evaluerCitation(m.citations.first.id, 'difficile', maintenant: now);
    // difficile : la carte revient DEMAIN, echec memorise.
    expect(m.citations.first.intervalleJours, 1);
    expect(m.citations.first.echecs, 1);
    expect(m.citations.first.prochaineRevision, DateTime(2026, 10, 7));
  });

  test('matières littéraires : pas de rappels de chapitres, cap sur les cartes',
      () {
    final now = DateTime(2026, 10, 6, 18);
    // Un chapitre d'anglais planifie (vieille reactivation) ne doit PAS
    // revenir en rappel espace : il n'y a rien a « revoir » en anglais.
    m.chapitres.add(
        Chapitre(matiere: 'Anglais', nom: 'Unit 3', etape: 1, maitrise: 2)
          ..prochaineRevision = DateTime(2026, 10, 6)
          ..intervalleJours = 1);
    expect(rappelsDus(m, maintenant: now), isEmpty);
    // Du voc est du -> la suggestion d'anglais pointe les CARTES, pas le
    // chapitre.
    m.addMotVocab(MotVocab(francais: 'pallier', anglais: 'to make up for'));
    m.vocab.first.prochaineRevision = DateTime(2026, 10, 6);
    final s = suggere(m, 120, maintenant: now);
    final ang = s.where((x) => x.matiere == 'Anglais').toList();
    expect(ang, isNotEmpty);
    expect(ang.first.titre, contains('Cartes'));
  });

  test('etalerReactivation : les chapitres de langues/français sont exclus',
      () {
    final now = DateTime(2026, 8, 4, 10);
    m.sansCours.add(PlageSansCours(
        titre: 'Été',
        debut: DateTime(2026, 7, 1),
        fin: DateTime(2026, 8, 31),
        type: 'ete'));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 1, maitrise: 2));
    m.chapitres
        .add(Chapitre(matiere: 'Anglais', nom: 'Unit 1', etape: 1, maitrise: 2));
    m.chapitres.add(
        Chapitre(matiere: 'Français', nom: 'Le thème', etape: 1, maitrise: 2));
    final n = m.etalerReactivation(maintenant: now);
    expect(n, 1); // seul le chapitre de Maths est planifie
    expect(
        m.chapitres
            .firstWhere((c) => c.matiere == 'Anglais')
            .prochaineRevision,
        isNull);
  });

  test('listes de voc : noms, mots par liste, round-trip avec la khôlle', () {
    m.addMotVocab(MotVocab(francais: 'a', anglais: 'b', liste: 'Liste 5'));
    m.addMotVocab(MotVocab(francais: 'c', anglais: 'd', liste: 'Liste 6'));
    m.addMotVocab(MotVocab(francais: 'e', anglais: 'f'));
    expect(m.listesVocNoms, ['Liste 5', 'Liste 6']);
    expect(m.vocabDeListes(['Liste 5']), hasLength(1));
    m.colles.add(Colle(
        matiere: 'Anglais',
        start: DateTime(2026, 10, 8, 16),
        listesVoc: ['Liste 5', 'Liste 6']));
    final raw = m.exportJson();
    reset(m);
    m.importJson(raw);
    expect(m.colles.first.listesVoc, ['Liste 5', 'Liste 6']);
    expect(m.vocab.where((v) => v.liste == 'Liste 5'), hasLength(1));
  });

  // ---------- v0.19 : robustesse des donnees (review 0.18) ----------

  test('parseListeTolerante : un enregistrement abîmé ne jette pas les autres',
      () {
    final brut = [
      Colle(matiere: 'Maths', start: DateTime(2026, 9, 10)).toJson(),
      {'matiere': 'Physique', 'start': 'pas-une-date'}, // malade
      Colle(matiere: 'Anglais', start: DateTime(2026, 9, 12)).toJson(),
    ];
    final (liste, ignores) = parseListeTolerante(brut, Colle.fromJson);
    expect(liste, hasLength(2));
    expect(ignores, 1);
    expect(liste.first.matiere, 'Maths');
  });

  test('repareJsonTronque : une sauvegarde coupée en pleine écriture se répare',
      () {
    m.colles.add(Colle(matiere: 'Maths', start: DateTime(2026, 9, 10)));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 1, maitrise: 2));
    final complet = m.exportJson();
    // Coupure brutale au milieu du fichier (coupure de courant, kill).
    final tronque = complet.substring(0, complet.length ~/ 2);
    final repare = repareJsonTronque(tronque);
    expect(repare, isNotNull);
    // Le JSON repare est restaurable (au moins partiellement).
    reset(m);
    m.importJson(repare!);
    // Un texte sans aucune structure JSON reste irreparable.
    expect(repareJsonTronque('pas du json'), isNull);
  });

  test('exportJsonCompact : mêmes données, nettement plus petit (synchro)',
      () {
    for (var i = 0; i < 20; i++) {
      m.chapitres.add(Chapitre(
          matiere: 'Maths', nom: 'Chapitre $i', etape: 1, maitrise: 2));
    }
    final compact = m.exportJsonCompact();
    final indente = m.exportJson();
    // Meme contenu logique (exportedAt mis a part : deux horodatages).
    final a = jsonDecode(compact) as Map<String, dynamic>..remove('exportedAt');
    final b = jsonDecode(indente) as Map<String, dynamic>..remove('exportedAt');
    expect(a, b);
    // ...mais bien plus court : c'est lui qui part vers le serveur.
    expect(compact.length * 1.2, lessThan(indente.length));
  });

  test('étaleur de DM : une semaine de RÉVISIONS n\'est pas des vacances', () {
    final now = DateTime(2026, 10, 20, 10);
    m.sansCours.add(PlageSansCours(
      titre: 'Révisions',
      debut: DateTime(2026, 10, 18),
      fin: DateTime(2026, 11, 1),
      type: 'revisions',
    ));
    m.devoirs.add(Devoir(
        matiere: 'Maths',
        titre: 'DM 5',
        dateRendu: now.add(const Duration(days: 5)),
        dateDonne: now.subtract(const Duration(days: 1))));
    final s = suggere(m, 240, maintenant: now);
    expect(s.any((x) => x.titre.contains('Créneau DM')), isFalse,
        reason:
            'pas de « Créneau DM (vacances) » pendant une semaine banalisée');
  });

  test('extraction IA tronquée : les accolades DANS une chaîne survivent', () {
    // Reponse d'IA coupee par la limite de tokens, avec un nom de chapitre
    // contenant des accolades : l'ancien repechage regex \{[^{}]*\} perdait
    // cet element — la reparation propre (fermeture des crochets) le garde.
    const complet = '{"chapitres": ['
        '{"matiere": "Maths", "nom": "Ensembles {1;2} et parties"},'
        '{"matiere": "Maths", "nom": "Applications"},'
        '{"matiere": "Maths", "nom": "Relations"}'
        '], "avertissements": []}';
    final tronque = complet.substring(0, complet.indexOf('"Relations"') + 4);
    final r = parseChapitresExtraction(tronque);
    expect(r.chapitres.length, 2);
    expect(r.chapitres.first.nom, contains('{1;2}'));
    expect(r.avertissements.join(), contains('incomplète'));
  });

  test('veillesAPlannifier : tri par date, jalons 🚨 inclus, DM respecte son '
      'réglage', () {
    final now = DateTime(2026, 10, 5, 12);
    m.notifVeilleKholle = true;
    m.notifVeilleDm = false;
    m.colles
        .add(Colle(matiere: 'Anglais', start: DateTime(2026, 10, 20, 16)));
    m.colles.add(Colle(matiere: 'Maths', start: DateTime(2026, 10, 8, 16)));
    // DM : exclu (notifVeilleDm desactive).
    m.devoirs.add(Devoir(
        matiere: 'Physique',
        dateRendu: DateTime(2026, 10, 9),
        dateDonne: DateTime(2026, 10, 2)));
    // Jalon critique : TOUJOURS inclus, quels que soient les sous-reglages.
    m.evenements.add(Evenement(
        titre: '🚨 Clôture SCEI',
        matiere: 'TIPE',
        date: DateTime(2026, 12, 10),
        debutMin: 8 * 60,
        dureeMin: 60));
    final l = Notifs.veillesAPlannifier(m, maintenant: now);
    expect(l.map((e) => e.$2).toList(), [
      'Khôlle demain — Maths',
      'Khôlle demain — Anglais',
      'Demain — Clôture SCEI',
    ]);
    // Le reglage DM reactive : le devoir entre, a sa place chronologique.
    m.notifVeilleDm = true;
    final l2 = Notifs.veillesAPlannifier(m, maintenant: now);
    expect(l2[1].$2, 'À rendre demain — Physique');
  });

  test('fusion de synchro : union par id, plus récent gagne, suppressions '
      'respectées des deux côtés', () {
    // LOCAL : A (modifiee ICI le 5), C (jamais touchee) ; B supprimee ici.
    final a = Colle(matiere: 'Maths', start: DateTime(2026, 9, 10, 16));
    final b = Colle(matiere: 'Physique', start: DateTime(2026, 9, 11, 16));
    final c = Colle(matiere: 'Anglais', start: DateTime(2026, 9, 12, 16));
    m.colles.addAll([a, c]);
    m.majEnregistrements[a.id] = DateTime(2026, 9, 5);
    m.suppressions[b.id] = DateTime(2026, 9, 6);
    // DISTANT : A en version plus VIEILLE (le 3), B toujours presente
    // (jamais retouchee la-bas), D nouvelle.
    final aDistant = Colle(
        id: a.id,
        matiere: 'Maths',
        start: DateTime(2026, 9, 10, 16),
        note: 15);
    final d = Colle(matiere: 'SII', start: DateTime(2026, 9, 13, 16));
    final resume = m.fusionnerDonnees(jsonEncode({
      'colles': [aDistant.toJson(), b.toJson(), d.toJson()],
      'majEnregistrements': {a.id: DateTime(2026, 9, 3).toIso8601String()},
    }));
    // Union : A + C + D ; B reste MORTE (tombale locale plus recente).
    expect(m.colles.map((x) => x.id).toSet(), {a.id, c.id, d.id});
    // A locale plus recente : la note distante n'ecrase pas.
    expect(m.colles.firstWhere((x) => x.id == a.id).note, isNull);
    expect(resume, contains('1 ajouté'));
    // Cas inverse : le distant plus RECENT gagne.
    m.fusionnerDonnees(jsonEncode({
      'colles': [aDistant.toJson()],
      'majEnregistrements': {a.id: DateTime(2026, 9, 8).toIso8601String()},
    }));
    expect(m.colles.firstWhere((x) => x.id == a.id).note, 15);
    // Suppression DISTANTE d'un enregistrement local jamais retouche.
    m.fusionnerDonnees(jsonEncode({
      'suppressions': {c.id: DateTime(2026, 9, 9).toIso8601String()},
    }));
    expect(m.colles.any((x) => x.id == c.id), isFalse);
  });

  test('fusion : deleteColle pose une pierre tombale, updateColle un '
      'horodatage', () {
    final a = Colle(matiere: 'Maths', start: DateTime(2026, 9, 10, 16));
    m.colles.add(a);
    m.updateColle(a);
    expect(m.majEnregistrements.containsKey(a.id), isTrue);
    m.deleteColle(a.id);
    expect(m.suppressions.containsKey(a.id), isTrue);
    expect(m.majEnregistrements.containsKey(a.id), isFalse);
  });

  test('progression : histogramme hebdo, minutes par matière, tendance de '
      'notes', () {
    final now = DateTime(2026, 10, 20, 18); // mardi (lundi = 19/10)
    m.seances.add(Seance(
        matiere: 'Maths', date: DateTime(2026, 10, 19, 20), minutes: 60));
    m.seances.add(Seance(
        matiere: 'Maths', date: DateTime(2026, 10, 12, 20), minutes: 30));
    m.seances.add(Seance(
        matiere: 'Physique', date: DateTime(2026, 10, 13, 20), minutes: 45));
    final histo = m.minutesParSemaineHisto(maintenant: now, semaines: 3);
    expect(histo, hasLength(3));
    expect(histo.last.$2, 60); // semaine courante
    expect(histo[1].$2, 75); // semaine precedente
    final parMat = m.minutesParMatiere(maintenant: now);
    expect(parMat.first, ('Maths', 90));
    // Tendance : 12 sur les 30 derniers jours, 10 sur les 30 d'avant.
    m.colles.add(
        Colle(matiere: 'Maths', start: DateTime(2026, 10, 5, 16), note: 12));
    m.ds.add(Ds(matiere: 'Maths', date: DateTime(2026, 9, 1), note: 10));
    final (recente, ancienne) = m.tendanceNotes('Maths', maintenant: now);
    expect(recente, 12);
    expect(ancienne, 10);
  });

  test('sauvegarde : citations, voc, trajet et interro survivent au round-trip',
      () {
    m.addCitation(Citation(
        texte: 'Vivre sans temps mort',
        auteur: 'Vaneigem',
        axe: 'la liberté',
        usage: 'pour montrer que la contrainte tue l\'élan'));
    m.addMotVocab(MotVocab(
        francais: 'pallier', anglais: 'to make up for', pourColle: true));
    m.trajetMinutes = 45;
    m.ds.add(Ds(matiere: 'Maths', date: DateTime(2026, 10, 10), interro: true));
    final raw = m.exportJson();
    reset(m);
    expect(m.citations, isEmpty);
    m.importJson(raw);
    expect(m.citations, hasLength(1));
    expect(m.citations.first.auteur, 'Vaneigem');
    expect(m.citations.first.usage, contains('contrainte'));
    expect(m.vocab, hasLength(1));
    expect(m.vocab.first.pourColle, isTrue);
    expect(m.trajetMinutes, 45);
    expect(m.ds.first.interro, isTrue);
  });

  // ---------- v0.21 : retours d'usage reel ----------

  test('devoir de vacances : visible tout l’été et ÉTALÉ sur les jours '
      'restants', () {
    final now = DateTime(2026, 8, 4, 10);
    m.sansCours.add(PlageSansCours(
        titre: 'Été',
        debut: DateTime(2026, 7, 1),
        fin: DateTime(2026, 8, 31),
        type: 'ete'));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 1, maitrise: 2));
    // Exos donnes pour la rentree : 6 h annoncees, a rendre dans 28 jours.
    // AVANT : invisibles (le plan d'ete ignorait tout devoir a > 10 jours).
    m.devoirs.add(Devoir(
      matiere: 'Maths',
      titre: 'Exos de rentrée',
      dateRendu: DateTime(2026, 9, 1),
      dateDonne: DateTime(2026, 7, 5),
      dureeEstimeeMin: 360,
    ));
    final s = suggere(m, 240, maintenant: now);
    final bloc = s.where((x) => x.titre.contains('Exos de rentrée')).toList();
    expect(bloc, isNotEmpty, reason: 'le devoir de rentrée doit être visible');
    // 6 h sur 29 jours -> une seance courte, jamais le mur des 6 h.
    expect(bloc.first.minutes, lessThanOrEqualTo(60));
    expect(bloc.first.raison, contains('6 h annoncées'));
  });

  test('minutesPourDevoir : la charge annoncée x', () {
    final now = DateTime(2026, 9, 1, 18);
    final loin = Devoir(
        matiere: 'Maths',
        dateRendu: DateTime(2026, 9, 11),
        dureeEstimeeMin: 600);
    final proche = Devoir(
        matiere: 'Maths',
        dateRendu: DateTime(2026, 9, 2),
        dureeEstimeeMin: 600);
    // 10 h sur 11 jours -> ~1 h par jour ; sur 2 jours -> le plafond.
    expect(minutesPourDevoir(loin, now, 240), lessThan(90));
    expect(minutesPourDevoir(proche, now, 240),
        greaterThan(minutesPourDevoir(loin, now, 240)));
    // Sans charge annoncee : bloc standard d'une heure.
    final sansCharge =
        Devoir(matiere: 'Maths', dateRendu: DateTime(2026, 9, 11));
    expect(minutesPourDevoir(sansCharge, now, 240), 60);
  });

  test('DS avec programme annoncé : ce sont CES chapitres qui remontent', () {
    final now = DateTime(2026, 10, 5, 18);
    final vise =
        Chapitre(matiere: 'Maths', nom: 'Séries entières', etape: 1, maitrise: 1);
    final autre =
        Chapitre(matiere: 'Maths', nom: 'Topologie', etape: 1, maitrise: 3);
    m.chapitres.addAll([vise, autre]);
    m.ds.add(Ds(
        matiere: 'Maths',
        titre: 'DS 3',
        date: DateTime(2026, 10, 9),
        chapitreIds: [vise.id]));
    final s = suggere(m, 120, maintenant: now);
    final maths = s.where((x) => x.matiere == 'Maths').toList();
    expect(maths, isNotEmpty);
    expect(maths.first.titre, contains('Au programme du DS'));
    expect(maths.first.titre, contains('Séries entières'));
  });

  test('matière déjà faite aujourd’hui : elle ne revient pas dans le plan',
      () {
    final now = DateTime(2026, 10, 5, 18);
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 1, maitrise: 2));
    m.chapitres.add(
        Chapitre(matiere: 'Physique', nom: 'Optique', etape: 1, maitrise: 2));
    expect(suggere(m, 120, maintenant: now).any((x) => x.matiere == 'Maths'),
        isTrue);
    m.marquerFait('Maths', maintenant: now);
    expect(suggere(m, 120, maintenant: now).any((x) => x.matiere == 'Maths'),
        isFalse);
    // Le lendemain, la matiere revient normalement.
    expect(
        suggere(m, 120, maintenant: DateTime(2026, 10, 6, 18))
            .any((x) => x.matiere == 'Maths'),
        isTrue);
  });

  test('EPL/S : un bloc par jour, rotation sur les 4 épreuves, coché il '
      'disparaît', () {
    // Lundi 5 octobre 2026 et les 3 jours suivants (aucun dimanche).
    m.eplS = true;
    final s1 = suggere(m, 120, maintenant: DateTime(2026, 10, 5, 18))
        .where((x) => x.matiere == 'EPL/S')
        .toList();
    expect(s1, hasLength(1));
    // 4 jours d'affilée couvrent les 4 épreuves (maths, physique, anglais,
    // psychotechnique) : la rotation ne se répète pas avant.
    final titres = <String>{
      for (var j = 0; j < 4; j++)
        suggere(m, 120, maintenant: DateTime(2026, 10, 5 + j, 18))
            .firstWhere((x) => x.matiere == 'EPL/S')
            .titre
    };
    expect(titres, hasLength(4));
    // Coché aujourd'hui -> le bloc ne revient pas dans la soirée.
    m.marquerFait('EPL/S', maintenant: DateTime(2026, 10, 5, 18));
    expect(
        suggere(m, 120, maintenant: DateTime(2026, 10, 5, 19))
            .any((x) => x.matiere == 'EPL/S'),
        isFalse);
    // Compte à rebours des la date connue, series allongees a J-30.
    m.dateEplS = DateTime(2026, 10, 30);
    final proche = suggere(m, 120, maintenant: DateTime(2026, 10, 6, 18))
        .firstWhere((x) => x.matiere == 'EPL/S');
    expect(proche.raison, contains('écrits dans 24 j'));
    expect(proche.minutes, 30);
    // Un mois apres les ecrits, le bloc s'eteint tout seul.
    expect(
        suggere(m, 120, maintenant: DateTime(2026, 12, 15, 18))
            .any((x) => x.matiere == 'EPL/S'),
        isFalse);
    // Mode coupe -> rien.
    m.eplS = false;
    expect(
        suggere(m, 120, maintenant: DateTime(2026, 10, 7, 18))
            .any((x) => x.matiere == 'EPL/S'),
        isFalse);
  });

  test('EPL/S : le bloc tourne aussi en mode été et en mode révisions', () {
    m.eplS = true;
    m.dateEplS = null; // autonome : ne pas heriter de la date du test precedent
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 1, maitrise: 2));
    // Été.
    m.sansCours.add(PlageSansCours(
        titre: 'Été',
        debut: DateTime(2026, 7, 1),
        fin: DateTime(2026, 8, 31),
        type: 'ete'));
    expect(
        suggere(m, 180, maintenant: DateTime(2026, 8, 4, 10))
            .any((x) => x.matiere == 'EPL/S'),
        isTrue,
        reason: 'été');
    // Révisions concours (< 90 j des écrits CPGE).
    m.sansCours.clear();
    m.dateConcours = DateTime(2027, 4, 20);
    expect(
        suggere(m, 180, maintenant: DateTime(2027, 3, 1, 18))
            .any((x) => x.matiere == 'EPL/S'),
        isTrue,
        reason: 'révisions');
  });

  test('EPL/S : survit au round-trip de sauvegarde', () {
    m.eplS = true;
    m.dateEplS = DateTime(2027, 4, 26);
    final j = m.exportJsonCompact();
    expect(j, contains('"eplS":true'));
    expect(j, contains('2027-04-26'));
  });

  test('été implicite : en août SANS plage saisie, le plan passe quand même '
      'en réactivation et demande le ressenti', () {
    // Le cas du camarade qui recoit le lien : chapitres importes (deja
    // vus) mais AUCUNE plage ete, reactivation jamais planifiee.
    final now = DateTime(2026, 8, 4, 18); // mardi, debut aout (rentree loin)
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 1, maitrise: 2));
    final s = suggere(m, 120, maintenant: now);
    expect(s, isNotEmpty);
    final bloc = s.firstWhere((x) => x.chapitreId != null);
    expect(bloc.raison, contains('réactivation'));
    // rappel:true -> le ✓ ouvre la feuille de ressenti.
    expect(bloc.rappel, isTrue);
    // L'evaluation INSCRIT le chapitre dans l'espacement : « ca va »
    // espace de x1,7 (intervalle 1 -> 2 j), donc le canal « Rappel »
    // 15 min prend le relais a J+2.
    m.evaluerRevision(bloc.chapitreId!, 'cava', maintenant: now);
    final aJPlus2 = suggere(m, 120, maintenant: DateTime(2026, 8, 6, 18));
    final rappel = aJPlus2.firstWhere((x) => x.chapitreId != null);
    expect(rappel.titre, contains('Rappel'));
    expect(rappel.minutes, 15);
  });

  test('été implicite : hors juillet/août sans plage, le mode normal reste '
      'inchangé', () {
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 1, maitrise: 2));
    final s = suggere(m, 120, maintenant: DateTime(2026, 10, 5, 18));
    expect(s.any((x) => x.raison.contains('réactivation')), isFalse);
  });

  test('bandeau « Planifier » : un chapitre littéraire ne le maintient pas '
      'après une planification réussie', () {
    // Le cas du camarade : Maths ET Anglais marques « deja vus », aucune
    // plage saisie, on est en aout.
    final now = DateTime(2026, 8, 4, 18);
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 1, maitrise: 2));
    m.chapitres.add(
        Chapitre(matiere: 'Anglais', nom: 'Voc kholle', etape: 1, maitrise: 2));
    // Avant : le bandeau a une raison de s'afficher (Maths a planifier).
    expect(m.chapitresSansReactivation(), hasLength(1));
    expect(m.chapitresSansReactivation().first.matiere, 'Maths');
    // Planifier — sans plage saisie, la fin implicite est le 31 aout.
    final n = m.etalerReactivation(maintenant: now);
    expect(n, 1, reason: 'Maths planifie, Anglais exclu (litteraire)');
    // INVARIANT du bandeau : apres une planification reussie, plus rien a
    // planifier -> le bandeau disparait (il partage cette liste).
    expect(m.chapitresSansReactivation(), isEmpty);
    expect(
        m.chapitres.firstWhere((c) => c.matiere == 'Maths').prochaineRevision,
        isNotNull);
  });

  test('bloc DM coché : il disparaît du plan du jour et revient demain', () {
    final now = DateTime(2026, 8, 4, 18);
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 1, maitrise: 2));
    m.devoirs.add(Devoir(
      id: 'dm-test',
      matiere: 'Maths',
      titre: 'Exos de rentrée',
      dateRendu: DateTime(2026, 9, 1),
      dateDonne: DateTime(2026, 7, 6),
      dureeEstimeeMin: 360,
    ));
    bool blocDm(Suggestion x) => x.devoirId == 'dm-test';
    expect(suggere(m, 240, maintenant: now).any(blocDm), isTrue);
    // Le ✓ marque le creneau du jour (cle dediee au devoir).
    m.marquerFait('dm:dm-test', maintenant: now);
    expect(suggere(m, 240, maintenant: now).any(blocDm), isFalse,
        reason: 'coche, le creneau ne doit pas revenir ce soir');
    // Demain, l'etalement reprend normalement.
    expect(
        suggere(m, 240, maintenant: DateTime(2026, 8, 5, 18)).any(blocDm),
        isTrue);
  });

  test('etalerReactivation est NON DESTRUCTIF : un chapitre deja programme '
      'garde sa date et son intervalle', () {
    final now = DateTime(2026, 8, 4);
    // Deja dans la repetition espacee : intervalle gagne de 20 j.
    final rode = Chapitre(
        matiere: 'Maths',
        nom: 'Rodé',
        etape: 2,
        maitrise: 3,
        intervalleJours: 20,
        prochaineRevision: DateTime(2026, 8, 20));
    rode.dernierRevu = DateTime(2026, 7, 31);
    final vierge =
        Chapitre(matiere: 'Physique', nom: 'Vierge', etape: 1, maitrise: 2);
    m.chapitres.addAll([rode, vierge]);
    final n = m.etalerReactivation(maintenant: now);
    // Seul le chapitre hors systeme est planifie.
    expect(n, 1);
    expect(vierge.prochaineRevision, isNotNull);
    // Le chapitre rode n'a PAS bouge (replanifier ecrasait des semaines de
    // progression : revisions retassees, intervalles remis a 7).
    expect(rode.prochaineRevision, DateTime(2026, 8, 20));
    expect(rode.intervalleJours, 20);
  });

  test('reparerEspacement : guerit une revision due avant '
      'dernierRevu + intervalle (donnees ecrasees par l ancien etaleur)', () {
    final casse = Chapitre(
        matiere: 'Maths',
        nom: 'Écrasé',
        etape: 2,
        intervalleJours: 7,
        prochaineRevision: DateTime(2026, 8, 27));
    casse.dernierRevu = DateTime(2026, 8, 26); // revu hier, du demain : KO
    final sain = Chapitre(
        matiere: 'Physique',
        nom: 'Sain',
        etape: 2,
        intervalleJours: 10,
        prochaineRevision: DateTime(2026, 9, 5));
    sain.dernierRevu = DateTime(2026, 8, 26);
    // Retard legitime : du bien APRES dernierRevu + intervalle a l'epoque —
    // simplement jamais fait. Ne doit pas bouger.
    final enRetard = Chapitre(
        matiere: 'SII',
        nom: 'En retard',
        etape: 2,
        intervalleJours: 5,
        prochaineRevision: DateTime(2026, 7, 1));
    enRetard.dernierRevu = DateTime(2026, 6, 26);
    m.chapitres.addAll([casse, sain, enRetard]);
    expect(m.reparerEspacement(), 1);
    expect(casse.prochaineRevision, DateTime(2026, 9, 2)); // 26/08 + 7 j
    expect(sain.prochaineRevision, DateTime(2026, 9, 5));
    expect(enRetard.prochaineRevision, DateTime(2026, 7, 1));
  });

  // ---------- Audit v0.24 : findings verifies ----------

  test('semaine A/B : la parité SURVIT au changement d\u2019heure de mars', () {
    // Reference posee un lundi d'HEURE D'HIVER. En local, 21 semaines plus
    // tard (apres le passage a l'heure d'ete), la difference vaut
    // 147 j - 1 h que .inDays tronquait a 146 -> parite INVERSEE pendant
    // sept mois, pile la periode des revisions.
    m.refSemaineA = DateTime(2025, 11, 3); // lundi, heure d'hiver
    // Meme parite : 0 et 21 semaines plus tard (21 impaire -> semaine B).
    expect(m.semaineEstA(DateTime(2025, 11, 3)), isTrue);
    expect(m.semaineEstA(DateTime(2025, 11, 10)), isFalse);
    // Lundi 30 mars 2026 : premiere semaine APRES le passage a l'heure
    // d'ete, 21 semaines apres la reference -> B (l'ancien code disait A).
    expect(m.semaineEstA(DateTime(2026, 3, 30)), isFalse);
    expect(m.semaineEstA(DateTime(2026, 4, 6)), isTrue);
    // Et en plein ete aussi.
    expect(m.semaineEstA(DateTime(2026, 6, 22)), isFalse,
        reason: '33 semaines apres la reference (impair) = B');
  });

  test('erreurs : successive relearning — une coche ne suffit pas, deux '
      'succès espacés consolident', () {
    final e = Erreur(matiere: 'Maths', texte: 'Signe oublié');
    final now = DateTime(2026, 10, 6);
    // Jamais refaite : a refaire.
    expect(e.aRefaire(now), isTrue);
    // Refaite AUJOURD'HUI : sort de la file...
    e.refaite = true;
    e.refaiteLe = now;
    e.foisRefaite = 1;
    expect(e.aRefaire(now), isFalse);
    // ... mais REVIENT 30 j plus tard (un seul succes ne consolide pas).
    expect(e.aRefaire(now.add(const Duration(days: 35))), isTrue);
    // Deux succes espaces : consolidee pour de bon.
    e.foisRefaite = 2;
    expect(e.aRefaire(now.add(const Duration(days: 100))), isFalse);
  });

  test('erreurs : proposées aussi en modes révisions et été (elles ne '
      'sortaient jamais hors période de khôlle)', () {
    final now = DateTime(2027, 3, 1, 18);
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 2, maitrise: 2));
    m.erreurs.add(Erreur(matiere: 'Maths', texte: 'Signe oublié'));
    // Mode revisions (concours a J-50).
    m.dateConcours = DateTime(2027, 4, 20);
    final sRev = suggere(m, 180, maintenant: now);
    expect(sRev.any((x) => x.titre.contains('erreur')), isTrue,
        reason: 'revisions : le cahier d erreurs doit tourner');
    // Mode ete.
    m.dateConcours = null;
    expect(
        suggere(m, 180, maintenant: DateTime(2026, 8, 4, 18))
            .any((x) => x.titre.contains('erreur')),
        isTrue,
        reason: 'ete : idem');
  });

  test('vacances : un DM urgent ne prend jamais DEUX créneaux le même soir',
      () {
    final now = DateTime(2026, 8, 10, 18); // vacances d'ete... mode ete ?
    // Vacances de Toussaint plutot : plage 'vacances', mode normal.
    m.sansCours.add(PlageSansCours(
        titre: 'Toussaint',
        debut: DateTime(2026, 10, 17),
        fin: DateTime(2026, 11, 1),
        type: 'vacances'));
    m.chapitres
        .add(Chapitre(matiere: 'Maths', nom: 'Séries', etape: 2, maitrise: 2));
    m.devoirs.add(Devoir(
      id: 'dm-6h',
      matiere: 'Maths',
      titre: 'DM 4',
      dateRendu: DateTime(2026, 10, 24),
      dateDonne: DateTime(2026, 10, 15),
      dureeEstimeeMin: 360,
    ));
    final s = suggere(m, 180, maintenant: DateTime(2026, 10, 20, 18));
    expect(s.where((x) => x.devoirId == 'dm-6h').length, lessThanOrEqualTo(1),
        reason: 'creneau dedie + etaleur vacances ne doivent pas doubler');
    expect(now, isNotNull); // (utilise pour eviter le lint unused)
  });

  // ---------- Tableau de bord (lib/stats.dart) ----------

  test('série : jours consécutifs, tolérante au jour en cours', () {
    final now = DateTime(2026, 10, 6, 19); // mardi
    // Travaille les 3 jours precedents + aujourd'hui.
    for (var d = 0; d < 4; d++) {
      m.seances.add(Seance(
          matiere: 'Maths',
          date: DateTime(2026, 10, 6 - d, 20),
          minutes: 60));
    }
    expect(serieEnCours(m, maintenant: now), 4);
    // Un trou casse la serie : on ajoute un jour isole 10 j avant.
    m.seances.add(
        Seance(matiere: 'Maths', date: DateTime(2026, 9, 26), minutes: 60));
    expect(serieEnCours(m, maintenant: now), 4, reason: 'le trou coupe');
    expect(meilleureSerie(m), 4);
    // RIEN aujourd'hui a 8 h du matin : la serie de la veille TIENT (on ne
    // casse pas une serie avant que la soiree ait eu lieu).
    m.seances.removeWhere((x) => x.date.day == 6);
    expect(serieEnCours(m, maintenant: DateTime(2026, 10, 6, 8)), 3);
    // Mais deux jours sans rien, la serie tombe.
    expect(serieEnCours(m, maintenant: DateTime(2026, 10, 7, 20)), 0);
  });

  test('état mémoire : maîtrise, file, intervalle moyen, littéraires exclus',
      () {
    final now = DateTime(2026, 10, 6, 19);
    m.chapitres.add(Chapitre(
        matiere: 'Maths',
        nom: 'A',
        etape: 2,
        maitrise: 4,
        intervalleJours: 30,
        prochaineRevision: DateTime(2026, 11, 1)));
    m.chapitres.add(Chapitre(
        matiere: 'Maths',
        nom: 'B',
        etape: 2,
        maitrise: 1,
        intervalleJours: 10,
        prochaineRevision: DateTime(2026, 10, 2))); // en retard
    m.chapitres.add(
        Chapitre(matiere: 'Physique', nom: 'C', etape: 1, maitrise: 2));
    // Un chapitre LITTERAIRE ne compte pas (rien a reviser en chapitres).
    m.chapitres.add(
        Chapitre(matiere: 'Anglais', nom: 'Voc', etape: 1, maitrise: 0));
    final e = etatMemoire(m, maintenant: now);
    expect(e.parMaitrise[4], 1);
    expect(e.parMaitrise[1], 1);
    expect(e.parMaitrise[2], 1);
    expect(e.parMaitrise[0], 0, reason: 'le chapitre d anglais est exclu');
    expect(e.programmes, 2);
    expect(e.horsSysteme, 1, reason: 'Physique C : commence, jamais programme');
    expect(e.dus, 1);
    expect(e.enRetard, 1);
    expect(e.intervalleMoyen, 20); // (30 + 10) / 2
    expect(e.consolides, 1);
  });

  test('notes : khôlles et DS séparés, écart à la moyenne de classe', () {
    m.colles.add(Colle(
        matiere: 'Maths', start: DateTime(2026, 10, 1, 16), note: 14));
    m.colles.add(Colle(
        matiere: 'Maths', start: DateTime(2026, 10, 3, 16), note: 16));
    m.ds.add(Ds(
        matiere: 'Maths',
        date: DateTime(2026, 10, 2),
        note: 9,
        moyenneClasse: 7)); // sous 10 mais AU-DESSUS de la classe
    final (kh, dsM, ecart) = moyennesMatiere(m, 'Maths');
    expect(kh, 15);
    expect(dsM, 9);
    expect(ecart, 2, reason: 'un 9 pour 7 de moyenne est une bonne note');
    // Historique chronologique, kholles et DS melanges.
    final h = historiqueNotes(m, 'Maths');
    expect(h.map((e) => e.$2).toList(), [14, 9, 16]);
  });

  test('cahier d’erreurs : répartition par type et bilan de consolidation',
      () {
    final now = DateTime(2026, 10, 6);
    m.erreurs.add(Erreur(matiere: 'Maths', texte: 'a', type: 'Calcul'));
    m.erreurs.add(Erreur(matiere: 'Maths', texte: 'b', type: 'Calcul'));
    m.erreurs.add(Erreur(matiere: 'Physique', texte: 'c', type: 'Cours'));
    final consolidee = Erreur(matiere: 'Maths', texte: 'd', type: 'Calcul')
      ..refaite = true
      ..foisRefaite = 2
      ..refaiteLe = now;
    m.erreurs.add(consolidee);
    expect(erreursPar(m, 'type').first, ('Calcul', 3));
    final (total, cons, attente) = bilanErreurs(m, maintenant: now);
    expect(total, 4);
    expect(cons, 1);
    expect(attente, 3);
  });

  test('temps : total 30 j et rythme par jour de semaine', () {
    final now = DateTime(2026, 10, 6, 19);
    m.seances.add(
        Seance(matiere: 'Maths', date: DateTime(2026, 10, 5), minutes: 120));
    m.seances.add(
        Seance(matiere: 'Maths', date: DateTime(2026, 9, 28), minutes: 60));
    // Hors fenetre de 30 j : ignoree.
    m.seances.add(
        Seance(matiere: 'Maths', date: DateTime(2026, 8, 1), minutes: 999));
    expect(minutesTotal(m, maintenant: now, jours: 30), 180);
    // Les deux seances tombent un LUNDI (index 0) : moyenne non nulle.
    final parJour = minutesParJourSemaine(m, maintenant: now, jours: 56);
    expect(parJour[0], greaterThan(0));
    expect(parJour[2], 0, reason: 'aucun mercredi travaille');
  });

  // ---------- Findings de gravité 1 écartés par le filtre de l'audit ----------

  test('rotation : l’ancre est en UTC — pas de jour rejoué au changement '
      'd’heure', () {
    // 29 mars 2026 = dernier jour d'heure d'hiver, 30 mars = premier jour
    // d'heure d'ete. En heure LOCALE, la difference avec l'ancre perdait
    // 1 h et .inDays tronquait : deux jours de suite recevaient le meme
    // index de rotation.
    final avant = jourRotation(DateTime(2026, 3, 29));
    final apres = jourRotation(DateTime(2026, 3, 30));
    expect(apres, avant + 1, reason: 'le 30 mars doit avancer d’un cran');
    // Et le retour a l'heure d'hiver ne doit pas sauter de jour non plus.
    expect(jourRotation(DateTime(2026, 10, 26)),
        jourRotation(DateTime(2026, 10, 25)) + 1);
    // Une annee entiere = 365 crans exactement.
    expect(jourRotation(DateTime(2027, 1, 1)) - jourRotation(DateTime(2026, 1, 1)),
        365);
  });

  test('EPL/S : le bloc ne dépasse jamais le budget du soir', () {
    m.eplS = true;
    m.dateEplS = DateTime(2026, 10, 20); // J-14 : le bloc veut s’allonger
    final now = DateTime(2026, 10, 6, 19);
    // Budget de 25 min : le bloc long (30) ne tient pas -> il reste à 20.
    final court = suggestionEplS(m, now, 25);
    expect(court, isNotNull);
    expect(court!.minutes, 20, reason: 'jamais plus que le budget restant');
    // Budget confortable : il s’allonge comme prévu.
    expect(suggestionEplS(m, now, 60)!.minutes, 30);
  });

  test('« ce qui est tombé en khôlle » ressort avant le DS de la matière',
      () {
    final now = DateTime(2026, 10, 6, 18);
    final c = Chapitre(
        matiere: 'Maths', nom: 'Séries entières', etape: 1, maitrise: 1);
    m.chapitres.add(c);
    // Une khôlle passée AVEC son post-mortem.
    m.colles.add(Colle(
        matiere: 'Maths',
        start: DateTime(2026, 9, 29, 16),
        note: 14,
        remarque: 'question de cours Cauchy-Lipschitz'));
    // Une khôlle trop ancienne (> 5 semaines) : elle ne doit PAS ressortir.
    m.colles.add(Colle(
        matiere: 'Maths',
        start: DateTime(2026, 7, 1, 16),
        remarque: 'vieux sujet oublié'));
    expect(tombeEnKholles(m, 'Maths', now), 'question de cours Cauchy-Lipschitz');
    // Et un DS annoncé fait ressortir l’info dans le plan du soir.
    m.ds.add(Ds(
        matiere: 'Maths',
        titre: 'DS 3',
        date: DateTime(2026, 10, 9),
        chapitreIds: [c.id]));
    final maths = suggere(m, 120, maintenant: now)
        .firstWhere((x) => x.matiere == 'Maths');
    expect(maths.titre, contains('Tombé en khôlle'));
    expect(maths.titre, contains('Cauchy-Lipschitz'));
  });

  test('Physique-Chimie : la matière fusionnée couvre ses composantes '
      '(programme du DS, échéances)', () {
    expect(matiereCouvre('Physique-Chimie', 'Physique'), isTrue);
    expect(matiereCouvre('Physique-Chimie', 'Chimie'), isTrue);
    expect(matiereCouvre('Physique/Chimie', 'chimie'), isTrue);
    expect(matiereCouvre('Physique-Chimie', 'Maths'), isFalse);
    expect(matiereCouvre('Physique', 'Physique-Chimie'), isFalse);
    expect(matiereCouvre('Physique', 'Physique'), isTrue);

    // Chapitres saisis dans Physique et Chimie, DS dans la matiere FUSIONNEE.
    final now = DateTime(2026, 10, 6, 18);
    final cPhys = Chapitre(
        matiere: 'Physique', nom: 'Induction', etape: 1, maitrise: 1);
    final cChim =
        Chapitre(matiere: 'Chimie', nom: 'Cinétique', etape: 1, maitrise: 2);
    m.chapitres.addAll([cPhys, cChim]);
    m.ds.add(Ds(
        matiere: 'Physique-Chimie',
        titre: 'DS 1',
        date: DateTime(2026, 10, 10),
        chapitreIds: [cPhys.id, cChim.id]));
    final s = suggere(m, 180, maintenant: now);
    // Le bloc Physique (composante) connait le programme du DS fusionne.
    final phys = s.where((x) => x.matiere == 'Physique').toList();
    expect(phys, isNotEmpty, reason: 'le DS fusionné crée une échéance Physique');
    expect(phys.first.titre, contains('Au programme du DS'));
  });

  test('DS avec heure : sérialisation aller-retour', () {
    final d = Ds(
        matiere: 'Physique-Chimie',
        titre: 'DS 1',
        date: DateTime(2026, 10, 10),
        debutMin: 8 * 60,
        dureeMin: 240);
    final r = Ds.fromJson(d.toJson());
    expect(r.debutMin, 480);
    expect(r.dureeMin, 240);
    // Sans heure : les valeurs par defaut restent stables.
    final sans = Ds.fromJson(
        Ds(matiere: 'Maths', date: DateTime(2026, 10, 10)).toJson());
    expect(sans.debutMin, isNull);
    expect(sans.dureeMin, 120);
  });

  test('EDT en « Physique-Chimie » : le bonus cours du jour touche Physique '
      'et Chimie', () {
    final now = DateTime(2026, 10, 6, 18); // mardi
    m.chapitres.add(
        Chapitre(matiere: 'Physique', nom: 'Induction', etape: 2, maitrise: 2));
    m.chapitres.add(
        Chapitre(matiere: 'Maths', nom: 'Séries', etape: 2, maitrise: 2));
    // Cours de la matiere FUSIONNEE ce mardi a l'EDT.
    m.routines.add(Routine(
        titre: 'Physique-Chimie',
        matiere: 'Physique-Chimie',
        jour: 2,
        debutMin: 600,
        dureeMin: 120));
    // Une autre routine pour que la journee ne soit pas « libre ».
    m.routines.add(
        Routine(titre: 'Maths', matiere: 'Maths', jour: 2, debutMin: 480, dureeMin: 60));
    final s = suggere(m, 120, maintenant: now);
    final phys = s.firstWhere((x) => x.matiere == 'Physique');
    expect(phys.raison, contains('Cours d'), 
        reason: 'le cours fusionné doit booster la composante Physique');
  });
}
