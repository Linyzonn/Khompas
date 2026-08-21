import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';

/// PROGRESSION : l'ecran que la roadmap promettait — heures de travail par
/// semaine (13 mois de seances conserves expres), repartition par matiere,
/// tendance des notes sur 30 jours, et etat de consolidation des chapitres.
/// Toujours BIENVEILLANT : des tendances et des progres, jamais de rouge
/// culpabilisant ni de comparaison a autrui.
class ProgressionScreen extends StatelessWidget {
  const ProgressionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final histo = m.minutesParSemaineHisto();
    final maxSemaine =
        histo.fold<int>(0, (t, e) => e.$2 > t ? e.$2 : t).clamp(1, 1 << 31);
    final parMatiere = m.minutesParMatiere();
    final maxMatiere = parMatiere.isEmpty ? 1 : parMatiere.first.$2;
    final totalHisto = histo.fold<int>(0, (t, e) => t + e.$2);
    final semainesActives = histo.where((e) => e.$2 > 0).length;

    // Matieres avec au moins une note recente : tendance 30 j.
    final tendances = <(String, double?, double?)>[];
    for (final mat in m.matieres) {
      final (recente, ancienne) = m.tendanceNotes(mat);
      if (recente != null || ancienne != null) {
        tendances.add((mat, recente, ancienne));
      }
    }

    // Chapitres : consolidation par matiere.
    final matieresChapitres = <String>{
      for (final c in m.chapitres)
        if (!matiereLitteraire(c.matiere)) c.matiere
    }.toList()
      ..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('Ma progression')),
      body: listeCentree(context, children: [
          // ---- Heures par semaine ----
          Text('Heures de travail — 12 semaines',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            totalHisto == 0
                ? 'Coche tes sessions du soir : les heures se comptent toutes seules.'
                : '${_labelMin(totalHisto)} au total · ${semainesActives == 0 ? '—' : _labelMin(totalHisto ~/ semainesActives)} par semaine active.',
            style: TextStyle(color: couleurSecondaire(context), fontSize: 12),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 120,
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
                              (minutes / 60).toStringAsFixed(
                                  minutes % 60 == 0 ? 0 : 1),
                              style: TextStyle(
                                  fontSize: 9,
                                  color: couleurSecondaire(context)),
                            ),
                          const SizedBox(height: 2),
                          Container(
                            height: 88.0 * minutes / maxSemaine + 2,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(
                                      alpha: minutes == 0 ? 0.15 : 0.75),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3)),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text('${lundi.day}/${lundi.month}',
                              style: TextStyle(
                                  fontSize: 8,
                                  color: couleurSecondaire(context))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ---- Par matiere (4 dernieres semaines) ----
          const SizedBox(height: 24),
          Text('Par matière — 4 dernières semaines',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (parMatiere.isEmpty)
            Text('Pas encore de séance enregistrée sur la période.',
                style:
                    TextStyle(color: couleurSecondaire(context), fontSize: 12)),
          for (final (mat, minutes) in parMatiere.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(mat,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(kRayonJauge),
                      child: LinearProgressIndicator(
                        value: minutes / maxMatiere,
                        minHeight: 8,
                        color: Color(subjectColor(mat)),
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    child: Text(_labelMin(minutes),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: couleurSecondaire(context))),
                  ),
                ],
              ),
            ),

          // ---- Tendance des notes ----
          if (tendances.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Notes — tendance sur 30 jours',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Moyenne des 30 derniers jours (khôlles + DS) comparée aux 30 jours d\'avant.',
              style: TextStyle(color: couleurSecondaire(context), fontSize: 12),
            ),
            const SizedBox(height: 6),
            for (final (mat, recente, ancienne) in tendances)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: Color(subjectColor(mat)),
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(mat, style: const TextStyle(fontSize: 13))),
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
              ),
          ],

          // ---- Chapitres consolides ----
          if (matieresChapitres.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Chapitres consolidés',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Consolidé = maîtrise ≥ 3. C\'est la jauge qui monte au fil des révisions espacées.',
              style: TextStyle(color: couleurSecondaire(context), fontSize: 12),
            ),
            const SizedBox(height: 6),
            for (final mat in matieresChapitres)
              _ligneChapitres(context, m, mat),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _ligneChapitres(BuildContext context, AppModel m, String mat) {
    final tous = m.chapitres.where((c) => c.matiere == mat).toList();
    final commences = tous.where((c) => c.etape > 0).length;
    final consolides =
        tous.where((c) => c.etape > 0 && c.maitrise >= 3).length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(mat,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kRayonJauge),
              child: LinearProgressIndicator(
                value: tous.isEmpty ? 0 : consolides / tous.length,
                minHeight: 8,
                color: Color(subjectColor(mat)),
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 86,
            child: Text('$consolides/${tous.length} · $commences vus',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 11, color: couleurSecondaire(context))),
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
    if (recente == null) return '${ancienne!.toStringAsFixed(1)} (avant)';
    final r = recente.toStringAsFixed(1);
    if (ancienne == null) return r;
    final delta = recente - ancienne;
    if (delta.abs() < 0.3) return '$r →';
    return '$r ${delta > 0 ? '↗' : '↘'} (${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)})';
  }

  Color _couleurTendance(
      BuildContext context, double? recente, double? ancienne) {
    if (recente == null || ancienne == null) {
      return couleurSecondaire(context);
    }
    final delta = recente - ancienne;
    if (delta.abs() < 0.3) return couleurSecondaire(context);
    // Jamais de rouge : une baisse s'affiche en orange doux, pas en alarme.
    return delta > 0 ? context.tokens.succes : context.tokens.attention;
  }
}
