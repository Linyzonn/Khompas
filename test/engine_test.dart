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
