// SIMULATEUR D'ELEVES : le moteur est execute JOUR PAR JOUR pendant des
// mois avec une horloge injectee. Un « eleve » deterministe fait chaque
// soir une partie du plan (verdicts pseudo-aleatoires reproductibles), et
// tout est journalise dans build/sim/<profil>.jsonl pour analyse.
//
// Objectif : voir ce qui casse A LA DUREE (accumulation de la file de
// revisions, DM jamais rendus, plans vides, doublons) — ce que les tests
// unitaires a un instant donne ne peuvent pas voir.
//
// Le test lui-meme n'echoue que sur des INVARIANTS durs (budget respecte,
// pas de doublon un meme soir) : le reste est observationnel, a lire dans
// les journaux et le resume final build/sim/resume.json.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khompas/engine.dart';
import 'package:khompas/models.dart';
import 'package:khompas/store.dart';

// ---------- Pseudo-aleatoire DETERMINISTE (rejouable a l'identique) ----------
int _hash(int x) {
  x = ((x >> 16) ^ x) * 0x45d9f3b;
  x = ((x >> 16) ^ x) * 0x45d9f3b;
  return ((x >> 16) ^ x) & 0x7fffffff;
}

/// Reel dans [0, 1) dependant du jour et d'un sel — jamais de Random().
double alea(int jour, int sel) => (_hash(jour * 7919 + sel) % 10000) / 10000.0;

/// Remise a zero complete du modele partage entre profils.
void resetSim(AppModel m) {
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
  m.cinqDemi = false;
  m.objectifs = {};
  m.codeClasse = '';
}

/// Un profil d'eleve : etat initial + evenements de l'annee + comportement.
class Profil {
  final String nom;
  final DateTime debut;
  final int jours;
  final void Function(AppModel m) installer;
  // Evenements qui tombent CE jour (nouveau chapitre fini en cours, kholle
  // annoncee, DM distribue...) — appele chaque matin.
  final void Function(AppModel m, DateTime date, int jour)? evenements;
  final int Function(DateTime date) budgetMin;
  // Nombre max de blocs traites ce soir (l'assiduite de l'eleve) ;
  // 99 = fait tout ce que le plan propose.
  final int Function(int jour) blocsFaits;
  // true = l'eleve n'ouvre pas l'app ce jour-la.
  final bool Function(int jour) saute;

  const Profil({
    required this.nom,
    required this.debut,
    required this.jours,
    required this.installer,
    this.evenements,
    required this.budgetMin,
    required this.blocsFaits,
    required this.saute,
  });
}

/// Le geste ✓ de l'eleve — MIROIR du handler de today.dart. Si l'un des
/// deux change sans l'autre, la simulation ment : garder synchronises.
void cocher(AppModel m, Suggestion s, DateTime now, int jour, int sel,
    Map<String, int> minParDevoir) {
  m.seances.add(Seance(matiere: s.matiere, date: now, minutes: s.minutes));
  if (s.lecture) {
    // Lire l'enonce : cle a part, ni la matiere ni le DM ne sont « faits ».
    m.marquerFait('lu:${s.devoirId}', maintenant: now);
    return;
  }
  m.marquerFait(s.matiere, maintenant: now);
  if (s.devoirId != null) m.marquerFait('dm:${s.devoirId}', maintenant: now);

  if (s.rappel && s.chapitreId != null) {
    // Feuille de ressenti : 20 % difficile, 60 % ca va, 20 % facile.
    final r = alea(jour, sel);
    final verdict = r < 0.2 ? 'difficile' : (r < 0.8 ? 'cava' : 'facile');
    m.evaluerRevision(s.chapitreId!, verdict, maintenant: now);
    return;
  }
  if (s.oeuvreId != null) {
    final i = m.oeuvres.indexWhere((o) => o.id == s.oeuvreId);
    if (i >= 0) {
      final o = m.oeuvres[i];
      o.pageActuelle = (o.pageActuelle + 25).clamp(0, o.pages ?? 400);
      if (o.pages != null && o.pageActuelle >= o.pages!) o.finie = true;
    }
    return;
  }
  if (s.devoirId != null) {
    final cumul =
        (minParDevoir[s.devoirId!] = (minParDevoir[s.devoirId!] ?? 0) + s.minutes);
    final i = m.devoirs.indexWhere((d) => d.id == s.devoirId);
    if (i >= 0) {
      final d = m.devoirs[i];
      // L'eleve rend quand la charge annoncee est couverte (ou par defaut
      // apres ~3 h de travail dessus).
      final cible = d.dureeEstimeeMin > 0 ? d.dureeEstimeeMin : 180;
      if (cumul >= cible) {
        d.rendu = true;
        m.updateDevoir(d);
      }
    }
    return;
  }
  if (s.chapitreId != null) {
    final i = m.chapitres.indexWhere((c) => c.id == s.chapitreId);
    if (i >= 0) {
      if (m.chapitres[i].prochaineRevision == null) {
        m.demarrerEspacement(s.chapitreId!, maintenant: now);
      } else {
        // Miroir de today.dart : un bloc non-rappel credite dernierRevu —
        // c'est lui qui fait TOURNER la rotation « A revoir ».
        m.chapitres[i].dernierRevu = now;
      }
    }
  }
}

