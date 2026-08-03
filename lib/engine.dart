import 'dart:math';

import 'methodes.dart';
import 'models.dart';
import 'store.dart';

/// Une suggestion de travail pour la soiree.
class Suggestion {
  final String matiere;
  final String titre;
  final String raison;
  final int minutes;
  // Chapitre vise : permet de le marquer "revu" d'un tap.
  final String? chapitreId;
  // Devoir vise (DM/exos) : le ✓ propose de le marquer "rendu".
  final String? devoirId;
  // Oeuvre de francais visee (bloc lecture) : le ✓ demande la page atteinte.
  final String? oeuvreId;
  // Rappel espace : le ✓ declenche l'auto-evaluation en 1 tap.
  final bool rappel;
  // Consigne d'action testable (rappel actif) affichee sous la suggestion.
  final String consigne;
  Suggestion(this.matiere, this.titre, this.raison, this.minutes,
      {this.chapitreId,
      this.devoirId,
      this.oeuvreId,
      this.rappel = false,
      this.consigne = ''});
}

/// Le mode revisions concours ne s'active qu'a l'approche des ecrits :
/// avant ce seuil, saisir sa date de concours (des septembre, par exemple)
/// ne doit PAS faire disparaitre kholles, DM et cahier d'erreurs du plan
/// du soir pendant des mois.
const int kSeuilModeRevisionsJours = 90;

/// Ancre fixe et arbitraire pour les rotations "un jour sur N" : seul le
/// nombre de jours ecoules modulo N compte, pas la date elle-meme.
final DateTime kAncreRotation = DateTime(2026);

/// Minutes reellement disponibles ce soir compte tenu de l'heure limite de
/// sommeil. Fonction PURE (testable) : [nowMin] = minutes depuis minuit.
int budgetSoir(
    {required int minutes, required int? limiteMin, required int nowMin}) {
  if (limiteMin == null) return minutes;
  int restant;
  if (limiteMin < 360) {
    // Limite "apres minuit" (ex. 0h30) : valable de la soiree jusqu'a elle.
    restant = nowMin < 360 ? limiteMin - nowMin : limiteMin + 1440 - nowMin;
  } else {
    // Limite du soir (ex. 23h). ATTENTION apres minuit : elle est DEPASSEE
    // (23h - 0h30 donnait 22h30 de budget et zero message sommeil — pile
    // au moment ou il compte le plus).
    restant = nowMin < 360 ? limiteMin - nowMin - 1440 : limiteMin - nowMin;
  }
  if (restant < 0) restant = 0;
  return minutes < restant ? minutes : restant;
}

/// Moteur "Que faire ce soir ?" — volontairement TRANSPARENT :
/// des regles simples et explicables, pas une boite noire.
///
/// Ordre du plan (mode normal) :
/// 1. Rappels du jour (repetition espacee : chapitres dont la revision est due)
/// 2. "Lis le DM distribue aujourd'hui" le cas echeant
/// 3. Scoring par matiere : urgence (kholle/DS/DM) x priorite x fragilite
///    (moyenne + minimum) x bonus cours du jour x jachere (matieres delaissees)
/// En mode REVISIONS CONCOURS : rotation des chapitres, revisions dues d'abord.
/// En mode ETE (grandes vacances) : reactivation douce du programme.
///
/// [maintenant] : horloge injectable (tests deterministes) — par defaut
/// l'heure reelle.
List<Suggestion> suggere(AppModel m, int minutesDispo, {DateTime? maintenant}) {
  final now = maintenant ?? DateTime.now();
  // JOUR OFF (trajet, famille, journee ou travailler est impossible) :
  // pas de plan du tout — la culpabilisation ne fait pas reviser, et le
  // travail reprogramme retombera naturellement demain (rappels en
  // retard, rotation). L'UI affiche une carte dediee.
  if (m.estJourOff(now)) return [];
  // Mode ORAUX (post-ecrits) : prioritaire sur tout le reste.
  if (m.modeOraux && m.oraux.isNotEmpty) {
    return _suggereOraux(m, minutesDispo, now);
  }
  // GRANDES VACANCES : la plage « été » du calendrier bascule le plan en
  // reactivation douce (rotation du programme, annales, repos) — un ete de
  // 5/2 ne ressemble ni a une soiree de semaine ni aux revisions d'avril.
  final plage = m.plageSansCours(now);
  if (plage != null &&
      plage.type == 'ete' &&
      m.chapitres.any((c) => c.etape > 0)) {
    return _suggereEte(m, minutesDispo, now, plage);
  }
  if (m.dateConcours != null &&
      now.isBefore(m.dateConcours!) &&
      m.dateConcours!.difference(now).inDays <= kSeuilModeRevisionsJours &&
      m.chapitres.any((c) => c.etape > 0)) {
    return _suggereRevisions(m, minutesDispo, now);
  }
  return _suggereNormal(m, minutesDispo, now);
}

/// Chapitres dont la revision espacee est due (aujourd'hui ou en retard).
List<Chapitre> rappelsDus(AppModel m, {DateTime? maintenant}) {
  final now = maintenant ?? DateTime.now();
  final finJour = DateTime(now.year, now.month, now.day, 23, 59);
  return m.chapitres
      .where((c) =>
          c.prochaineRevision != null && c.prochaineRevision!.isBefore(finJour))
      .toList()
    ..sort((a, b) => a.prochaineRevision!.compareTo(b.prochaineRevision!));
}

