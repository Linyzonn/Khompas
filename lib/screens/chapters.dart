import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'import_chapitres.dart';

/// Onglet "Chapitres" : ou tu en es (etape) et a quel point tu tiens chaque
/// chapitre (maitrise 0-4). Nourrit le plan de travail du soir.
class ChaptersScreen extends StatelessWidget {
  const ChaptersScreen({super.key});

  void _importer(BuildContext context) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const ImportChapitresScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final matieres = <String>{
      ...m.matieres,
      ...m.chapitres.map((c) => c.matiere),
    }.toList()
      ..sort();

    return Scaffold(
      body: m.chapitres.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Charge les chapitres du programme officiel de ta filière '
                      '(prepa.org), puis fais-les vivre : vu en cours → revu → '
                      'exos → DS. Le plan du soir s\'appuie dessus.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      icon: const Icon(Icons.menu_book),
                      label: const Text('Importer le programme officiel'),
                      onPressed: () => _importer(context),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.menu_book),
                    label: const Text('Importer le programme officiel (IA)'),
                    onPressed: () => _importer(context),
                  ),
                ),
                for (final mat in matieres)
                  if (m.chapitres.any((c) => c.matiere == mat))
                    _section(context, mat),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _ajouter(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _section(BuildContext context, String mat) {
    final m = AppModel.instance;
    final color = Color(subjectColor(mat));
    final chs = m.chapitres.where((c) => c.matiere == mat).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(mat, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
        for (final c in chs)
          ListTile(
            dense: true,
            title: Text(c.nom),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Etape de progression : le workflow prepa.
                Wrap(
                  spacing: 4,
                  runSpacing: -8,
                  children: [
                    for (var iEt = 0; iEt < kEtapesChapitre.length; iEt++)
                      ChoiceChip(
                        label: Text(kEtapesChapitre[iEt],
                            style: const TextStyle(fontSize: 10)),
                        selected: c.etape == iEt,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        onSelected: (_) {
                          c.etape = iEt;
                          m.updateChapitre(c);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                // Maitrise : a quel point tu le tiens.
                Row(
                  children: [
                    for (var i = 0; i < 5; i++)
                      InkWell(
                        onTap: () {
                          c.maitrise = i;
                          m.updateChapitre(c);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(
                            i <= c.maitrise
                                ? Icons.circle
                                : Icons.circle_outlined,
                            size: 16,
                            color: i <= c.maitrise
                                ? _couleurMaitrise(c.maitrise)
                                : Colors.grey,
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    Text(
                      _labelMaitrise(c.maitrise),
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => m.deleteChapitre(c.id),
            ),
          ),
      ],
    );
  }

  Color _couleurMaitrise(int n) {
    if (n <= 1) return Colors.red;
    if (n == 2) return Colors.orange;
    if (n == 3) return Colors.lightGreen;
    return Colors.green;
  }

  String _labelMaitrise(int n) {
    switch (n) {
      case 0:
        return 'pas vu';
      case 1:
        return 'fragile';
      case 2:
        return 'moyen';
      case 3:
        return 'solide';
      default:
        return 'maîtrisé';
    }
  }

  void _ajouter(BuildContext context) {
    final m = AppModel.instance;
    final matiereCtl = TextEditingController();
    final nomCtl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Nouveau chapitre'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
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
                controller: nomCtl,
                decoration: const InputDecoration(
                    labelText: 'Chapitre (ex. Suites, Optique géométrique…)'),
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (matiereCtl.text.trim().isEmpty || nomCtl.text.trim().isEmpty) return;
                m.addChapitre(Chapitre(
                  matiere: matiereCtl.text.trim(),
                  nom: nomCtl.text.trim(),
                  // Ajoute a la main = generalement un chapitre en cours.
                  etape: 1,
                ));
                Navigator.pop(context);
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
  }
}
