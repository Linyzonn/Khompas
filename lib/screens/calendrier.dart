import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';

/// Calendrier interne : roulement des semaines (A/B) et periodes SANS cours
/// (vacances, semaines de revisions avant les concours). L'emploi du temps
/// et le plan du soir en tiennent compte automatiquement.
class CalendrierScreen extends StatefulWidget {
  const CalendrierScreen({super.key});

  @override
  State<CalendrierScreen> createState() => _CalendrierScreenState();
}

class _CalendrierScreenState extends State<CalendrierScreen> {
  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Calendrier')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Roulement des semaines (A/B)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Si ton emploi du temps alterne une semaine sur deux, indique un '
            'lundi de semaine A : l\'app saura ensuite quelle semaine tu vis, '
            'et n\'affichera que les bons créneaux (marqués « Semaine A/B » '
            'dans Mon emploi du temps).',
            style: TextStyle(color: couleurSecondaire(context), fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (m.refSemaineA == null)
            OutlinedButton.icon(
              icon: const Icon(Icons.looks_one),
              label: const Text('Définir une semaine A'),
              onPressed: _definirSemaineA,
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.looks_one),
              title: Text(
                  'Semaine A : semaine du ${frDateCourte(mondayOf(m.refSemaineA!))}'),
              subtitle: Text(
                  'Cette semaine-ci est une semaine ${m.semaineEstA(now) ? 'A' : 'B'}.'),
              onTap: _definirSemaineA,
              trailing: TextButton(
                onPressed: () {
                  m.setRefSemaineA(null);
                  setState(() {});
                },
                child: const Text('Retirer'),
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text('Périodes sans cours',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ajouter'),
                onPressed: _ajouterPlage,
              ),
            ],
          ),
          Text(
            'Vacances, et — pour les 3/2 et 5/2 — semaines de révisions avant '
            'les concours : l\'emploi du temps se met en veille sur ces '
            'périodes (pas de « cours du jour » dans le plan du soir).',
            style: TextStyle(color: couleurSecondaire(context), fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (m.sansCours.isEmpty)
            Text('Aucune période pour le moment.',
                style: TextStyle(color: Colors.grey.shade400)),
          for (final p in m.sansCours)
            ListTile(
              contentPadding: EdgeInsets.zero,
              // Le TYPE de plage (et plus une heuristique sur le titre)
              // choisit l'icone — et pilote le plan du soir (mode ete).
              leading: Text(
                kTypesPlage
                    .firstWhere((t) => t.$1 == p.type,
                        orElse: () => kTypesPlage.first)
                    .$2,
                style: const TextStyle(fontSize: 22),
              ),
              title: Text(p.titre),
              subtitle:
                  Text('du ${frDateCourte(p.debut)} au ${frDateCourte(p.fin)}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () {
                  m.deletePlageSansCours(p.id);
                  setState(() {});
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _definirSemaineA() async {
    final m = AppModel.instance;
    final d = await showDatePicker(
      context: context,
      initialDate: m.refSemaineA ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime(2032),
      helpText: 'Choisis un jour d\'une semaine A',
    );
    if (d != null) {
      m.setRefSemaineA(mondayOf(d));
      if (mounted) setState(() {});
    }
  }

  Future<void> _ajouterPlage() async {
    final titreCtl = TextEditingController(text: 'Vacances');
    var debut = DateTime.now();
    var fin = DateTime.now().add(const Duration(days: 13));
    var type = 'vacances';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Période sans cours'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titreCtl,
                decoration: const InputDecoration(
                    labelText: 'Titre (Toussaint, Révisions concours…)'),
              ),
              const SizedBox(height: 10),
              // Le type pilote le plan du soir : « Été » = reactivation
              // douce du programme (rotation, annales, dimanche de repos).
              Wrap(
                spacing: 6,
                children: [
                  for (final t in kTypesPlage)
                    ChoiceChip(
                      label: Text('${t.$2} ${t.$3}',
                          style: const TextStyle(fontSize: 12)),
                      selected: type == t.$1,
                      onSelected: (_) => setLocal(() {
                        type = t.$1;
                        if (t.$1 == 'ete' &&
                            titreCtl.text.trim() == 'Vacances') {
                          titreCtl.text = 'Grandes vacances';
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      child: Text('Du ${frDateCourte(debut)}'),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: debut,
                          firstDate: DateTime(2023),
                          lastDate: DateTime(2032),
                        );
                        if (d != null) {
                          setLocal(() {
                            debut = d;
                            if (fin.isBefore(debut)) fin = debut;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      child: Text('au ${frDateCourte(fin)}'),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: fin,
                          firstDate: debut,
                          lastDate: DateTime(2032),
                        );
                        if (d != null) setLocal(() => fin = d);
                      },
                    ),
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
                child: const Text('Ajouter')),
          ],
        ),
      ),
    );
    if (ok == true && titreCtl.text.trim().isNotEmpty) {
      AppModel.instance.addPlageSansCours(PlageSansCours(
        titre: titreCtl.text.trim(),
        debut: debut,
        fin: fin,
        type: type,
      ));
      if (mounted) setState(() {});
    }
  }
}