List<Suggestion> _suggereNormal(AppModel m, int minutesDispo, DateTime now) {
  final horizon = now.add(const Duration(days: 10));
  final out = <Suggestion>[];
  var budget = minutesDispo;

  // JOUR LIBRE (dimanche, samedi sans cours, vacances, journee banalisee) :
  // la journee de travail remplace la soiree — plus de matieres retenues,
  // et pendant les vacances les DM s'etalent a cadence VISIBLE.
  final plage = m.plageSansCours(now);
  final jourLibre =
      plage != null || (m.routines.isNotEmpty && m.routinesLe(now).isEmpty);

  // ---- 1. Rappels du jour (repetition espacee) ----
  // Blocs courts (15 min), jamais plus de la moitie de la soiree. Le nombre
  // s'adapte au budget (3 sur une petite soiree, jusqu'a 5 sur une grosse) :
  // avec un programme complet importe, un plafond fixe a 3 laissait la file
  // des revisions dues grossir sans limite ni signal.
  final dus = rappelsDus(m, maintenant: now);
  final capRappels = (minutesDispo ~/ 60 + 2).clamp(3, 5);
  for (final c in dus.take(capRappels)) {
    if (budget < 30 || (minutesDispo - budget) + 15 > minutesDispo ~/ 2) break;
    final retard =
        DateTime(now.year, now.month, now.day).difference(c.prochaineRevision!).inDays;
    // La dette de revisions est AFFICHEE (transparence) au lieu de rester
    // cachee derriere le plafond du soir.
    final enAttente =
        dus.length > capRappels ? ' · ${dus.length} chapitres en attente' : '';
    out.add(Suggestion(
      c.matiere,
      'Rappel 🔁 ${c.nom}',
      (retard > 0
              ? 'Révision espacée — en attente depuis $retard j'
              : 'Révision espacée — c\'est le bon jour') +
          enAttente,
      15,
      chapitreId: c.id,
      rappel: true,
      consigne: consigneDe(c.matiere, 'rappel'),
    ));
    budget -= 15;
  }

  // ---- 2. DM distribue aujourd'hui : le lire ce soir ----
  for (final d in m.devoirsARendre()) {
    if (d.dateDonne.year == now.year &&
        d.dateDonne.month == now.month &&
        d.dateDonne.day == now.day &&
        budget >= 30) {
      out.add(Suggestion(
        d.matiere,
        '📖 Lis le ${d.titre} distribué aujourd\'hui',
        'Le lire le soir même désamorce la procrastination',
        15,
        consigne:
            'Lis l\'énoncé en entier et repère les questions abordables — ton cerveau y travaillera en tâche de fond.',
      ));
      budget -= 15;
      break; // un seul par soir
    }
  }

  // ---- 2 ter. Vacances : un creneau DM a cadence fixe et annoncee
  // ("un jour sur N") — de l'etalement TRANSPARENT, pas un planificateur.
  // Les DM qui tombent dans ≤ 3 jours passent par le circuit urgence normal.
  if (plage != null && budget >= 60) {
    final aEtaler = m
        .devoirsARendre()
        .where((d) => d.dateRendu.difference(now).inDays >= 3)
        .toList();
    if (aEtaler.isNotEmpty) {
      // La cadence se calcule sur l'echeance la plus proche, et les creneaux
      // TOURNENT entre les DM : avant, seul le premier DM etait servi, les
      // suivants n'avaient jamais de creneau alors que la cadence etait
      // pourtant calculee pour eux.
      final joursDevant = aEtaler.first.dateRendu.difference(now).inDays + 1;
      var cadence = joursDevant ~/ (aEtaler.length * 2); // ~2 creneaux/DM
      if (cadence < 1) cadence = 1;
      if (cadence > 3) cadence = 3;
      final aujourdHui = DateTime(now.year, now.month, now.day);
      final jourIdx = aujourdHui.difference(kAncreRotation).inDays;
      if (jourIdx % cadence == 0) {
        final d = aEtaler[(jourIdx ~/ cadence) % aEtaler.length];
        final joursRestants = d.dateRendu.difference(now).inDays + 1;
        out.add(Suggestion(
          d.matiere,
          '📥 Créneau DM : ${d.titre}${d.remarque.isEmpty ? '' : ' · ${d.remarque}'}',
          'Vacances — ${aEtaler.length} DM à rendre, $joursRestants j devant toi : un créneau ${cadence == 1 ? 'par jour' : 'un jour sur $cadence'}',
          budget >= 150 ? 90 : 60,
          devoirId: d.id,
          consigne:
              'Avance d\'un bloc de questions. Bloqué ≥ 20 min ? Passe à la suivante et note le point de blocage.',
        ));
        budget -= budget >= 150 ? 90 : 60;
      }
    }
  }

  // ---- 2 bis. Cahier d'erreurs : kholle/DS dans ≤ 2 jours dans une
  // matiere ou des erreurs ne sont pas encore refaites -> les revoir est
  // le meilleur rendement de la soiree. Un seul bloc par soir.
  if (budget >= 30) {
    final proches = <String>{};
    final limite = now.add(const Duration(days: 2, hours: 12));
    final aujourdHui = DateTime(now.year, now.month, now.day);
    for (final c in m.collesAvenir()) {
      if (c.start.isBefore(limite)) proches.add(c.matiere);
    }
    for (final d in m.ds) {
      // A VENIR uniquement : un DS d'hier n'est plus une epreuve imminente.
      if (!d.date.isBefore(aujourdHui) && d.date.isBefore(limite)) {
        proches.add(d.matiere);
      }
    }
    for (final mat in proches) {
      final aRefaire =
          m.erreurs.where((e) => e.matiere == mat && !e.refaite).length;
      if (aRefaire == 0) continue;
      out.add(Suggestion(
        mat,
        '📕 Refais tes erreurs de $mat ($aRefaire à revoir)',
        'Épreuve imminente — tes erreurs passées sont tes points faibles connus',
        15,
        consigne:
            'Ouvre ton cahier d\'erreurs et REFAIS une erreur sans regarder la correction. Si tu la maîtrises, coche « refaite ».',
      ));
      budget -= 15;
      break; // un seul bloc erreurs par soir
    }
  }

  // ---- 2 quater. Rattrapage lecture : une oeuvre de francais pas finie
  // pendant l'ete revient UN JOUR SUR TROIS en debut d'annee (cadence
  // transparente), tant qu'il en reste — toutes les kholles de francais
  // de l'annee s'appuient sur ces livres.
  final aLire = m.oeuvresNonFinies();
  if (aLire.isNotEmpty && budget >= 45) {
    final jourIdx =
        DateTime(now.year, now.month, now.day).difference(kAncreRotation).inDays;
    if (jourIdx % 3 == 0) {
      final o = aLire[(jourIdx ~/ 3) % aLire.length];
      final progression = (o.pages != null && o.pages! > 0)
          ? ' (page ${o.pageActuelle}/${o.pages})'
          : '';
      out.add(Suggestion(
        'Français',
        '📖 Rattrape « ${o.titre} »$progression',
        'Œuvre pas finie — un jour sur 3 avant que les khôlles de français ne s\'enchaînent',
        30,
        oeuvreId: o.id,
        consigne:
            'Lecture ACTIVE : marque les passages forts et relève 2-3 citations — ce sont elles qui font la note.',
      ));
      budget -= 30;
    }
  }

  // ---- 3. Echeances par matiere (kholle, DS, devoir a rendre) ----
  final Map<String, _Echeance> echeances = {};
  for (final c in m.collesAvenir()) {
    if (c.start.isAfter(horizon)) continue;
    final e = echeances[c.matiere];
    if (e == null || c.start.isBefore(e.date)) {
      echeances[c.matiere] = _Echeance(
          c.start,
          'Khôlle ${c.kholleur.isEmpty ? '' : 'avec ${c.kholleur} '}',
          c.programme,
          'kholle');
    }
  }
  // Les DS sont dates a MINUIT : comparer a `now` (18h au moment du calcul)
  // ecartait le DS du jour meme, et la branche "AUJOURD'HUI" etait donc
  // inatteignable pour un DS. On compare a minuit, comme le cahier
  // d'erreurs plus haut.
  final minuit = DateTime(now.year, now.month, now.day);
  for (final d in m.ds) {
    if (d.date.isBefore(minuit) || d.date.isAfter(horizon)) continue;
    final e = echeances[d.matiere];
    if (e == null || d.date.isBefore(e.date)) {
      echeances[d.matiere] = _Echeance(d.date, '${d.titre} ', '', 'ds');
    }
  }
  for (final d in m.devoirsARendre()) {
    if (d.dateRendu.isBefore(now.subtract(const Duration(days: 5)))) continue;
    if (d.dateRendu.isAfter(horizon)) continue;
    final e = echeances[d.matiere];
    if (e == null || d.dateRendu.isBefore(e.date)) {
      echeances[d.matiere] = _Echeance(
        d.dateRendu,
        '${d.titre} à rendre ',
        '',
        'dm',
        tache: '${d.titre}${d.remarque.isEmpty ? '' : ' (${d.remarque})'}',
        devoirId: d.id,
      );
    }
  }

  // ---- Cours du jour / du lendemain (EDT reel + evenements ponctuels) ----
  final coursAujourdhui = <String>{};
  final coursDemain = <String>{};
  final demain = now.add(const Duration(days: 1));
  for (final r in m.routinesLe(now)) {
    if (r.matiere.trim().isNotEmpty) {
      coursAujourdhui.add(r.matiere.trim().toLowerCase());
    }
  }
  for (final r in m.routinesLe(demain)) {
    if (r.matiere.trim().isNotEmpty) {
      coursDemain.add(r.matiere.trim().toLowerCase());
    }
  }
  for (final e in m.evenementsLe(now)) {
    if (e.matiere.trim().isNotEmpty) {
      coursAujourdhui.add(e.matiere.trim().toLowerCase());
    }
  }
  for (final e in m.evenementsLe(demain)) {
    if (e.matiere.trim().isNotEmpty) {
      coursDemain.add(e.matiere.trim().toLowerCase());
    }
  }

  // ---- Jachere : derniere seance par matiere ----
  final derniereSeance = <String, DateTime>{};
  for (final s in m.seances) {
    final cle = s.matiere.toLowerCase();
    final prec = derniereSeance[cle];
    if (prec == null || s.date.isAfter(prec)) derniereSeance[cle] = s.date;
  }

  // ---- Scoring ----
  final scores = <String, double>{};
  final raisons = <String, String>{};
  final allMatieres = <String>{...m.matieres, ...echeances.keys};

  for (final mat in allMatieres) {
    double urgence = 0.6; // travail de fond par defaut
    String raison = 'Travail de fond';
    final e = echeances[mat];
    if (e != null) {
      final jours = e.date.difference(now).inHours / 24.0;
      final memeJour = e.date.year == now.year &&
          e.date.month == now.month &&
          e.date.day == now.day;
      // Les DS et devoirs sont dates a minuit : pas d'heure a afficher.
      final heure = (e.date.hour == 0 && e.date.minute == 0)
          ? ''
          : ' ${frHeure(e.date)}';
      if (memeJour) {
        // Une kholle de 18h ou un DM date a minuit restent "AUJOURD'HUI"
        // toute la journee (avant, un DM du jour passait "EN RETARD").
        urgence = 4.5;
        raison = '${e.type}AUJOURD\'HUI$heure';
      } else if (jours < 0) {
        urgence = 4.5;
        raison = '${e.type}EN RETARD — rends-le vite';
      } else if (jours <= 1.2) {
        urgence = 4;
        raison = '${e.type}demain (${frJour(e.date)}$heure)';
      } else if (jours <= 2.5) {
        urgence = 3;
        raison = '${e.type}dans ${jours.ceil()} jours';
      } else if (jours <= 7) {
        // Dans les 7 jours = "ce samedi", pas "samedi prochain".
        urgence = 2;
        raison = '${e.type}ce ${frJour(e.date)}';
      } else {
        urgence = 1.2;
        raison = '${e.type}le ${frDateCourte(e.date)}';
      }
    }

    final prio = (m.prios[mat] ?? 2).toDouble(); // 1 a 3

    // Fragilite : moyenne (60 %) + MINIMUM (40 %) des chapitres commences —
    // la moyenne seule masquait un chapitre a zero au milieu de bons.
    final chs =
        m.chapitres.where((c) => c.matiere == mat && c.etape > 0).toList();
    // Sans donnees, on ne sait rien : leger benefice du doute (1.15), mais
    // pas au point qu'une matiere jamais renseignee passe devant une
    // matiere reellement fragile (l'ancien 1.3 battait une matiere
    // parfaitement maitrisee a 1.0).
    double fragilite = 1.15;
    if (chs.isNotEmpty) {
      final avg = chs.map((c) => c.maitrise).reduce((a, b) => a + b) / chs.length;
      final mini = chs.map((c) => c.maitrise).reduce(min);
      fragilite = 1 + ((4 - avg) / 4) * 0.6 + ((4 - mini) / 4) * 0.4;
    }

    // Bonus "cours du jour / du lendemain".
    var bonusCours = 1.0;
    if (coursAujourdhui.contains(mat.toLowerCase())) {
      bonusCours = 1.5;
      if (e == null) raison = "Cours d'aujourd'hui — à revoir ce soir";
    } else if (coursDemain.contains(mat.toLowerCase())) {
      bonusCours = 1.2;
      if (e == null) raison = 'Cours demain — prends de l\'avance';
    }

    // Jachere : une matiere delaissee remonte progressivement (contre la
    // famine du francais et des langues, qui n'ont presque pas d'echeances).
    final dSeance = derniereSeance[mat.toLowerCase()];
    final joursSans =
        dSeance == null ? 999 : now.difference(dSeance).inDays;
    final jachere =
        1.0 + ((joursSans - 3) / 7).clamp(0.0, 1.0); // 1.0 -> 2.0 en ~10 j
    if (e == null &&
        bonusCours == 1.0 &&
        jachere >= 1.6 &&
        joursSans < 999) {
      raison = 'Pas travaillée depuis $joursSans j — entretien';
    }

    scores[mat] = urgence * prio * fragilite * bonusCours * jachere;
    raisons[mat] = raison;
  }

  if (scores.isEmpty || budget < 15) return out;

  // ---- Repartition du budget restant sur les meilleures matieres ----
  // Jour libre + gros budget : jusqu'a 4 matieres (une journee de travail
  // couvre plus large qu'une soiree).
  final classees = scores.keys.toList()
    ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
  final nbMatieres = jourLibre && budget >= 240 ? 4 : (budget >= 150 ? 3 : 2);
  final retenues = classees.take(nbMatieres).toList();
  final totalScore = retenues.fold<double>(0, (s, mat) => s + scores[mat]!);

  var reste = budget;
  for (var i = 0; i < retenues.length; i++) {
    if (reste < 15) break;
    final mat = retenues[i];
    var mins = i == retenues.length - 1
        ? reste
        : ((scores[mat]! / totalScore) * budget / 15).round() * 15;
    if (mins < 15) mins = 15;
    if (mins > reste) mins = reste;
    reste -= mins;

    // Contenu conseille + consigne d'action (rappel actif).
    var quoi = '';
    var typeConsigne = 'fond';
    String? chapitreId;
    // Second demi-bloc (interleaving) : sur un long bloc SANS echeance
    // imminente, alterner deux chapitres distincts consolide mieux que
    // 60-90 min monolithiques sur le meme theme (Rohrer & Taylor 2007).
    String? quoi2;
    String? typeConsigne2;
    String? chapitreId2;
    final e = echeances[mat];
    final aRevoir =
        m.chapitres.where((c) => c.matiere == mat && c.etape == 1).toList();
    final fragiles = m.chapitres
        .where((c) => c.matiere == mat && c.maitrise <= 2 && c.etape > 0)
        .toList()
      ..sort((a, b) => a.maitrise.compareTo(b.maitrise));
    final interleave = mins >= 60 && e == null;
    if (e != null && e.genre == 'dm' && e.tache.isNotEmpty) {
      // Le travail impose s'affiche comme LA TACHE, pas comme un bloc de
      // matiere abstrait ("avance le DM 3 (exos 1 à 4)").
      quoi = '📥 Avance ${e.tache}';
      typeConsigne = 'dm';
    } else if (e != null && e.programme.trim().isNotEmpty) {
      quoi = 'Programme : ${e.programme.trim()}';
      typeConsigne = e.genre;
    } else if (aRevoir.isNotEmpty) {
      final ancien = fragiles.where((c) => c.id != aRevoir.first.id).toList();
      if (interleave && (ancien.isNotEmpty || aRevoir.length >= 2)) {
        // Demi-bloc 1 : le chapitre recent. Demi-bloc 2 : un chapitre plus
        // ancien a consolider (ou le 2e chapitre recent, a defaut).
        quoi = 'À revoir (vu en cours) : ${aRevoir.first.nom}';
        typeConsigne = 'rappel';
        chapitreId = aRevoir.first.id;
        if (ancien.isNotEmpty) {
          quoi2 = 'À consolider : ${ancien.first.nom}';
          typeConsigne2 = 'consolider';
          chapitreId2 = ancien.first.id;
        } else {
          quoi2 = 'À revoir (vu en cours) : ${aRevoir[1].nom}';
          typeConsigne2 = 'rappel';
          chapitreId2 = aRevoir[1].id;
        }
      } else {
        quoi =
            'À revoir (vu en cours) : ${aRevoir.take(2).map((c) => c.nom).join(', ')}';
        typeConsigne = 'rappel';
        if (aRevoir.length == 1) chapitreId = aRevoir.first.id;
      }
    } else {
      if (fragiles.isNotEmpty) {
        if (interleave && fragiles.length >= 2) {
          quoi = 'À consolider : ${_nomFragile(fragiles[0])}';
          typeConsigne = 'consolider';
          chapitreId = fragiles[0].id;
          quoi2 = 'À consolider : ${_nomFragile(fragiles[1])}';
          typeConsigne2 = 'consolider';
          chapitreId2 = fragiles[1].id;
        } else {
          quoi =
              'À consolider : ${fragiles.take(2).map(_nomFragile).join(', ')}';
          typeConsigne = 'consolider';
          if (fragiles.length == 1) chapitreId = fragiles.first.id;
        }
      } else {
        quoi = 'Exercices + reprise du dernier cours';
        typeConsigne = e == null ? 'fond' : e.genre;
      }
    }

    if (quoi2 != null) {
      // Moitie du bloc chacun, arrondie au quart d'heure (le reliquat va au
      // premier demi-bloc).
      final demi = ((mins ~/ 2) ~/ 15) * 15;
      out.add(Suggestion(mat, quoi, raisons[mat] ?? '', mins - demi,
          chapitreId: chapitreId,
          consigne: consigneDe(mat, typeConsigne)));
      out.add(Suggestion(
          mat, quoi2, 'Alterner les thèmes consolide mieux (interleaving)', demi,
          chapitreId: chapitreId2,
          consigne: consigneDe(mat, typeConsigne2 ?? 'consolider')));
    } else {
      out.add(Suggestion(mat, quoi, raisons[mat] ?? '', mins,
          chapitreId: chapitreId,
          devoirId: e?.genre == 'dm' ? e?.devoirId : null,
          consigne: consigneDe(mat, typeConsigne)));
    }
  }
  return out;
}

