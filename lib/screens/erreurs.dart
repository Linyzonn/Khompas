import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';

/// CAHIER D'ERREURS : chaque erreur notee apres une kholle / un DS / un TD,
/// classee par type. Le but n'est pas la liste — c'est de REFAIRE chaque
/// erreur jusqu'a la maitriser (case « refaite »). Le plan du soir ressort
/// les erreurs non refaites avant une epreuve de la matiere.
class ErreursScreen extends StatefulWidget {
  const ErreursScreen({super.key});

  @override
  State<ErreursScreen> createState() => _ErreursScreenState();
}

class _ErreursScreenState extends State<ErreursScreen> {
  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final matieres = <String>[];
    for (final e in m.erreurs) {
      if (!matieres.contains(e.matiere)) matieres.add(e.matiere);
    }
    matieres.sort();

    return Scaffold(
      appBar: AppBar(title: const Text('Cahier d\'erreurs')),
      body: m.erreurs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('📕', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text(
                      'Après chaque khôlle, DS ou TD raté : note l\'erreur ici (20 s), puis refais-la un autre soir jusqu\'à la maîtriser.\n\nLes erreurs non refaites remontent dans ton plan du soir avant une épreuve de la matière.',
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
                for (final mat in matieres) _section(mat),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final ok = await ajouterErreurDialog(context);
          if (ok && mounted) setState(() {});
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _section(String mat) {
    final m = AppModel.instance;
    final color = Color(subjectColor(mat));
    final liste = m.erreursDe(mat);
    final aRefaire = liste.where((e) => !e.refaite).length;
    final stats = m.statsErreurs(mat);
    final total = stats.values.fold<int>(0, (s, v) => s + v);
    String ligneStats = '';
    if (total >= 3) {
      final tri = stats.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top = tri.first;
      ligneStats =
          '${(top.value * 100 / total).round()} % de tes erreurs à refaire sont « ${top.key} »';
    }

    return ExpansionTile(
      initiallyExpanded: aRefaire > 0,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.18),
        child: Text(mat.characters.first.toUpperCase(),
            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ),
      title: Text(mat, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        aRefaire == 0
            ? 'Tout est refait 🎉'
            : '$aRefaire à refaire${ligneStats.isEmpty ? '' : ' · $ligneStats'}',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      children: [
        for (final e in liste) _tuile(e, color),
      ],
    );
  }

  Widget _tuile(Erreur e, Color color) {
    final m = AppModel.instance;
    String? chapitreNom;
    if (e.chapitreId != null) {
      final i = m.chapitres.indexWhere((c) => c.id == e.chapitreId);
      if (i >= 0) chapitreNom = m.chapitres[i].nom;
    }
    return ListTile(
      dense: true,
      leading: Checkbox(
        value: e.refaite,
        onChanged: (v) {
          e.refaite = v ?? false;
          m.updateErreur(e);
          setState(() {});
        },
      ),
      title: Text(
        e.texte,
        style: e.refaite
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text(
        '${e.type} · ${e.source} · ${frDateCourte(e.date)}'
        '${chapitreNom == null ? '' : ' · $chapitreNom'}',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'edit') {
            final ok = await ajouterErreurDialog(context, initial: e);
            if (ok && mounted) setState(() {});
          } else if (v == 'delete') {
            m.deleteErreur(e.id);
            setState(() {});
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Modifier')),
          const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
        ],
      ),
    );
  }
}

/// Dialog d'ajout / modification d'une erreur. [matiere] pre-remplit la
/// matiere (ex. depuis le recalibrage apres une mauvaise note).
/// Retourne true si une erreur a ete enregistree.
Future<bool> ajouterErreurDialog(BuildContext context,
    {Erreur? initial, String? matiere}) async {
  final m = AppModel.instance;
  final matiereCtl = TextEditingController(
      text: initial?.matiere ?? matiere ?? '');
  final texteCtl = TextEditingController(text: initial?.texte ?? '');
  var type = initial?.type ?? 'Méthode';
  var source = initial?.source ?? 'Autre';
  String? chapitreId = initial?.chapitreId;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final chapitres = m.chapitres
            .where((c) => c.matiere == matiereCtl.text.trim())
            .toList();
        return AlertDialog(
          title: Text(initial == null ? 'Noter une erreur' : 'Modifier l\'erreur'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: matiereCtl,
                  decoration: const InputDecoration(labelText: 'Matière'),
                  onChanged: (_) => setState(() => chapitreId = null),
                ),
                if (m.matieres.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final mat in m.matieres)
                          ActionChip(
                            label:
                                Text(mat, style: const TextStyle(fontSize: 12)),
                            onPressed: () => setState(() {
                              matiereCtl.text = mat;
                              chapitreId = null;
                            }),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: texteCtl,
                  autofocus: initial == null,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'L\'erreur',
                    hintText: 'ex. Oubli du cas λ = 0 dans la diagonalisation',
                  ),
                ),
                const SizedBox(height: 12),
                Text('Type', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final t in kTypesErreur)
                      ChoiceChip(
                        label: Text(t, style: const TextStyle(fontSize: 12)),
                        selected: type == t,
                        onSelected: (_) => setState(() => type = t),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Vue en…', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final s in kSourcesErreur)
                      ChoiceChip(
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        selected: source == s,
                        onSelected: (_) => setState(() => source = s),
                      ),
                  ],
                ),
                if (chapitres.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  DropdownButton<String?>(
                    value: chapitreId,
                    isExpanded: true,
                    hint: const Text('Chapitre (facultatif)'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('— aucun chapitre —')),
                      for (final c in chapitres)
                        DropdownMenuItem(value: c.id, child: Text(c.nom)),
                    ],
                    onChanged: (v) => setState(() => chapitreId = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (matiereCtl.text.trim().isEmpty ||
                    texteCtl.text.trim().isEmpty) {
                  return;
                }
                if (initial == null) {
                  m.addErreur(Erreur(
                    matiere: matiereCtl.text.trim(),
                    texte: texteCtl.text.trim(),
                    type: type,
                    source: source,
                    chapitreId: chapitreId,
                  ));
                } else {
                  initial
                    ..matiere = matiereCtl.text.trim()
                    ..texte = texteCtl.text.trim()
                    ..type = type
                    ..source = source
                    ..chapitreId = chapitreId;
                  m.updateErreur(initial);
                }
                Navigator.pop(context, true);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    ),
  );
  return ok ?? false;
}
