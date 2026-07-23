import 'package:flutter/material.dart';

import '../engine.dart';
import '../models.dart';
import '../store.dart';

/// Onglet "Aujourd'hui" : prochaine khôlle + plan de la soiree + semaine.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  int minutes = 120;

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final prochaine = m.prochaineColle();
    final suggestions = suggere(m, minutes);
    final now = DateTime.now();
    final lundi = mondayOf(now);
    final dimanche = lundi.add(const Duration(days: 7));
    final semaineColles = m.colles
        .where((c) => c.start.isAfter(lundi) && c.start.isBefore(dimanche))
        .toList();
    final semaineDs = m.ds
        .where((d) => d.date.isAfter(lundi.subtract(const Duration(days: 1))) &&
            d.date.isBefore(dimanche))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (prochaine != null) _prochaineCard(context, prochaine),
        if (prochaine == null) _emptyCard(context),
        const SizedBox(height: 20),
        Text('Ce soir, tu as…', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final e in const [
              (60, '1 h'),
              (90, '1 h 30'),
              (120, '2 h'),
              (180, '3 h'),
            ])
              ChoiceChip(
                label: Text(e.$2),
                selected: minutes == e.$1,
                onSelected: (_) => setState(() => minutes = e.$1),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (suggestions.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Importe ton colloscope et ajoute quelques chapitres : je te proposerai un plan de travail pour chaque soirée.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          ),
        for (final s in suggestions) _suggestionCard(context, s),
        const SizedBox(height: 20),
        Text('Cette semaine', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (semaineColles.isEmpty && semaineDs.isEmpty)
          Text('Rien au programme cette semaine 🎉',
              style: TextStyle(color: Colors.grey.shade600)),
        for (final c in semaineColles) _miniEvent(
              color: Color(subjectColor(c.matiere)),
              titre: 'Khôlle ${c.matiere}',
              sousTitre:
                  '${frJour(c.start)} ${frHeure(c.start)}${c.salle.isEmpty ? '' : ' · salle ${c.salle}'}',
              passe: c.end.isBefore(now),
            ),
        for (final d in semaineDs) _miniEvent(
              color: Color(subjectColor(d.matiere)),
              titre: '${d.titre} ${d.matiere}',
              sousTitre: frDate(d.date),
              passe: d.date.isBefore(DateTime(now.year, now.month, now.day)),
            ),
      ],
    );
  }

  Widget _prochaineCard(BuildContext context, Colle c) {
    final now = DateTime.now();
    final diff = c.start.difference(now);
    String quand;
    if (diff.isNegative) {
      quand = 'en cours';
    } else if (c.start.day == now.day && c.start.month == now.month) {
      quand = "aujourd'hui à ${frHeure(c.start)}";
    } else if (diff.inHours < 36) {
      quand = 'demain à ${frHeure(c.start)}';
    } else {
      quand = 'J-${diff.inDays + 1}';
    }
    final color = Color(subjectColor(c.matiere));
    return Card(
      color: color.withOpacity(0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color,
              child: const Icon(Icons.record_voice_over, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Prochaine khôlle : ${c.matiere}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 3),
                  Text(
                    '${frDate(c.start)} · ${frHeure(c.start)}'
                    '${c.salle.isEmpty ? '' : ' · salle ${c.salle}'}'
                    '${c.kholleur.isEmpty ? '' : '\n${c.kholleur}'}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                ],
              ),
            ),
            Chip(
              label: Text(quand, style: const TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: color.withOpacity(0.2),
              side: BorderSide.none,
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.photo_camera_outlined, size: 40),
              const SizedBox(height: 10),
              const Text(
                'Aucune khôlle à venir.\nCommence par importer ton colloscope : une photo suffit.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  Widget _suggestionCard(BuildContext context, Suggestion s) {
    final color = Color(subjectColor(s.matiere));
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.18),
          child: Text(
            '${s.minutes >= 60 ? '${s.minutes ~/ 60}h' : ''}${s.minutes % 60 == 0 ? '' : (s.minutes % 60).toString().padLeft(2, '0')}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        title: Text(s.matiere, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${s.raison}\n${s.titre}'),
        isThreeLine: true,
      ),
    );
  }

  Widget _miniEvent({
    required Color color,
    required String titre,
    required String sousTitre,
    required bool passe,
  }) =>
      Opacity(
        opacity: passe ? 0.45 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titre, style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text(sousTitre,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
              if (passe) const Icon(Icons.check, size: 16, color: Colors.grey),
            ],
          ),
        ),
      );
}