String _nomFragile(Chapitre c) =>
    c.maitrise == 0 ? '⚠ ${c.nom} (jamais consolidé)' : c.nom;

/// MODE REVISIONS CONCOURS : couvrir tout le programme avant les ecrits.
/// Revisions espacees dues d'abord, puis jamais revus (fragiles en tete),
/// puis les plus anciens — en alternant les matieres (interleaving).
List<Suggestion> _suggereRevisions(
    AppModel m, int minutesDispo, DateTime now) {
  final jours = m.dateConcours!.difference(now).inDays + 1;
  final out = <Suggestion>[];
  var reste = minutesDispo;

  // Un DS / concours blanc dans les 2 jours garde la priorite absolue.
  final aujourdHui = DateTime(now.year, now.month, now.day);
  Ds? prochainDs;
  for (final d in m.ds) {
    final dj = DateTime(d.date.year, d.date.month, d.date.day)
        .difference(aujourdHui)
        .inDays;
    if (dj < 0 || dj > 2) continue;
    if (prochainDs == null || d.date.isBefore(prochainDs.date)) prochainDs = d;
  }
  if (prochainDs != null && reste >= 30) {
    final mins = reste >= 90 ? 60 : 30;
    out.add(Suggestion(
      prochainDs.matiere,
      'Prépa ${prochainDs.titre} : annales et points faibles',
      '${prochainDs.titre} ${frJour(prochainDs.date)} — priorité',
      mins,
      consigne: consigneDe(prochainDs.matiere, 'ds'),
    ));
    reste -= mins;
  }

  // Le travail IMPOSE ne disparait pas parce que les ecrits approchent :
  // une kholle imminente ou un DM a rendre gardent leur place dans le plan
  // (avant, saisir la date de concours les faisait disparaitre des mois).
  for (final c in m.collesAvenir()) {
    if (!c.start.isBefore(now.add(const Duration(days: 2, hours: 12)))) break;
    if (reste < 30) break;
    final prog = c.programme.trim();
    out.add(Suggestion(
      c.matiere,
      'Prépa khôlle${prog.isEmpty ? '' : ' — programme : $prog'}',
      'Khôlle ${frJour(c.start)} ${frHeure(c.start)} — le travail imposé d\'abord',
      30,
      consigne: consigneDe(c.matiere, 'kholle'),
    ));
    reste -= 30;
    break; // une seule kholle en tete, le reste au circuit revision
  }
  for (final d in m.devoirsARendre()) {
    final dj = DateTime(d.dateRendu.year, d.dateRendu.month, d.dateRendu.day)
        .difference(aujourdHui)
        .inDays;
    if (dj > 3 || reste < 30) break;
    final mins = reste >= 90 ? 45 : 30;
    out.add(Suggestion(
      d.matiere,
      '📥 Avance ${d.titre}${d.remarque.isEmpty ? '' : ' (${d.remarque})'}',
      dj < 0
          ? '${d.titre} EN RETARD — rends-le vite'
          : 'À rendre ${frJour(d.dateRendu)} — même en mode révisions',
      mins,
      devoirId: d.id,
      consigne: consigneDe(d.matiere, 'dm'),
    ));
    reste -= mins;
    break; // un seul DM par soir en mode revisions
  }

  // Annales, version REALISTE : une epreuve de concours fait 3-4 h — la
  // suggerer "en conditions" un mardi soir de 90 min etait contradictoire.
  // (1) Une annale faite ces derniers jours ? La CORRECTION ACTIVE d'abord :
  //     c'est la que l'apprentissage se fait, et ca tient dans une soiree.
  // (2) Gros budget (week-end/vacances, ≥ 3 h) ? Annale complete.
  // (3) Soir de semaine ? Une PARTIE d'annale, dite comme telle.
  if (jours <= 45 && reste >= 45) {
    final recente = m.annales
        .where((a) =>
            a.fait &&
            a.dateFait != null &&
            now.difference(a.dateFait!).inDays <= 4)
        .toList()
      ..sort((x, y) => y.dateFait!.compareTo(x.dateFait!));
    final nonFaites = m.annales.where((a) => !a.fait).toList();
    final faitesParMatiere = <String, int>{};
    for (final a in m.annales) {
      if (a.fait) {
        faitesParMatiere[a.matiere] = (faitesParMatiere[a.matiere] ?? 0) + 1;
      }
    }
    if (recente.isNotEmpty && recente.first.ressenti <= 3) {
      final a = recente.first;
      out.add(Suggestion(
        a.matiere,
        '🧾 Correction active : ${a.concours} ${a.annee} — ${a.matiere}',
        'J-$jours · faite il y a ${now.difference(a.dateFait!).inDays} j — la correction est là où on apprend',
        45,
        consigne:
            'Reprends ta copie question par question SANS regarder la correction d\'abord, puis compare — et note chaque erreur dans le cahier d\'erreurs.',
      ));
      reste -= 45;
    } else if (nonFaites.isNotEmpty && reste >= 60) {
      nonFaites.sort((x, y) {
        final fx = faitesParMatiere[x.matiere] ?? 0;
        final fy = faitesParMatiere[y.matiere] ?? 0;
        return fx != fy ? fx.compareTo(fy) : y.annee.compareTo(x.annee);
      });
      final a = nonFaites.first;
      if (reste >= 180) {
        out.add(Suggestion(
          a.matiere,
          '📜 Annale ${a.concours} ${a.annee} — ${a.matiere}, EN CONDITIONS',
          'J-$jours · grosse journée : le bon moment pour une épreuve entière',
          180,
          consigne:
              'Conditions réelles : chrono, sans le cours, rédige. La correction se fera un autre jour (elle aura sa propre séance).',
        ));
        reste -= 180;
      } else {
        out.add(Suggestion(
          a.matiere,
          '📜 Une PARTIE de l\'annale ${a.concours} ${a.annee} — ${a.matiere}',
          'J-$jours · une épreuve fait 3-4 h — ce soir, une partie chrono suffit',
          60,
          consigne:
              'Choisis un problème ou une partie, chrono, sans le cours. Garde l\'épreuve entière pour un week-end.',
        ));
        reste -= 60;
      }
    }
  }

  final finJour = DateTime(now.year, now.month, now.day, 23, 59);
  final alternes = _chapitresAlternes(m, finJour);

  var i = 0;
  while (reste >= 30 && i < alternes.length) {
    final c = alternes[i];
    final due = c.prochaineRevision != null &&
        c.prochaineRevision!.isBefore(finJour);
    final mins = due ? 30 : (reste >= 75 ? 60 : (reste ~/ 15) * 15);
    final quandRevu = due
        ? 'révision espacée due'
        : c.dernierRevu == null
            ? 'jamais revu'
            : 'revu il y a ${now.difference(c.dernierRevu!).inDays} j';
    out.add(Suggestion(
      c.matiere,
      'Réviser : ${c.nom}',
      'J-$jours · $quandRevu',
      mins > reste ? reste : mins,
      chapitreId: c.id,
      rappel: due,
      consigne: consigneDe(c.matiere, due ? 'rappel' : 'revision'),
    ));
    reste -= mins;
    i++;
  }
  return out;
}

