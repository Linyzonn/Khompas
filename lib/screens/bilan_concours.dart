import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';

/// BILAN DE CONCOURS (5/2) : les notes de l'an dernier, epreuve par
/// epreuve, avec les barres quand on les connait. L'app en tire « ou tu
/// perds des points » (deficit pondere par matiere) et propose — sur un
/// bouton explicite, jamais en silence — d'ajuster les priorites de
/// matieres. C'est la donnee la plus utile d'une 5/2 : travailler d'abord
/// la ou les points se perdent vraiment, pas la ou on est a l'aise.
class BilanConcoursScreen extends StatefulWidget {
  const BilanConcoursScreen({super.key});

  @override
  State<BilanConcoursScreen> createState() => _BilanConcoursScreenState();
}

class _BilanConcoursScreenState extends State<BilanConcoursScreen> {
  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final concours = <String>[];
    for (final r in m.resultatsConcours) {
      if (!concours.contains(r.concours)) concours.add(r.concours);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Bilan de concours')),
      body: m.resultatsConcours.isEmpty
          ? etatVide(
            context,
            emoji: '🎯',
            message: 'Saisis tes notes de l\'an dernier, épreuve par épreuve '
              '(et les barres si tu les connais).\n\nL\'app calcule où '
              'tu as vraiment perdu des points et te propose de '
              'régler tes priorités de matières dessus — le cœur '
              'd\'une 5/2 efficace.',
          )
          : listeCentree(context,
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                _syntheseDeficits(context),
                for (final c in concours) _section(c),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _ajouter,
        child: const Icon(Icons.add),
      ),
    );
  }

  /// « Où tu perds des points » : deficits ponderes tries, barres
  /// proportionnelles, et le bouton d'application aux priorites.
  Widget _syntheseDeficits(BuildContext context) {
    final m = AppModel.instance;
    final deficits = m.deficitsConcours();
    if (deficits.isEmpty) return const SizedBox.shrink();
    final tri = deficits.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxDef = tri.first.value <= 0 ? 1.0 : tri.first.value;
    return Card(
      margin: const EdgeInsets.all(kEsp12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRayonCarte),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(kEsp12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Où tu perds des points',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: kEsp4),
            Text(
              'Déficit pondéré = coefficient × points sous la barre '
              '(ou sous ta médiane si la barre n\'est pas saisie).',
              style: styleMeta(context),
            ),
            const SizedBox(height: 10),
            for (final e in tri)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(e.key,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(kRayonJauge),
                        child: LinearProgressIndicator(
                          value: (e.value / maxDef).clamp(0.0, 1.0),
                          minHeight: 8,
                          color: Color(subjectColor(e.key)),
                          backgroundColor:
                              Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(width: kEsp8),
                    Text(
                      e.value <= 0
                          ? 'OK'
                          : '−${e.value.toStringAsFixed(1)} pts',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Appliquer à mes priorités de matières'),
              onPressed: () {
                AppModel.instance.appliquerPrioritesDepuisDeficits();
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Priorités réglées sur ton bilan ✅ (modifiables dans Réglages)'),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String concours) {
    final m = AppModel.instance;
    final liste =
        m.resultatsConcours.where((r) => r.concours == concours).toList();
    return ExpansionTile(
      initiallyExpanded: true,
      leading: const Text('🏛', style: TextStyle(fontSize: 22)),
      title:
          Text(concours, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${liste.length} épreuve(s)',
          style: styleMeta(context)),
      children: [for (final r in liste) _tuile(r)],
    );
  }

  Widget _tuile(ResultatConcours r) {
    final m = AppModel.instance;
    final color = Color(subjectColor(r.matiere));
    final sousBarre = r.note != null && r.barre != null && r.note! < r.barre!;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: color.withValues(alpha: 0.18),
        child: Text(r.matiere.isEmpty ? '?' : r.matiere.characters.first,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
      title: Text('${r.epreuve} · ${r.annee}'),
      subtitle: Text(
        '${r.note == null ? 'note ?' : '${r.note!.toStringAsFixed(r.note! % 1 == 0 ? 0 : 1)}/20'}'
        '${r.barre == null ? '' : ' · barre ${r.barre!.toStringAsFixed(r.barre! % 1 == 0 ? 0 : 1)}'}'
        ' · coeff ${r.coeff.toStringAsFixed(r.coeff % 1 == 0 ? 0 : 1)}'
        '${sousBarre ? '  ⚠ sous la barre' : ''}',
        style: TextStyle(
            fontSize: 12,
            color: sousBarre ? context.tokens.attention : couleurSecondaire(context)),
      ),
      onTap: () => _ajouter(existant: r),
      trailing: IconButton(
        tooltip: 'Supprimer ce résultat',
        icon: const Icon(Icons.delete_outline, size: 18),
        onPressed: () {
          m.deleteResultatConcours(r.id);
          setState(() {});
        },
      ),
    );
  }

  Future<void> _ajouter({ResultatConcours? existant}) async {
    final m = AppModel.instance;
    final concoursCtl = TextEditingController(text: existant?.concours ?? '');
    final epreuveCtl = TextEditingController(text: existant?.epreuve ?? '');
    final matiereCtl = TextEditingController(text: existant?.matiere ?? '');
    final noteCtl = TextEditingController(
        text: existant?.note?.toString().replaceAll('.', ',') ?? '');
    final barreCtl = TextEditingController(
        text: existant?.barre?.toString().replaceAll('.', ',') ?? '');
    final coeffCtl = TextEditingController(
        text: (existant?.coeff ?? 1).toString().replaceAll('.0', ''));
    final anneeCtl = TextEditingController(
        text: (existant?.annee ?? DateTime.now().year).toString());

    double? nombre(String s) =>
        double.tryParse(s.trim().replaceAll(',', '.'));

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existant == null
              ? 'Ajouter un résultat'
              : 'Modifier le résultat'),
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
                  decoration: const InputDecoration(
                      labelText: 'Épreuve (ex. Maths 1, Physique-Chimie)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: matiereCtl,
                  decoration: const InputDecoration(
                      labelText: 'Matière (pour le plan de travail)'),
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
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: noteCtl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration:
                            const InputDecoration(labelText: 'Note /20'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: barreCtl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Barre (facultatif)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: coeffCtl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration:
                            const InputDecoration(labelText: 'Coefficient'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: anneeCtl,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Année'),
                      ),
                    ),
                  ],
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
                    epreuveCtl.text.trim().isEmpty ||
                    matiereCtl.text.trim().isEmpty ||
                    annee == null ||
                    annee < 1990 ||
                    annee > 2100) {
                  return;
                }
                final note = nombre(noteCtl.text);
                final barre = nombre(barreCtl.text);
                final coeff = nombre(coeffCtl.text) ?? 1;
                if (existant == null) {
                  m.addResultatConcours(ResultatConcours(
                    concours: concoursCtl.text.trim(),
                    epreuve: epreuveCtl.text.trim(),
                    matiere: normaliseMatiere(matiereCtl.text),
                    annee: annee,
                    note: note,
                    barre: barre,
                    coeff: coeff <= 0 ? 1 : coeff,
                  ));
                } else {
                  existant
                    ..concours = concoursCtl.text.trim()
                    ..epreuve = epreuveCtl.text.trim()
                    ..matiere = normaliseMatiere(matiereCtl.text)
                    ..annee = annee
                    ..note = note
                    ..barre = barre
                    ..coeff = coeff <= 0 ? 1 : coeff;
                  m.updateResultatConcours(existant);
                }
                Navigator.pop(context);
              },
              child: Text(existant == null ? 'Ajouter' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }
}
