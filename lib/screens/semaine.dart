import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';

/// Colonnes-jours partagees entre le tableau de bord (« Ma semaine »,
/// lundi -> dimanche) et l'Agenda (les 7 PROCHAINS jours) : EDT reel,
/// evenements ⭐, khôlles 🎤, DS 📝, DM 📥, oraux 🎓 — tries par heure,
/// aujourd'hui surligne, periodes sans cours grisees 🏖.
class VueSemaineColonnes extends StatelessWidget {
  final DateTime debut;
  final int jours;
  final double largeurColonne;
  const VueSemaineColonnes({
    super.key,
    required this.debut,
    this.jours = 7,
    this.largeurColonne = 112,
  });

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final now = DateTime.now();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < jours; i++)
            _colonneJour(context, m, debut.add(Duration(days: i)), now),
        ],
      ),
    );
  }

  Widget _colonneJour(
      BuildContext context, AppModel m, DateTime d, DateTime now) {
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
    return Container(
      width: largeurColonne,
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: estAujourdhui
            ? scheme.primary.withOpacity(0.08)
            : plage != null
                ? Colors.grey.withOpacity(0.08)
                : null,
        border: estAujourdhui
            ? Border.all(color: scheme.primary.withOpacity(0.4))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${frJour(d)[0].toUpperCase()}${frJour(d).substring(1, 3)} ${d.day}',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: estAujourdhui ? scheme.primary : null),
          ),
          const SizedBox(height: 4),
          if (plage != null)
            Text('🏖 ${plage.titre}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600))
          else if (items.isEmpty)
            Text('—', style: TextStyle(color: Colors.grey.shade400)),
          for (final it in items.take(7))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                it.$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10,
                    color: it.$3,
                    fontWeight: it.$4 ? FontWeight.w700 : FontWeight.w400),
              ),
            ),
          if (items.length > 7)
            Text('+${items.length - 7}',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
