import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';

/// Colonnes-jours compactes (blocs teintes) : la carte « Ma semaine » du
/// tableau de bord, et l'Agenda sur TELEPHONE. Sur PC, l'Agenda utilise la
/// vraie grille horaire (grille_semaine.dart).
///
/// [etire] est decide par l'APPELANT (pas de LayoutBuilder ici : ce widget
/// vit dans une carte IntrinsicHeight, qui ne supporte pas LayoutBuilder).
class VueSemaineColonnes extends StatelessWidget {
  final DateTime debut;
  final int jours;
  // true = les colonnes remplissent la largeur (Expanded) ; false = scroll
  // horizontal a largeur fixe.
  final bool etire;
  final double hauteurMin;
  const VueSemaineColonnes({
    super.key,
    required this.debut,
    this.jours = 7,
    this.etire = false,
    this.hauteurMin = 120,
  });

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final now = DateTime.now();
    if (etire) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < jours; i++)
            Expanded(
              child: _colonneJour(
                  context, m, debut.add(Duration(days: i)), now,
                  etire: true, dernier: i == jours - 1),
            ),
        ],
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < jours; i++)
            SizedBox(
              width: 128,
              child: _colonneJour(
                  context, m, debut.add(Duration(days: i)), now,
                  etire: false, dernier: i == jours - 1),
            ),
        ],
      ),
    );
  }

  Widget _colonneJour(
      BuildContext context, AppModel m, DateTime d, DateTime now,
      {required bool etire, required bool dernier}) {
    final estAujourdhui =
        d.year == now.year && d.month == now.month && d.day == now.day;
    final plage = m.plageSansCours(d);
    final items = <(int, String, Color, bool)>[];
    if (plage == null) {
      for (final r in m.routinesLe(d)) {
        items.add((
          r.debutMin,
          '${r.debutMin ~/ 60}h ${r.titre}',
          r.matiere.isEmpty ? Colors.blueGrey : Color(subjectColor(r.matiere)),
          false,
        ));
      }
    }
    for (final e in m.evenementsLe(d)) {
      items.add((
        e.debutMin,
        '⭐ ${e.debutMin ~/ 60}h ${e.titre}',
        e.matiere.isEmpty ? Colors.blueGrey : Color(subjectColor(e.matiere)),
        false,
      ));
    }
    for (final c in m.colles) {
      if (c.start.year == d.year &&
          c.start.month == d.month &&
          c.start.day == d.day) {
        items.add((
          c.start.hour * 60 + c.start.minute,
          '🎤 ${frHeure(c.start)} ${c.matiere}${c.salle.isEmpty ? '' : ' s.${c.salle}'}',
          Color(subjectColor(c.matiere)),
          true,
        ));
      }
    }
    for (final ds in m.ds) {
      if (ds.date.year == d.year &&
          ds.date.month == d.month &&
          ds.date.day == d.day) {
        items.add(
            (0, '📝 ${ds.titre} ${ds.matiere}', Color(subjectColor(ds.matiere)), true));
      }
    }
    for (final dev in m.devoirsARendre()) {
      if (dev.dateRendu.year == d.year &&
          dev.dateRendu.month == d.month &&
          dev.dateRendu.day == d.day) {
        items.add((
          1,
          '📥 ${dev.titre} ${dev.matiere}',
          Color(subjectColor(dev.matiere)),
          true,
        ));
      }
    }
    for (final o in m.oraux) {
      if (o.date != null &&
          o.date!.year == d.year &&
          o.date!.month == d.month &&
          o.date!.day == d.day) {
        items.add((
          o.debutMin ?? 0,
          '🎓 ${o.concours} ${o.epreuve}',
          Color(subjectColor(o.epreuve)),
          true,
        ));
      }
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));

    final scheme = Theme.of(context).colorScheme;
    final maxItems = etire ? 10 : 7;
    final jourLong = frJour(d);
    final labelJour = etire
        ? '${jourLong[0].toUpperCase()}${jourLong.substring(1)}'
        : '${jourLong[0].toUpperCase()}${jourLong.substring(1, 3)}';

    return Container(
      margin: EdgeInsets.only(right: dernier ? 0 : 8),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      constraints: BoxConstraints(minHeight: hauteurMin),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: estAujourdhui
            ? scheme.primary.withValues(alpha: 0.07)
            : plage != null
                ? Colors.grey.withValues(alpha: 0.10)
                : Colors.grey.withValues(alpha: 0.04),
        border: Border.all(
          color: estAujourdhui
              ? scheme.primary.withValues(alpha: 0.55)
              : Colors.grey.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tete : jour + numero, badge « auj. » le jour meme.
          Row(
            children: [
              Expanded(
                child: Text(
                  '$labelJour ${d.day}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: etire ? 13.5 : 12.5,
                      fontWeight: FontWeight.w800,
                      color: estAujourdhui
                          ? scheme.primary
                          : Colors.grey.shade700),
                ),
              ),
              if (estAujourdhui)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('auj.',
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (plage != null)
            Text('🏖 ${plage.titre}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: couleurSecondaire(context)))
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('—',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
            ),
          // Chaque element = un petit bloc teinte a liseret colore (bien
          // plus lisible que des lignes de texte nues).
          for (final it in items.take(maxItems))
            Container(
              margin: const EdgeInsets.only(bottom: 3),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              width: double.infinity,
              decoration: BoxDecoration(
                color: it.$3.withValues(alpha: it.$4 ? 0.16 : 0.09),
                borderRadius: BorderRadius.circular(6),
                border: Border(
                    left: BorderSide(color: it.$3, width: 3)),
              ),
              child: Text(
                it.$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: etire ? 11.5 : 10.5,
                    height: 1.2,
                    color: it.$3,
                    fontWeight: it.$4 ? FontWeight.w800 : FontWeight.w500),
              ),
            ),
          if (items.length > maxItems)
            Text('+${items.length - maxItems} autres',
                style: TextStyle(fontSize: 10, color: couleurSecondaire(context))),
        ],
      ),
    );
  }
}