/// Deroule un profil et ecrit son journal. Retourne le resume.
Map<String, dynamic> simuler(Profil p, Directory sortie) {
  final m = AppModel.instance;
  resetSim(m);
  p.installer(m);

  final lignes = <String>[];
  final anomalies = <String, int>{};
  final minParDevoir = <String, int>{};
  var backlogMax = 0;
  var joursCroissance = 0;
  var backlogPrecedent = -1;
  var totalFaits = 0;
  var totalProposes = 0;
  var joursPlanVide = 0;

  for (var j = 0; j < p.jours; j++) {
    final date = p.debut.add(Duration(days: j));
    final now = DateTime(date.year, date.month, date.day, 19);
    p.evenements?.call(m, now, j);

    final dusAvant = rappelsDus(m, maintenant: now).length;
    final budget = p.budgetMin(now);
    final sugg = suggere(m, budget, maintenant: now);
    totalProposes += sugg.length;

    // ---- Invariants durs ----
    final minutesTotal = sugg.fold<int>(0, (t, s) => t + s.minutes);
    if (minutesTotal > budget + 15) {
      anomalies['budget_depasse'] = (anomalies['budget_depasse'] ?? 0) + 1;
    }
    final cles = sugg.map((s) => '${s.matiere}|${s.titre}').toList();
    if (cles.toSet().length != cles.length) {
      anomalies['doublon_meme_soir'] = (anomalies['doublon_meme_soir'] ?? 0) + 1;
    }
    if (sugg.isEmpty && dusAvant > 0 && now.weekday != DateTime.sunday) {
      joursPlanVide++;
    }

    // ---- L'eleve travaille ----
    var faits = <String>[];
    if (!p.saute(j)) {
      final n = p.blocsFaits(j);
      for (final s in sugg.take(n)) {
        cocher(m, s, now, j, faits.length, minParDevoir);
        faits.add('${s.matiere}|${s.titre}|${s.minutes}');
        totalFaits++;
      }
    }

    final dusApres = rappelsDus(m, maintenant: now).length;
    if (backlogPrecedent >= 0 && dusApres > backlogPrecedent) joursCroissance++;
    backlogPrecedent = dusApres;
    if (dusApres > backlogMax) backlogMax = dusApres;

    lignes.add(jsonEncode({
      'j': j,
      'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'sem': date.weekday,
      'dus': dusApres,
      'nSugg': sugg.length,
      'minSugg': minutesTotal,
      'nFaits': faits.length,
      'sugg': [
        for (final s in sugg)
          '${s.matiere}|${s.titre}|${s.minutes}${s.rappel ? '|R' : ''}'
      ],
    }));
  }

  // DM restes non rendus a la fin (echeance passee) : signe d'un etaleur
  // qui n'a pas fait passer assez de creneaux.
  final dmRates = m.devoirs
      .where((d) => !d.rendu && d.dateRendu.isBefore(p.debut.add(Duration(days: p.jours))))
      .length;

  File('${sortie.path}/${p.nom}.jsonl').writeAsStringSync(lignes.join('\n'));
  return {
    'profil': p.nom,
    'jours': p.jours,
    'backlogFin': backlogPrecedent,
    'backlogMax': backlogMax,
    'joursOuLeBacklogCroit': joursCroissance,
    'blocsFaits': totalFaits,
    'blocsProposes': totalProposes,
    'joursPlanVideAvecDus': joursPlanVide,
    'dmNonRendusEchus': dmRates,
    'chapitresConsolides(maitrise4)':
        m.chapitres.where((c) => c.maitrise >= 4).length,
    'intervalleMoyenJ': m.chapitres.isEmpty
        ? 0
        : (m.chapitres.fold<int>(0, (t, c) => t + c.intervalleJours) /
                m.chapitres.length)
            .round(),
    'anomalies': anomalies,
  };
}