/// Chapitres commences (etape > 0) tries — revisions dues d'abord, puis
/// jamais revus (fragiles en tete), puis revus les plus anciens — et
/// ALTERNES par matiere (interleaving, Rohrer & Taylor). [parPriorite] :
/// insere la priorite de matiere (m.prios) juste apres le critere « du »,
/// pour que le bilan de concours d'un 5/2 pilote l'ordre de reactivation.
List<Chapitre> _chapitresAlternes(AppModel m, DateTime finJour,
    {bool parPriorite = false}) {
  final aReviser = m.chapitres.where((c) => c.etape > 0).toList()
    ..sort((a, b) {
      // 1. Revisions espacees dues d'abord.
      final aDue = a.prochaineRevision != null &&
          a.prochaineRevision!.isBefore(finJour);
      final bDue = b.prochaineRevision != null &&
          b.prochaineRevision!.isBefore(finJour);
      if (aDue != bDue) return aDue ? -1 : 1;
      // 1 bis. Matieres prioritaires d'abord (mode ete).
      if (parPriorite) {
        final pa = m.prios[a.matiere] ?? 2;
        final pb = m.prios[b.matiere] ?? 2;
        if (pa != pb) return pb.compareTo(pa);
      }
      // 2. Jamais revus (les plus fragiles en tete).
      if (a.dernierRevu == null && b.dernierRevu != null) return -1;
      if (a.dernierRevu != null && b.dernierRevu == null) return 1;
      if (a.dernierRevu == null && b.dernierRevu == null) {
        return a.maitrise.compareTo(b.maitrise);
      }
      // 3. Revus les plus anciens.
      final cmp = a.dernierRevu!.compareTo(b.dernierRevu!);
      return cmp != 0 ? cmp : a.maitrise.compareTo(b.maitrise);
    });

  // Interleaving : on alterne les matieres en respectant l'ordre ci-dessus.
  final files = <String, List<Chapitre>>{};
  for (final c in aReviser) {
    files.putIfAbsent(c.matiere, () => []).add(c);
  }
  final ordreMatieres = <String>[];
  for (final c in aReviser) {
    if (!ordreMatieres.contains(c.matiere)) ordreMatieres.add(c.matiere);
  }
  final alternes = <Chapitre>[];
  while (alternes.length < aReviser.length) {
    for (final mat in ordreMatieres) {
      final file = files[mat]!;
      if (file.isNotEmpty) alternes.add(file.removeAt(0));
    }
  }
  return alternes;
}

