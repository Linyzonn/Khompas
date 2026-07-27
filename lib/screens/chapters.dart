import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'dialogs.dart';
import 'import_chapitres.dart';

/// Onglet "Chapitres", version COMPACTE : avec 60+ chapitres importes,
/// l'ancienne liste (10 chips par chapitre, toujours visibles) devenait un
/// mur illisible. Desormais :
/// - recherche + filtres (fragiles / a reviser / en cours en classe) ;
/// - une section repliable par matiere avec resume + barre de progression ;
/// - chaque chapitre = une petite carte (etape, maitrise, badges) ;
/// - le TAP ouvre la fiche d'edition (etape, maitrise, suppression).
/// Sur PC les cartes se rangent en plusieurs colonnes.
class ChaptersScreen extends StatefulWidget {
  const ChaptersScreen({super.key});

  @override
  State<ChaptersScreen> createState() => _ChaptersScreenState();
}

class _ChaptersScreenState extends State<ChaptersScreen> {
  String recherche = '';
  String filtre = 'tous'; // tous | fragiles | reviser | encours

  void _importer(BuildContext context) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const ImportChapitresScreen()));
  }

  bool _garde(Chapitre c) {
    if (recherche.isNotEmpty &&
        !c.nom.toLowerCase().contains(recherche.toLowerCase())) {
      return false;
    }
    final finJour = DateTime.now().add(const Duration(days: 1));
    switch (filtre) {
      case 'fragiles':
        return c.etape > 0 && c.maitrise <= 1;
      case 'reviser':
        return c.prochaineRevision != null &&
            c.prochaineRevision!.isBefore(
                DateTime(finJour.year, finJour.month, finJour.day));
      case 'encours':
        return c.entame && c.etape == 0;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;

    if (m.chapitres.isEmpty) {
      return Scaffold(
        body: Center(
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
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _ajouter(context),
          child: const Icon(Icons.add),
        ),
      );
    }

    final matieres = <String>{for (final c in m.chapitres) c.matiere}.toList()
      ..sort();
    final nbFragiles =
        m.chapitres.where((c) => c.etape > 0 && c.maitrise <= 1).length;
    final demain = DateTime.now().add(const Duration(days: 1));
    final nbAReviser = m.chapitres
        .where((c) =>
            c.prochaineRevision != null &&
            c.prochaineRevision!
                .isBefore(DateTime(demain.year, demain.month, demain.day)))
        .length;
    final nbEnCours =
        m.chapitres.where((c) => c.entame && c.etape == 0).length;
    final actif = filtre != 'tous' || recherche.isNotEmpty;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          // ---- Recherche + filtres ----
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Rechercher un chapitre…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (v) => setState(() => recherche = v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Importer le programme officiel (IA)',
                  icon: const Icon(Icons.menu_book),
                  onPressed: () => _importer(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final f in [
                  ('tous', 'Tous (${m.chapitres.length})'),
                  ('fragiles', '⚠ Fragiles ($nbFragiles)'),
                  ('reviser', '🔁 À réviser ($nbAReviser)'),
                  ('encours', '⏳ En cours en classe ($nbEnCours)'),
                ])
                  ChoiceChip(
                    label:
                        Text(f.$2, style: const TextStyle(fontSize: 12)),
                    selected: filtre == f.$1,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => filtre = f.$1),
                  ),
              ],
            ),
          ),
          // ---- Sections par matiere ----
          for (final mat in matieres) _section(context, mat, actif),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _ajouter(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _section(BuildContext context, String mat, bool actif) {
    final m = AppModel.instance;
    final color = Color(subjectColor(mat));
    final tous = m.chapitres.where((c) => c.matiere == mat).toList();
    final visibles = tous.where(_garde).toList();
    if (actif && visibles.isEmpty) return const SizedBox.shrink();

    final revus = tous.where((c) => c.etape >= 2).length;
    final fragiles =
        tous.where((c) => c.etape > 0 && c.maitrise <= 1).length;
    final large = MediaQuery.of(context).size.width >= 760;

    return ExpansionTile(
      // La cle force le repli/depli quand le filtre ou la recherche change.
      key: ValueKey('$mat|$filtre|$recherche'),
      initiallyExpanded: actif,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.18),
        child: Text(mat.characters.first.toUpperCase(),
            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ),
      title: Text(mat, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: tous.isEmpty ? 0 : revus / tous.length,
                  minHeight: 5,
                  color: color,
                  backgroundColor: Colors.grey.withOpacity(0.15),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Text(
                '$revus/${tous.length} revus'
                '${fragiles == 0 ? '' : ' · ⚠ $fragiles fragile(s)'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in visibles)
              SizedBox(
                width: large ? 300 : double.infinity,
                child: _carteChapitre(context, c, color),
              ),
          ],
        ),
      ],
    );
  }

  static const _couleursEtape = [
    Colors.blueGrey,
    Colors.indigo,
    Colors.teal,
    Colors.orange,
    Colors.green,
  ];

  Widget _carteChapitre(BuildContext context, Chapitre c, Color color) {
    final due = c.prochaineRevision != null &&
        !c.prochaineRevision!
            .isAfter(DateTime.now().add(const Duration(hours: 12)));
    final couleurEtape = _couleursEtape[c.etape.clamp(0, 4)];
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _editerChapitre(c),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.nom,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13.5)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 5,
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: couleurEtape.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    kEtapesChapitre[c.etape.clamp(0, 4)],
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: couleurEtape),
                  ),
                ),
                if (c.entame && c.etape == 0)
                  const Text('⏳', style: TextStyle(fontSize: 12)),
                if (due) const Text('🔁', style: TextStyle(fontSize: 12)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 5; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Icon(
                          i <= c.maitrise
                              ? Icons.circle
                              : Icons.circle_outlined,
                          size: 9,
                          color: i <= c.maitrise
                              ? _couleurMaitrise(c.maitrise)
                              : Colors.grey.withOpacity(0.5),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Fiche d'edition d'un chapitre (etape, maitrise, suppression).
  Future<void> _editerChapitre(Chapitre c) async {
    final m = AppModel.instance;
    await feuilleAdaptative<void>(
      context,
      (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(c.nom,
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    IconButton(
                      tooltip: 'Supprimer ce chapitre',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () {
                        m.deleteChapitre(c.id);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
                Text(c.matiere,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                if (c.prochaineRevision != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '🔁 Prochaine révision espacée : ${frDateCourte(c.prochaineRevision!)}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                const SizedBox(height: 12),
                Text('Étape',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 5,
                  runSpacing: 2,
                  children: [
                    for (var i = 0; i < kEtapesChapitre.length; i++)
                      ChoiceChip(
                        label: Text(kEtapesChapitre[i],
                            style: const TextStyle(fontSize: 11)),
                        selected: c.etape == i,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          c.etape = i;
                          m.updateChapitre(c);
                          setSheet(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Maîtrise',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    for (var i = 0; i < 5; i++)
                      InkWell(
                        onTap: () {
                          c.maitrise = i;
                          m.updateChapitre(c);
                          setSheet(() {});
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            i <= c.maitrise
                                ? Icons.circle
                                : Icons.circle_outlined,
                            size: 20,
                            color: i <= c.maitrise
                                ? _couleurMaitrise(c.maitrise)
                                : Colors.grey,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Text(_labelMaitrise(c.maitrise),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fermer'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
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
                  matiere: normaliseMatiere(matiereCtl.text),
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