// ---------- Constructions partagees ----------

/// Programme d'une annee de sup deja vue : [n] chapitres par matiere,
/// maitrise 2 (« deja vus, a reactiver »).
void programmeImporte(AppModel m,
    {int maths = 35, int physique = 35, int sii = 25}) {
  for (final (mat, n) in [('Maths', maths), ('Physique', physique), ('SII', sii)]) {
    for (var i = 1; i <= n; i++) {
      m.chapitres.add(
          Chapitre(matiere: mat, nom: '$mat ch.$i', etape: 1, maitrise: 2));
    }
  }
  // Matieres litteraires : quelques « chapitres » saisis quand meme (le cas
  // reel du camarade — elles ne doivent PAS entrer dans la reactivation).
  for (var i = 1; i <= 4; i++) {
    m.chapitres.add(
        Chapitre(matiere: 'Anglais', nom: 'Voc $i', etape: 1, maitrise: 2));
  }
}

/// Colloscope + DS + DM d'une periode scolaire (a partir de [rentree]).
void anneeScolaire(AppModel m, DateTime date, int jour, DateTime rentree) {
  if (date.isBefore(rentree)) return;
  final js = date.difference(rentree).inDays;
  // EDT : cours chaque jour de semaine (le soir est une vraie soiree).
  if (js == 0) {
    for (var wd = 1; wd <= 5; wd++) {
      m.routines.add(Routine(titre: 'Cours', jour: wd, debutMin: 480, dureeMin: 480));
    }
  }
  // Une kholle par semaine, matiere en rotation, programmee a J+6.
  if (date.weekday == DateTime.monday) {
    final mat = ['Maths', 'Physique', 'Anglais'][(js ~/ 7) % 3];
    m.colles.add(Colle(
        matiere: mat,
        kholleur: 'K',
        salle: 'S',
        start: DateTime(date.year, date.month, date.day, 17)
            .add(const Duration(days: 6)),
        dureeMin: 60,
        programme: mat == 'Anglais' ? '' : 'Programme ch. ${(js ~/ 7) + 1}'));
  }
  // Un DS toutes les 2 semaines (vendredi J+10), 2 chapitres au programme.
  if (date.weekday == DateTime.monday && (js ~/ 7).isEven) {
    final mat = (js ~/ 14).isEven ? 'Maths' : 'Physique';
    final duMeme = m.chapitres.where((c) => c.matiere == mat).toList();
    m.ds.add(Ds(
        matiere: mat,
        titre: 'DS',
        date: DateTime(date.year, date.month, date.day)
            .add(const Duration(days: 10)),
        coeff: 2,
        chapitreIds: [for (final c in duMeme.take(2)) c.id]));
  }
  // Un DM par semaine (mercredi), a rendre sous 7 jours, 3 h annoncees.
  if (date.weekday == DateTime.wednesday) {
    m.devoirs.add(Devoir(
        matiere: 'Maths',
        titre: 'DM s${js ~/ 7}',
        dateRendu: DateTime(date.year, date.month, date.day)
            .add(const Duration(days: 7)),
        dateDonne: date,
        dureeEstimeeMin: 180));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final m = AppModel.instance;

  test('simulation multi-profils sur plusieurs mois', () {
    final sortie = Directory('build/sim');
    if (!sortie.existsSync()) sortie.createSync(recursive: true);
    final resumes = <Map<String, dynamic>>[];

    // ---------- A. Sup qui demarre en septembre (110 jours) ----------
    resumes.add(simuler(
      Profil(
        nom: 'sup_septembre',
        debut: DateTime(2026, 9, 1),
        jours: 110,
        installer: (m) {
          m.filiere = 'PCSI';
        },
        evenements: (m, date, j) {
          anneeScolaire(m, date, j, DateTime(2026, 9, 1));
          // Un chapitre FINI en cours tous les 5 jours, matiere en rotation.
          if (j % 5 == 0) {
            final mat = ['Maths', 'Physique', 'Chimie'][(j ~/ 5) % 3];
            m.chapitres.add(Chapitre(
                matiere: mat, nom: '$mat nouv.${j ~/ 5}', etape: 1, maitrise: 2));
          }
          // Toussaint (17 oct - 1 nov).
          if (j == 0) {
            m.sansCours.add(PlageSansCours(
                titre: 'Toussaint',
                debut: DateTime(2026, 10, 17),
                fin: DateTime(2026, 11, 1),
                type: 'vacances'));
          }
        },
        budgetMin: (d) => d.weekday >= 6 ? 240 : 120,
        blocsFaits: (j) => 4,
        saute: (j) => false,
      ),
      sortie,
    ));

    // ---------- B. 5/2 : programme importe le 1er aout (122 jours) ----------
    // LE cas utilisateur : 95 chapitres de sciences reactives d'un coup.
    resumes.add(simuler(
      Profil(
        nom: 'cinq_demi_aout',
        debut: DateTime(2026, 8, 1),
        jours: 122,
        installer: (m) {
          m.filiere = 'PSI';
          m.cinqDemi = true;
          programmeImporte(m);
          m.sansCours.add(PlageSansCours(
              titre: 'Été',
              debut: DateTime(2026, 7, 1),
              fin: DateTime(2026, 8, 31),
              type: 'ete'));
          m.etalerReactivation(maintenant: DateTime(2026, 8, 1));
          m.eplS = true;
          m.dateEplS = DateTime(2027, 4, 26);
          for (var i = 1; i <= 3; i++) {
            m.oeuvres.add(Oeuvre(titre: 'Oeuvre $i', auteur: 'A', pages: 320));
          }
        },
        evenements: (m, date, j) {
          anneeScolaire(m, date, j, DateTime(2026, 9, 1));
          // Re-clics sur « Planifier » en cours d'ete : le geste qui a
          // ecrase les donnees reelles (etaleur destructif, v0.23.1). Un
          // etaleur sain doit etre IDEMPOTENT — le backlog ne doit pas
          // sauter apres ces jours-la.
          if (j == 10 || j == 25) m.etalerReactivation(maintenant: date);
        },
        budgetMin: (d) =>
            d.month == 8 || d.weekday >= 6 ? 240 : 120,
        blocsFaits: (j) => 5,
        saute: (j) => false,
      ),
      sortie,
    ));

    // ---------- C. Spe en fevrier -> oraux (120 jours) ----------
    resumes.add(simuler(
      Profil(
        nom: 'spe_revisions',
        debut: DateTime(2027, 2, 1),
        jours: 120,
        installer: (m) {
          m.filiere = 'PSI';
          programmeImporte(m, maths: 30, physique: 30, sii: 20);
          // Chapitres RODES : intervalles varies, revisions deja en cours.
          var k = 0;
          for (final c in m.chapitres.where((c) => c.matiere != 'Anglais')) {
            c.intervalleJours = 5 + (k * 7) % 40;
            c.prochaineRevision =
                DateTime(2027, 2, 1).add(Duration(days: k % 14));
            c.maitrise = 2 + k % 3;
            k++;
          }
          m.dateConcours = DateTime(2027, 4, 20);
          m.eplS = true;
          m.dateEplS = DateTime(2027, 4, 26);
          for (var i = 0; i < 10; i++) {
            m.annales.add(Annale(
                concours: 'CCINP', matiere: i.isEven ? 'Maths' : 'Physique',
                annee: 2016 + i));
          }
          m.sansCours.add(PlageSansCours(
              titre: 'Révisions',
              debut: DateTime(2027, 4, 6),
              fin: DateTime(2027, 4, 19),
              type: 'revisions'));
        },
        evenements: (m, date, j) {
          // Apres les ecrits : mode oraux, 3 epreuves debut juin.
          if (date == DateTime(2027, 5, 2, 19)) {
            m.modeOraux = true;
            for (var i = 0; i < 3; i++) {
              m.oraux.add(EpreuveOrale(
                  concours: 'CCINP',
                  epreuve: ['Maths', 'Physique', 'Anglais'][i],
                  date: DateTime(2027, 6, 10 + i)));
            }
          }
        },
        budgetMin: (d) {
          final revisions = d.isAfter(DateTime(2027, 4, 5)) &&
              d.isBefore(DateTime(2027, 4, 20));
          return revisions ? 360 : (d.weekday >= 6 ? 240 : 150);
        },
        blocsFaits: (j) => 6,
        saute: (j) => false,
      ),
      sortie,
    ));

    // ---------- D. 5/2 irregulier : 1 bloc/soir, saute ~30 % ----------
    resumes.add(simuler(
      Profil(
        nom: 'irregulier',
        debut: DateTime(2026, 8, 1),
        jours: 122,
        installer: (m) {
          m.cinqDemi = true;
          programmeImporte(m);
          m.sansCours.add(PlageSansCours(
              titre: 'Été',
              debut: DateTime(2026, 7, 1),
              fin: DateTime(2026, 8, 31),
              type: 'ete'));
          m.etalerReactivation(maintenant: DateTime(2026, 8, 1));
        },
        evenements: (m, date, j) =>
            anneeScolaire(m, date, j, DateTime(2026, 9, 1)),
        budgetMin: (d) => 90,
        blocsFaits: (j) => 1,
        saute: (j) => alea(j, 42) < 0.3,
      ),
      sortie,
    ));

    // ---------- E. Assidu : fait TOUT ce que le plan propose ----------
    resumes.add(simuler(
      Profil(
        nom: 'assidu',
        debut: DateTime(2026, 8, 1),
        jours: 122,
        installer: (m) {
          m.cinqDemi = true;
          programmeImporte(m);
          m.sansCours.add(PlageSansCours(
              titre: 'Été',
              debut: DateTime(2026, 7, 1),
              fin: DateTime(2026, 8, 31),
              type: 'ete'));
          m.etalerReactivation(maintenant: DateTime(2026, 8, 1));
        },
        evenements: (m, date, j) =>
            anneeScolaire(m, date, j, DateTime(2026, 9, 1)),
        budgetMin: (d) => 180,
        blocsFaits: (j) => 99,
        saute: (j) => false,
      ),
      sortie,
    ));

    File('${sortie.path}/resume.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(resumes));
    // Lisible directement dans la sortie du test.
    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert(resumes));

    // Invariants durs uniquement — le reste est a analyser dans build/sim/.
    for (final r in resumes) {
      final a = r['anomalies'] as Map<String, int>;
      expect(a['budget_depasse'] ?? 0, 0,
          reason: '${r['profil']} : des soirs depassent le budget demande');
      expect(a['doublon_meme_soir'] ?? 0, 0,
          reason: '${r['profil']} : suggestions en double un meme soir');
    }
    resetSim(m);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
