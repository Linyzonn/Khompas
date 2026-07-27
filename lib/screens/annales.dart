import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';

/// TRACKER D'ANNALES : les sujets de concours a faire / faits, par matiere,
/// avec un ressenti /5. En mode revisions concours (J-45 et moins), le plan
/// du soir pioche dedans : « Annale CCINP 2024 — Maths », matiere la moins
/// couverte d'abord.
class AnnalesScreen extends StatefulWidget {
  const AnnalesScreen({super.key});

  @override
  State<AnnalesScreen> createState() => _AnnalesScreenState();
}

class _AnnalesScreenState extends State<AnnalesScreen> {
  static const _emojis = ['😵', '😮‍💨', '🙂', '😊', '😎'];

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final matieres = <String>[];
    for (final a in m.annales) {
      if (!matieres.contains(a.matiere)) matieres.add(a.matiere);
    }
    matieres.sort();
    final faites = m.annales.where((a) => a.fait).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Annales')),
      body: m.annales.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('📜', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text(
                      'Ajoute les annales que tu comptes faire (CCINP 2024 Maths, Centrale 2023 Physique…).\n\nÀ J-45 des écrits, le plan du soir te proposera « une annale en conditions » en piochant ici, matière la moins couverte d\'abord.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '$faites / ${m.annales.length} faites',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: Colors.grey.shade600),
                  ),
                ),
                for (final mat in matieres) _section(mat),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _ajouter,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _section(String mat) {
    final m = AppModel.instance;
    final color = Color(subjectColor(mat));
    final liste = m.annales.where((a) => a.matiere == mat).toList();
    final faites = liste.where((a) => a.fait).length;
    return ExpansionTile(
      initiallyExpanded: true,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.18),
        child: Text(mat.characters.first.toUpperCase(),
            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ),
      title: Text(mat, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('$faites / ${liste.length} faites',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      children: [
        for (final a in liste) _tuile(a),
      ],
    );
  }

  Widget _tuile(Annale a) {
    final m = AppModel.instance;
    return ListTile(
      dense: true,
      leading: Checkbox(
        value: a.fait,
        onChanged: (v) {
          a.fait = v ?? false;
          a.dateFait = a.fait ? DateTime.now() : null;
          if (!a.fait) a.ressenti = 0;
          m.updateAnnale(a);
          setState(() {});
        },
      ),
      title: Text(
        '${a.concours} ${a.annee}',
        style: a.fait
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: a.fait
          ? Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Ressenti : ',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                for (var i = 1; i <= 5; i++)
                  GestureDetector(
                    onTap: () {
                      a.ressenti = i;
                      m.updateAnnale(a);
                      setState(() {});
                    },
                    child: Opacity(
                      opacity: a.ressenti == i ? 1 : 0.35,
                      child: Text(_emojis[i - 1],
                          style: const TextStyle(fontSize: 16)),
                    ),
                  ),
              ],
            )
          : null,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 18),
        onPressed: () {
          m.deleteAnnale(a.id);
          setState(() {});
        },
      ),
    );
  }

  Future<void> _ajouter() async {
    final m = AppModel.instance;
    final concoursCtl = TextEditingController();
    final matiereCtl = TextEditingController();
    final anneeCtl =
        TextEditingController(text: (DateTime.now().year - 1).toString());
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Ajouter une annale'),
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
                            label: Text(mat,
                                style: const TextStyle(fontSize: 12)),
                            onPressed: () =>
                                setState(() => matiereCtl.text = mat),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: anneeCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Année'),
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
                final annee = int.tryParse(anneeCtl.text.trim());
                if (concoursCtl.text.trim().isEmpty ||
                    matiereCtl.text.trim().isEmpty ||
                    annee == null ||
                    annee < 1990 ||
                    annee > 2100) {
                  return;
                }
                m.addAnnale(Annale(
                  concours: concoursCtl.text.trim(),
                  matiere: matiereCtl.text.trim(),
                  annee: annee,
                ));
                Navigator.pop(context);
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}
