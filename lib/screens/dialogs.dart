import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';

/// "45 min", "1 h", "1 h 30"...
String _labelDuree(int min) {
  if (min < 60) return '$min min';
  if (min % 60 == 0) return '${min ~/ 60} h';
  return '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';
}

/// Editeur de khôlle (creation ou modification).
Future<Colle?> editColleDialog(BuildContext context, {Colle? initial}) async {
  final m = AppModel.instance;
  final matiereCtl = TextEditingController(text: initial?.matiere ?? '');
  final kholleurCtl = TextEditingController(text: initial?.kholleur ?? '');
  final salleCtl = TextEditingController(text: initial?.salle ?? '');
  final progCtl = TextEditingController(text: initial?.programme ?? '');
  var date = initial?.start ?? DateTime.now().add(const Duration(days: 1));
  var time = TimeOfDay(hour: initial?.start.hour ?? 16, minute: initial?.start.minute ?? 0);
  var duree = initial?.dureeMin ?? 60;

  return showDialog<Colle>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(initial == null ? 'Nouvelle khôlle' : 'Modifier la khôlle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: matiereCtl,
                decoration: const InputDecoration(labelText: 'Matière'),
                textCapitalization: TextCapitalization.sentences,
              ),
              if (m.matieres.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final mat in m.matieres)
                        ActionChip(
                          label: Text(mat, style: const TextStyle(fontSize: 12)),
                          onPressed: () => setState(() => matiereCtl.text = mat),
                        ),
                    ],
                  ),
                ),
              TextField(
                controller: kholleurCtl,
                decoration: const InputDecoration(labelText: 'Khôlleur (facultatif)'),
              ),
              TextField(
                controller: salleCtl,
                decoration: const InputDecoration(labelText: 'Salle (facultatif)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event, size: 18),
                      label: Text(frDateCourte(date)),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: date,
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
                      label: Text(time.format(context)),
                      onPressed: () async {
                        final t = await showTimePicker(context: context, initialTime: time);
                        if (t != null) setState(() => time = t);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Durée : '),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: duree,
                    // La valeur courante est toujours dans la liste, meme si
                    // l'import IA a donne une duree inhabituelle (45, 80 min...) :
                    // sans ca, Flutter plante ("exactly one item with value").
                    items: [
                      for (final d in ({30, 45, 55, 60, 90, 120, duree}.toList()..sort()))
                        DropdownMenuItem(value: d, child: Text(_labelDuree(d))),
                    ],
                    onChanged: (v) => setState(() => duree = v ?? 60),
                  ),
                ],
              ),
              TextField(
                controller: progCtl,
                decoration: const InputDecoration(labelText: 'Programme de colle (facultatif)'),
                maxLines: 3,
                minLines: 1,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (matiereCtl.text.trim().isEmpty) return;
              final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
              final c = initial ?? Colle(matiere: '', start: start, custom: true);
              c
                ..matiere = matiereCtl.text.trim()
                ..kholleur = kholleurCtl.text.trim()
                ..salle = salleCtl.text.trim()
                ..start = start
                ..dureeMin = duree
                ..programme = progCtl.text.trim();
              Navigator.pop(context, c);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
}

/// Editeur de DS.
Future<Ds?> editDsDialog(BuildContext context, {Ds? initial}) async {
  final m = AppModel.instance;
  final matiereCtl = TextEditingController(text: initial?.matiere ?? '');
  final titreCtl = TextEditingController(text: initial?.titre ?? 'DS');
  var date = initial?.date ?? DateTime.now().add(const Duration(days: 3));

  return showDialog<Ds>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(initial == null ? 'Nouveau DS' : 'Modifier le DS'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: matiereCtl,
              decoration: const InputDecoration(labelText: 'Matière'),
            ),
            if (m.matieres.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final mat in m.matieres)
                      ActionChip(
                        label: Text(mat, style: const TextStyle(fontSize: 12)),
                        onPressed: () => setState(() => matiereCtl.text = mat),
                      ),
                  ],
                ),
              ),
            TextField(
              controller: titreCtl,
              decoration: const InputDecoration(labelText: 'Titre (DS, concours blanc…)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event, size: 18),
              label: Text(frDate(date)),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2023),
                  lastDate: DateTime(2032),
                );
                if (d != null) setState(() => date = d);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (matiereCtl.text.trim().isEmpty) return;
              final d = initial ?? Ds(matiere: '', date: date);
              d
                ..matiere = matiereCtl.text.trim()
                ..titre = titreCtl.text.trim().isEmpty ? 'DS' : titreCtl.text.trim()
                ..date = DateTime(date.year, date.month, date.day);
              Navigator.pop(context, d);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
}

/// Saisie d'une note /20. Retourne -1 pour "effacer la note".
Future<double?> noteDialog(BuildContext context, {double? current}) async {
  final ctl = TextEditingController(text: current?.toString() ?? '');
  return showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Note /20'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(hintText: 'ex. 14.5'),
      ),
      actions: [
        if (current != null)
          TextButton(
            onPressed: () => Navigator.pop(context, -1.0),
            child: const Text('Effacer'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final v = double.tryParse(ctl.text.replaceAll(',', '.'));
            if (v != null && v >= 0 && v <= 20) Navigator.pop(context, v);
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
