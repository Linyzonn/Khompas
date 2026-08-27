import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'import_cartes.dart';

/// CARTES : citations de francais et voc d'anglais, revisees facon Anki
/// (repetition espacee, memes verdicts que les chapitres). Le sens de
/// revision est celui de la PRODUCTION :
///  - citation : axe + usage affiches -> restituer la citation ET l'auteur
///    (un meme argument peut s'appuyer sur deux auteurs) ;
///  - voc : francais affiche -> sortir l'anglais (le sens de la colle).

// ---------- Citations ----------

class CitationsScreen extends StatefulWidget {
  const CitationsScreen({super.key});

  @override
  State<CitationsScreen> createState() => _CitationsScreenState();
}

class _CitationsScreenState extends State<CitationsScreen> {
  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final dues = m.citationsDues().length;
    // Groupees par axe (les axes vides a la fin, sous « Sans axe »).
    final axes = m.citations.map((c) => c.axe.trim()).toSet().toList()
      ..sort((a, b) {
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return a.compareTo(b);
      });
    return Scaffold(
      appBar: AppBar(
        title: const Text('Citations de français'),
        actions: [
          IconButton(
            tooltip: 'Importer en masse (IA)',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const ImportCartesScreen(vocabulaire: false)))
                .then((_) => setState(() {})),
          ),
        ],
      ),
      body: m.citations.isEmpty
          ? etatVide(
            context,
            emoji: '📜',
            message: 'Tes citations, classées par axe du thème, avec « comment '
              's\'en servir » — l\'arme de la dissert et de la khôlle.\n\n'
              'Ajoute-les au fil des lectures (bouton + citation sur '
              'chaque œuvre) ou importe ta fiche entière avec l\'IA '
              '(bouton ✨ en haut).\n\nElles se révisent ensuite façon '
              'Anki : l\'axe s\'affiche, tu restitues la citation et '
              'son auteur.',
          )
          : listeCentree(context,
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                for (final axe in axes) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                    child: Text(axe.isEmpty ? 'Sans axe' : axe,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  for (final c in m.citations
                      .where((c) => c.axe.trim() == axe)
                      .toList())
                    ListTile(
                      dense: true,
                      title: Text('« ${c.texte} »',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5)),
                      subtitle: Text(
                        [
                          if (c.auteur.isNotEmpty) c.auteur,
                          if (c.oeuvre.isNotEmpty) c.oeuvre,
                          if (c.usage.isNotEmpty) c.usage,
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      onTap: () async {
                        final edited =
                            await editCitationDialog(context, initial: c);
                        if (edited != null) {
                          AppModel.instance.updateCitation(edited);
                        }
                        if (mounted) setState(() {});
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () async {
                          if (!await confirmerSuppression(
                              context, 'cette citation')) {
                            return;
                          }
                          m.deleteCitation(c.id);
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                ],
              ],
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (dues > 0)
            FloatingActionButton.extended(
              heroTag: 'reviser-citations',
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => RevisionCartesScreen(
                          cartes: List<Object>.from(m.citationsDues()),
                          titre: 'Citations'))).then((_) => setState(() {})),
              icon: const Icon(Icons.style),
              label: Text('Réviser ($dues)'),
            ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'ajouter-citation',
            onPressed: () async {
              final c = await editCitationDialog(context);
              if (c != null) AppModel.instance.addCitation(c);
              if (mounted) setState(() {});
            },
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// Editeur d'une citation. [oeuvre] et [auteur] pre-remplissent (ex. depuis
/// la fiche d'une oeuvre ou une session de lecture).
Future<Citation?> editCitationDialog(BuildContext context,
    {Citation? initial, String? oeuvre, String? auteur}) {
  final m = AppModel.instance;
  final texteCtl = TextEditingController(text: initial?.texte ?? '');
  final auteurCtl =
      TextEditingController(text: initial?.auteur ?? auteur ?? '');
  final oeuvreCtl =
      TextEditingController(text: initial?.oeuvre ?? oeuvre ?? '');
  final axeCtl = TextEditingController(text: initial?.axe ?? '');
  final usageCtl = TextEditingController(text: initial?.usage ?? '');
  // Axes deja utilises : proposes en chips pour rester coherent.
  final axesConnus = m.citations
      .map((c) => c.axe.trim())
      .where((a) => a.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return showDialog<Citation>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(initial == null ? 'Nouvelle citation' : 'Modifier'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: texteCtl,
                autofocus: initial == null,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(labelText: 'Citation'),
              ),
              TextField(
                controller: auteurCtl,
                decoration: const InputDecoration(labelText: 'Auteur'),
              ),
              TextField(
                controller: oeuvreCtl,
                decoration:
                    const InputDecoration(labelText: 'Œuvre (facultatif)'),
              ),
              if (m.oeuvres.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final o in m.oeuvres)
                        ActionChip(
                          label: Text(o.titre),
                          onPressed: () => setState(() {
                            oeuvreCtl.text = o.titre;
                            if (auteurCtl.text.trim().isEmpty) {
                              auteurCtl.text = o.auteur;
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              TextField(
                controller: axeCtl,
                decoration: const InputDecoration(
                    labelText: 'Axe du thème',
                    helperText: 'Le sous-thème auquel elle répond.'),
              ),
              if (axesConnus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final a in axesConnus)
                        ActionChip(
                          label:
                              Text(a),
                          onPressed: () => setState(() => axeCtl.text = a),
                        ),
                    ],
                  ),
                ),
              TextField(
                controller: usageCtl,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                    labelText: 'Comment l\'utiliser',
                    helperText: '« Pour montrer que… » — l\'argument.'),
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
              if (texteCtl.text.trim().isEmpty) return;
              // Auteur et oeuvre sont LIES : si l'un manque, on le deduit
              // de l'autre via les oeuvres de l'annee.
              var auteurF = auteurCtl.text.trim();
              var oeuvreF = oeuvreCtl.text.trim();
              if (oeuvreF.isNotEmpty && auteurF.isEmpty) {
                for (final o in m.oeuvres) {
                  if (o.titre.toLowerCase() == oeuvreF.toLowerCase()) {
                    auteurF = o.auteur;
                    break;
                  }
                }
              } else if (auteurF.isNotEmpty && oeuvreF.isEmpty) {
                final corresp = m.oeuvres
                    .where((o) =>
                        o.auteur.toLowerCase() == auteurF.toLowerCase())
                    .toList();
                if (corresp.length == 1) oeuvreF = corresp.first.titre;
              }
              final c = initial ?? Citation(texte: '');
              c
                ..texte = texteCtl.text.trim()
                ..auteur = auteurF
                ..oeuvre = oeuvreF
                ..axe = axeCtl.text.trim()
                ..usage = usageCtl.text.trim();
              Navigator.pop(context, c);
            },
            child: Text(initial == null ? 'Ajouter' : 'Enregistrer'),
          ),
        ],
      ),
    ),
  );
}

