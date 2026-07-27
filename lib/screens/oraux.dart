import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';

/// MODE ORAUX : le planning des epreuves orales par concours (les dates
/// tombent apres l'admissibilite — tout est facultatif sauf concours +
/// epreuve), et l'interrupteur qui fait basculer le plan du soir en
/// preparation d'oral (travail a voix haute, rotation des epreuves,
/// TIPE / ADS inclus).
class OrauxScreen extends StatefulWidget {
  const OrauxScreen({super.key});

  @override
  State<OrauxScreen> createState() => _OrauxScreenState();
}

class _OrauxScreenState extends State<OrauxScreen> {
  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final concoursListe = <String>[];
    for (final o in m.oraux) {
      if (!concoursListe.contains(o.concours)) concoursListe.add(o.concours);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Mode oraux')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          SwitchListTile(
            title: const Text('Activer le mode oraux'),
            subtitle: const Text(
                'Le plan du soir bascule en préparation d\'oral : travail À VOIX HAUTE, rotation de tes épreuves (TIPE et ADS compris), l\'épreuve la plus proche en tête.'),
            value: m.modeOraux,
            onChanged: m.oraux.isEmpty
                ? null
                : (v) {
                    m.setModeOraux(v);
                    setState(() {});
                  },
          ),
          if (m.oraux.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text('🎓', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text(
                    'Ajoute tes épreuves orales par concours (Maths CCINP, TIPE, anglais Centrale…).\n\nLes dates et salles se complètent plus tard, quand les convocations tombent — l\'app te préviendra la veille de chaque passage si les notifications sont actives.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          else
            for (final c in concoursListe) _section(c),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editer(null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _section(String concours) {
    final m = AppModel.instance;
    final liste = m.oraux.where((o) => o.concours == concours).toList();
    return ExpansionTile(
      initiallyExpanded: true,
      leading: const Icon(Icons.school),
      title:
          Text(concours, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${liste.length} épreuve(s)',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      children: [
        for (final o in liste) _tuile(o),
      ],
    );
  }

  Widget _tuile(EpreuveOrale o) {
    final m = AppModel.instance;
    final color = Color(subjectColor(o.epreuve));
    final now = DateTime.now();
    String sous;
    if (o.date == null) {
      sous = 'Date à venir (après l\'admissibilité)';
    } else {
      final j = DateTime(o.date!.year, o.date!.month, o.date!.day)
          .difference(DateTime(now.year, now.month, now.day))
          .inDays;
      sous = '${frDate(o.date!)}'
          '${o.debutMin == null ? '' : ' · ${o.debutMin! ~/ 60}h${(o.debutMin! % 60).toString().padLeft(2, '0')}'}'
          '${j >= 0 ? ' · J-$j' : ''}';
    }
    if (o.lieu.isNotEmpty) sous += '\n📍 ${o.lieu}';
    return ListTile(
      dense: true,
      isThreeLine: o.lieu.isNotEmpty,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.18),
        child: Icon(Icons.record_voice_over, color: color, size: 18),
      ),
      title: Text(o.epreuve),
      subtitle: Text(sous,
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'edit') {
            _editer(o);
          } else if (v == 'delete') {
            m.deleteOral(o.id);
            setState(() {});
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Modifier / dater')),
          const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
        ],
      ),
    );
  }

  Future<void> _editer(EpreuveOrale? initial) async {
    final m = AppModel.instance;
    final concoursCtl = TextEditingController(text: initial?.concours ?? '');
    final epreuveCtl = TextEditingController(text: initial?.epreuve ?? '');
    final lieuCtl = TextEditingController(text: initial?.lieu ?? '');
    var date = initial?.date;
    var heure = initial?.debutMin == null
        ? null
        : TimeOfDay(
            hour: initial!.debutMin! ~/ 60, minute: initial.debutMin! % 60);

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(initial == null ? 'Épreuve orale' : 'Modifier l\'épreuve'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: concoursCtl,
                  decoration: const InputDecoration(labelText: 'Concours'),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final c in kConcoursPour(m.filiere))
                        ActionChip(
                          label: Text(c, style: const TextStyle(fontSize: 12)),
                          onPressed: () =>
                              setState(() => concoursCtl.text = c),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: epreuveCtl,
                  decoration: const InputDecoration(labelText: 'Épreuve'),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final e in kEpreuvesOrales)
                        ActionChip(
                          label: Text(e, style: const TextStyle(fontSize: 12)),
                          onPressed: () =>
                              setState(() => epreuveCtl.text = e),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.event, size: 18),
                        label: Text(
                            date == null ? 'Date ?' : frDateCourte(date!)),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: date ??
                                DateTime.now().add(const Duration(days: 30)),
                            firstDate: DateTime(2023),
                            lastDate: DateTime(2032),
                          );
                          if (d != null) setState(() => date = d);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text(heure == null
                            ? 'Heure ?'
                            : heure!.format(context)),
                        onPressed: () async {
                          final t = await showTimePicker(
                              context: context,
                              initialTime: heure ??
                                  const TimeOfDay(hour: 8, minute: 0));
                          if (t != null) setState(() => heure = t);
                        },
                      ),
                    ),
                  ],
                ),
                if (date != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() {
                        date = null;
                        heure = null;
                      }),
                      child: const Text('Effacer la date',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                TextField(
                  controller: lieuCtl,
                  decoration: const InputDecoration(
                      labelText: 'Lieu (facultatif — ex. Lycée Hoche, salle B12)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (concoursCtl.text.trim().isEmpty ||
                    epreuveCtl.text.trim().isEmpty) {
                  return;
                }
                final o = initial ??
                    EpreuveOrale(concours: '', epreuve: '');
                o
                  ..concours = concoursCtl.text.trim()
                  ..epreuve = epreuveCtl.text.trim()
                  ..date = date == null
                      ? null
                      : DateTime(date!.year, date!.month, date!.day)
                  ..debutMin =
                      heure == null ? null : heure!.hour * 60 + heure!.minute
                  ..lieu = lieuCtl.text.trim();
                if (initial == null) {
                  m.addOral(o);
                } else {
                  m.updateOral(o);
                }
                Navigator.pop(context);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}