/// MODE ETE (grandes vacances) : la reactivation douce du programme —
/// pensee pour le 5/2 qui prepare sa nouvelle annee, utile a tous.
/// Principes (et leur justification) :
///  - la repetition espacee continue (les « rappels du jour » d'abord) :
///    c'est l'ete que le programme de l'an passe s'evapore ;
///  - rotation du programme par matieres PRIORITAIRES d'abord (le bilan de
///    concours regle les prios -> l'ete travaille la ou les points se
///    perdent) ;
///  - une annale en douceur par semaine glissante, correction active en
///    priorite le lendemain (effet de test, pas de bachotage estival) ;
///  - le dimanche est un JOUR DE REPOS : un seul bloc leger facultatif —
///    la consolidation exige aussi de la recuperation, et une 5/2 se gagne
///    sur dix mois, pas sur un ete d'epuisement ;
///  - derniere semaine : messages de remise en rythme avant la rentree.
List<Suggestion> _suggereEte(
    AppModel m, int minutesDispo, DateTime now, PlageSansCours plage) {
  final out = <Suggestion>[];
  var reste = minutesDispo;
  final aujourdHui = DateTime(now.year, now.month, now.day);
  final finJour = DateTime(now.year, now.month, now.day, 23, 59);
  final joursAvantRentree = DateTime(plage.fin.year, plage.fin.month,
          plage.fin.day)
      .difference(aujourdHui)
      .inDays;
  final rentreeProche = joursAvantRentree <= 7;
  final contexte = rentreeProche
      ? 'Rentrée dans $joursAvantRentree j — remise en rythme'
      : 'Été · réactivation';

  // ---- Dimanche : repos. Un unique bloc leger, explicitement facultatif.
  if (now.weekday == DateTime.sunday) {
    final dus = rappelsDus(m, maintenant: now);
    final c = dus.isNotEmpty
        ? dus.first
        : (_chapitresAlternes(m, finJour, parPriorite: true).firstOrNull);
    if (c != null) {
      out.add(Suggestion(
        c.matiere,
        'Si tu y tiens : ${c.nom} (léger)',
        'Dimanche = repos 😌 La consolidation se fait aussi en dormant — un seul petit bloc, et seulement si tu en as envie',
        30,
        chapitreId: c.id,
        rappel: dus.isNotEmpty && c.id == dus.first.id,
        consigne: consigneDe(c.matiere, 'rappel'),
      ));
    }
    return out;
  }

  // ---- 1. Rappels du jour (repetition espacee) : le squelette de l'ete.
  // Cap plus genereux qu'en periode scolaire : c'est le canal principal
  // quand la reactivation a ete planifiee (etalerReactivation).
  final dus = rappelsDus(m, maintenant: now);
  final capRappels = (minutesDispo ~/ 45).clamp(2, 6);
  for (final c in dus.take(capRappels)) {
    if (reste < 15) break;
    final enAttente =
        dus.length > capRappels ? ' · ${dus.length} chapitres en attente' : '';
    out.add(Suggestion(
      c.matiere,
      'Rappel 🔁 ${c.nom}',
      '$contexte — révision espacée$enAttente',
      15,
      chapitreId: c.id,
      rappel: true,
      consigne: consigneDe(c.matiere, 'rappel'),
    ));
    reste -= 15;
  }

  // ---- 2. DM de vacances saisis (rare mais possible pour un 3/2).
  for (final d in m.devoirsARendre()) {
    if (reste < 60) break;
    final dj = DateTime(d.dateRendu.year, d.dateRendu.month, d.dateRendu.day)
        .difference(aujourdHui)
        .inDays;
    if (dj > 10) continue;
    out.add(Suggestion(
      d.matiere,
      '📥 Avance ${d.titre}${d.remarque.isEmpty ? '' : ' (${d.remarque})'}',
      dj < 0 ? '${d.titre} EN RETARD' : 'À rendre ${frDateCourte(d.dateRendu)}',
      60,
      devoirId: d.id,
      consigne: consigneDe(d.matiere, 'dm'),
    ));
    reste -= 60;
    break; // un seul par jour
  }

  // ---- 3. Annale en douceur : ~1 par semaine glissante, correction
  // active en priorite (c'est la qu'on apprend).
  if (m.annales.isNotEmpty && reste >= 45) {
    final recente = m.annales
        .where((a) =>
            a.fait &&
            a.dateFait != null &&
            now.difference(a.dateFait!).inDays <= 2)
        .toList()
      ..sort((x, y) => y.dateFait!.compareTo(x.dateFait!));
    final derniereFaite = m.annales
        .where((a) => a.fait && a.dateFait != null)
        .fold<DateTime?>(null,
            (t, a) => t == null || a.dateFait!.isAfter(t) ? a.dateFait : t);
    final joursSansAnnale = derniereFaite == null
        ? 999
        : now.difference(derniereFaite).inDays;
    if (recente.isNotEmpty && recente.first.ressenti <= 3) {
      final a = recente.first;
      out.add(Suggestion(
        a.matiere,
        '🧾 Correction active : ${a.concours} ${a.annee} — ${a.matiere}',
        '$contexte · la correction est là où on apprend',
        45,
        consigne:
            'Reprends ta copie question par question SANS regarder la correction d\'abord, puis compare — et note chaque erreur dans le cahier d\'erreurs.',
      ));
      reste -= 45;
    } else if (joursSansAnnale >= 5 && reste >= 120) {
      final nonFaites = m.annales.where((a) => !a.fait).toList();
      if (nonFaites.isNotEmpty) {
        // Matiere la moins couverte d'abord (meme regle qu'en revisions).
        final faitesParMatiere = <String, int>{};
        for (final a in m.annales) {
          if (a.fait) {
            faitesParMatiere[a.matiere] =
                (faitesParMatiere[a.matiere] ?? 0) + 1;
          }
        }
        nonFaites.sort((x, y) {
          final fx = faitesParMatiere[x.matiere] ?? 0;
          final fy = faitesParMatiere[y.matiere] ?? 0;
          return fx != fy ? fx.compareTo(fy) : y.annee.compareTo(x.annee);
        });
        final a = nonFaites.first;
        out.add(Suggestion(
          a.matiere,
          '📜 Une PARTIE de l\'annale ${a.concours} ${a.annee} — ${a.matiere}',
          '$contexte · une annale douce par semaine garde le niveau concours',
          90,
          consigne:
              'Choisis un problème ou une partie, chrono, sans le cours. La correction active aura sa séance demain.',
        ));
        reste -= 90;
      }
    }
  }

  // ---- 3 bis. Lecture des oeuvres de francais : un jour sur deux.
  // L'ete est LE moment pour les 3 livres (l'annee ne laisse plus le temps
  // de lire), et chaque kholle de francais de l'annee s'appuiera dessus.
  final aLire = m.oeuvresNonFinies();
  final jourIdx = aujourdHui.difference(kAncreRotation).inDays;
  if (aLire.isNotEmpty && reste >= 45 && jourIdx % 2 == 0) {
    final o = aLire[(jourIdx ~/ 2) % aLire.length];
    var progression = '';
    if (o.pages != null && o.pages! > 0) {
      final restantes = (o.pages! - o.pageActuelle).clamp(0, o.pages!);
      final seances = (joursAvantRentree ~/ 2).clamp(1, 99);
      final parSeance = (restantes / seances).ceil();
      progression =
          ' · page ${o.pageActuelle}/${o.pages} — ~$parSeance p./séance pour finir avant la rentrée';
    }
    out.add(Suggestion(
      'Français',
      '📖 Lis « ${o.titre} »${o.auteur.isEmpty ? '' : ' (${o.auteur})'}',
      '$contexte · les œuvres se lisent l\'été$progression',
      45,
      oeuvreId: o.id,
      consigne:
          'Lecture ACTIVE : marque les passages forts et relève 2-3 citations par séance — ce sont elles qui font la note en khôlle et en dissertation.',
    ));
    reste -= 45;
  }

  // ---- 4. Rotation de reactivation : matieres prioritaires d'abord
  // (bilan de concours), interleaving, blocs moyens de 45 min.
  final alternes = _chapitresAlternes(m, finJour, parPriorite: true)
      .where((c) => !out.any((s) => s.chapitreId == c.id))
      .toList();
  var i = 0;
  while (reste >= 30 && i < alternes.length) {
    final c = alternes[i];
    final mins = reste >= 60 ? 45 : (reste ~/ 15) * 15;
    final quandRevu = c.dernierRevu == null
        ? 'jamais revu'
        : 'revu il y a ${now.difference(c.dernierRevu!).inDays} j';
    out.add(Suggestion(
      c.matiere,
      'Réactiver : ${c.nom}',
      '$contexte · $quandRevu',
      mins > reste ? reste : mins,
      chapitreId: c.id,
      consigne: consigneDe(c.matiere, 'revision'),
    ));
    reste -= mins;
    i++;
  }
  return out;
}