// ---------- Voc d'anglais ----------

class VocabScreen extends StatefulWidget {
  const VocabScreen({super.key});

  @override
  State<VocabScreen> createState() => _VocabScreenState();
}

class _VocabScreenState extends State<VocabScreen> {
  @override
  Widget build(BuildContext context) {
    final m = AppModel.instance;
    final dues = m.vocabDus().length;
    final pourColle = m.vocab.where((v) => v.pourColle).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voc d\'anglais'),
        actions: [
          IconButton(
            tooltip: 'Importer en masse (IA)',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const ImportCartesScreen(vocabulaire: true)))
                .then((_) => setState(() {})),
          ),
        ],
      ),
      body: m.vocab.isEmpty
          ? etatVide(
            context,
            emoji: '🇬🇧',
            message: 'Le voc que le prof d\'anglais exige en khôlle.\n\n'
              'Importe ta feuille de voc entière avec l\'IA (bouton ✨ '
              'en haut) ou ajoute les mots un par un.\n\nRévision façon '
              'Anki dans le sens de la colle : le français s\'affiche, '
              'tu sors l\'anglais. Marque ⭐ les mots à savoir '
              'absolument — la veille d\'une khôlle d\'anglais, le '
              'tableau de bord te les rappelle.',
          )
          : listeCentree(context,
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                if (pourColle > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Text(
                        '⭐ $pourColle mot(s) « de colle » — rappelés la veille de chaque khôlle d\'anglais.',
                        style: TextStyle(
                            fontSize: 12,
                            color: couleurSecondaire(context))),
                  ),
                // Organise par LISTES (feuilles de voc) : une kholle
                // d'anglais peut exiger telle(s) liste(s), pas du vrac.
                for (final liste in _listes(m)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                    child: Text(
                        '${liste.isEmpty ? 'Sans liste' : liste} · ${m.vocab.where((v) => v.liste.trim() == liste).length} mot(s)',
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  for (final v in m.vocab
                      .where((v) => v.liste.trim() == liste)
                      .toList())
                    ListTile(
                      dense: true,
                      title: Text('${v.francais} → ${v.anglais}',
                          style: const TextStyle(fontSize: 14)),
                      subtitle: v.remarque.isEmpty
                          ? null
                          : Text(v.remarque,
                              style: const TextStyle(fontSize: 11.5)),
                      onTap: () async {
                        final edited = await _editVocabDialog(context, v);
                        if (edited != null) m.updateMotVocab(edited);
                        if (mounted) setState(() {});
                      },
                      leading: IconButton(
                        tooltip: 'À savoir pour la khôlle',
                        icon: Icon(
                            v.pourColle ? Icons.star : Icons.star_border,
                            size: 20,
                            color: v.pourColle ? context.tokens.attention : null),
                        onPressed: () {
                          v.pourColle = !v.pourColle;
                          m.updateMotVocab(v);
                          setState(() {});
                        },
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () async {
                          if (!await confirmerSuppression(
                              context, 'ce mot de voc')) {
                            return;
                          }
                          m.deleteMotVocab(v.id);
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                ],
              ],
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (dues > 0)
            FloatingActionButton.extended(
              heroTag: 'reviser-vocab',
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => RevisionCartesScreen(
                          cartes: List<Object>.from(m.vocabDus()),
                          titre: 'Voc d\'anglais'))).then(
                  (_) => setState(() {})),
              icon: const Icon(Icons.style),
              label: Text('Réviser ($dues)'),
            ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'ajouter-vocab',
            onPressed: () async {
              final v = await _editVocabDialog(context, null);
              if (v != null) m.addMotVocab(v);
              if (mounted) setState(() {});
            },
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  /// Listes presentes, triees ('' — « Sans liste » — a la fin).
  List<String> _listes(AppModel m) {
    final l = m.vocab.map((v) => v.liste.trim()).toSet().toList()
      ..sort((a, b) {
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return a.compareTo(b);
      });
    return l;
  }

  Future<MotVocab?> _editVocabDialog(BuildContext context, MotVocab? initial) {
    final m = AppModel.instance;
    final frCtl = TextEditingController(text: initial?.francais ?? '');
    final enCtl = TextEditingController(text: initial?.anglais ?? '');
    final remCtl = TextEditingController(text: initial?.remarque ?? '');
    final listeCtl = TextEditingController(text: initial?.liste ?? '');
    var pourColle = initial?.pourColle ?? false;
    return showDialog<MotVocab>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(initial == null ? 'Nouveau mot' : 'Modifier'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: frCtl,
                  autofocus: initial == null,
                  decoration: const InputDecoration(labelText: 'Français'),
                ),
                TextField(
                  controller: enCtl,
                  decoration: const InputDecoration(labelText: 'Anglais'),
                ),
                TextField(
                  controller: remCtl,
                  decoration: const InputDecoration(
                      labelText: 'Remarque (facultatif)',
                      helperText: 'Prononciation, faux-ami, contexte…'),
                ),
                TextField(
                  controller: listeCtl,
                  decoration: const InputDecoration(
                      labelText: 'Liste',
                      helperText:
                          'La feuille d\'origine (ex. « Liste 5 ») — une khôlle peut exiger telle liste.'),
                ),
                if (m.listesVocNoms.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final nom in m.listesVocNoms)
                          ActionChip(
                            label: Text(nom),
                            onPressed: () =>
                                setState(() => listeCtl.text = nom),
                          ),
                      ],
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('⭐ À savoir pour la khôlle',
                      style: TextStyle(fontSize: 14)),
                  value: pourColle,
                  onChanged: (v) => setState(() => pourColle = v),
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
                if (frCtl.text.trim().isEmpty || enCtl.text.trim().isEmpty) {
                  return;
                }
                final v = initial ?? MotVocab(francais: '', anglais: '');
                v
                  ..francais = frCtl.text.trim()
                  ..anglais = enCtl.text.trim()
                  ..remarque = remCtl.text.trim()
                  ..liste = listeCtl.text.trim()
                  ..pourColle = pourColle;
                Navigator.pop(context, v);
              },
              child: Text(initial == null ? 'Ajouter' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Session de revision (type Anki) ----------

/// Fait defiler des cartes ([Citation] ou [MotVocab]) : recto -> « voir la
/// reponse » -> verdict en 1 tap (memes reglages d'espacement que les
/// chapitres). Concu pour le TRAJET : une main, zero papier.
class RevisionCartesScreen extends StatefulWidget {
  final List<Object> cartes;
  final String titre;
  const RevisionCartesScreen(
      {super.key, required this.cartes, required this.titre});

  @override
  State<RevisionCartesScreen> createState() => _RevisionCartesScreenState();
}

class _RevisionCartesScreenState extends State<RevisionCartesScreen> {
  int index = 0;
  bool montreVerso = false;
  int revues = 0;

  void _verdict(String v) {
    final m = AppModel.instance;
    final carte = widget.cartes[index];
    if (carte is Citation) m.evaluerCitation(carte.id, v);
    if (carte is MotVocab) m.evaluerMotVocab(carte.id, v);
    setState(() {
      revues++;
      index++;
      montreVerso = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (index >= widget.cartes.length) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.titre)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 48)),
              const SizedBox(height: kEsp12),
              Text('Session finie — $revues carte(s) revue(s)',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: kEsp16),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Retour'),
              ),
            ],
          ),
        ),
      );
    }
    final carte = widget.cartes[index];
    return Scaffold(
      appBar: AppBar(
          title: Text('${widget.titre} · ${index + 1}/${widget.cartes.length}')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kRayonCarte),
                  side:
                      BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(kRayonCarte),
                  onTap: montreVerso
                      ? null
                      : () => setState(() => montreVerso = true),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: carte is Citation
                            ? _faceCitation(carte)
                            : _faceVocab(carte as MotVocab),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: kEsp16),
            if (!montreVerso)
              FilledButton.tonal(
                onPressed: () => setState(() => montreVerso = true),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('Voir la réponse'),
                ),
              )
            else
              Row(
                children: [
                  for (final v in const [
                    ('difficile', '😮‍💨', 'Difficile'),
                    ('cava', '🙂', 'Ça va'),
                    ('facile', '😎', 'Facile'),
                  ]) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _verdict(v.$1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              Text(v.$2,
                                  style: const TextStyle(fontSize: 22)),
                              Text(v.$3,
                                  style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (v.$1 != 'facile') const SizedBox(width: kEsp8),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _faceCitation(Citation c) {
    return [
      Text('📜 CITATION', style: _etiquette(context)),
      const SizedBox(height: kEsp12),
      if (c.axe.isNotEmpty) ...[
        Text('Axe : ${c.axe}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: kEsp8),
      ],
      if (c.usage.isNotEmpty)
        Text(c.usage, style: const TextStyle(fontSize: 15))
      else if (c.axe.isEmpty)
        const Text('(Sans axe ni usage — retrouve la citation associée)',
            style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
      const SizedBox(height: 10),
      Text('→ La citation ? Et son AUTEUR ?',
          style: TextStyle(fontSize: 13, color: couleurSecondaire(context))),
      if (montreVerso) ...[
        const Divider(height: 28),
        Text('« ${c.texte} »',
            style: const TextStyle(
                fontSize: 17, fontStyle: FontStyle.italic, height: 1.35)),
        const SizedBox(height: 10),
        Text(
          '— ${c.auteur.isEmpty ? 'auteur non renseigné' : c.auteur}'
          '${c.oeuvre.isEmpty ? '' : ', ${c.oeuvre}'}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    ];
  }

  List<Widget> _faceVocab(MotVocab v) {
    return [
      Text('🇬🇧 VOC ${v.pourColle ? '⭐' : ''}', style: _etiquette(context)),
      const SizedBox(height: kEsp16),
      Text(v.francais,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text('→ En anglais ?',
          style: TextStyle(fontSize: 13, color: couleurSecondaire(context))),
      if (montreVerso) ...[
        const Divider(height: 28),
        Text(v.anglais,
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: context.tokens.succes)),
        if (v.remarque.isNotEmpty) ...[
          const SizedBox(height: kEsp8),
          Text(v.remarque,
              style:
                  TextStyle(fontSize: 13, color: couleurSecondaire(context))),
        ],
      ],
    ];
  }

  TextStyle _etiquette(BuildContext context) => TextStyle(
      fontSize: 11,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w600,
      color: couleurSecondaire(context));
}
