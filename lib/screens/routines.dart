import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';

const _jours = [
  'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche',
];

/// "Ma semaine type" : cours qui finissent tard, sport, musique, asso...
/// Ces evenements recurrents s'affichent sur l'onglet Aujourd'hui, pour
/// avoir sa journee complete en tete au moment de planifier le soir.
class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({super.key});

  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Ma semaine type')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Cours qui finissent tard, sport, musique, asso… Ajoute ici ce qui '
              'revient chaque semaine : tu le verras sur l\'onglet Aujourd\'hui, '
              'pour calibrer ton travail du soir en connaissance de cause.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
          for (var jour = 1; jour <= 7; jour++) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
              child: Text(_jours[jour - 1],
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            if (m.routinesDu(jour).isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('—',
                    style: TextStyle(color: Colors.grey.shade400)),
              ),
            for (final r in m.routinesDu(jour))
              ListTile(
                dense: true,
                leading: const Icon(Icons.loop, size: 18),
                title: Text(r.titre),
                subtitle: Text(
                    '${r.labelHeure}${r.matiere.isEmpty ? '' : ' · ${r.matiere}'}'),
                onTap: () => _edit(initial: r),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () {
                    m.deleteRoutine(r.id);
                    setState(() {});
                  },
                ),
              ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _edit({Routine? initial}) async {
    final titreCtl = TextEditingController(text: initial?.titre ?? '');
    final matiereCtl = TextEditingController(text: initial?.matiere ?? '');
    var jour = initial?.jour ?? 1;
    var time = TimeOfDay(
        hour: (initial?.debutMin ?? 1080) ~/ 60,
        minute: (initial?.debutMin ?? 1080) % 60);
    var duree = initial?.dureeMin ?? 60;

    String labelDuree(int min) {
      if (min < 60) return '$min min';
      if (min % 60 == 0) return '${min ~/ 60} h';
      return '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(initial == null ? 'Nouvelle activité' : 'Modifier'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titreCtl,
                decoration: const InputDecoration(
                    labelText: 'Titre (ex. Cours de Maths, Foot, Solfège…)'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: matiereCtl,
                decoration: const InputDecoration(
                  labelText: 'Matière (si c\'est un cours — facultatif)',
                  helperText:
                      'Le soir d\'un cours, le plan de travail proposera de le revoir.',
                  helperMaxLines: 2,
                ),
              ),
              if (AppModel.instance.matieres.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final mat in AppModel.instance.matieres)
                        ActionChip(
                          label:
                              Text(mat, style: const TextStyle(fontSize: 12)),
                          onPressed: () =>
                              setLocal(() => matiereCtl.text = mat),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              DropdownButton<int>(
                value: jour,
                isExpanded: true,
                items: [
                  for (var j = 1; j <= 7; j++)
                    DropdownMenuItem(value: j, child: Text(_jours[j - 1])),
                ],
                onChanged: (v) => setLocal(() => jour = v ?? 1),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(time.format(context)),
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: context, initialTime: time);
                        if (t != null) setLocal(() => time = t);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: duree,
                    items: [
                      for (final d
                          in ({30, 45, 60, 90, 120, 150, 180, duree}.toList()
                            ..sort()))
                        DropdownMenuItem(value: d, child: Text(labelDuree(d))),
                    ],
                    onChanged: (v) => setLocal(() => duree = v ?? 60),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true || titreCtl.text.trim().isEmpty) return;
    final m = AppModel.instance;
    if (initial == null) {
      m.addRoutine(Routine(
        titre: titreCtl.text.trim(),
        jour: jour,
        debutMin: time.hour * 60 + time.minute,
        dureeMin: duree,
        matiere: matiereCtl.text.trim(),
      ));
    } else {
      initial
        ..titre = titreCtl.text.trim()
        ..jour = jour
        ..debutMin = time.hour * 60 + time.minute
        ..dureeMin = duree
        ..matiere = matiereCtl.text.trim();
      m.updateRoutine(initial);
    }
    setState(() {});
  }
}
