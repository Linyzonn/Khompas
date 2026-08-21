import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'cartes.dart';

/// ŒUVRES DE FRANÇAIS de l'année (3 livres + le thème) : suivi de lecture
/// page par page, dans l'ORDRE choisi (glisser-déposer — le plan sert
/// toujours le premier livre pas fini). Le plan d'été programme des séances
/// de lecture un jour sur deux ; en début d'année, ce qui n'est pas fini
/// revient un jour sur trois — chaque khôlle de français s'appuie dessus.
class LecturesScreen extends StatefulWidget {
  const LecturesScreen({super.key});

  @override
  State<LecturesScreen> createState() => _LecturesScreenState();
}

class _LecturesScreenState extends State<LecturesScreen> {
  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Œuvres de français'),
        actions: [
          IconButton(
            tooltip: 'Mes citations',
            icon: const Icon(Icons.format_quote),
            onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CitationsScreen()))
                .then((_) => setState(() {})),
          ),
        ],
      ),
      body: m.oeuvres.isEmpty
          ? etatVide(
            context,
            emoji: '📖',
            message: 'Ajoute les œuvres du programme de français-philo de '
              'l\'année (le thème et ses 3 livres).\n\nPendant les '
              'grandes vacances, le plan te programme des séances de '
              'lecture un jour sur deux — l\'été est LE moment pour '
              'les lire. Ce qui n\'est pas fini revient en début '
              'd\'année.',
          )
          // Bornee en largeur comme les autres listes, mais le
          // ReorderableListView est conserve : c'est lui qui porte le
          // glisser-deposer de l'ordre de lecture.
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ReorderableListView(
              padding: const EdgeInsets.only(bottom: 90),
              header: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text(
                  'L\'ordre de la liste = ton ordre de lecture (maintiens une '
                  'œuvre pour la déplacer). Le plan programme toujours le '
                  'PREMIER livre pas fini.',
                  style: TextStyle(
                      fontSize: 12, color: couleurSecondaire(context)),
                ),
              ),
              onReorderItem: (oldIndex, newIndex) {
                m.reorderOeuvres(oldIndex, newIndex);
                setState(() {});
              },
                  children: [for (final o in m.oeuvres) _tuile(o)],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editer(null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _tuile(Oeuvre o) {
    final m = AppModel.instance;
    final avecPages = o.pages != null && o.pages! > 0;
    final avancement =
        avecPages ? (o.pageActuelle / o.pages!).clamp(0.0, 1.0) : null;
    return Card(
      key: ValueKey(o.id),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRayonCarte),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(o.finie ? '✅' : '📖', style: const TextStyle(fontSize: 20)),
                const SizedBox(width: kEsp8),
                Expanded(
                  child: Text(
                    '${o.titre}${o.auteur.isEmpty ? '' : ' — ${o.auteur}'}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration:
                            o.finie ? TextDecoration.lineThrough : null),
                  ),
                ),
                IconButton(
                  tooltip: 'Modifier',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _editer(o),
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () {
                    m.deleteOeuvre(o.id);
                    setState(() {});
                  },
                ),
              ],
            ),
            if (!o.finie) ...[
              if (avancement != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(kRayonJauge),
                    child: LinearProgressIndicator(
                        value: avancement, minHeight: 7),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('page ${o.pageActuelle} / ${o.pages}',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: couleurSecondaire(context))),
                ),
              ],
              Wrap(
                spacing: 6,
                children: [
                  if (avecPages)
                    ActionChip(
                      label: const Text('+10 pages',
                          style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        o.pageActuelle =
                            (o.pageActuelle + 10).clamp(0, o.pages!);
                        if (o.pageActuelle >= o.pages!) o.finie = true;
                        m.updateOeuvre(o);
                        setState(() {});
                      },
                    ),
                  ActionChip(
                    label: const Text('Où j\'en suis…',
                        style: TextStyle(fontSize: 12)),
                    onPressed: () => _saisirPage(o),
                  ),
                  ActionChip(
                    label: const Text('+ citation',
                        style: TextStyle(fontSize: 12)),
                    onPressed: () async {
                      final c = await editCitationDialog(context,
                          oeuvre: o.titre, auteur: o.auteur);
                      if (c != null) m.addCitation(c);
                      if (mounted) setState(() {});
                    },
                  ),
                  ActionChip(
                    label:
                        const Text('Finie ✅', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      o.finie = true;
                      if (avecPages) o.pageActuelle = o.pages!;
                      m.updateOeuvre(o);
                      setState(() {});
                    },
                  ),
                ],
              ),
            ] else
              TextButton(
                onPressed: () {
                  o.finie = false;
                  m.updateOeuvre(o);
                  setState(() {});
                },
                child: const Text('Reprendre la lecture'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _saisirPage(Oeuvre o) async {
    final m = AppModel.instance;
    final ctl = TextEditingController(text: o.pageActuelle.toString());
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('« ${o.titre} » — page atteinte ?'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
              labelText: o.pages == null ? 'Page' : 'Page (sur ${o.pages})'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, int.tryParse(ctl.text.trim())),
              child: const Text('OK')),
        ],
      ),
    );
    if (page == null) return;
    o.pageActuelle = o.pages == null ? page : page.clamp(0, o.pages!);
    if (o.pages != null && o.pageActuelle >= o.pages!) o.finie = true;
    m.updateOeuvre(o);
    if (mounted) setState(() {});
  }

  Future<void> _editer(Oeuvre? existante) async {
    final m = AppModel.instance;
    final titreCtl = TextEditingController(text: existante?.titre ?? '');
    final auteurCtl = TextEditingController(text: existante?.auteur ?? '');
    final pagesCtl =
        TextEditingController(text: existante?.pages?.toString() ?? '');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existante == null ? 'Ajouter une œuvre' : 'Modifier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titreCtl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Titre'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: auteurCtl,
              decoration: const InputDecoration(labelText: 'Auteur'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pagesCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Nombre de pages (facultatif)',
                  helperText:
                      'S\'il est connu, l\'app calcule ton rythme de lecture.'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (titreCtl.text.trim().isEmpty) return;
              final pages = int.tryParse(pagesCtl.text.trim());
              if (existante == null) {
                m.addOeuvre(Oeuvre(
                  titre: titreCtl.text.trim(),
                  auteur: auteurCtl.text.trim(),
                  pages: pages,
                ));
              } else {
                existante
                  ..titre = titreCtl.text.trim()
                  ..auteur = auteurCtl.text.trim()
                  ..pages = pages;
                m.updateOeuvre(existante);
              }
              Navigator.pop(context);
            },
            child: Text(existante == null ? 'Ajouter' : 'Enregistrer'),
          ),
        ],
      ),
    );
    if (mounted) setState(() {});
  }
}