/// MODE ORAUX : apres les ecrits, le plan du soir prepare les epreuves
/// orales. Un oral date dans ≤ 7 jours prend la tete ; les autres epreuves
/// tournent (l'ordre de depart change chaque jour — couverture complete
/// sans etat supplementaire).
List<Suggestion> _suggereOraux(AppModel m, int minutesDispo, DateTime now) {
  final aujourdHui = DateTime(now.year, now.month, now.day);
  final out = <Suggestion>[];
  var reste = minutesDispo;

  // Epreuves encore a passer (datees en premier — triees par le store).
  final aVenir = m.oraux
      .where((o) => o.date == null || !o.date!.isBefore(aujourdHui))
      .toList();
  if (aVenir.isEmpty) return out;

  String raisonDe(EpreuveOrale o) {
    if (o.date == null) return 'Date pas encore connue — entretien régulier';
    final j = o.date!.difference(aujourdHui).inDays;
    if (j == 0) return 'C\'EST AUJOURD\'HUI — échauffement léger seulement';
    return 'Oral le ${frDateCourte(o.date!)} · J-$j';
  }

  // 1. Oral date imminent (≤ 7 jours) : bloc principal en tete.
  EpreuveOrale? urgent;
  for (final o in aVenir) {
    if (o.date == null) continue;
    if (o.date!.difference(aujourdHui).inDays > 7) continue;
    urgent = o;
    break; // aVenir est deja trie par date
  }
  if (urgent != null && reste >= 30) {
    // Le JOUR de l'oral, le message dit "echauffement leger" : la duree
    // doit dire la meme chose (20 min, pas une seance complete).
    final jourJ = urgent.date != null &&
        urgent.date!.difference(aujourdHui).inDays == 0;
    final mins = jourJ ? 20 : (reste >= 90 ? 60 : (reste ~/ 15) * 15);
    out.add(Suggestion(
      urgent.epreuve,
      'Oral ${urgent.concours} — ${urgent.epreuve}',
      raisonDe(urgent),
      mins,
      consigne: consigneOral(urgent.epreuve),
    ));
    reste -= mins;
  }

  // 2. Rotation quotidienne des autres epreuves.
  final autres = aVenir.where((o) => o.id != urgent?.id).toList();
  if (autres.isEmpty) return out;
  final depart = aujourdHui.difference(kAncreRotation).inDays % autres.length;
  var i = 0;
  while (reste >= 30 && i < autres.length) {
    final o = autres[(depart + i) % autres.length];
    var mins = reste >= 75 ? 45 : (reste ~/ 15) * 15;
    if (mins > reste) mins = reste;
    out.add(Suggestion(
      o.epreuve,
      'Oral ${o.concours} — ${o.epreuve}',
      raisonDe(o),
      mins,
      consigne: consigneOral(o.epreuve),
    ));
    reste -= mins;
    i++;
  }
  return out;
}

class _Echeance {
  final DateTime date;
  final String type;
  final String programme;
  final String genre; // 'kholle' | 'ds' | 'dm'
  // Pour les DM : la tache concrete ("DM 3 (exos 1 à 4)") et l'id du devoir
  // — la soiree d'un preparationnaire est une liste de taches, pas des
  // blocs de matiere.
  final String tache;
  final String? devoirId;
  _Echeance(this.date, this.type, this.programme, this.genre,
      {this.tache = '', this.devoirId});
}
