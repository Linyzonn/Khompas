import 'package:flutter/material.dart';

import '../models.dart';
import '../stats.dart';
import '../store.dart';
import '../theme.dart';

/// MA PROGRESSION — le tableau de bord complet : temps, notes, memorisation,
/// cahier d'erreurs, cartes, travail impose, annales, lecture.
///
/// Regle de la charte : une statistique INFORME, elle ne juge pas. Pas de
/// score global, pas de comparaison a autrui, jamais de rouge sur une note —
/// des faits et des tendances, pour decider quoi travailler ce soir.
class ProgressionScreen extends StatelessWidget {
  const ProgressionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Ma progression')),
      body: listeCentree(context, largeurMax: 760, children: [
        ..._chiffresCles(context, m, now),
        ..._sectionTemps(context, m, now),
        ..._sectionNotes(context, m),
        ..._sectionMemoire(context, m, now),
        ..._sectionErreurs(context, m, now),
        ..._sectionDivers(context, m),
        const SizedBox(height: kEsp32),
      ]),
    );
  }

  // ------------------------------------------------------ Chiffres cles

  List<Widget> _chiffresCles(BuildContext context, AppModel m, DateTime now) {
    final min30 = minutesTotal(m, maintenant: now, jours: 30);
    final serie = serieEnCours(m, maintenant: now);
    final memoire = etatMemoire(m, maintenant: now);
    final moyenne = _moyenneGenerale(m, now);
    return [
      // Wrap et non Row : sur telephone les tuiles passent a la ligne au
      // lieu d'ecraser les chiffres.
      Wrap(
        spacing: kEsp8,
        runSpacing: kEsp8,
        children: [
          _tuile(context, _labelMin(min30), 'travaillées (30 j)',
              Icons.timer_outlined),
          _tuile(
              context,
              serie == 0 ? '—' : '$serie j',
              serie <= 1 ? 'jour de suite' : 'jours de suite',
              Icons.local_fire_department_outlined),
          _tuile(context, '${memoire.consolides}', 'chapitres maîtrisés',
              Icons.verified_outlined),
          _tuile(
              context,
              moyenne == null ? '—' : moyenne.toStringAsFixed(1),
              'moyenne (60 j)',
              Icons.grade_outlined),
        ],
      ),
      const SizedBox(height: kEsp24),
    ];
  }

  Widget _tuile(
      BuildContext context, String chiffre, String legende, IconData icone) {
    return Container(
      width: 168,
      padding: const EdgeInsets.all(kEsp12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(kRayonCarte),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 16, color: couleurSecondaire(context)),
          const SizedBox(height: kEsp4),
          Text(chiffre, style: styleChiffre(context).copyWith(fontSize: 22)),
          Text(legende, style: styleMeta(context)),
        ],
      ),
    );
  }

  /// Moyenne toutes matieres sur 60 j (kholles + DS, non ponderes) : une
  /// DIRECTION, pas un bulletin — d'ou l'absence de coefficients.
  double? _moyenneGenerale(AppModel m, DateTime now) {
    final debut = now.subtract(const Duration(days: 60));
    final notes = <double>[];
    for (final c in m.colles) {
      if (c.note != null && c.start.isAfter(debut)) notes.add(c.note!);
    }
    for (final d in m.ds) {
      if (d.note != null && d.date.isAfter(debut)) notes.add(d.note!);
    }
    if (notes.isEmpty) return null;
    return notes.reduce((a, b) => a + b) / notes.length;
  }

  // ------------------------------------------------------------- Temps

  List<Widget> _sectionTemps(BuildContext context, AppModel m, DateTime now) {
    final histo = m.minutesParSemaineHisto(maintenant: now);
    final maxSem = histo.fold<int>(0, (t, e) => e.$2 > t ? e.$2 : t).clamp(1, 1 << 31);
    final total = histo.fold<int>(0, (t, e) => t + e.$2);
    final actives = histo.where((e) => e.$2 > 0).length;
    final parMatiere = m.minutesParMatiere(maintenant: now);
    final maxMat = parMatiere.isEmpty ? 1 : parMatiere.first.$2;
    final parJour = minutesParJourSemaine(m, maintenant: now);
    final maxJour = parJour.fold<int>(0, (t, v) => v > t ? v : t).clamp(1, 1 << 31);
    const nomsJours = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    return [
      titreSection(context, 'Temps de travail'),
      Text(
        total == 0
            ? 'Coche tes blocs du soir : les heures se comptent toutes seules.'
            : '${_labelMin(total)} sur 12 semaines · ${actives == 0 ? '—' : _labelMin(total ~/ actives)} par semaine active.',
        style: styleMeta(context),
      ),
      const SizedBox(height: kEsp12),
      // Histogramme des 12 semaines.
      SizedBox(
        height: 110,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (lundi, minutes) in histo)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (minutes > 0)
                        Text(
                          (minutes / 60).toStringAsFixed(minutes % 60 == 0 ? 0 : 1),
                          style: TextStyle(
                              fontSize: 9, color: couleurSecondaire(context)),
                        ),
                      const SizedBox(height: 2),
                      Container(
                        height: 74.0 * minutes / maxSem + 2,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(
                              alpha: minutes == 0 ? 0.15 : 0.75),
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text('${lundi.day}/${lundi.month}',
                          style: TextStyle(
                              fontSize: 8, color: couleurSecondaire(context))),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),

      // Rythme de la semaine : ou sont les creux reels.
      const SizedBox(height: kEsp16),
      Text('Rythme d’une semaine type (8 dernières semaines)',
          style: styleMeta(context)),
      const SizedBox(height: kEsp8),
      SizedBox(
        height: 64,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(parJour[i] == 0 ? '' : '${parJour[i]}',
                          style: TextStyle(
                              fontSize: 9, color: couleurSecondaire(context))),
                      Container(
                        height: 34.0 * parJour[i] / maxJour + 2,
                        decoration: BoxDecoration(
                          // Le dimanche est un jour de REPOS assume : il
                          // s'affiche dans la couleur « repos », pas comme
                          // un manque.
                          color: (i == 6
                                  ? context.tokens.repos
                                  : Theme.of(context).colorScheme.primary)
                              .withValues(alpha: parJour[i] == 0 ? 0.15 : 0.6),
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(nomsJours[i],
                          style: TextStyle(
                              fontSize: 10, color: couleurSecondaire(context))),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),

      // Repartition par matiere.
      const SizedBox(height: kEsp16),
      Text('Par matière — 4 dernières semaines', style: styleMeta(context)),
      const SizedBox(height: kEsp8),
      if (parMatiere.isEmpty)
        Text('Pas encore de séance enregistrée sur la période.',
            style: styleMeta(context)),
      for (final (mat, minutes) in parMatiere.take(10))
        _barre(context, mat, minutes / maxMat, _labelMin(minutes),
            Color(subjectColor(mat))),
      const SizedBox(height: kEsp24),
    ];
  }

  // ------------------------------------------------------------- Notes

  List<Widget> _sectionNotes(BuildContext context, AppModel m) {
    final lignes = <Widget>[];
    for (final mat in m.matieres) {
      final (kh, dsM, ecart) = moyennesMatiere(m, mat);
      if (kh == null && dsM == null) continue;
      final (recente, ancienne) = m.tendanceNotes(mat);
      lignes.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: Color(subjectColor(mat)), shape: BoxShape.circle),
            ),
            const SizedBox(width: kEsp8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mat, style: const TextStyle(fontSize: 13)),
                  Text(
                    [
                      if (kh != null) 'khôlles ${kh.toStringAsFixed(1)}',
                      if (dsM != null) 'DS ${dsM.toStringAsFixed(1)}',
                      // L'ecart a la classe dit ce qu'une note brute cache.
                      if (ecart != null)
                        '${ecart >= 0 ? '+' : ''}${ecart.toStringAsFixed(1)} vs classe',
                    ].join(' · '),
                    style: styleMeta(context),
                  ),
                ],
              ),
            ),
            Text(
              _labelTendance(recente, ancienne),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _couleurTendance(context, recente, ancienne),
              ),
            ),
          ],
        ),
      ));
    }
    if (lignes.isEmpty) return [];
    return [
      titreSection(context, 'Notes'),
      Text(
        'Moyennes de toutes tes notes, khôlles et DS séparés. La flèche compare les 30 derniers jours aux 30 précédents.',
        style: styleMeta(context),
      ),
      const SizedBox(height: kEsp8),
      ...lignes,
      const SizedBox(height: kEsp24),
    ];
  }

  // ------------------------------------------------------- Memorisation

  List<Widget> _sectionMemoire(BuildContext context, AppModel m, DateTime now) {
    final e = etatMemoire(m, maintenant: now);
    final totalChap = e.parMaitrise.fold<int>(0, (t, v) => t + v);
    if (totalChap == 0) return [];
    final matieres = <String>{
      for (final c in m.chapitres)
        if (!matiereLitteraire(c.matiere)) c.matiere
    }.toList()
      ..sort();
    const labels = ['pas vu', 'fragile', 'à revoir', 'solide', 'maîtrisé'];

    return [
      titreSection(context, 'Mémorisation'),
      Text(
        e.programmes == 0
            ? 'Aucun chapitre dans la répétition espacée pour l’instant.'
            : '${e.programmes} chapitres suivis · intervalle moyen ${e.intervalleMoyen} j (plus il monte, plus c’est ancré) · ${e.dus} à revoir aujourd’hui${e.enRetard > 0 ? ', dont ${e.enRetard} en attente' : ''}.',
        style: styleMeta(context),
      ),
      const SizedBox(height: kEsp12),
      // Barre empilee de maitrise : la photo du programme en un coup d'oeil.
      ClipRRect(
        borderRadius: BorderRadius.circular(kRayonJauge),
        child: SizedBox(
          height: 14,
          child: Row(
            children: [
              for (var i = 0; i < 5; i++)
                if (e.parMaitrise[i] > 0)
                  Expanded(
                    flex: e.parMaitrise[i],
                    child: Container(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.15 + i * 0.2),
                    ),
                  ),
            ],
          ),
        ),
      ),
      const SizedBox(height: kEsp8),
      Wrap(
        spacing: kEsp12,
        runSpacing: kEsp4,
        children: [
          for (var i = 4; i >= 0; i--)
            if (e.parMaitrise[i] > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.15 + i * 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('${e.parMaitrise[i]} ${labels[i]}',
                      style: styleMeta(context)),
                ],
              ),
          if (e.horsSysteme > 0)
            Text('${e.horsSysteme} hors révisions', style: styleMeta(context)),
        ],
      ),
      const SizedBox(height: kEsp16),
      Text('Consolidation par matière', style: styleMeta(context)),
      const SizedBox(height: kEsp8),
      for (final mat in matieres) _ligneChapitres(context, m, mat),
      const SizedBox(height: kEsp24),
    ];
  }

  Widget _ligneChapitres(BuildContext context, AppModel m, String mat) {
    final tous = m.chapitres.where((c) => c.matiere == mat).toList();
    final commences = tous.where((c) => c.etape > 0).length;
    final consolides = tous.where((c) => c.etape > 0 && c.maitrise >= 3).length;
    return _barre(
      context,
      mat,
      tous.isEmpty ? 0 : consolides / tous.length,
      '$consolides/${tous.length} · $commences vus',
      Color(subjectColor(mat)),
      largeurValeur: 92,
    );
  }

  // -------------------------------------------------------- Erreurs

  List<Widget> _sectionErreurs(BuildContext context, AppModel m, DateTime now) {
    final (total, consolidees, attente) = bilanErreurs(m, maintenant: now);
    if (total == 0) return [];
    final parType = erreursPar(m, 'type');
    final parSource = erreursPar(m, 'source');
    final maxType = parType.isEmpty ? 1 : parType.first.$2;

    return [
      titreSection(context, 'Cahier d’erreurs'),
      Text(
        '$total erreur(s) notées · $consolidees consolidées (2 succès espacés) · $attente à refaire. Le type le plus fréquent est ta marge de progression la plus rentable.',
        style: styleMeta(context),
      ),
      const SizedBox(height: kEsp12),
      for (final (type, n) in parType.take(6))
        _barre(context, type, n / maxType, '$n',
            Theme.of(context).colorScheme.primary,
            largeurLabel: 150),
      if (parSource.isNotEmpty) ...[
        const SizedBox(height: kEsp8),
        Text(
          'Origine : ${parSource.map((e) => '${e.$1} (${e.$2})').join(' · ')}',
          style: styleMeta(context),
        ),
      ],
      const SizedBox(height: kEsp24),
    ];
  }

  // ------------------------------------------------- Cartes, DM, annales

  List<Widget> _sectionDivers(BuildContext context, AppModel m) {
    final (cartes, cartesDues) = bilanCartes(m);
    final (dmFaits, _, dmEnCours, dmRates) = bilanDevoirs(m);
    final (annFaites, annTotal, annRessenti) = bilanAnnales(m);
    final (pagesLues, pagesTotal, oeuvresFinies, oeuvresTotal) = bilanLecture(m);
    final lignes = <Widget>[];

    void ligne(IconData icone, String titre, String detail) {
      lignes.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 17, color: couleurSecondaire(context)),
            const SizedBox(width: kEsp8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titre, style: const TextStyle(fontSize: 13)),
                  Text(detail, style: styleMeta(context)),
                ],
              ),
            ),
          ],
        ),
      ));
    }

    if (cartes > 0) {
      ligne(Icons.style_outlined, 'Cartes (citations + voc)',
          '$cartes carte(s) · ${cartesDues == 0 ? 'aucune à revoir aujourd’hui' : '$cartesDues à revoir aujourd’hui'}');
    }
    if (dmFaits + dmEnCours + dmRates > 0) {
      ligne(
          Icons.assignment_turned_in_outlined,
          'Travail imposé',
          '$dmFaits rendu(s) · $dmEnCours en cours'
              '${dmRates > 0 ? ' · $dmRates non rendu(s) échu(s)' : ''}');
    }
    if (annTotal > 0) {
      ligne(
          Icons.description_outlined,
          'Annales',
          '$annFaites/$annTotal faite(s)'
              '${annRessenti == null ? '' : ' · ressenti moyen ${annRessenti.toStringAsFixed(1)}/5'}');
    }
    if (oeuvresTotal > 0) {
      ligne(
          Icons.menu_book_outlined,
          'Lecture',
          '$oeuvresFinies/$oeuvresTotal œuvre(s) finie(s)'
              '${pagesTotal > 0 ? ' · $pagesLues/$pagesTotal pages' : ''}');
    }
    if (m.eplS) {
      final minEplS = m.seances
          .where((s) => s.matiere == 'EPL/S')
          .fold<int>(0, (t, s) => t + s.minutes);
      ligne(Icons.flight_takeoff, 'EPL/S (ENAC)',
          '${_labelMin(minEplS)} d’entraînement au total');
    }
    if (lignes.isEmpty) return [];
    return [
      titreSection(context, 'Le reste'),
      const SizedBox(height: kEsp4),
      ...lignes,
    ];
  }

  // ------------------------------------------------------------ Briques

  /// Ligne « label — jauge — valeur », brique partagee de tout l'ecran.
  Widget _barre(BuildContext context, String label, double valeur,
      String texteValeur, Color couleur,
      {double largeurLabel = 110, double largeurValeur = 60}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: largeurLabel,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kRayonJauge),
              child: LinearProgressIndicator(
                value: valeur.clamp(0, 1),
                minHeight: 8,
                color: couleur,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: kEsp8),
          SizedBox(
            width: largeurValeur,
            child: Text(texteValeur,
                textAlign: TextAlign.right,
                style:
                    TextStyle(fontSize: 11, color: couleurSecondaire(context))),
          ),
        ],
      ),
    );
  }

  String _labelMin(int minutes) {
    final h = minutes ~/ 60;
    final min = minutes % 60;
    if (h == 0) return '$min min';
    return min == 0 ? '$h h' : '$h h $min';
  }

  String _labelTendance(double? recente, double? ancienne) {
    if (recente == null) {
      return ancienne == null ? '—' : '${ancienne.toStringAsFixed(1)} (avant)';
    }
    final r = recente.toStringAsFixed(1);
    if (ancienne == null) return r;
    final delta = recente - ancienne;
    if (delta.abs() < 0.3) return '$r →';
    return '$r ${delta > 0 ? '↗' : '↘'} (${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)})';
  }

  Color _couleurTendance(
      BuildContext context, double? recente, double? ancienne) {
    if (recente == null || ancienne == null) return couleurSecondaire(context);
    final delta = recente - ancienne;
    if (delta.abs() < 0.3) return couleurSecondaire(context);
    // Jamais de rouge : une baisse s'affiche en orange doux, pas en alarme.
    return delta > 0 ? context.tokens.succes : context.tokens.attention;
  }
}
